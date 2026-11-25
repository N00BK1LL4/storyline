-- EXPERIMENT, not a feature yet: a line of AI cars driving to a marked spot.
--   gm.mark at the destination, go to the start (at most 1000 m away), stand in the
--   lane facing the way traffic goes, gm.convoy [cars] [speed]
-- The game drives the cars, so a player has to stay near them.
local core = GM.core
local RECORDS = {
    "Vehicle.v_standard2_villefort_cortes_arasaka",
    "Vehicle.v_standard25_villefort_columbus_arasaka",
    "Vehicle.v_standard2_villefort_cortes_arasaka",
}
local DRIVER = "Character.arasaka_security1_ranged1_kenshin_ma"
local MAX_DISTANCE, MIN_DISTANCE = 1000, 80
local SPACING, ARRIVED = 15, 35
local GAP_LOW, GAP_HIGH, GAP_LOST = 11, 24, 60

local convoy -- one at a time

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

local function say(c, text)
    core.reply(c.owner, nil, true, "convoy: " .. text)
    if c.owner and c.owner > 0 then TriggerClientEvent("gm_events:convoyLog", c.owner, text) end
end

function GM.clearConvoy()
    local c = convoy
    convoy = nil
    if not c then return end
    for _, car in ipairs(c.cars) do
        pcall(Open77.vehicles.ai.removeDriver, car.id)
        if Open77.vehicles.get(car.id) then Open77.vehicles.remove(car.id) end
        if car.npc and Open77.npcs.get(car.npc) then Open77.npcs.remove(car.npc) end
    end
end

for _, name in ipairs({ "arrived", "failed", "cancelled", "blocked", "resumed" }) do
    Open77.vehicles.ai.on(name, function(state)
        local c = convoy
        for i, car in ipairs(c and c.cars or {}) do
            if tostring(car.id) == tostring(state.vehicleId) then
                if name == "arrived" then car.arrived = true end
                if not (name == "cancelled" and state.reason == "replaced") then
                    say(c, ("car %d %s%s"):format(i, name, (state.reason or "") ~= "" and (" (" .. tostring(state.reason) .. ")") or ""))
                end
            end
        end
    end)
end

-- Every car drives the whole way itself, with one order. The platform's "follow" aims
-- just behind the car ahead, arrives at once and starts again, which looks like wiggling.
local function order(c, i, behavior)
    local car = c.cars[i]
    car.speed = c.speed
    return Open77.vehicles.ai.driveTo(car.id, {
        position = { x = c.goal.x, y = c.goal.y, z = c.goal.z }, speed = c.speed,
        arrivalRadius = math.min(20, 4 + i * 5), -- they stop one behind another
        timeoutMilliseconds = 15 * 60000, behavior = behavior or "normal",
    })
end

local function setSpeed(car, wanted)
    wanted = math.max(2, math.min(35, wanted))
    if car.speed and math.abs(car.speed - wanted) < 2 then return end
    local ok, why = Open77.vehicles.ai.setSpeed(car.id, wanted)
    if ok then car.speed = wanted else car.speedProblem = tostring(why) end
end

-- Told to drive but standing still. Ask again, then ask it to push through traffic.
local function unstick(c, i, car, now)
    if not car.launched or car.arrived or car.left < ARRIVED then return end
    if not car.restAt or dist(car.p, car.restAt) > 2 then
        car.restAt, car.restSince, car.unstuck = car.p, now, 0
        return
    end
    local still = now - car.restSince
    if still > 12000 and car.unstuck == 0 then
        car.unstuck = 1
        local task, why = order(c, i)
        say(c, ("car %d is not moving, asked again: %s"):format(i, task and "ok" or tostring(why)))
    elseif still > 24000 and car.unstuck == 1 then
        car.unstuck = 2
        local task, why = order(c, i, "aggressive")
        say(c, ("car %d still not moving, told to push through: %s"):format(i, task and "ok" or tostring(why)))
    elseif still > 40000 and car.unstuck == 2 then
        car.unstuck = 3
        say(c, ("car %d is stuck"):format(i))
    end
end

-- The ones behind match the car ahead; the front waits for stragglers.
local function keepTogether(c)
    local widest, ahead = 0, nil
    local now = GetGameTimer()
    for i, car in ipairs(c.cars) do
        local v, st = Open77.vehicles.get(car.id), Open77.vehicles.ai.state(car.id)
        local p = v and (v.position or v)
        car.p = p and p.x and { x = p.x, y = p.y, z = p.z } or nil
        car.status = st and st.status or "no AI"
        car.gap = nil
        if car.p then
            car.left = dist(car.p, c.goal)
            if ahead then
                car.gap = dist(car.p, ahead.p)
                car.passed = car.left < ahead.left - 8
                if car.launched and not ahead.arrived and car.status == "running" then
                    widest = math.max(widest, car.gap)
                    local base = math.min(ahead.speed or c.speed, c.speed * 1.1)
                    if car.passed then base = base * 0.4
                    elseif car.gap < GAP_LOW then base = base * 0.5
                    elseif car.gap > GAP_HIGH then base = c.speed * 1.35 end
                    setSpeed(car, base)
                end
            end
            unstick(c, i, car, now)
            if car.launched and (car.status == "failed" or car.status == "cancelled") and car.left > ARRIVED
                and (car.retries or 0) < 5 and now - (car.askedAt or 0) > 4000 then
                car.retries, car.askedAt = (car.retries or 0) + 1, now
                local task, why = order(c, i)
                say(c, ("car %d asked again (%d): %s"):format(i, car.retries, task and "ok" or tostring(why)))
            end
            ahead = car
        end
    end
    local lead = c.cars[1]
    if lead.launched and lead.status == "running" then setSpeed(lead, widest > GAP_LOST and c.speed * 0.5 or c.speed) end
