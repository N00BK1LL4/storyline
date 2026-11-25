-- Objective sets: given to players who enter a radius, shared by everyone in it.
-- The server decides everything from its own positions and deaths; clients only draw.
--
-- gm_events:objectives is raised for owners' rewards and logs:
--   { phase, id, name, players = { { id, seconds } }, playerId?, index?, text?, reason? }
-- phase: started, entered, left, objective, completed, failed, ended (stopped by staff)
local MAX_RUNS = 5
local RISE = 40 -- metres above or below the centre that still count as inside
local core = GM.core

local runs = {}       -- id -> run
local memberOf = {}   -- playerId -> run
local sent = {}       -- playerId -> last text sent
local sequence = 0

local function online()
    local set = {}
    for _, id in ipairs(Open77.players.all()) do set[id] = true end
    return set
end

local function flat(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy), math.abs(a.z - b.z)
end

local function within(p, at, radius)
    local d, dz = flat(p, at)
    return d <= radius and dz <= RISE
end

local function clock(seconds)
    seconds = math.max(0, math.ceil(seconds))
    return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

-- Everyone still online who took part, with the seconds they spent inside and alive.
local function participants(run)
    local list = {}
    local here = online()
    -- Ids are reused: someone who left the server, even for a moment, starts over.
    for id in pairs(run.credit) do if not here[id] then run.credit[id] = nil end end
    for id, seconds in pairs(run.credit) do list[#list + 1] = { id = id, seconds = math.floor(seconds) } end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

local eventNumber = 0 -- events sent together may arrive swapped: owners can sort by seq
local function raise(run, phase, extra)
    eventNumber = eventNumber + 1
    local payload = { seq = eventNumber, phase = phase, id = run.id, name = run.def.name, players = participants(run) }
    for k, v in pairs(extra or {}) do payload[k] = v end
    local ok, why = TriggerEvent("gm_events:objectives", payload)
    if not ok then print("[gm] gm_events:objectives not raised: " .. tostring(why)) end
end

-- ------------------------------------------------------------------- enemies

local function enemyCount(run)
    local present, alive, dead, bosses, waiting = {}, 0, 0, 0, 0
    for _, n in pairs(GM.living()) do present[n] = true end
    for n, fate in pairs(run.enemies) do
        if fate == "dead" then
            dead = dead + 1
        elseif not present[n] then
            run.enemies[n] = nil -- cleaned up: no longer part of the total
        elseif n.missing then -- a body no game has shown is not counted against players
            waiting = waiting + 1
            if n.boss then bosses = bosses + 1 end -- but a boss is never skipped
        else
            alive = alive + 1
            if n.boss then bosses = bosses + 1 end
        end
    end
    if alive == 0 and dead == 0 then alive = waiting end -- nothing has shown yet: nothing is won
    return alive, dead, bosses
end

-- Called by main.lua for every NPC that carries an event, and for every death.
function GM.objectiveEnemy(n)
    if n.event and runs[n.event.id] == n.event then n.event.enemies[n] = "alive" end
end

function GM.objectiveDeath(n)
    for _, run in pairs(runs) do
        if run.enemies[n] then run.enemies[n] = "dead" end
    end
end

-- ------------------------------------------------------------------ the types

-- Each returns note, finished. `here` is the list of living members inside.
local types = {}

function types.enemies(run, item)
    local alive, dead = enemyCount(run)
    item.need = alive + dead
    item.progress = dead
    return dead .. "/" .. item.need, not run.pending and alive == 0
end

function types.kill(run, item)
    local alive, dead = enemyCount(run)
    item.need = run.pending and item.def.count or math.min(item.def.count, alive + dead)
    item.progress = math.min(dead, item.need)
    return item.progress .. "/" .. item.need, not run.pending and dead >= item.need
end

function types.boss(run)
    local _, _, bosses = enemyCount(run)
    return "", not run.pending and bosses == 0
end

function types.reach(run, item, here)
    for _, m in ipairs(here) do
        if within(m.p, item.point, item.def.size) then return "", true end
    end
    local nearest
    for _, m in ipairs(here) do
        local d = flat(m.p, item.point)
        nearest = math.min(nearest or d, d)
    end
    return nearest and ("%d m"):format(math.floor(nearest)) or "", false
end

function types.hold(run, item, here, elapsed)
    local count = 0
    for _, m in ipairs(here) do
        if within(m.p, item.point, item.def.size) then count = count + 1 end
    end
    local enough = count >= item.def.players
    if enough then item.progress = item.progress + elapsed end
    local note = ("%d/%d s"):format(math.floor(math.min(item.progress, item.def.seconds)), item.def.seconds)
    if item.def.players > 1 then note = note .. (", %d/%d players"):format(count, item.def.players) end
    return note, item.progress >= item.def.seconds
end

function types.survive(run, item, here, elapsed)
    if #here > 0 then item.progress = item.progress + elapsed end
    return clock(item.def.seconds - item.progress), item.progress >= item.def.seconds
end

function types.custom(_, item) return item.hookNote or "", false end

function types.interact(run, item)
    local done, left = run.interactDone or 0, GM.interactLeft(run)
    local need = math.min(item.def.count, done + left)
    item.progress = math.min(done, need)
    return item.progress .. "/" .. need, not run.pending and run.interactSeen == true and done > 0 and done >= need
end

-- An owner's own kind: their resource is told when it starts and says when it is done.
local function hookEvent(run, i, phase)
    local item = run.items[i]
    local at = item.point or run.anchor
    eventNumber = eventNumber + 1
    local players = {}
    for id in pairs(run.members) do players[#players + 1] = id end
    table.sort(players)
    local ok, why = TriggerEvent("gm_events:objectiveHook", {
        seq = eventNumber, phase = phase, hook = item.def.hook, id = run.id, index = i, name = run.def.name, text = item.text,
        players = players, position = { x = at.x, y = at.y, z = at.z, bucket = run.anchor.bucket }, radius = run.def.radius,
    })
    if not ok then print("[gm] gm_events:objectiveHook not raised: " .. tostring(why)) end
end

local function stopHooks(run)
    for i, item in ipairs(run.items) do
        if item.hooked then
            item.hooked = nil
            hookEvent(run, i, "stop")
        end
    end
end

function types.hook(run, item)
    if not item.hooked and run.firstEntry then
        item.hooked = true
        for i, other in ipairs(run.items) do if other == item then hookEvent(run, i, "start") end end
    end
    return item.hookNote or "", item.hookDone == true
end

function GM.patchObjective(id, index, patch)
    local run = runs[math.tointeger(tonumber(id)) or -1]
    if not run or run.outcome then return false, "that set has already ended" end
    local i = math.tointeger(tonumber(index)) or 0
    local item = run.items[i]
    if not item then return false, "no such objective" end
    if item.def.type ~= "hook" and item.def.type ~= "custom" then return false, "only hooked and custom objectives can be set" end
    if item.done then return false, "already done" end
    if not item.active then return false, "it is not this objective's turn yet" end
    if type(patch.note) == "string" then
        local note = patch.note:gsub("[%c<>]", ""):sub(1, 40)
        item.hookNote = utf8.len(note) and note or item.hookNote
    end
    if patch.done == true then
        if item.def.type == "hook" then item.hookDone = true else GM.tickObjective(run, i) end
    end
    return true
end

-- Why a set cannot start now, because an owner's resource is not there.
function GM.hooksMissing(def)
    for _, o in ipairs(def.items) do
        if o.type == "hook" and not GM.hookType(o.hook) then return o.hook .. " is not registered (is its resource running?)" end
    end
end

local usual = {
    enemies = "Defeat the enemies", kill = "Take out hostiles", boss = "Defeat the boss",
    reach = "Reach the location", hold = "Hold the area", survive = "Survive", interact = "Use the objects",
}
GM.objectiveTypes = { enemies = true, kill = true, boss = true, reach = true, hold = true, survive = true, interact = true, custom = true, hook = true }

-- -------------------------------------------------------------------- display

local showing = {} -- playerId -> our own tracker is up
local function showTo(playerId, state, key)
    if sent[playerId] == key then return end
    sent[playerId] = key
    if GM.objectiveDisplay == "event" then
        eventNumber = eventNumber + 1
        local ok, why = TriggerEvent("gm_events:objectiveState", { seq = eventNumber, playerId = playerId, state = state })
        if not ok then print("[gm] gm_events:objectiveState not raised: " .. tostring(why)) end
        state = false -- and nothing of ours on the screen
        if showing[playerId] then
            showing[playerId] = nil
            TriggerClientEvent("gm_events:objectives", playerId, false)
        end
        return
    end
    showing[playerId] = state ~= false or nil
    TriggerClientEvent("gm_events:objectives", playerId, state)
end

local function hide(playerId)
    if sent[playerId] then showTo(playerId, false, nil) end
end

local function currentPoint(run)
    for _, item in ipairs(run.items) do
        if not item.done and item.active then return item.point or run.anchor, item.text end
    end
    return run.anchor, run.def.name
end

local function map(method, ...)
    local ok, value = pcall(Open77.exports.callSync, "op77_map3d", method, ...)
    return ok and value or nil
end

-- The 3D map marker, for members only. Players without that map get the game's own.
local function updateMap(run, native)
    local point, text = currentPoint(run)
    local ids = {}
    if not native and not run.outcome and run.anchor.bucket == 0 then
        for id in pairs(run.members) do ids[#ids + 1] = id end
        table.sort(ids)
    end
    local key = #ids > 0 and (table.concat(ids, ",") .. ("|%.1f|%.1f|"):format(point.x, point.y) .. text) or nil
    if key == run.mapKey then return end
    run.mapKey = key
    if not key then
        if run.mapBlip then map("removeBlip", run.mapBlip) end
        run.mapBlip = nil
        return
    end
    run.mapBlip = map("addBlip", ids, {
        id = "objective-" .. run.id, position = { x = point.x, y = point.y, z = point.z },
        icon = "target", color = "#FFD23D", label = text, description = run.def.name, pulse = true, edge = true, scale = 1.3,
    })
end

local function stateFor(run, m, now, native)
    local items, key = {}, {}
    for i, item in ipairs(run.items) do
        -- in order: later ones stay hidden until it is their turn
        if item.done or item.active then
            items[#items + 1] = { text = item.text, note = item.done and "" or item.note, done = item.done }
        end
        key[i] = item.text .. (item.done and "x" or item.active and item.note or "-")
    end
    local status = ""
    if run.outcome == "completed" then status = "EVENT COMPLETE"
    elseif run.outcome == "failed" then status = "EVENT FAILED"
    elseif m.outSince then
        status = "RETURN TO THE AREA  " .. clock(GM.objectiveGrace - (now - m.outSince) / 1000)
    end
    local time = ""
    if run.deadline and not run.outcome then time = clock((run.deadline - now) / 1000) end
    local point, label = currentPoint(run)
    local marker
    if (native or GM.objectiveDisplay == "event") and not run.outcome then marker = { x = point.x, y = point.y, z = point.z, label = label } end
    local state = {
        title = run.def.name, status = status, time = time, items = items,
        outcome = run.outcome or "active", away = m.outSince ~= nil, marker = marker,
    }
    return state, table.concat({
        run.id, status, time, run.outcome or "", table.concat(key, ";"),
        marker and ("%.1f,%.1f"):format(point.x, point.y) or "",
    }, "|")
end

local function refresh(run, now, native)
    for id, m in pairs(run.members) do
        local state, key = stateFor(run, m, now, native)
        -- Sent again every few seconds: a client may have been loading.
        m.beats = (m.beats or 0) + 1
        if m.beats >= 10 and GM.objectiveDisplay ~= "event" then m.beats, sent[id] = 0, nil end
        showTo(id, state, key)
    end
    updateMap(run, native or GM.objectiveDisplay == "event")
end

-- ----------------------------------------------------------------- membership

local function leave(run, playerId, quiet)
    if not run.members[playerId] then return end
    run.members[playerId] = nil
    memberOf[playerId] = nil
    hide(playerId)
    if not quiet then raise(run, "left", { playerId = playerId }) end
end

local function enter(run, playerId, now)
    run.members[playerId] = {}
    memberOf[playerId] = run
    run.credit[playerId] = run.credit[playerId] or 0
    if not run.firstEntry then
        run.firstEntry = now
        if run.def.timeLimit > 0 then run.deadline = now + run.def.timeLimit * 1000 end
    end
    raise(run, "entered", { playerId = playerId })
end

local function updateMembers(now, elapsed)
    local here = online()
    local gone = {}
    for _, run in pairs(runs) do
        for id in pairs(run.credit) do if not here[id] then run.credit[id] = nil end end
    end
    for id in pairs(memberOf) do
        if not here[id] or core.isGhost(id) then gone[#gone + 1] = id end
    end
    for _, id in ipairs(gone) do
        if not here[id] then sent[id] = nil end -- nobody there to tell
        leave(memberOf[id], id)
    end

    for id in pairs(here) do
        -- An unreadable position pauses the player; it never counts as leaving.
        local p = not core.isGhost(id) and Open77.players.position(id) or nil
        local run = memberOf[id]
        if run and not p then
            run.members[id].inside = false
        elseif run and not run.outcome then
            local m = run.members[id]
            m.p, m.dead = p, Open77.players.isDead(id) == true
            local edge = run.def.radius + math.max(3, run.def.radius * 0.05)
            m.inside = p.bucket == run.anchor.bucket and within(p, run.anchor, edge)
            if m.inside or m.dead then -- the dead may respawn elsewhere: no countdown yet
                m.outSince = nil
                if m.inside and not m.dead then run.credit[id] = (run.credit[id] or 0) + elapsed end
            else
                m.outSince = m.outSince or now
                if now - m.outSince >= GM.objectiveGrace * 1000 then leave(run, id) end
            end
        elseif p and not run then
            local best, bestD
            for _, candidate in pairs(runs) do
                if not candidate.outcome and p.bucket == candidate.anchor.bucket
                    and within(p, candidate.anchor, candidate.def.radius) then
                    local d = flat(p, candidate.anchor)
                    if not bestD or d < bestD then best, bestD = candidate, d end
                end
            end
            if best and Open77.players.isDead(id) ~= true then
                enter(best, id, now)
                local m = best.members[id]
                m.p, m.inside, m.dead = p, true, false
            end
        end
    end
end

-- -------------------------------------------------------------------- outcome

local function remove(run)
    stopHooks(run)
    for id in pairs(run.members) do leave(run, id, true) end
    if run.mapBlip then map("removeBlip", run.mapBlip) end
    runs[run.id] = nil
end

local function finish(run, outcome, reason)
    if run.outcome then return end
    run.outcome, run.endsAt = outcome, GetGameTimer() + 6000
    stopHooks(run)
    for _, m in pairs(run.members) do m.outSince = nil end
    GM.say("scene", outcome == "completed" and run.def.success or run.def.failure)
    print(("[gm] objectives '%s' %s%s"):format(run.def.name, outcome, reason and (": " .. reason) or ""))
    raise(run, outcome, { reason = reason })
    if outcome == "completed" and run.def.lootDef then GM.lootObjectives(run.def.lootDef, run.def.name, participants(run)) end
end

local function markDone(run, i)
    local item = run.items[i]
    if item.done then return end
    item.done, item.note = true, ""
    if item.hooked then
        item.hooked = nil
        hookEvent(run, i, "stop")
    end
    raise(run, "objective", { index = i, text = item.text })
end

local function updateItems(run, elapsed)
    local here, members, dead = {}, 0, 0
    for id, m in pairs(run.members) do
        members = members + 1
        if m.dead then dead = dead + 1 elseif m.inside and m.p then here[#here + 1] = m end
    end
    local open = 0
    for i, item in ipairs(run.items) do
        if not item.done then
            -- nothing moves before the first player arrives
            item.active = not run.def.ordered or open == 0
            if item.active then
                local note, finished = types[item.def.type](run, item, here, elapsed)
                item.note = note
                if finished and run.firstEntry then markDone(run, i) end
            end
            if not item.done then open = open + 1 end
        end
    end
    if open == 0 then return finish(run, "completed") end
    local now = GetGameTimer()
    if run.deadline and now >= run.deadline then return finish(run, "failed", "time ran out") end
    if run.def.failOnWipe and members > 0 and dead == members then
        run.wipedSince = run.wipedSince or now
        if now - run.wipedSince >= 3000 then return finish(run, "failed", "everyone is down") end
    else
        run.wipedSince = nil
    end
end

-- ------------------------------------------------------------------- starting

function GM.canStartObjectives()
    local count = 0
    for _ in pairs(runs) do count = count + 1 end
    if count >= MAX_RUNS then return false, "at most " .. MAX_RUNS .. " objective sets can run at once" end
    return true
end

-- comes: what the event brings, { enemies = bool, boss = bool }; nil when started
-- on its own, where event NPCs already standing in the area are used instead.
-- Returns why the set could never be finished, or nil.
local function impossible(def, comes)
    for _, o in ipairs(def.items) do
        if (o.type == "enemies" or o.type == "kill") and not comes.enemies then
            return "this set needs enemies, and none come with it"
        end
        if o.type == "interact" and not comes.interact then return "this set needs an interactable, and none comes with it" end
        if o.type == "boss" and not comes.boss then return "this set needs a boss, and none comes with it" end
    end
end
GM.objectivesImpossible = impossible

-- pending: enemies are still on their way, so nothing about them may finish yet.
function GM.startObjectives(anchor, def, pending)
    local can, full = GM.canStartObjectives()
    if not can then return nil, full end
    local missing = GM.hooksMissing(def)
    if missing then return nil, missing end
    sequence = sequence + 1
    local run = {
        id = sequence, def = def, pending = pending == true, members = {}, credit = {}, enemies = {}, items = {},
        anchor = { x = anchor.x, y = anchor.y, z = anchor.z, bucket = anchor.bucket },
    }
    if not pending then
        local comes = {}
        for _, n in pairs(GM.living()) do
            local npc = not n.event and not n.settled and GM.readNpc(n) or nil
            if npc and npc.health > 0 and npc.bucket == anchor.bucket and within(npc, anchor, def.radius) then
                run.enemies[n] = "alive"
                comes.enemies = true
                comes.boss = comes.boss or n.boss
            end
        end
        comes.interact = GM.adoptInteracts(run, function(at) return within(at, anchor, def.radius) end)
        local why = impossible(def, comes)
        if why then
            GM.releaseInteracts(run)
            return nil, "what this set needs (enemies, a boss or an interactable) is not inside the radius yet"
        end
    end
    for i, o in ipairs(def.items) do
        local item = { def = o, text = o.text or usual[o.type] or (o.type == "hook" and GM.hookType(o.hook).label) or o.type, note = "", progress = 0 }
        if o.type == "reach" or o.type == "hold" then
            -- direction 0 is straight ahead of the staff member, 90 to their right
            local a = math.rad(anchor.heading - (o.direction or 0))
            local d = math.min(o.distance or 0, def.radius)
            item.point = { x = anchor.x - math.sin(a) * d, y = anchor.y + math.cos(a) * d, z = anchor.z }
        end
        run.items[i] = item
    end
    runs[run.id] = run
    GM.say("scene", def.intro)
    raise(run, "started")
    return run
end

-- Everything has spawned. If what a set needs did not, it could only be won for
-- nothing, so it ends instead.
function GM.objectivesReady(run)
    run.pending = false
    local comes = { interact = run.interactSeen }
    for n in pairs(run.enemies) do
        comes.enemies = true
        comes.boss = comes.boss or n.boss
    end
    local why = impossible(run.def, comes)
    if why then
        print("[gm] objectives '" .. run.def.name .. "' ended: " .. why)
        GM.cancelObjectives(run)
    end
end

-- Nothing spawned after all.
function GM.cancelObjectives(run)
    if runs[run.id] ~= run then return end
    raise(run, "ended")
    remove(run)
end

function GM.clearObjectives()
    local list = {}
    for _, run in pairs(runs) do list[#list + 1] = run end
    for _, run in ipairs(list) do
        if not run.outcome then raise(run, "ended") end
        remove(run)
    end
end

function core.actions.objectives(anchor, step)
    local run, why = GM.startObjectives(anchor, step.def)
    if not run then return false, why end
    return true, ("%s: active within %d m"):format(step.def.name, step.def.radius)
end

-- --------------------------------------------------------------------- staff

function GM.objectiveList()
    local list, now = {}, GetGameTimer()
    for _, run in pairs(runs) do
        local items, players = {}, 0
        for i, item in ipairs(run.items) do
            items[i] = { type = item.def.type, hook = item.def.hook, text = item.text, note = item.note, done = item.done == true, active = item.active == true }
        end
        for _ in pairs(run.members) do players = players + 1 end
        list[#list + 1] = {
            id = run.id, name = run.def.name, players = players, items = items, outcome = run.outcome or "",
            time = run.deadline and not run.outcome and clock((run.deadline - now) / 1000) or "",
        }
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

function GM.tickObjective(run, i) markDone(run, i) end

function GM.controlObjectives(id, what, index)
    local run = runs[math.tointeger(tonumber(id)) or -1]
    if not run or run.outcome then return false, "that set has already ended" end
    if what == "tick" then
        local i = math.tointeger(tonumber(index)) or 0
        if not run.items[i] then return false, "no such objective" end
        if run.items[i].done then return false, "already done" end
        markDone(run, i)
        return true, "ticked: " .. run.items[i].text
    elseif what == "complete" then
        finish(run, "completed", "staff")
        return true, run.def.name .. " completed"
    elseif what == "fail" then
        finish(run, "failed", "staff")
        return true, run.def.name .. " failed"
    elseif what == "end" then
        GM.cancelObjectives(run)
        return true, run.def.name .. " ended"
    end
    return false, "unknown button"
end

AddEventHandler("onPlayerDisconnected", function(id)
    local playerId = tonumber(id)
    if not playerId then return end
    sent[playerId] = nil
    if memberOf[playerId] then leave(memberOf[playerId], playerId) end
    for _, run in pairs(runs) do run.credit[playerId] = nil end
end)

core.command("gm.objectives", function()
    local lines = {}
    for _, r in ipairs(GM.objectiveList()) do
        local done = 0
        for _, item in ipairs(r.items) do if item.done then done = done + 1 end end
        lines[#lines + 1] = ("%s: %d/%d done, %d player(s)%s"):format(
            r.name, done, #r.items, r.players, r.outcome ~= "" and (", " .. r.outcome) or "")
    end
    return true, #lines > 0 and table.concat(lines, " | ") or "no objectives are running"
end)

local function tick(now, elapsed)
    updateMembers(now, elapsed)
    local native = GetResourceState("op77_map3d") ~= "running"
    local list = {}
    for _, run in pairs(runs) do list[#list + 1] = run end
    for _, run in ipairs(list) do
        if run.outcome and now >= run.endsAt then
            remove(run)
        else
            if not run.outcome then updateItems(run, elapsed) end
            refresh(run, now, native)
        end
    end
end

CreateThread(function()
    local last = GetGameTimer()
    while true do
        Wait(500)
        local now = GetGameTimer()
        local elapsed = math.min(2, (now - last) / 1000) -- a stalled server never gives free progress
        last = now
        if next(runs) then
            local ok, why = pcall(tick, now, elapsed)
            if not ok then print("[gm] objectives error: " .. tostring(why)) end
        end
    end
end)
