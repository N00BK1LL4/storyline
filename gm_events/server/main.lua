-- Server authority. Every command is restricted: callers need command.gm.* in the ACL.
local marks = {}    -- playerId -> anchor
local npcs = {}     -- tostring(npcId) -> { id, name, boss }
local vehicles = {} -- vehicleId -> true
local fires = {}    -- list of fire ids
local props = {}    -- prop id -> true
local bursts = {}   -- effect id -> true: short effects, each with its own end

-- A short effect that always ends. Never use Open77.effects.play for these: a
-- one-shot has no handle, so an effect that loops stays in the world for good.
function GM.burst(effect, position, bucket, seconds, radius)
    local id, why = Open77.effects.create({
        effect = effect, bucket = bucket, streamingRadius = radius or 250, ttlMs = math.floor(seconds * 1000),
        position = { x = position.x, y = position.y, z = position.z },
    })
    if not id then return print("[gm] effect refused: " .. effect .. " " .. tostring(why)) end
    bursts[id] = true
    SetTimeout(math.floor(seconds * 1000) + 250, function()
        if bursts[id] then
            bursts[id] = nil
            Open77.effects.remove(id) -- already gone if its lifetime ran out
        end
    end)
end

local function clearBursts()
    for id in pairs(bursts) do Open77.effects.remove(id) end
    bursts = {}
end
local runId = 0     -- gm.stop bumps this; older runs abort
local ghosts = {}   -- playerId -> what was true before ghost mode

local function reply(source, raw, ok, text)
    print("[gm] " .. text)
    if source and source > 0 then
        TriggerClientEvent("open77:command:result", source, raw or "", ok == true, text)
    end
end


-- A preset may carry its own arrival and defeat lines.
local function announceBoss(kind, template, n, percent)
    if GM.announceBosses then
        GM.say(kind, template, { boss = n.name, players = n.players or 1, percent = percent })
    end
end

local function freshPlayer(source)
    if not source or source <= 0 then return nil, "run this in-game" end
    local me = Open77.players.get(source)
    if not me or not me.position or not me.fresh then return nil, "no fresh position for you yet" end
    return me
end

-- Where things happen: the caller's mark, or `distance` metres in front of them.
local anchorOverride -- set by the panel around one synchronous call
local function anchorFor(source, distance, ignoreMark)
    if anchorOverride then return anchorOverride end
    local me, why = freshPlayer(source)
    if not me then return nil, why end
    local mark = marks[source]
    if mark and not ignoreMark and mark.bucket == (me.bucket or 0) then return mark end
    local heading = me.heading or 0
    local a = math.rad(heading)
    local d = distance or GM.eventDistance
    return {
        x = me.position.x - math.sin(a) * d,
        y = me.position.y + math.cos(a) * d,
        z = me.position.z,
        heading = heading,
        bucket = me.bucket or 0,
        source = source,
    }
end

local function point(anchor)
    return { x = anchor.x, y = anchor.y, z = anchor.z }
end