end

local function run(c)
    Wait(6000) -- bodies and cars stream in and settle
    for i, car in ipairs(c.cars) do
        if convoy ~= c then return end
        local held, reason
        if car.npc then held, reason = Open77.vehicles.ai.attachDriver(car.id, { npcId = car.npc }) end
        if not held then
            if car.npc then say(c, ("car %d goes without a visible driver: %s"):format(i, tostring(reason))) end
            held, reason = Open77.vehicles.ai.attachDriver(car.id)
        end
        if not held then say(c, ("car %d has no AI: %s"):format(i, tostring(reason))) end
    end
    Wait(3000)
    local beat, nextCar = 0, 1
    while convoy == c do
        keepTogether(c)
        -- one by one: each leaves when the car ahead has room
        local car, front = c.cars[nextCar], c.cars[nextCar - 1]
        if car and car.p and (not front or (front.p and dist(front.p, front.start) > 18) or GetGameTimer() - front.launched > 45000) then
            car.launched, car.start = GetGameTimer(), car.p
            local task, reason = order(c, nextCar)
            say(c, task and ("car %d sets off, %.0f m to go"):format(nextCar, car.left) or ("car %d refused: %s"):format(nextCar, tostring(reason)))
            nextCar = nextCar + 1
        end
        if beat % 3 == 0 then
            local parts = {}
            for n, one in ipairs(c.cars) do
                parts[n] = one.p and ("%d %s %.0f m left%s, %.0f m/s%s%s"):format(n, one.status, one.left,
                    one.gap and (", gap %.0f"):format(one.gap) or "", one.speed or 0, one.passed and ", PASSED" or "",
                    one.speedProblem and (", speed " .. one.speedProblem) or "") or n .. " gone"
            end
            local line = table.concat(parts, " | ")
            print("[gm] convoy " .. math.floor((GetGameTimer() - c.began) / 1000) .. " s: " .. line)
            if c.owner > 0 then TriggerClientEvent("gm_events:convoyLog", c.owner, line) end
        end
        beat = beat + 1
        Wait(2000)
    end
end

core.command("gm.convoy", function(source, args)
    if args[1] == "stop" then
        GM.clearConvoy()
        return true, "convoy removed"
    end
    if convoy then return false, "a convoy is running; gm.convoy stop" end
    local goal = core.mark(source)
    local start, why = core.anchorFor(source, 8, true)
    if not start then return false, why end
    if not goal or goal.bucket ~= start.bucket then return false, "use gm.mark at the destination first" end
    local away = dist(start, goal)
    if away > MAX_DISTANCE then
        return false, ("the mark is %.0f m away; start within %d m of it"):format(away, MAX_DISTANCE)
    end
    if away < MIN_DISTANCE then return false, ("the mark is only %.0f m away; start at least %d m from it"):format(away, MIN_DISTANCE) end
    local count = math.max(1, math.min(5, math.floor(tonumber(args[1]) or 3)))
    local c = {
        owner = source, goal = { x = goal.x, y = goal.y, z = goal.z }, cars = {}, began = GetGameTimer(),
        speed = math.max(3, math.min(30, tonumber(args[2]) or 12)),
    }
    convoy = c
    local a = math.rad(start.heading)
    for i = 1, count do
        local forward = (count - i) * SPACING -- the first car furthest ahead
        local at = { x = start.x - math.sin(a) * forward, y = start.y + math.cos(a) * forward, z = start.z + 0.5 }
        local id, refused = Open77.vehicles.create({
            record = RECORDS[(i - 1) % #RECORDS + 1], position = at, yaw = start.heading, bucket = start.bucket, ttlMs = 30 * 60000,
        })
        if not id then
            GM.clearConvoy()
            return false, "car refused: " .. tostring(refused)
        end
        c.cars[i] = { id = id }
        local npc, noDriver = Open77.npcs.create({
            record = DRIVER, position = { x = at.x + math.cos(a) * 3, y = at.y + math.sin(a) * 3, z = at.z },
            yaw = start.heading, bucket = start.bucket, health = 100, maxHealth = 100,
        })
        if npc then c.cars[i].npc = npc else say(c, "driver refused: " .. tostring(noDriver)) end
    end
    CreateThread(function()
        local ok, problem = pcall(run, c)
        if not ok then
            print("[gm] convoy error: " .. tostring(problem))
            if convoy == c then GM.clearConvoy() end
        end
    end)
    local ahead = -math.sin(a) * (goal.x - start.x) + math.cos(a) * (goal.y - start.y)
    return true, ("convoy of %d: %.0f m, starting in about 10 s%s"):format(count, away,
        ahead < 0 and ". The destination is behind you: they may need room to turn round" or "")
end)
