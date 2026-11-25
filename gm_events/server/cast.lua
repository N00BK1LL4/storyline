-- Story NPCs: friendly characters staff place, move and speak through, and bookmarks:
-- named places, kept by the server, where any event can start.
local core = GM.core
local MAX_CAST, MAX_BOOKMARKS, MAX_TEXT = 8, 80, 160

-- ------------------------------------------------------------------ bookmarks

local bookmarks = {} -- id -> { name, group, x, y, z, heading }

local function loadBookmarks()
    local rows, why = Open77.kvp.find("bookmark:", 500)
    if not rows then return print("[gm] bookmarks not loaded: " .. tostring(why)) end
    for _, row in ipairs(rows) do
        local ok, b = pcall(json.decode, row.value)
        if ok and type(b) == "table" and tonumber(b.x) and tonumber(b.y) and tonumber(b.z) and type(b.name) == "string" then
            bookmarks[row.key:sub(10)] = {
                name = b.name, group = type(b.group) == "string" and b.group or "", x = b.x, y = b.y, z = b.z, heading = tonumber(b.heading) or 0,
            }
        else
            print("[gm] skipped a bad bookmark: " .. tostring(row.key))
        end
    end
end

function GM.bookmarkList()
    local list = {}
    for id, b in pairs(bookmarks) do list[#list + 1] = { id = id, name = b.name, group = b.group } end
    table.sort(list, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return list
end

-- By id, or by name for scripts and commands.
function GM.bookmarkAnchor(wanted, source)
    local b = bookmarks[wanted]
    if not b then
        for _, other in pairs(bookmarks) do if other.name == wanted then b = other end end
    end
    if not b then return nil, "no such bookmark" end
    return { x = b.x, y = b.y, z = b.z, heading = b.heading, bucket = 0, source = source }
end

function GM.saveBookmark(playerId, name, group)
    local me, why = core.freshPlayer(playerId)
    if not me then return false, why end
    if (me.bucket or 0) ~= 0 then return false, "bookmarks are for the main world only" end
    local count, id = 0, nil
    for key, b in pairs(bookmarks) do
        count = count + 1
        if b.name == name then id = key end -- the same name moves the bookmark here
    end
    if not id then
        if count >= MAX_BOOKMARKS then return false, "bookmark limit reached (" .. MAX_BOOKMARKS .. ")" end
        local n = 1
        while bookmarks["b" .. n] do n = n + 1 end
        id = "b" .. n
    end
    local b = { name = name, group = group or "", x = me.position.x, y = me.position.y, z = me.position.z, heading = me.heading or 0 }
    local ok, problem = Open77.kvp.set("bookmark:" .. id, json.encode(b))
    if not ok then return false, "not saved: " .. tostring(problem) end
    bookmarks[id] = b
    print(("[gm] player %d saved bookmark '%s'"):format(playerId, name))
    return true, "bookmark '" .. name .. "' saved where you stand"
end

function GM.deleteBookmark(playerId, id)
    local b = bookmarks[id]
    if not b then return false, "no such bookmark" end
    local ok, why = Open77.kvp.delete("bookmark:" .. id)
    if not ok then return false, "not deleted: " .. tostring(why) end
    bookmarks[id] = nil
    print(("[gm] player %d deleted bookmark '%s'"):format(playerId, b.name))
    return true, "bookmark '" .. b.name .. "' deleted"
end

-- ----------------------------------------------------------------------- cast

local cast = {} -- id -> { npc, def, name, doing }
local sequence = 0

local function read(c) return Open77.npcs.get(c.npc) end

local function remove(c)
    if cast[c.id] ~= c then return end
    cast[c.id] = nil
    if read(c) then Open77.npcs.remove(c.npc) end
end

function GM.clearCast()
    local list = {}
    for _, c in pairs(cast) do list[#list + 1] = c end
    for _, c in ipairs(list) do remove(c) end
end

local function nearestPlayer(npc, range)
    local best, bestD
    for _, id in ipairs(Open77.players.all()) do
        local p = not core.isGhost(id) and Open77.players.position(id) or nil
        if p and p.bucket == npc.bucket then
            local d = (p.x - npc.x) ^ 2 + (p.y - npc.y) ^ 2 + (p.z - npc.z) ^ 2
            if d <= range * range and (not bestD or d < bestD) then best, bestD = { id = id, p = p }, d end
        end
    end
    return best
end

local function task(name, ...)
    local id, why = Open77.npcs.tasks[name](...)
    if not id then return false, tostring(why) end
    return true
end

function core.actions.cast(anchor, step)
    local count = 0
    for _ in pairs(cast) do count = count + 1 end
    if count >= MAX_CAST then return false, "at most " .. MAX_CAST .. " story characters at once" end
    local def = step.def
    local npc, why = Open77.npcs.create({
        record = def.record, position = { x = anchor.x, y = anchor.y, z = anchor.z }, yaw = anchor.heading + 180, bucket = anchor.bucket,
        aiMode = Open77.npcs.ai.tasks,
        damagePolicy = def.mortal and Open77.npcs.damage.mortal or Open77.npcs.damage.invulnerable,
        behavior = { combatEnabled = false, hitPricing = def.mortal and "platform" or nil },
        health = 100, maxHealth = 100,
    })
    if not npc then return false, "character refused: " .. tostring(why) end
    sequence = sequence + 1
    local c = { id = sequence, npc = npc, def = def, name = def.name, doing = "standing" }
    cast[c.id] = c
    local ready = Open77.npcs.whenReady(npc, 15000)
    if ready then
        ready:next(function()
            if cast[c.id] ~= c then return end
            core.reply(anchor.source, nil, true, def.name .. " is in the world")
            if def.pose ~= "" then GM.directCast(0, c.id, "pose", { pose = def.pose }) else task("hold", npc) end
        end, function(problem)
            if cast[c.id] == c then core.reply(anchor.source, nil, false, def.name .. " never appeared: " .. tostring(problem)) end
        end)
    end
    return true, def.name .. " placed"
end

-- Everyone in hearing range reads the line over the head and as a subtitle.
local ranges = { whisper = 6, normal = 18, shout = 50 }

local function say(c, text, volume)
    local npc = read(c)
    if not npc or npc.health <= 0 then return false, c.name .. " cannot speak now" end
    local range, heard = ranges[volume] or ranges.normal, 0
    local ms = math.floor(math.max(2500, math.min(12000, 1500 + (utf8.len(text) or #text) * 65)))
    for _, id in ipairs(Open77.players.all()) do
        local p = Open77.players.position(id)
        if p and p.bucket == npc.bucket and (p.x - npc.x) ^ 2 + (p.y - npc.y) ^ 2 + (p.z - npc.z) ^ 2 <= range * range then
            TriggerClientEvent("gm_events:say", id, tostring(c.npc), c.name, text, ms, volume == "shout")
            if not core.isGhost(id) then heard = heard + 1 end
        end
    end
    return true, ("%s said it, %d heard"):format(c.name, heard)
end

-- what: say, bark, face, come, go, follow, stay, pose, remove. Rights are the panel's job.
function GM.directCast(playerId, id, what, data)
    local c = cast[math.tointeger(tonumber(id)) or -1]
    if not c then return false, "that character is gone" end
    if what == "remove" then
        remove(c)
        return true, c.name .. " removed"
    end
    local npc = read(c)
    if not npc or npc.health <= 0 then return false, c.name .. " is down or gone" end
    if what == "say" then
        if c.doing == "standing" then
            local near = nearestPlayer(npc, 25)
            if near then task("lookAt", c.npc, { type = "player", id = near.id }) end
        end
        local ok, text = say(c, data.text, data.volume)
        if ok then
            print(("[gm] player %s as %s: %s"):format(tostring(playerId), c.name, data.text))
            GM.moment("characterSpoke", { name = c.name, text = data.text, volume = data.volume, staff = playerId,
                position = { x = npc.x, y = npc.y, z = npc.z, bucket = npc.bucket } })
            if data.bark and data.bark ~= "" then
                local heard, why = Open77.npcs.speak(c.npc, data.bark)
                if not heard then text = text .. ", no voice: " .. tostring(why) end
            end
        end
        return ok, text
    elseif what == "bark" then
        local ok, why = Open77.npcs.speak(c.npc, data.bark)
        return ok == true, ok and c.name .. ": " .. data.bark or tostring(why)
    end
    -- everything below replaces what it is doing
    Open77.npcs.tasks.clear(c.npc)
    local ok, why
    if what == "face" then
        local near = nearestPlayer(npc, 60)
        if not near then return false, "nobody is near" end
        c.doing = "standing"
        ok, why = task("face", c.npc, { x = near.p.x, y = near.p.y, z = near.p.z })
    elseif what == "come" or what == "go" then
        local to = data.to
        if not to then return false, "no place to go to" end
        if to.bucket ~= npc.bucket then return false, "that place is in another world" end
        c.doing = what == "come" and "coming" or "walking"
        ok, why = task("moveTo", c.npc, { x = to.x, y = to.y, z = to.z }, { speed = data.run and "run" or "walk" })
    elseif what == "follow" then
        c.doing = "following"
        ok, why = task("follow", c.npc, { type = "player", id = data.player }, { distance = 2.5, speed = "walk" })
    elseif what == "stay" then
        c.doing = "standing"
        ok, why = task("hold", c.npc)
    elseif what == "pose" then
        c.doing = "posing"
        ok, why = task("workspot", c.npc, data.pose, { loop = true })
    else
        return false, "unknown button"
    end
    if not ok then
        c.doing = "standing"
        return false, c.name .. ": " .. tostring(why)
    end
    return true, c.name .. ": " .. what
end

AddEventHandler("onNpcTaskState", function(npcId, _, status)
    if status ~= "succeeded" and status ~= "failed" then return end
    for _, c in pairs(cast) do
        if tostring(c.npc) == tostring(npcId) and (c.doing == "walking" or c.doing == "coming") then
            c.doing = "standing"
            if status == "failed" then print("[gm] " .. c.name .. " could not get there") end
        end
    end
end)

AddEventHandler("onNpcDied", function(npcId)
    for _, c in pairs(cast) do
        if tostring(c.npc) == tostring(npcId) and not c.dead then
            c.dead, c.doing = true, "dead"
            SetTimeout(GM.corpseSeconds * 1000, function() remove(c) end)
        end
    end
end)

function GM.castList()
    local list = {}
    for _, c in pairs(cast) do
        list[#list + 1] = { id = c.id, name = c.name, doing = c.doing, lines = c.def.lines or {} }
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

GM.castPoses = { "smoke", "cigar", "drink", "phone", "dance", "handsup", "meditate", "sit", "clap", "cry", "think", "stretch" }
GM.castBarks = { "greeting", "bump", "fear_beg", "danger", "enemy_warning", "battlecry_curse", "start_combat", "rep_ask_to_leave",
    "rep_final_warning", "hurry_up", "phone_start", "stlh_curious" }

-- gm.say <id> <line>: for staff who prefer typing; gm.cast lists the ids.
core.command("gm.cast", function()
    local lines = {}
    for _, c in ipairs(GM.castList()) do lines[#lines + 1] = ("%d %s (%s)"):format(c.id, c.name, c.doing) end
    return true, #lines > 0 and table.concat(lines, " | ") or "no story characters"
end)

core.command("gm.say", function(source, args)
    local words = {}
    for i = 2, #args do words[#words + 1] = tostring(args[i]) end
    local text = table.concat(words, " "):gsub("[%c<>]", "")
    local length = utf8.len(text)
    if not length or length == 0 or length > MAX_TEXT then return false, "gm.say <id> <line of 1 to " .. MAX_TEXT .. " characters>" end
    return GM.directCast(source, args[1], "say", { text = text, volume = "normal" })
end)

loadBookmarks()
