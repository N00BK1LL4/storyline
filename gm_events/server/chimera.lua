-- Gas and core for the Chimera. open77_chimera only unlocks the boss's own gas
-- ability and calls the last 1% of health "core", so in play neither is felt.
-- This runs both on the server; the provider's phases still drive everything.
local core = GM.core
local TICK = 500
local PULSE_MS, PULSE_RADIUS = 6000, 12
local clouds = {} -- npc record -> list of effect ids
local wrecks = {} -- npc record -> list of effect ids

local function clearCloud(n)
    for _, id in ipairs(clouds[n] or {}) do Open77.effects.remove(id) end
    clouds[n] = nil
end

-- Living, un-ghosted players within `radius` of the boss.
local function inside(s, radius)
    local list = {}
    for _, id in ipairs(Open77.players.all()) do
        local p = not core.isGhost(id) and Open77.players.position(id) or nil
        if p and p.bucket == s.bucket then
            local dx, dy, dz = p.x - s.position.x, p.y - s.position.y, p.z - s.position.z
            local life = Open77.players.getLifeState(id)
            if dx * dx + dy * dy + dz * dz <= radius * radius and life and life.phase == "alive" then list[#list + 1] = id end
        end
    end
    return list
end

local function hurt(list, amount)
    if amount <= 0 then return end
    for _, id in ipairs(list) do
        local ok, why = Open77.players.damage(id, amount, { cause = "environment" })
        if not ok then print("[gm] chimera damage refused for " .. id .. ": " .. tostring(why)) end
    end
end

local LOOKS = {
    chimera = [[ep1\fx\vehicles\chimera\v_chimera_gas_cloud.effect]], -- needs Phantom Liberty, as the boss does
    smoke = "smoke.machine",
    poison = "smoke.poison_gas",
}

-- Returns the effect ids of one cloud at `at` ({ x, y, z, bucket }).
local function cloud(at, look, radius, seconds)
    local ids = {}
    local function add(effect, r, count)
        for i = 1, count do
            local a = i * 2 * math.pi / count
            local id, why = Open77.effects.create({
                effect = effect, bucket = at.bucket, streamingRadius = 200, ttlMs = math.floor((seconds + 2) * 1000),
                position = { x = at.x + math.cos(a) * r, y = at.y + math.sin(a) * r, z = at.z + 0.5 },
            })
            if id then ids[#ids + 1] = id else print("[gm] gas effect refused: " .. effect .. " " .. tostring(why)) end
        end
    end
    if look == "both" or look == "chimera" then add(LOOKS.chimera, 0, 1) end
    if look == "both" or look == "smoke" then add(LOOKS.smoke, radius * 0.55, 6) end
    if look == "poison" then
        add(LOOKS.poison, 0, 1)
        add(LOOKS.poison, radius * 0.6, 4)
    end
    return ids
end

local function openCloud(n, s)
    clouds[n] = cloud({ x = s.position.x, y = s.position.y, z = s.position.z, bucket = s.bucket },
        GM.gasLook, GM.gasRadius, GM.gasSeconds)
    n.gasClouds = (n.gasClouds or 0) + 1
end

-- Look at the gas without a fight: gm.gas [both|chimera|smoke|poison]. No damage.
core.command("gm.gas", function(source, args)
    local look = args[1] or GM.gasLook
    if look ~= "both" and not LOOKS[look] then return false, "usage: gm.gas [both|chimera|smoke|poison]" end
    local anchor, why = core.anchorFor(source, 12, true)
    if not anchor then return false, why end
    local ids = cloud(anchor, look, GM.gasRadius, 10)
    SetTimeout(10000, function() for _, id in ipairs(ids) do Open77.effects.remove(id) end end)
    return #ids > 0, ("%s gas for 10 seconds (%d effects)"):format(look, #ids)
end)

local function gas(n, s, now)
    if not s.gas or not GM.gasEnabled or s.repairing or n.core then -- the core has its own attack
        if clouds[n] then clearCloud(n) end
        n.gasUntil, n.gasNext = nil, nil
        return
    end
    if n.gasUntil then
        if now >= n.gasUntil then
            clearCloud(n)
            n.gasUntil, n.gasNext = nil, now + GM.gasPause * 1000
        elseif now >= (n.gasHurt or 0) then
            n.gasHurt = now + 1000
            hurt(inside(s, GM.gasRadius), GM.gasDamage)
        end
    elseif now >= (n.gasNext or 0) then
        if not n.gasTold then
            n.gasTold = true
            GM.say("bossPhase", GM.msgChimeraGas, { boss = n.name, players = n.players })
        end
        openCloud(n, s)
        -- two seconds to get out before it bites
        n.gasHurt, n.gasUntil = now + 2000, now + GM.gasSeconds * 1000
    end
end

local function difficulty(n, inCore)
    -- In the core the game's own pricing is made negligible: coreHit decides.
    local health = inCore and 100 or core.scaledHealth(n.baseHealth, n.players, n.noScale)
    local ok, why = core.setNpcDifficulty(n, {
        healthMultiplier = math.min(100, health),
        damageMultiplier = math.min(100, n.baseDamage * (inCore and 1.4 or 1)),
    })
    if not ok then print("[gm] chimera difficulty refused: " .. tostring(why)) end
    return ok
end

-- The core takes hits, not weapon damage: weak spots stop counting in this phase
-- and the game prices hits at nothing while the boss is down.
local HIT_GAP_MS, HIT_RANGE = 50, 150

local function coreHit(n, playerId, counter)
    if not n.core or n.defeated or core.isGhost(playerId) then return end
    local now = GetGameTimer()
    if now - (n.hitAt[playerId] or -1000) < HIT_GAP_MS then return end -- pellets, and one shot seen twice
    local s = core.chimera("get", n.id)
    if not s or not s.alive or s.phase ~= "core" then return end
    local p, life = Open77.players.position(playerId), Open77.players.getLifeState(playerId)
    if not p or p.bucket ~= s.bucket or not life or life.phase ~= "alive" then return end
    local dx, dy, dz = p.x - s.position.x, p.y - s.position.y, p.z - s.position.z
    if dx * dx + dy * dy + dz * dz > HIT_RANGE * HIT_RANGE then return end
    n.hitAt[playerId] = now
    GM.lootHit(n, "player:" .. playerId)
    n[counter] = n[counter] + 1
    n.coreHits = n.coreHits + 1
    local needed = GM.coreHits * (n.noScale and 1 or core.scaledHealth(1, n.players))
    local amount = s.maxHealth * 0.01 / needed
    -- The last hit beats it; earlier ones always leave a sliver.
    if n.coreHits >= needed then return GM.defeatChimera(n) end
    amount = math.min(amount, s.health * 0.9)
    local ok, why = core.chimera("applyDamage", n.id, amount)
    if not ok then print("[gm] core hit refused: " .. tostring(why)) end
end

function GM.clearWreck(n)
    for _, id in ipairs(wrecks[n] or {}) do Open77.effects.remove(id) end
    wrecks[n] = nil
    clearCloud(n)
end

local function byId(id)
    local n = GM.living()[tostring(id)]
    return n and n.chimera and n or nil
end

-- The shooter's own game says it hit the boss; everything else is checked here.
RegisterNetEvent("gm_events:coreHit", function(id)
    local playerId = tonumber(source)
    local n = playerId and playerId > 0 and type(id) == "string" and #id <= 24 and byId(id) or nil
    if n then coreHit(n, playerId, "coreShots") end
end)

-- Weak-spot hits are admitted by the server itself.
AddEventHandler("onNpcPartHit", function(id, shooter)
    local n, playerId = byId(id), tonumber(shooter)
    if n and playerId and playerId > 0 then coreHit(n, playerId, "coreParts") end
end)

local function exposeCore(n, s, now)
    if s.phase == "core" then
        if not n.core then
            difficulty(n, true)
            n.core, n.pulseAt = true, now + 2000
            n.coreHits, n.coreShots, n.coreParts, n.hitAt = 0, 0, 0, {}
            GM.say("bossPhase", GM.msgChimeraCore, { boss = n.name, players = n.players })
        elseif now >= (n.pulseAt or 0) then
            n.pulseAt = now + PULSE_MS
            n.pulses = (n.pulses or 0) + 1
            GM.burst("electric.emp.big", { x = s.position.x, y = s.position.y, z = s.position.z + 1.5 }, s.bucket, 2)
            hurt(inside(s, PULSE_RADIUS), GM.corePulse)
        end
        return
    end
    if n.core then -- staff jumped back a phase
        n.core, n.gasTold = false, false
        difficulty(n, false)
        return
    end
    if not s.repairing and s.healthPercent <= GM.coreStart then
        -- Toughen first: the next shot could otherwise end a 1% boss.
        if difficulty(n, true) then
            local ok, why = core.actions.chimeraPhase(nil, { phase = "core", only = n })
            if not ok then print("[gm] core not started: " .. tostring(why)) end
        end
    end
end

-- The client does not always play the boss's collapse, so the death is staged
-- here. Scripted damage is zero: the fight is over.
local function deathShow(n, s)
    local at, bucket = s.position, s.bucket
    local function alive() -- gm.stop drops the record
        for _, other in pairs(GM.living()) do if other == n then return true end end
        return false
    end
    CreateThread(function()
        for i = 1, 8 do
            if not alive() then return end
            local a = i * 2.4
            local r = i == 8 and 0 or 2.5
            local p = { x = at.x + math.cos(a) * r, y = at.y + math.sin(a) * r, z = at.z + 1 + (i % 3) }
            GM.burst("electric.emp.small", p, bucket, 1.5)
            local blast, why = Open77.effects.explosion(p, { radius = 6, damage = 0, bucket = bucket })
            if not blast then print("[gm] death blast refused: " .. tostring(why)) end
            core.shake({ x = at.x, y = at.y, z = at.z, bucket = bucket })
            Wait(i < 6 and 450 or 250)
        end
        if not alive() then return end
        GM.burst("electric.emp.big", { x = at.x, y = at.y, z = at.z + 2 }, bucket, 2.5)
        local life = (GM.deathWreckSeconds == 0 and 120 or math.max(1, GM.deathWreckSeconds - 4)) * 1000 -- a wreck that stays burns for two minutes
        local ids = {}
        for _, e in ipairs({ { "fire.large", 0, 0 }, { "fire.medium", 2.5, 1 }, { "fire.medium", -2.5, -1 }, { "smoke.column.black", 0, 0 } }) do
            local id, why = Open77.effects.create({
                effect = e[1], bucket = bucket, ttlMs = life, streamingRadius = 250,
                position = { x = at.x + e[2], y = at.y + e[3], z = at.z + 0.5 },
            })
            if id then ids[#ids + 1] = id else print("[gm] wreck effect refused: " .. tostring(why)) end
        end
        n.wreck = ids
        wrecks[n] = ids
    end)
end

CreateThread(function()
    while true do
        Wait(TICK)
        local now, seen = GetGameTimer(), {}
        local list = {}
        for _, n in pairs(GM.living()) do
            if n.chimera then list[#list + 1] = n end
        end
        for _, n in ipairs(list) do
            local s = core.chimera("get", n.id)
            if s and s.alive and not n.defeated then
                seen[n] = true
                exposeCore(n, s, now)
                gas(n, s, now)
            elseif s and not n.deathShown then
                n.deathShown = true
                if GM.deathShow then deathShow(n, s) end
            end
        end
        for n, ids in pairs(wrecks) do
            local there = false
            for _, other in ipairs(list) do there = there or other == n end
            if not there then
                for _, id in ipairs(ids) do Open77.effects.remove(id) end
                wrecks[n] = nil
            end
        end
        for n in pairs(clouds) do
            if not seen[n] then clearCloud(n) end
        end
    end
end)

-- A player's game could not show part of the Chimera. Log only, rate limited.
local errors = {} -- playerId -> count
RegisterNetEvent("gm_events:chimeraError", function(line)
    local playerId = tonumber(source)
    if not playerId or playerId <= 0 or type(line) ~= "string" or #line > 200 then return end
    errors[playerId] = (errors[playerId] or 0) + 1
    if errors[playerId] > 40 then return end
    print(("[gm] chimera client problem, player %d: %s"):format(playerId, (line:gsub("[%c]", " "))))
end)

AddEventHandler("onPlayerDisconnected", function(id)
    local playerId = tonumber(id)
    if playerId then errors[playerId] = nil end
end)
