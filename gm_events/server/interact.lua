-- Interactables: something in the world players use by holding a key next to it, to
-- hack, search, plant, rescue. The client only says "holding" or "let go"; who is close
-- enough, how long it takes and what comes of it is decided here.
--
-- gm_events:interact is raised for owners' scripts and logs:
--   { phase = "used" | "finished" | "ended", id, name, players = { ids }, left, total }
local core = GM.core
local MAX_GROUPS, CARD_RANGE, REACH, TICK = 10, 25, 2.6, 250

local groups = {}  -- id -> group
local holding = {} -- playerId -> true while the key is down
local sequence = 0

local function alive(g) return groups[g.id] == g end

local function dist3(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end

local eventNumber = 0 -- events sent together may arrive swapped: owners can sort by seq

local function describe(g, point)
    return {
        id = point.cardId, group = g.id, name = g.def.name, prompt = g.def.prompt, seconds = g.def.seconds, players = g.def.players,
        model = g.def.model, reach = REACH, position = { x = point.at.x, y = point.at.y, z = point.at.z, bucket = g.bucket },
        finished = point.finished == true, ready = not point.finished and not point.fuseAt and GetGameTimer() >= (point.readyAt or 0),
    }
end

-- One point, for owners who draw their own prompts: placed, finished, fuse or removed.
local function raisePoint(g, point, phase, seconds)
    eventNumber = eventNumber + 1
    local payload = describe(g, point)
    payload.seq, payload.phase, payload.fuse = eventNumber, phase, seconds
    local ok, why = TriggerEvent("gm_events:interactPoint", payload)
    if not ok then print("[gm] gm_events:interactPoint not raised: " .. tostring(why)) end
end

function GM.interactPoints()
    local list = {}
    for _, g in pairs(groups) do
        for _, point in ipairs(g.points) do if not point.gone then list[#list + 1] = describe(g, point) end end
    end
    table.sort(list, function(x, y) return x.id < y.id end)
    return list
end

local function raise(g, phase, players)
    eventNumber = eventNumber + 1
    local left = 0
    for _, p in ipairs(g.points) do if not p.finished then left = left + 1 end end
    local ok, why = TriggerEvent("gm_events:interact", {
        seq = eventNumber, phase = phase, id = g.id, name = g.def.name, players = players or {}, left = left, total = #g.points,
    })
    if not ok then print("[gm] gm_events:interact not raised: " .. tostring(why)) end
    if phase == "used" or phase == "finished" then
        GM.moment(phase == "used" and "interactUsed" or "interactFinished", {
            id = g.id, name = g.def.name, players = players or {}, playerId = players and players[1], left = left, total = #g.points,
        })
    end
end

-- ------------------------------------------------------------------- display

local function send(point, playerId, state)
    local key = state and (state.text .. "|" .. state.percent .. "|" .. tostring(state.key)) or nil
    if point.shown[playerId] == key then return end
    point.shown[playerId] = key
    if GM.interactPrompt == "event" then state = nil end
    TriggerClientEvent("gm_events:drop", playerId, point.cardId, state or false)
end

local function hideCards(point)
    for id in pairs(point.shown) do TriggerClientEvent("gm_events:drop", id, point.cardId, false) end
    point.shown = {}
end

local function removeProp(point)
    if point.prop then GM.removeProp(point.prop) end
    point.prop = nil
end

local function removeGroup(g, quiet)
    if not alive(g) then return end
    groups[g.id] = nil
    for _, point in ipairs(g.points) do
        hideCards(point)
        removeProp(point)
        if not point.gone then
            point.gone = true
            raisePoint(g, point, "removed")
        end
    end
    if not quiet then raise(g, "ended") end
end

function GM.clearInteracts()
    local list = {}
    for _, g in pairs(groups) do list[#list + 1] = g end
    for _, g in ipairs(list) do removeGroup(g) end
end

-- What objectives ask: how many of an event's points can still be finished.
function GM.interactLeft(run)
    local left = 0
    for _, g in pairs(groups) do
        if g.run == run then
            for _, p in ipairs(g.points) do if not p.finished then left = left + 1 end end
        end
    end
    return left
end

-- A set started on its own takes over interactables already inside its radius.
function GM.adoptInteracts(run, inside)
    local found = false
    for _, g in pairs(groups) do
        if not g.run and g.bucket == run.anchor.bucket and not g.over and inside(g.points[1].at) then
            g.run, found = run, true
            run.interactSeen = true
        end
    end
    return found
end

function GM.releaseInteracts(run)
    for _, g in pairs(groups) do if g.run == run then g.run = nil end end
end

-- ------------------------------------------------------------------- results

local function alarm(g, point)
    if not g.def.squadDef or g.alarmed then return end
    g.alarmed = true
    CreateThread(function()
        Wait(math.floor(g.def.spawnDelay * 1000))
        if not alive(g) and not g.over then return end
        if g.def.arrival then GM.say("scene", g.def.arrival) end
        local site = {
            x = point.at.x, y = point.at.y, z = point.at.z, heading = g.heading, bucket = g.bucket, source = g.source, event = g.run,
        }
        g.def.squadDef.radius = math.max(8, g.def.squadDef.radius)
        local ok, why = core.actions.squad(site, { def = g.def.squadDef })
        if not ok then core.reply(g.source, nil, false, "interactable squad: " .. tostring(why)) end
    end)
end

local function blow(g, point)
    local d = g.def
    local blast, why = Open77.effects.explosion(point.at, { radius = d.blastRadius, damage = d.blastDamage, bucket = g.bucket })
    if not blast then print("[gm] interactable blast refused: " .. tostring(why)) end
    core.shake({ x = point.at.x, y = point.at.y, z = point.at.z, bucket = g.bucket })
    removeProp(point)
end

local function finishGroup(g)
    if g.over then return end
    g.over = true
    if g.def.done then GM.say("scene", g.def.done) end
    SetTimeout(150, function() raise(g, "finished") end) -- always after its "used": events sent together may swap
    -- Objectives count it for a moment longer; the things themselves stay until staff clear them.
    for _, p in ipairs(g.points) do hideCards(p) end
    if not g.def.stays then
        SetTimeout(20000, function() removeGroup(g, true) end)
    end
end

local function complete(g, point, users)
    local d, ids = g.def, {}
    for _, one in ipairs(users) do ids[#ids + 1] = one.id end
    point.progress, point.uses, point.failText = 0, point.uses + 1, nil
    point.readyAt = GetGameTimer() + d.cooldown * 1000
    if d.uses > 0 and point.uses >= d.uses then
        point.finished = true
        raisePoint(g, point, "finished")
        if g.run then g.run.interactDone = (g.run.interactDone or 0) + 1 end
    end
    core.reply(g.source, nil, true, ("%s used by player %s"):format(d.name, table.concat(ids, ", ")))
    if d.lootDef then
        if GM.lootMethod == "ground" then
            GM.lootGive(d.lootDef, "interact", d.name, nil, { x = point.at.x, y = point.at.y, z = point.at.z, bucket = g.bucket })
        else
            for _, one in ipairs(users) do GM.lootGive(d.lootDef, "interact", d.name, one.id, one.p) end
        end
    end
    if d.effect == "spark" then
        GM.burst("electric.emp.small", { x = point.at.x, y = point.at.y, z = point.at.z + 0.8 }, g.bucket, 1.5)
    elseif d.effect == "smoke" then
        GM.burst("smoke.machine", point.at, g.bucket, 12)
    elseif d.effect == "blast" then
        if d.fuse > 0 then
            point.fuseAt = GetGameTimer() + d.fuse * 1000
            raisePoint(g, point, "fuse", d.fuse)
        else
            blow(g, point)
        end
    end
    raise(g, "used", ids)
    alarm(g, point)
    if point.finished and d.effect ~= "blast" and not d.stays then removeProp(point) end
    for _, p in ipairs(g.points) do if not p.finished then return end end
    finishGroup(g)
end

-- ---------------------------------------------------------------------- tick

local function tickPoint(g, point, now, elapsed)
    local d = g.def
    if point.fuseAt then
        local left = (point.fuseAt - now) / 1000
        if left <= 0 then
            point.fuseAt = nil
            hideCards(point)
            return blow(g, point)
        end
        for _, id in ipairs(Open77.players.all()) do
            local p = Open77.players.position(id)
            local close = p and p.bucket == g.bucket and dist3(p, point.at) <= 40
            send(point, id, close and { x = point.at.x, y = point.at.y, z = point.at.z + 1.1, label = d.name,
                text = "Get clear! " .. math.ceil(left), percent = 0 } or nil)
        end
        return
    end
    if point.finished then return end
    local users, watching = {}, {}
    local ready = now >= (point.readyAt or 0)
    for _, id in ipairs(Open77.players.all()) do
        local p = Open77.players.position(id)
        local close = p and p.bucket == g.bucket and dist3(p, point.at)
        if close and close <= CARD_RANGE then
            local able = close <= REACH and not core.isGhost(id) and Open77.players.isDead(id) ~= true
            watching[#watching + 1] = { id = id, able = able }
            if able and holding[id] and ready then users[#users + 1] = { id = id, p = p } end
        else
            send(point, id, nil)
        end
    end
    if point.checking then
        point.progress = d.seconds
    elseif #users >= d.players then
        point.progress = point.progress + elapsed
    elseif point.progress > 0 then
        point.progress = math.max(0, point.progress - elapsed * 2)
    end
    if point.progress >= d.seconds and not point.checking then
        if not d.check then return complete(g, point, users) end
        -- the owner's own test decides; everything waits for its answer
        point.checking = true
        local ids = {}
        for _, one in ipairs(users) do ids[#ids + 1] = one.id end
        local payload = describe(g, point)
        payload.check, payload.playerId, payload.players = d.check, ids[1], ids
        GM.runCheck(d.check, payload, function(passed, why)
            point.checking = nil
            if not alive(g) or point.finished then return end
            point.progress = 0
            if not passed then
                point.failText, point.readyAt = why or "Failed", GetGameTimer() + 2500
                return
            end
            point.failText = nil
            local still = {}
            for _, id in ipairs(ids) do
                local p = Open77.players.position(id)
                if p and p.bucket == g.bucket and dist3(p, point.at) <= REACH + 3 and Open77.players.isDead(id) ~= true then
                    still[#still + 1] = { id = id, p = p }
                end
            end
            if #still >= d.players then complete(g, point, still) end
        end)
        return
    end
    local percent = math.min(95, math.floor(point.progress / d.seconds * 20) * 5)
    local text = d.prompt
    if point.checking then
        text, percent = "Working...", 95
    elseif not ready then
        text = point.failText or "Not ready yet"
    elseif #users > 0 and #users < d.players then
        text = ("%d of %d players"):format(#users, d.players)
    elseif d.players > 1 and #users == 0 then
        text = d.prompt .. (" (%d players)"):format(d.players)
    end
    for _, one in ipairs(watching) do
        send(point, one.id, {
            x = point.at.x, y = point.at.y, z = point.at.z + 1.1, label = d.name, text = text, percent = percent,
            key = one.able and ready and not point.checking or nil,
        })
    end
end

CreateThread(function()
    local last = GetGameTimer()
    while true do
        Wait(TICK)
        local now = GetGameTimer()
        local elapsed = math.min(1, (now - last) / 1000)
        last = now
        for _, g in pairs(groups) do
            for _, point in ipairs(g.points) do
                if alive(g) then
                    local ok, why = pcall(tickPoint, g, point, now, elapsed)
                    if not ok then print("[gm] interactable error: " .. tostring(why)) end
                end
            end
        end
    end
end)

RegisterNetEvent("gm_events:use", function(down)
    local playerId = tonumber(source)
    if playerId and playerId > 0 then holding[playerId] = down == true or nil end
end)
function GM.setHolding(playerId, down) holding[playerId] = down or nil end

AddEventHandler("onPlayerDisconnected", function(id)
    local playerId = tonumber(id)
    if not playerId then return end
    holding[playerId] = nil
    for _, g in pairs(groups) do
        for _, p in ipairs(g.points) do p.shown[playerId] = nil end
    end
end)

-- ------------------------------------------------------------------ starting

-- step.offset: how far from the centre a single point stands.
function core.actions.interact(anchor, step)
    local def, count = step.def, 0
    for _ in pairs(groups) do count = count + 1 end
    if count >= MAX_GROUPS then return false, "at most " .. MAX_GROUPS .. " interactable sets at once" end
    sequence = sequence + 1
    local g = {
        id = sequence, def = def, points = {}, run = anchor.event, bucket = anchor.bucket, heading = anchor.heading, source = anchor.source,
    }
    local props = def.model ~= "" and GetResourceState("open77_props") == "running"
    local problem = def.model ~= "" and not props and "shown without objects: they need open77_props" or nil
    local a = math.rad(anchor.heading)
    for i = 1, def.count do
        local at
        if def.count == 1 then
            local off = step.offset or 0
            at = { x = anchor.x + math.sin(a) * off, y = anchor.y - math.cos(a) * off, z = anchor.z }
        else
            local turn = (i / def.count) * 2 * math.pi + a
            at = { x = anchor.x + math.cos(turn) * def.spread, y = anchor.y + math.sin(turn) * def.spread, z = anchor.z }
        end
        local point = { at = at, cardId = "i" .. g.id .. "-" .. i, shown = {}, progress = 0, uses = 0 }
        if props then
            local id, why = GM.createProp({
                model = def.model, position = at, yaw = anchor.heading + 180, bucket = anchor.bucket, streamingRadius = 150,
            })
            if id then point.prop = id else problem = "an object was refused: " .. tostring(why) end
        end
        g.points[i] = point
    end
    groups[g.id] = g
    if g.run then g.run.interactSeen = true end
    for _, point in ipairs(g.points) do raisePoint(g, point, "placed") end
    if problem then core.reply(anchor.source, nil, false, def.name .. ": " .. problem) end
    if def.intro then GM.say("scene", def.intro) end
    return true, ("%s: %d placed"):format(def.name, def.count)
end

function GM.interactList()
    local list = {}
    for _, g in pairs(groups) do
        if not g.over then
            local done = 0
            for _, p in ipairs(g.points) do if p.finished then done = done + 1 end end
            list[#list + 1] = { id = g.id, name = g.def.name, done = done, total = #g.points }
        end
    end
    table.sort(list, function(x, y) return x.id < y.id end)
    return list
end

-- An owner's own interaction system says these players used a point.
function GM.useInteract(pointId, players)
    for _, g in pairs(groups) do
        for _, point in ipairs(g.points) do
            if point.cardId == pointId then
                if point.finished then return false, "already used" end
                if point.fuseAt or point.checking or GetGameTimer() < (point.readyAt or 0) then return false, "not ready yet" end
                local users, seen = {}, {}
                for _, value in ipairs(players) do
                    local id = math.tointeger(tonumber(value))
                    local p = id and id > 0 and not seen[id] and Open77.players.position(id) or nil
                    if p and p.bucket == g.bucket and dist3(p, point.at) <= REACH + 1.5 and not core.isGhost(id)
                        and Open77.players.isDead(id) ~= true then
                        seen[id] = true
                        users[#users + 1] = { id = id, p = p }
                    end
                end
                if #users == 0 then return false, "nobody close enough" end
                if #users < g.def.players then return false, ("%d players are needed"):format(g.def.players) end
                complete(g, point, users)
                return true
            end
        end
    end
    return false, "no such interactable"
end

function GM.endInteract(id)
    local g = groups[math.tointeger(tonumber(id)) or -1]
    if not g then return false, "that interactable is already gone" end
    removeGroup(g)
    return true, g.def.name .. " removed"
end

core.command("gm.interact", function()
    local lines = {}
    for _, i in ipairs(GM.interactList()) do lines[#lines + 1] = ("%s: %d/%d"):format(i.name, i.done, i.total) end
    return true, #lines > 0 and table.concat(lines, " | ") or "no interactables"
end)
