-- Supply drops: an AV flies over and lets a crate go, it comes down gently and hovers
-- where it lands until players open it by standing next to it.
local core = GM.core
local MAX_DROPS, OPEN_RANGE, SHARE_RANGE, CARD_RANGE = 4, 3.5, 12, 70
local TICK = 50

local drops = {} -- id -> drop
local sequence = 0

local function running(d) return drops[d.id] == d end

local function dist3(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end

-- Players who may open it: alive, not ghosted, same world.
local function near(d, range)
    local list = {}
    for _, id in ipairs(Open77.players.all()) do
        local p = not core.isGhost(id) and Open77.players.position(id) or nil
        if p and p.bucket == d.anchor.bucket and dist3(p, d.at) <= range and Open77.players.isDead(id) ~= true then
            list[#list + 1] = { id = id, p = p }
        end
    end
    return list
end

local function card(d, text, percent)
    for _, id in ipairs(Open77.players.all()) do
        local p = Open77.players.position(id)
        local close = p and p.bucket == d.anchor.bucket and dist3(p, d.at) <= CARD_RANGE
        local key = close and (text .. percent) or nil
        if d.shown[id] ~= key then
            d.shown[id] = key
            TriggerClientEvent("gm_events:drop", id, d.id, close and {
                x = d.at.x, y = d.at.y, z = d.at.z + 1.6, label = d.def.name, text = text, percent = percent,
            } or false)
        end
    end
end

local function hideCard(d)
    for id in pairs(d.shown) do TriggerClientEvent("gm_events:drop", id, d.id, false) end
    d.shown = {}
end

local function remove(d)
    if not running(d) then return end
    drops[d.id] = nil
    hideCard(d)
    if d.flare then d.flare.stop() end
    if d.crate then d.crate.remove() end
    if d.av then d.av.remove() end
end

function GM.clearDrops()
    local list = {}
    for _, d in pairs(drops) do list[#list + 1] = d end
    for _, d in ipairs(list) do remove(d) end
end

local function moment(d, id, players)
    GM.moment(id, {
        kind = "drop", name = d.def.name, players = players or {}, playerId = players and players[1],
        position = { x = d.anchor.x, y = d.anchor.y, z = d.anchor.z, bucket = d.anchor.bucket },
    })
end

local function open(d, by)
    local names = {}
    if d.def.lootDef then
        if GM.lootMethod == "ground" then
            GM.lootGive(d.def.lootDef, "drop", d.def.name, nil, { x = d.at.x, y = d.at.y, z = d.ground, bucket = d.anchor.bucket })
        else
            for _, one in ipairs(d.def.share == "opener" and { by } or near(d, SHARE_RANGE)) do
                GM.lootGive(d.def.lootDef, "drop", d.def.name, one.id, one.p)
                names[#names + 1] = one.id
            end
        end
    end
    core.reply(d.anchor.source, nil, true, d.def.name .. " opened by player " .. by.id .. (#names > 1 and (", shared by " .. #names) or ""))
    GM.say("scene", d.def.opened)
    moment(d, "dropOpened", #names > 0 and names or { by.id })
    GM.burst("electric.emp.small", d.at, d.anchor.bucket, 1.5)
end

-- What came with it, and what it is for.
local function land(d)
    local def, anchor = d.def, d.anchor
    local run
    if def.objectivesDef then
        local why
        run, why = GM.startObjectives(anchor, def.objectivesDef, true)
        if not run then core.reply(anchor.source, nil, false, "objectives: " .. tostring(why)) end
    end
    if def.arrival then GM.say("scene", def.arrival) end
    if not (def.squadDef or def.bossDef or def.withChimera or def.interactDef) then
        if run then GM.objectivesReady(run) end
        return
    end
    CreateThread(function()
        Wait(math.floor((def.spawnDelay or 3) * 1000))
        if not running(d) and not d.opened then
            if run then GM.cancelObjectives(run) end
            return
        end
        local site = { heading = anchor.heading, bucket = anchor.bucket, source = anchor.source, event = run }
        local function at(distance)
            local a = math.rad(anchor.heading)
            site.x, site.y, site.z = anchor.x + math.sin(a) * distance, anchor.y - math.cos(a) * distance, anchor.z
            return site
        end
        local function report(what, ok, why)
            if not ok then core.reply(anchor.source, nil, false, what .. ": " .. tostring(why)) end
        end
        if def.interactDef then
            local here = at(0)
            report("interactable", core.actions.interact(here, { def = def.interactDef, offset = 5 }))
        end
        if def.squadDef then report("drop squad", core.actions.squad(at(0), { def = def.squadDef })) end
        if def.bossDef then report("drop boss", core.actions.boss(at(8), { def = def.bossDef })) end
        if def.withChimera then report("drop Chimera", core.actions.chimera(at(14), {})) end
        if run then GM.objectivesReady(run) end
    end)
end

-- Standing close opens it; walking off lets the progress run back.
local function hover(d)
    local def = d.def
    local began, last, beat = GetGameTimer(), GetGameTimer(), 0
    local progress = {}
    while running(d) do
        Wait(TICK)
        if not running(d) then return end
        local now = GetGameTimer()
        local dt = math.min(0.5, (now - last) / 1000)
        last = now
        local age = (now - began) / 1000
        if not d.crate.exists() then
            core.reply(d.anchor.source, nil, false, def.name .. " disappeared")
            return remove(d)
        end
        beat = beat + 1
        local watched = beat % 20 == 1 and #near(d, 120) > 0 or (beat % 20 ~= 1 and d.watched)
        d.watched = watched
        if watched then -- it only needs to bob while somebody can see it
            d.at.z = d.ground + def.hover + math.sin(age * 1.6) * 0.12
            d.crate.move(d.at, (d.yaw + age * 18) % 360)
        end
        if beat % 5 == 0 then
            local step = dt * 5
            local here, best, bestValue = {}, nil, 0
            for _, one in ipairs(near(d, OPEN_RANGE + def.hover)) do
                here[one.id] = true
                progress[one.id] = (progress[one.id] or 0) + step
                if progress[one.id] > bestValue then best, bestValue = one, progress[one.id] end
            end
            for id, value in pairs(progress) do
                if not here[id] then
                    value = value - step * 2
                    progress[id] = value > 0 and value or nil
                end
            end
            local percent = math.min(100, math.floor(bestValue / def.openSeconds * 100))
            card(d, best and "Opening" or "Stand close to open", percent - percent % 5)
            if best and bestValue >= def.openSeconds then
                d.opened = true
                open(d, best)
                return remove(d)
            end
        end
        if def.life > 0 and age > def.life * 60 then
            core.reply(d.anchor.source, nil, true, def.name .. " expired unopened")
            return remove(d)
        end
    end
end

local function fly(d)
    local def, anchor = d.def, d.anchor
    local h = math.rad(anchor.heading + def.direction)
    local fx, fy = math.cos(h), math.sin(h) -- crosses the staff member's view
    local yaw = anchor.heading + def.direction - 90
    local top = anchor.z + def.height
    local function over(t) -- t from 0 to 1, over the site at 0.5
        local s = (t - 0.5) * 2 * def.run
        return { x = anchor.x + fx * s, y = anchor.y + fy * s, z = top + (math.abs(t - 0.5) ^ 2) * 24 }
    end
    local function under(p) return { x = p.x, y = p.y, z = p.z - 3.2 } end

    local at = over(0)
    local why
    d.av, why = GM.makeBody({ record = def.record }, at, yaw, anchor.bucket, 5 * 60000)
    if not d.av then return false, "AV refused: " .. tostring(why) end
    d.crate, why = GM.makeBody({ record = GM.dropCrate }, under(at), yaw, anchor.bucket, math.max(30, def.life + 10) * 60000)
    if not d.crate then return false, "crate refused: " .. tostring(why) end

    CreateThread(function()
        local ok, problem = pcall(function()
            local waited = 0
            while waited < 4000 and not d.av.seen() do
                Wait(100)
                waited = waited + 100
                if not running(d) then return end
            end
            Wait(GM.av.loadMs)
            if not running(d) then return end
            local began, released = GetGameTimer(), false
            local total, fall = def.flySeconds * 1000, def.fallSeconds * 1000
            local from, releasedAt
            while true do
                if not running(d) then return end
                local now = GetGameTimer()
                local t = (now - began) / total
                if t < 1 then
                    local p = over(t)
                    if d.av then d.av.move(p, yaw) end
                    if not released then
                        d.crate.move(under(p), yaw)
                        if t >= 0.5 then
                            released, releasedAt, from = true, now, under(p)
                            d.flare = GM.makeFire(from, anchor.bucket, "smoke.machine")
                        end
                    end
                elseif d.av then
                    d.av.remove()
                    d.av = nil
                end
                if released then
                    -- quick at first, then slower and slower: no bump at the bottom
                    local f = math.min(1, (now - releasedAt) / fall)
                    local eased = 1 - (1 - f) ^ 1.8
                    local sway = (1 - f) * math.sin(f * 9) * 0.8
                    d.at = {
                        x = from.x + (anchor.x - from.x) * eased + fy * sway, y = from.y + (anchor.y - from.y) * eased - fx * sway,
                        z = from.z + (d.ground + def.hover - from.z) * eased,
                    }
                    d.yaw = yaw + f * 60
                    if not d.crate.move(d.at, d.yaw) then
                        core.reply(anchor.source, nil, false, "the crate could not be moved")
                        return remove(d)
                    end
                    if d.flare then d.flare.move(d.at) end
                    if f >= 1 and t >= 1 then break end
                end
                Wait(33)
            end
            -- the landing is marked by smoke for a while
            local flare = d.flare
            if flare then SetTimeout(25000, function() if d.flare == flare then flare.stop() d.flare = nil end end) end
            core.reply(anchor.source, nil, true, def.name .. " has landed")
            moment(d, "dropLanded")
            land(d)
            hover(d)
        end)
        if not ok then
            print("[gm] supply drop error: " .. tostring(problem))
            remove(d)
        end
    end)
    return true
end

function core.actions.drop(anchor, step)
    local count = 0
    for _ in pairs(drops) do count = count + 1 end
    if count >= MAX_DROPS then return false, "at most " .. MAX_DROPS .. " supply drops at once" end
    local def = step and step.def or {
        name = "Supply drop", record = GM.dropAv, height = 45, run = 130, flySeconds = 9, fallSeconds = 8, direction = 0,
        hover = 0.8, openSeconds = 5, life = 15, share = "near",
    }
    sequence = sequence + 1
    local d = {
        id = sequence, def = def, shown = {}, ground = anchor.z, yaw = 0,
        anchor = { x = anchor.x, y = anchor.y, z = anchor.z, heading = anchor.heading, bucket = anchor.bucket, source = anchor.source },
        at = { x = anchor.x, y = anchor.y, z = anchor.z },
    }
    drops[d.id] = d
    local lead = def.warning and (def.warningLead or 6) or 0
    if def.warning then
        GM.say("scene", def.warning, { seconds = math.max(3, math.min(GM.announceSeconds, lead + def.flySeconds)) })
    end
    local function go()
        if def.cinematic then core.actions.cinematic(d.anchor, { seconds = math.min(20, def.flySeconds + 3) }) end
        local ok, why = fly(d)
        if not ok then remove(d) end
        return ok, why
    end
    if lead <= 0 then return go() end
    SetTimeout(math.floor(lead * 1000), function()
        if not running(d) then return end
        local ok, why = go()
        if not ok then core.reply(anchor.source, nil, false, tostring(why)) end
    end)
    return true, ("warning sent, AV in %d s"):format(math.floor(lead))
end

core.command("gm.drop", function(source)
    local anchor, why = core.anchorFor(source, GM.eventDistance)
    if not anchor then return false, why end
    return core.actions.drop(anchor, nil)
end)

AddEventHandler("onPlayerDisconnected", function(id)
    local playerId = tonumber(id)
    for _, d in pairs(drops) do
        if playerId then d.shown[playerId] = nil end
    end
end)