local function distanceSquared(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return dx * dx + dy * dy + dz * dz
end

-- Ghosted staff are left out so a cinematic never takes their camera.
local function audience(anchor, event, ...)
    local limit = GM.audienceRadius * GM.audienceRadius
    for _, id in ipairs(Open77.players.all()) do
        local p = not ghosts[id] and Open77.players.position(id) or nil
        if p and p.bucket == anchor.bucket and distanceSquared(p, anchor) <= limit then
            TriggerClientEvent(event, id, ...)
        end
    end
end

-- Players in the fight: same bucket, within range, not ghosted staff.
local function fighters(at, bucket)
    local radius, count = GM.scaling.radius, 0
    for _, id in ipairs(Open77.players.all()) do
        local p = not ghosts[id] and Open77.players.position(id) or nil
        if p and p.bucket == bucket and distanceSquared(p, at) <= radius * radius then count = count + 1 end
    end
    return math.max(1, math.min(GM.scaling.maxPlayers, count))
end

local function scaledHealth(base, players, noScale)
    if noScale or not GM.scaling.enabled then return base end
    return math.min(100, base * (1 + GM.scaling.perPlayer * (players - 1)))
end

-- The Chimera is another resource's NPC: reach it through its exports only.
local function chimera(method, ...)
    local ok, value, reason = pcall(Open77.exports.callSync, "open77_chimera", method, ...)
    if not ok then
        if GetResourceState("open77_chimera") ~= "running" then return nil, "open77_chimera is not installed or not running" end
        return nil, "the installed open77_chimera has no " .. method
    end
    return value, reason
end

-- One read for every kind of event NPC.
local function readNpc(n)
    if not n.chimera then return Open77.npcs.get(n.id) end
    local s = chimera("get", n.id)
    if not s then return nil end
    local health, maxHealth = s.health, s.maxHealth
    if n.defeated then health = 0 end
    -- The core is the last 1% of the real bar: show it as a bar of its own.
    if n.core and health > 0 then health, maxHealth = math.min(100, health / (s.maxHealth * 0.01) * 100), 100 end
    return {
        health = health, maxHealth = maxHealth, bucket = s.bucket,
        x = s.position.x, y = s.position.y, z = s.position.z,
        phase = s.phase, repairing = s.repairing,
    }
end

local function setNpcDifficulty(n, difficulty)
    if n.chimera then
        local state, why = chimera("setDifficulty", n.id, difficulty)
        return state ~= nil, why
    end
    return Open77.npcs.setDifficulty(n.id, difficulty)
end

local function removeNpc(n)
    if n.chimera then return chimera("remove", n.id) end
    return Open77.npcs.remove(n.id)
end

local function setNpcAttitude(n, playerId, attitude)
    if n.chimera then
        local done, why = chimera("setPlayerAttitude", n.id, playerId, attitude)
        return done == true, why
    end
    return Open77.npcs.setAttitude(n.id, attitude, { towards = { playerId = playerId } })
end

local function spawnNpc(anchor, record, dx, dy, opts)
    local id, reason = Open77.npcs.create({
        record = record,
        position = { x = anchor.x + dx, y = anchor.y + dy, z = anchor.z },
        yaw = anchor.heading + 180,
        bucket = anchor.bucket,
        aiMode = Open77.npcs.ai.native,
        damagePolicy = Open77.npcs.damage.mortal,
        -- Without this, player gunfire never hurts a mortal NPC.
        behavior = { hitPricing = "platform" },
        loadout = { combat = { group = "gm_events_hostiles", acquirePlayers = true } },
        health = 100,
        maxHealth = 100,
    })
    if not id then return nil, reason end
    local entry = { id = id, name = opts.name, boss = opts.boss, height = opts.height, outro = opts.outro, event = anchor.event,
        lootDef = opts.loot }
    npcs[tostring(id)] = entry
    GM.objectiveEnemy(entry)
    -- create only promises a server record: say so when no game ever shows the body.
    local ready = Open77.npcs.whenReady(id, 15000)
    if ready then
        -- Tell the staff member what their game actually did, and how far away it is.
        local label = opts.name or "hostile"
        ready:next(function()
            local npc, me = Open77.npcs.get(id), nil
            if anchor.source then me = Open77.players.position(anchor.source) end
            if not npc or not npcs[tostring(id)] then return end
            local where = me and (", %.0f m from you"):format(math.sqrt(distanceSquared(npc, me))) or ""
            reply(anchor.source, nil, true, label .. " is in the world" .. where)
        end, function(why)
            if npcs[tostring(id)] then
                reply(anchor.source, nil, false, label .. " (" .. record .. ") never appeared: " .. tostring(why))
                -- Objectives leave it out until some game does show it.
                local function waitForBody()
                    if npcs[tostring(id)] ~= entry then return end
                    entry.missing = true
                    local again = Open77.npcs.whenReady(id, 30000)
                    if again then again:next(function() entry.missing = nil end, function() SetTimeout(1000, waitForBody) end) end
                end
                waitForBody()
            end
        end)
    end
    for playerId in pairs(ghosts) do
        local ok, why = Open77.npcs.setAttitude(id, "friendly", { towards = { playerId = playerId } })
        if not ok then print("[gm] attitude refused: " .. tostring(why)) end
    end
    if opts.health then
        local players = fighters(anchor, anchor.bucket)
        local n = npcs[tostring(id)]
        n.baseHealth, n.players, n.noScale = opts.health, players, opts.noScale
        local ok, why = Open77.npcs.setDifficulty(id, {
            healthMultiplier = scaledHealth(opts.health, players, opts.noScale), damageMultiplier = opts.damage or 1,
        })
        if not ok then print("[gm] difficulty refused: " .. tostring(why)) end
    end
    return id
end

-- Every toolkit NPC treats a ghost as an ally; nil removes the exception.
local function setNpcsTowards(playerId, attitude)
    for _, n in pairs(npcs) do
        local ok, why = setNpcAttitude(n, playerId, attitude)
        if not ok then print("[gm] attitude refused: " .. tostring(why)) end
    end
end

-- Hide, make non-solid, make invulnerable. Returns the first refusal.
local function applyGhost(playerId)
    local problem
    local ok, why = Open77.players.setVisible(playerId, false)
    if not ok then problem = "hide refused: " .. tostring(why) end
    ok, why = Open77.players.setGhosted(playerId, true, { autoClear = false })
    if not ok then problem = problem or ("non-solid refused: " .. tostring(why)) end
    ok, why = Open77.players.setGodMode(playerId, true)
    if not ok then problem = problem or ("god mode refused: " .. tostring(why)) end
    return problem
end

local function ghostOff(playerId)
    local before = ghosts[playerId]
    if not before then return end
    ghosts[playerId] = nil
    setNpcsTowards(playerId, nil)
    if before.visible then Open77.players.setVisible(playerId, true) end
    if not before.ghosted then Open77.players.setGhosted(playerId, false) end
    if not before.god then Open77.players.setGodMode(playerId, false) end
end

local function ghostOn(playerId)
    if ghosts[playerId] then return nil end
    local health = Open77.players.getHealth(playerId)
    ghosts[playerId] = {
        visible = Open77.players.isVisible(playerId) ~= false,
        ghosted = Open77.players.isGhosted(playerId) == true,
        god = health ~= nil and health.godMode == true,
    }
    local problem = applyGhost(playerId)
    if problem then
        ghostOff(playerId) -- all or nothing: never leave staff half hidden
        return problem
    end
    setNpcsTowards(playerId, "friendly")
    return nil
end

-- The server drops invisibility on death, respawn and bucket change: put it back.
CreateThread(function()
    while true do
        Wait(1000)
        for playerId, g in pairs(ghosts) do
            if Open77.players.isVisible(playerId) ~= false then
                local problem = applyGhost(playerId)
                if problem ~= g.problem then
                    g.problem = problem
                    if problem then reply(playerId, nil, false, "ghost mode interrupted: " .. problem) end
                end
            end
        end
    end
end)

-- Late arrivals make a living boss tougher; the percentage left is kept.
CreateThread(function()
    while true do
        Wait(5000)
        for _, n in pairs(npcs) do
            if n.baseHealth and GM.scaling.enabled and not n.noScale then
                local npc = readNpc(n)
                if npc and npc.health > 0 then
                    local players = fighters(npc, npc.bucket)
                    if players > n.players then
                        local health = n.core and 100 or scaledHealth(n.baseHealth, players)
                        local ok, why = setNpcDifficulty(n, { healthMultiplier = health })
                        if ok then
                            n.players = players
                            print(("[gm] %s scaled to %d players (%.1fx health)"):format(n.name or "boss", players, health))
                        else
                            print("[gm] rescale refused: " .. tostring(why))
                        end
                    end
                end
            end
        end
    end
end)

-- server/bosshud.lua reads the registry; cleanup replaces the table, so no copies.
function GM.living() return npcs end
GM.readNpc = readNpc

local actions = {}

function actions.announce(_, step)
    return GM.say("scene", step.message and GM[step.message] or step.text)
end

function actions.boss(anchor, step)
    local preset = step.def or GM.bosses[step.preset]
    if not preset then return false, "unknown boss preset: " .. tostring(step.preset) end
    local id, reason = spawnNpc(anchor, preset.record, 0, 0, {
        name = preset.name, boss = true, health = preset.health, damage = preset.damage,
        height = preset.height, noScale = preset.scaling == false, outro = preset.outro,
        loot = preset.lootDef,
    })
    if not id then return false, "boss refused: " .. tostring(reason) end
    announceBoss("bossAppeared", preset.intro or GM.msgBossAppeared, npcs[tostring(id)])
    return true
end

function actions.wave(anchor, step)
    local count = math.max(1, math.min(GM.maxWave, math.floor(step.count or 3)))
    local made, last = 0, nil
    for i = 1, count do
        local a = (i / count) * 2 * math.pi
        local id, reason = spawnNpc(anchor, GM.minion, math.cos(a) * 6, math.sin(a) * 6, {})
        if id then made = made + 1 else last = reason end
    end
    if made == 0 then return false, "wave refused: " .. tostring(last) end
    return true, made .. " spawned"
end

function actions.chimera(anchor, step)
    local def = setmetatable(step.def or {}, { __index = GM.chimera })
    local players = fighters(anchor, anchor.bucket)
    local noScale = def.scaling == false
    local state, reason = chimera("create", {
        position = point(anchor), yaw = anchor.heading + 180, bucket = anchor.bucket, maxHealth = 100,
        difficulty = { healthMultiplier = scaledHealth(def.health, players, noScale), damageMultiplier = def.damage },
    })
    if not state then return false, "Chimera refused: " .. tostring(reason) end
    local n = {
        id = state.id, name = def.name, boss = true, chimera = true, height = def.height,
        baseHealth = def.health, baseDamage = def.damage, players = players, noScale = noScale, event = anchor.event,
        lootDef = step.def and step.def.lootDef or nil,
    }
    npcs[tostring(state.id)] = n
    GM.objectiveEnemy(n)
    for playerId in pairs(ghosts) do
        local ok, why = setNpcAttitude(n, playerId, "friendly")
        if not ok then print("[gm] attitude refused: " .. tostring(why)) end
    end
    announceBoss("bossAppeared", GM.msgBossAppeared, n)
    return true, def.name .. " created; give it a few seconds to load"
end

-- Every living Chimera this toolkit made. Some phase changes replace the NPC.
function actions.chimeraPhase(_, step)
    local done, last = 0, nil
    local list = {}
    for key, n in pairs(npcs) do
        local now = n.chimera and (not step.only or step.only == n) and chimera("get", n.id) or nil
        if now and now.alive and not n.defeated then list[#list + 1] = { key = key, n = n } end
    end
    for _, item in ipairs(list) do
        local n, state, reason = item.n, nil, nil
        if step.phase == "endrepair" then
            local now = chimera("get", n.id)
            if now and now.repairing then
                state, reason = chimera("setHealth", n.id, now.health)
            else
                reason = "not repairing"
            end
        else
            state, reason = chimera("setPhase", n.id, step.phase)
        end
        if state then
            done = done + 1
            if tostring(state.id) ~= item.key then
                npcs[item.key] = nil
                n.id, n.quarter, n.deathShown, n.settled = state.id, nil, nil, nil
                npcs[tostring(state.id)] = n
            end
        else
            last = reason
        end
    end
    if done == 0 then return false, last and ("refused: " .. tostring(last)) or "no Chimera is active" end
    return true, "Chimera: " .. step.phase
end

-- step.def = { name, units = { { record, count } }, pattern, radius }
function actions.squad(anchor, step)
    local def, list = step.def, {}
    for _, unit in ipairs(def.units) do
        for _ = 1, unit.count do
            if #list < GM.maxSquad then list[#list + 1] = unit.record end
        end
    end
    local made, last = 0, nil
    local a = math.rad(anchor.heading)
    local rightX, rightY = math.cos(a), math.sin(a)
    for i, record in ipairs(list) do
        local dx, dy
        if def.pattern == "line" then
            local along = (i - (#list + 1) / 2) * 2
            dx, dy = rightX * along, rightY * along
        else
            local turn = (i / #list) * 2 * math.pi
            -- cluster: an even spread over the disc; ring: its edge
            local r = def.pattern == "cluster" and def.radius * math.sqrt(i / #list) or def.radius
            if def.pattern == "cluster" then turn = i * 2.39996 end
            dx, dy = math.cos(turn) * r, math.sin(turn) * r
        end
        local id, reason = spawnNpc(anchor, record, dx, dy, { name = def.name, loot = def.lootDef })
        if id then made = made + 1 else last = reason end
    end
    if made == 0 then return false, "squad refused: " .. tostring(last) end
    return true, ("%s: %d of %d spawned%s"):format(def.name, made, #list, last and (", last refusal " .. tostring(last)) or "")
end

function actions.boom(anchor)
    local blast, reason = Open77.effects.explosion(point(anchor), { radius = 10, damage = 0, bucket = anchor.bucket })
    if not blast then return false, "explosion refused: " .. tostring(reason) end
    audience(anchor, "gm_events:shake")
    return true
end

function actions.fire(anchor, step)
    local id, reason = Open77.effects.fire(point(anchor), {
        radius = 4,
        damagePerSecond = 0,
        durationMs = math.floor((step.seconds or 60) * 1000),
        vfx = "fire.large",
        bucket = anchor.bucket,
    })
    if not id then return false, "fire refused: " .. tostring(reason) end
    fires[#fires + 1] = id
    return true
end

function actions.cinematic(anchor, step)
    audience(anchor, "gm_events:cinematic", anchor.x, anchor.y, anchor.z, anchor.heading, step.seconds or 6)
    return true
end

-- What flies: a vehicle, or a set of props moved together.
local function makeBody(c, at, yaw, bucket, ttlMs)
    if not c.parts then
        local id, why = Open77.vehicles.create({ record = c.record, position = at, yaw = yaw, bucket = bucket, ttlMs = ttlMs })
        if not id then return nil, why end
        vehicles[id] = true
        local frozen, problem = Open77.vehicles.setFrozen(id, true)
        if not frozen then print("[gm] freeze refused: " .. tostring(problem)) end
        return {
            seen = function()
                for _, playerId in ipairs(Open77.players.all()) do
                    local p = Open77.players.position(playerId)
                    if p and p.bucket == bucket and Open77.vehicles.isVisibleTo(id, playerId) == true then return true end
                end
                return false
            end,
            exists = function() return Open77.vehicles.get(id) ~= nil end,
            move = function(p, facing) return Open77.vehicles.setTransform(id, { x = p.x, y = p.y, z = p.z, yaw = facing }) end,
            remove = function()
                vehicles[id] = nil
                if Open77.vehicles.get(id) then Open77.vehicles.remove(id) end
            end,
            destroy = function()
                Open77.vehicles.setFrozen(id, false)
                Open77.vehicles.explode(id)
            end,
        }
    end
    if GetResourceState("open77_props") ~= "running" then return nil, "this object needs the open77_props resource" end
    local parts = {}
    local function place(part, p, facing)
        local a = math.rad(facing)
        local side = part.side or 0
        return { x = p.x + math.cos(a) * side, y = p.y + math.sin(a) * side, z = p.z + (part.up or 0) }
    end
    local function drop()
        for _, part in ipairs(parts) do
            props[part.id] = nil
            Open77.props.remove(part.id)
        end
    end
    for _, part in ipairs(c.parts) do
        local s = part.scale or 1
        local id, why = Open77.props.create({
            model = part.model, position = place(part, at, yaw), yaw = yaw, bucket = bucket, collision = false, physics = "none",
            scale = { x = s, y = s, z = s }, streamingRadius = 600, streamingHysteresis = 50, ttlMs = ttlMs,
        })
        if not id then
            drop()
            return nil, part.model .. ": " .. tostring(why)
        end
        props[id] = true
        parts[#parts + 1] = { id = id, side = part.side, up = part.up }
    end
    return {
        seen = function() return true end, -- props have no such question; loadMs covers it
        exists = function() return props[parts[1].id] == true and Open77.props.get(parts[1].id) ~= nil end,
        move = function(p, facing)
            local moved = true
            for _, part in ipairs(parts) do
                moved = Open77.props.setTransform(part.id, { position = place(part, p, facing), yaw = facing }) and moved
            end
            return moved
        end,
        destroy = drop,
        remove = drop,
    }
end

-- One fire that travels with a falling body; it can be seen from far away.
local function makeFire(at, bucket, effect)
    local id, why = Open77.effects.create({
        effect = effect, position = at, bucket = bucket, streamingRadius = 800, streamingHysteresis = 20, ttlMs = 40000,
    })
    if not id then
        print("[gm] trail refused: " .. effect .. " " .. tostring(why))
        return { move = function() end, stop = function() end }
    end
    bursts[id] = true
    return {
        move = function(p) Open77.effects.update(id, { position = { x = p.x, y = p.y, z = p.z } }) end,
        stop = function()
            bursts[id] = nil
            Open77.effects.remove(id)
        end,
    }
end

GM.makeBody, GM.makeFire = makeBody, makeFire -- server/drop.lua

-- The AV dives along a straight line and detonates at the mark. Nobody sits in
-- it, so no client simulates it: the server moves a frozen body every tick.
function actions.av(anchor, step)
    local c = GM.av
    if step and step.def then c = setmetatable(step.def, { __index = GM.av }) end
    -- The warning comes first and is off the screen before anyone arrives.
    local lead = c.warningLead or 6
    if c.warning and not (step and step.warned) then
        GM.say("scene", c.warning, {
            seconds = math.max(3, math.min(GM.announceSeconds, lead + c.flightSeconds)),
        })
        if lead > 0 then
            local run = runId
            SetTimeout(math.floor(lead * 1000), function()
                if run ~= runId then return end
                local ok, why = actions.av(anchor, { def = c, warned = true })
                if not ok then reply(anchor.source, nil, false, tostring(why)) end
            end)
            return true, ("warning sent, %s in %d s"):format(c.fall and "impact" or "AV", math.floor(lead))
        end
    end
    local heading = anchor.heading + (c.direction or 0)
    local h = math.rad(heading)
    local fx, fy = math.cos(h), math.sin(h) -- crosses the staff member's view
    local yaw = heading - 90
    local start = {
        x = anchor.x - fx * c.distance, y = anchor.y - fy * c.distance, z = anchor.z + c.height,
    }
    local body, reason = makeBody(c, start, yaw, anchor.bucket, (c.fall and c.intact and 60 or 10) * 60 * 1000)
    if not body then return false, (c.fall and c.name or "AV") .. " refused: " .. tostring(reason) end

    if c.cinematic then
        actions.cinematic(anchor, { seconds = math.min(20, c.flightSeconds + c.loadMs / 1000 + 3) })
    end

    local myRun = runId
    CreateThread(function()
        -- Visible is not the same as loaded: give the model time to build.
        local waited = 0
        while waited < 4000 and not body.seen() do
            Wait(100)
            waited = waited + 100
            if myRun ~= runId then return end
        end
        if not body.seen() then
            reply(anchor.source, nil, false, (c.fall and c.name or "AV") .. " never streamed to a player")
        end
        Wait(c.loadMs)

        local began = GetGameTimer()
        local total = c.flightSeconds * 1000
        local lastTrail, lastFire = 0, 0
        local flames = c.fall and { makeFire(start, anchor.bucket, "fire.large"), makeFire(start, anchor.bucket, "smoke.machine") } or {}
        local function out()
            for _, f in ipairs(flames) do f.stop() end
            flames = {}
        end
        local moved = 0
        while true do
            if myRun ~= runId then return out() end
            if not body.exists() then
                reply(anchor.source, nil, false, (c.fall and c.name or "AV") .. " disappeared in flight")
                return out()
            end
            local elapsed = GetGameTimer() - began
            local t = math.min(1, elapsed / total)
            local drop = t * t -- level at first, then a steepening dive
            local along = t
            if c.fall then -- a straight, accelerating plunge
                along = t ^ 1.4
                drop = along
            end
            local pos = {
                x = start.x + (anchor.x - start.x) * along,
                y = start.y + (anchor.y - start.y) * along,
                z = start.z + (anchor.z + (c.fall and 0.3 or 1) - start.z) * drop,
            }
            local facing = yaw + (c.fall and (1 - t) * (c.spin or 0) or 0)
            if not body.move(pos, facing) then
                reply(anchor.source, nil, false, (c.fall and c.name or "AV") .. " move refused")
                break
            end
            moved = moved + 1
            if c.fall then
                if elapsed - lastFire >= 60 then
                    lastFire = elapsed
                    for _, f in ipairs(flames) do f.move(pos) end
                end
                if elapsed - lastTrail >= 180 then
                    lastTrail = elapsed
                    GM.burst("fire.medium", pos, anchor.bucket, 0.9, 600)
                end
            elseif not c.fall and elapsed - lastTrail >= 400 then
                lastTrail = elapsed
                GM.burst("fire.small", pos, anchor.bucket, 1.5)
            end
            if t >= 1 then break end
            Wait(33)
        end

        out()
        if body.exists() then
            if c.fall and c.intact then
                body.move({ x = anchor.x, y = anchor.y, z = anchor.z - (c.sink or 0) }, yaw)
            else
                body.destroy()
            end
        end
        if c.fall then
            -- a ring of blasts around the main one reads as a heavy impact
            for k = 1, 4 do
                local turn = k / 4 * 2 * math.pi
                Open77.effects.explosion({ x = anchor.x + math.cos(turn) * 4, y = anchor.y + math.sin(turn) * 4, z = anchor.z },
                    { radius = 4, damage = 0, bucket = anchor.bucket })
            end
            if (c.crater or 0) > 0 then actions.crater(anchor, c) end
            if not c.intact and c.parts and GetResourceState("open77_props") == "running" then
                local wreck, whyNot = Open77.props.create({
                    model = "debris.pile", position = point(anchor), yaw = yaw, bucket = anchor.bucket, collision = false,
                    scale = { x = 2, y = 2, z = 2 }, streamingRadius = 250, ttlMs = 15 * 60 * 1000,
                })
                if wreck then props[wreck] = true else print("[gm] wreckage refused: " .. tostring(whyNot)) end
            end
        end
        local blast, blastReason = Open77.effects.explosion(point(anchor), {
            radius = c.blastRadius, damage = c.blastDamage, bucket = anchor.bucket,
        })
        if not blast then print("[gm] AV blast refused: " .. tostring(blastReason)) end
        audience(anchor, "gm_events:shake")
        if c.fall and (c.debris or 0) > 0 then actions.debris(anchor, c, myRun) end
        if c.fireSeconds > 0 then
            local lit, fireReason = actions.fire(anchor, { seconds = c.fireSeconds })
            if not lit then print("[gm] " .. tostring(fireReason)) end
        end
        reply(anchor.source, nil, true, ((c.fall and "Impact" or "AV down") .. " after %d position updates (waited %d ms to stream)"):format(moved, waited))

        -- Whoever came with the crash. The panel resolved these when it started.
        local brings = c.squadDef or c.bossDef or c.withChimera
        local run
        if c.objectivesDef then
            local why2
            run, why2 = GM.startObjectives(anchor, c.objectivesDef, true)
            if not run then reply(anchor.source, nil, false, "objectives: " .. tostring(why2)) end
        end
        if not brings then
            if run then GM.objectivesReady(run) end
            return
        end
        Wait(math.floor((c.spawnDelay or 3) * 1000))
        if myRun ~= runId then return end
        local site = { -- a copy: the mark itself must not carry the event
            x = anchor.x, y = anchor.y, z = anchor.z, heading = anchor.heading,
            bucket = anchor.bucket, source = anchor.source, event = run,
        }
        GM.say("scene", c.arrival or GM.msgCrashSurvivors)
        local function report(what, ok, why)
            if not ok then reply(anchor.source, nil, false, what .. ": " .. tostring(why)) end
        end
        local rim = c.fall and (c.crater or 0) > 0 and c.crater + 2 or 0
        if c.squadDef and rim > 0 then -- outside the rim, not inside its earth
            c.squadDef.pattern, c.squadDef.radius = "ring", math.max(c.squadDef.radius, rim + 5)
        end
        if c.squadDef then report("crash squad", actions.squad(site, { def = c.squadDef })) end
        if c.bossDef or c.withChimera then
            -- clear of the wreck, on the side the staff member was facing from
            local a, d = math.rad(anchor.heading), math.max(c.withChimera and 14 or 8, rim + 6)
            local beside = {
                x = anchor.x + math.sin(a) * d, y = anchor.y - math.cos(a) * d, z = anchor.z,
                heading = anchor.heading, bucket = anchor.bucket, source = anchor.source, event = run,
            }
            if c.bossDef then report("crash boss", actions.boss(beside, { def = c.bossDef })) end
            if c.withChimera then report("crash Chimera", actions.chimera(beside, {})) end
        end
        if run then GM.objectivesReady(run) end
    end)
    return true
end

-- The ground cannot be dug, so a crater is a rim of earth with rubble thrown out of it
-- and smoke and embers inside. Openings in the rim let players and enemies through.
function actions.crater(anchor, c)
    if GetResourceState("open77_props") ~= "running" then
        reply(anchor.source, nil, false, "no crater: it needs the open77_props resource")
        return false
    end
    local size, life = c.crater, (c.intact and 60 or 15) * 60 * 1000
    local problem
    local function put(model, turn, r, scale, up, yaw)
        local id, why = Open77.props.create({
            model = model, bucket = anchor.bucket, yaw = yaw or math.random(0, 359), collision = false, scale = scale,
            position = { x = anchor.x + math.cos(turn) * r, y = anchor.y + math.sin(turn) * r, z = anchor.z + up },
            streamingRadius = 220, ttlMs = life,
        })
        if id then props[id] = true else problem = why end
    end
    -- Two overlapping rings: a high inner lip and a lower slope outside it.
    local high = c.rim or 1
    local count = math.max(10, math.floor(2 * math.pi * size / 2.0))
    local each = 2 * math.pi * size / count
    for k = 1, count do
        if k % math.max(3, count // 3) ~= 0 then -- three ways in
            local turn = k / count * 2 * math.pi
            local s = each * (1.05 + math.random() * 0.3)
            put("debris.sand_pile", turn, size * (0.97 + math.random() * 0.06),
                { x = s, y = s, z = s * high * (0.75 + math.random() * 0.3) }, -0.1, math.deg(turn) + 90)
            local outer = turn + math.pi / count
            if (k + 1) % math.max(3, count // 3) ~= 0 then
                put("debris.sand_pile", outer, size + each * 0.75,
                    { x = s * 1.1, y = s * 1.1, z = s * high * (0.45 + math.random() * 0.2) }, -0.15, math.deg(outer) + 90)
            end
        end
    end
    local rubble = { "debris.pile", "debris.rebar", "debris.construction_pile", "debris.corrugated_sheet" }
    for k = 1, math.min(8, 3 + math.floor(size / 2)) do
        local s = 0.35 + math.random() * 0.35
        put(rubble[(k - 1) % #rubble + 1], math.random() * 2 * math.pi, size * (1.45 + math.random() * 0.7),
            { x = s, y = s, z = s }, -0.1)
    end
    if problem then reply(anchor.source, nil, false, "part of the crater was refused: " .. tostring(problem)) end
    -- it smokes for a while and goes out by itself
    GM.burst("smoke.machine", point(anchor), anchor.bucket, 90, 300)
    GM.burst("smoke.steam", { x = anchor.x, y = anchor.y, z = anchor.z + 0.5 }, anchor.bucket, 120, 200)
    for _ = 1, math.max(3, math.floor(size)) do
        local turn, r = math.random() * 2 * math.pi, math.sqrt(math.random()) * size * 0.8
        GM.burst("fire.tiny", { x = anchor.x + math.cos(turn) * r, y = anchor.y + math.sin(turn) * r, z = anchor.z + 0.05 },
            anchor.bucket, 40 + math.random(0, 40))
    end
    return true
end

-- Smaller pieces coming down around the impact. Seen and heard; they do no damage.
function actions.debris(anchor, c, myRun)
    CreateThread(function()
        for _ = 1, c.debris do
            Wait(math.random(250, 1400))
            if myRun ~= runId then return end
            local turn, r = math.random() * 2 * math.pi, (0.25 + 0.75 * math.sqrt(math.random())) * c.debrisRadius
            local at = { x = anchor.x + math.cos(turn) * r, y = anchor.y + math.sin(turn) * r, z = anchor.z }
            CreateThread(function()
                for step = 6, 1, -1 do
                    if myRun ~= runId then return end
                    GM.burst("fire.small", { x = at.x - step * 1.5, y = at.y, z = at.z + step * 9 }, anchor.bucket, 0.8, 500)
                    Wait(110)
                end
                if myRun ~= runId then return end
                local blast, why = Open77.effects.explosion(at, { radius = 4, damage = 0, bucket = anchor.bucket })
                if not blast then print("[gm] debris blast refused: " .. tostring(why)) end
                GM.burst("fire.small", at, anchor.bucket, 12)
            end)
        end
    end)
    return true
end

-- Something from the sky: the AV's flight with a steeper path and its own ending.
function actions.fall(anchor, step)
    local def = step and step.def
    if not def then
        local first = GM.fallModels[1]
        def = { name = first.name, record = first.record, parts = first.parts, distance = 60, height = 160, flightSeconds = 5, direction = 0,
            blastRadius = 14, fireSeconds = 60, debris = 5, debrisRadius = 30, spin = 120, crater = 5, sink = 0.4 }
    end
    def.fall = true
    for _, body in ipairs(GM.fallModels) do
        if body.record == def.record then def.parts = body.parts end
    end
    return actions.av(anchor, { def = def })
end

local function cleanup()
    runId = runId + 1
    for _, n in pairs(npcs) do
        if n.chimera then GM.clearWreck(n) end
        removeNpc(n)
    end
    for id in pairs(vehicles) do
        if Open77.vehicles.get(id) then Open77.vehicles.remove(id) end
    end
    for _, id in ipairs(fires) do Open77.effects.removeFire(id) end
    for id in pairs(props) do Open77.props.remove(id) end
    props = {}
    npcs, vehicles, fires = {}, {}, {}
    clearBursts()
    GM.clearObjectives()
    GM.clearLoot()
    GM.clearDrops()
    TriggerClientEvent("gm_events:release", -1)
end

local function names(t)
    local list = {}
    for k in pairs(t) do list[#list + 1] = k end
    table.sort(list)
    return table.concat(list, ", ")
end

local handlers = {}
local function command(name, handler)
    handlers[name] = handler
    RegisterCommand(name, function(source, args, raw)
        local ok, done, text = pcall(handler, source, args)
        if not ok then return reply(source, raw, false, "error: " .. tostring(done)) end
        reply(source, raw, done, text or (done and "done" or "failed"))
    end, true)
end

-- A command that runs one action at the caller's anchor.
local function placed(name, build, distance)
    command(name, function(source, args)
        local anchor, why = anchorFor(source, distance and distance())
        if not anchor then return false, why end
        local step, bad = build(args)
        if not step then return false, bad end
        return actions[step.action](anchor, step)
    end)
end

local function seconds(value, default, max)
    return math.max(1, math.min(max, tonumber(value) or default))
end

command("gm.help", function()
    return true, "gm.mark, gm.unmark, gm.announce <text>, gm.boss <" .. names(GM.bosses)
        .. ">, gm.wave <n>, gm.av, gm.fall, gm.drop, gm.boom, gm.fire <sec>, gm.cinematic <sec>, gm.scene <"
        .. names(GM.scenes) .. ">, gm.chimera, gm.gas, gm.status, gm.killboss, gm.bring, gm.clean, gm.objectives, gm.loot, gm.ghost [on|off], gm.panel, gm.check, gm.stop"
end)

command("gm.ghost", function(source, args)
    local me, why = freshPlayer(source)
    if not me then return false, why end
    local enable = not ghosts[source]
    if args[1] == "on" then enable = true elseif args[1] == "off" then enable = false end
    if not enable then
        ghostOff(source)
        return true, "ghost mode OFF: players and NPCs can see you"
    end
    local problem = ghostOn(source)
    if problem then return false, problem end
    return true, "ghost mode ON: hidden, non-solid, invulnerable, ignored by event NPCs"
end)

command("gm.mark", function(source)
    local me, why = freshPlayer(source)
    if not me then return false, why end
    marks[source] = {
        x = me.position.x, y = me.position.y, z = me.position.z,
        heading = me.heading or 0, bucket = me.bucket or 0, source = source,
    }
    return true, "marked here; step away before triggering anything"
end)

command("gm.unmark", function(source)
    marks[source] = nil
    return true, "mark cleared; events land in front of you again"
end)

command("gm.announce", function(_, args)
    local words = {}
    for i = 1, args.n or #args do words[#words + 1] = tostring(args[i]) end
    if #words == 0 then return false, "usage: gm.announce <text>" end
    return GM.say("staff", table.concat(words, " "))
end)

placed("gm.boss", function(args)
    if not GM.bosses[args[1] or ""] then return nil, "usage: gm.boss <" .. names(GM.bosses) .. ">" end
    return { action = "boss", preset = args[1] }
end, function() return GM.npcDistance end)
placed("gm.chimera", function() return { action = "chimera" } end, function() return GM.chimera.distance end)
placed("gm.wave", function(args)
    return { action = "wave", count = tonumber(args[1]) or 3 }
end, function() return GM.npcDistance + 6 end) -- the wave is a 6 m ring around this point

-- Pull every living event NPC in front of the caller.
command("gm.bring", function(source)
    local anchor, why = anchorFor(source, GM.npcDistance, true)
    if not anchor then return false, why end
    local moved, last = 0, nil
    for _, n in pairs(npcs) do
        local npc = not n.chimera and Open77.npcs.get(n.id) or nil -- the Chimera cannot be moved
        if npc and npc.bucket == anchor.bucket and npc.health > 0 then
            local ok, reason = Open77.npcs.setTransform(n.id, {
                position = { x = anchor.x + moved * 1.5, y = anchor.y, z = anchor.z },
                yaw = anchor.heading + 180,
            })
            if ok then moved = moved + 1 else last = reason end
        end
    end
    if moved == 0 then return false, "nothing to bring" .. (last and (": " .. tostring(last)) or "") end
    return true, moved .. " brought to you"
end)

placed("gm.av", function() return { action = "av" } end)
placed("gm.fall", function() return { action = "fall" } end)
placed("gm.boom", function() return { action = "boom" } end)
placed("gm.fire", function(args) return { action = "fire", seconds = seconds(args[1], 60, 600) } end)
placed("gm.cinematic", function(args) return { action = "cinematic", seconds = seconds(args[1], 6, 20) } end)

command("gm.scene", function(source, args)
    local scene = GM.scenes[args[1] or ""]
    if not scene then return false, "usage: gm.scene <" .. names(GM.scenes) .. ">" end
    local anchor, why = anchorFor(source)
    if not anchor then return false, why end
    local myRun = runId
    CreateThread(function()
        for _, step in ipairs(scene) do
            if myRun ~= runId then return end
            if step.wait then
                Wait(math.floor(step.wait * 1000))
            else
                local run = actions[step.action]
                local ok, reason = false, "unknown action"
                if run then ok, reason = run(anchor, step) end
                if not ok then
                    reply(source, nil, false, "scene step " .. tostring(step.action) .. ": " .. tostring(reason))
                end
            end
        end
    end)
    return true, "scene started; gm.stop ends it"
end)

-- What a new owner needs to know, in plain words.
command("gm.check", function(source)
    local function running(name) return GetResourceState(name) == "running" end
    local lines = { "version " .. tostring(GM.version) }
    lines[#lines + 1] = running("open77_notifications") and "notifications OK" or "PROBLEM: open77_notifications is not running"
    local how = GM.announceMethod
    if how == "chat" and not running("open77_chat") then how = how .. " PROBLEM: open77_chat is not running" end
    if how == "export" and (GM.announceResource == "-" or not running(GM.announceResource)) then
        how = how .. " PROBLEM: " .. GM.announceResource .. " is not running"
    end
    lines[#lines + 1] = "announcements by " .. how
    lines[#lines + 1] = running("op77_map3d") and "map markers OK" or "no op77_map3d: map markers off (optional)"
    lines[#lines + 1] = running("open77_chimera") and "Chimera OK" or "no open77_chimera: Chimera tab hidden (optional)"
    if running("open77_pedestrians") then
        local near = GetConvarInt("open77_pedestrians_crowd_max_near_player", 200)
            + GetConvarInt("open77_pedestrians_max_near_player", 256)
        if near > 380 then
            lines[#lines + 1] = ("WARNING: the crowd may put %d pedestrians near a player and leave no room for event NPCs; see README"):format(near)
        else
            lines[#lines + 1] = "crowd size OK (" .. near .. ")"
        end
    end
    if source and source > 0 then
        lines[#lines + 1] = Open77.acl.isAllowed(source, "gm_events.edit") == true and "you can edit presets" or "you cannot edit presets (gm_events.edit)"
    end
    return true, table.concat(lines, " | ")
end)

-- Remove the dead only; the fight goes on.
command("gm.clean", function()
    local dead = {}
    for key, n in pairs(npcs) do
        local npc = readNpc(n)
        if not npc or npc.health <= 0 then dead[key] = n end
    end
    clearBursts()
    local count = 0
    for key, n in pairs(dead) do
        npcs[key] = nil
        if n.chimera then GM.clearWreck(n) end
        removeNpc(n)
        count = count + 1
    end
    return true, count .. " bodies removed"
end)

command("gm.stop", function()
    cleanup()
    return true, "stopped and cleaned up"
end)

-- Every argument arrives as a string. Quarter marks are announced once each.
AddEventHandler("onNpcDamaged", function(npcId, from, amount, health)
    local n = npcs[tostring(npcId)]
    if not n then return end
    n.hits, n.missing = (n.hits or 0) + 1, nil
    GM.lootHit(n, from)
    n.dealt = (n.dealt or 0) + (tonumber(amount) or 0)
    local hp = tonumber(health)
    if not n.boss or not hp or hp <= 0 then return end
    for _, mark in ipairs({ 25, 50, 75 }) do
        if hp <= mark then
            if not n.quarter or mark < n.quarter then
                n.quarter = mark
                announceBoss("bossHealth", GM.msgBossHealth, n, mark)
            end
            break
        end
    end
end)

command("gm.status", function()
    local lines = {}
    for _, n in pairs(npcs) do
        local npc = readNpc(n)
        if npc and (n.boss or (n.hits or 0) > 0) then
            local line = ("%s %.1f/%.0f hp, %d hits, %.2f total damage"):format(
                n.name or "hostile", npc.health, npc.maxHealth, n.hits or 0, n.dealt or 0)
            if n.core then
                line = line .. (", core hits %d (shots %d, parts %d)"):format(n.coreHits or 0, n.coreShots or 0, n.coreParts or 0)
            end
            if n.baseHealth then
                line = line .. (", %.1fx health for %d player(s)"):format(scaledHealth(n.baseHealth, n.players, n.noScale), n.players)
            end
            lines[#lines + 1] = line
        end
    end
    if #lines == 0 then return true, "no bosses or damaged hostiles" end
    return true, table.concat(lines, " | ")
end)

-- Finish every boss, for when a fight has run long enough.
command("gm.killboss", function()
    local killed = 0
    for _, n in pairs(npcs) do
        if n.boss then
            local done
            if n.chimera then done = GM.defeatChimera(n) else done = Open77.npcs.kill(n.id, "gm") end
            if done then killed = killed + 1 end
        end
    end
    return killed > 0, killed .. " boss(es) killed"
end)

local function onDefeat(key, n, from)
    if n.settled then return end
    n.settled = true
    GM.objectiveDeath(n)
    GM.lootDeath(n, from)
    if n.boss then announceBoss("bossDefeated", n.outro or GM.msgBossDefeated, n) end
    if n.chimera and GM.deathWreckSeconds == 0 then return end -- stays until gm.clean or gm.stop
    SetTimeout((n.chimera and GM.deathWreckSeconds or GM.corpseSeconds) * 1000, function()
        if npcs[key] == n then
            npcs[key] = nil
            removeNpc(n)
        end
    end)
end

AddEventHandler("onNpcDied", function(npcId, from)
    local key = tostring(npcId)
    if npcs[key] then onDefeat(key, npcs[key], from) end
end)

-- Beat a Chimera. It is held in its collapsed state instead of killed; without
-- that export, or with the setting off, it dies the ordinary way.
function GM.defeatChimera(n)
    if n.defeated then return false end
    local s = chimera("get", n.id)
    if not s or not s.alive then return false end
    if GM.stayDown then
        if s.phase ~= "core" then
            n.core = true -- the phase loop must not start a fresh core for it
            chimera("setPhase", n.id, "core")
        end
        local held, why = chimera("holdDown", n.id)
        if held then
            n.defeated = true
            onDefeat(tostring(n.id), n)
            return true
        end
        print("[gm] Chimera cannot be held down: " .. tostring(why))
    end
    return chimera("kill", n.id) ~= nil
end

AddEventHandler("onResourceStop", function(name)
    if name ~= GetCurrentResourceName() then return end
    local active = {}
    for playerId in pairs(ghosts) do active[#active + 1] = playerId end
    for _, playerId in ipairs(active) do ghostOff(playerId) end
    cleanup()
end)

-- Ids are reused: never let the next player inherit a mark or an NPC truce.
AddEventHandler("onPlayerDisconnected", function(id)
    local playerId = tonumber(id)
    if not playerId then return end
    marks[playerId] = nil
    if ghosts[playerId] then
        ghosts[playerId] = nil
        setNpcsTowards(playerId, nil)
    end
end)

-- What server/panel.lua may use. Rights are checked there, per click.
GM.core = {
    actions = actions,
    handlers = handlers,
    command = command,
    reply = reply,
    isGhost = function(playerId) return ghosts[playerId] ~= nil end,
    mark = function(playerId) return marks[playerId] end,
    anchorFor = anchorFor,
    freshPlayer = freshPlayer,
    chimera = chimera,
    setNpcDifficulty = setNpcDifficulty,
    scaledHealth = scaledHealth,
    shake = function(anchor) audience(anchor, "gm_events:shake") end,
    withAnchor = function(anchor, fn, ...)
        anchorOverride = anchor
        local ok, a, b = pcall(fn, ...)
        anchorOverride = nil
        if not ok then return false, "error: " .. tostring(a) end
        return a, b
    end,
}

print("gm_events ready; gm.help")
