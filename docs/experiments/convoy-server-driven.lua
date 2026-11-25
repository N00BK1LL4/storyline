-- EXPERIMENT, not a feature yet: a line of AI cars along a route a staff member drove.
--   gm.route start, drive the way, gm.route end, then gm.convoy [cars] [speed] [ai]
-- The server moves the cars itself, like the AV. "ai" uses the game's driving instead,
-- which needs a player near and has been seen to stop for good at a route point.
local core = GM.core
local RECORDS = {
    "Vehicle.v_standard2_villefort_cortes_arasaka",
    "Vehicle.v_standard25_villefort_columbus_arasaka",
    "Vehicle.v_standard2_villefort_cortes_arasaka",
}
local DRIVER = "Character.arasaka_security1_ranged1_kenshin_ma"
local STEP, LEG, SPACING, MAX_POINTS = 8, 200, 16, 1200
local GAP_LOW, GAP_HIGH, GAP_LOST = 11, 24, 60

local convoy            -- one at a time
local recording = {}    -- playerId -> { points, bucket }
local route             -- { points = { { x, y, z, d, yaw } }, length, bucket }

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

local function say(c, text)
    core.reply(c.owner, nil, true, "convoy: " .. text)
    if c.owner and c.owner > 0 then TriggerClientEvent("gm_events:convoyLog", c.owner, text) end
end

-- ------------------------------------------------------------------ recording

-- The car this player sits in, to learn how high a car's own origin is above the road.
local function carHeight(playerId)
    for _, v in ipairs(Open77.vehicles.all() or {}) do
        for _, o in ipairs(v.occupants or {}) do
            if tonumber(o.playerId) == playerId then
                local p = v.position or v
                return p and p.z
            end
        end
    end
end

local function median(list)
    table.sort(list)
    return list[(#list + 1) // 2]
end

local function finishRoute(r)
    local points, d = r.points, 0
    -- Road height, measured by the driver's own game. A gap takes its neighbours' difference.
    local seat, lifts, measured = {}, {}, 0
    for _, p in ipairs(points) do
        if p.ground then
            measured = measured + 1
            seat[#seat + 1] = p.z - p.ground
            if p.car then lifts[#lifts + 1] = p.car - p.ground end
        end
    end
    local above = #seat > 0 and median(seat) or 0.6
    r.lift = #lifts > 0 and math.max(-0.6, math.min(1.2, median(lifts))) or 0
    r.measured = measured
    for _, p in ipairs(points) do p.z = p.ground or (p.z - above) end
    for i, p in ipairs(points) do
        if i > 1 then d = d + dist(points[i - 1], p) end
        p.d = d
        local a, b = points[math.max(1, i - 1)], points[math.min(#points, i + 1)]
        p.yaw = math.deg(math.atan(-(b.x - a.x), b.y - a.y))
    end
    r.length = d
    return r
end

CreateThread(function()
    while true do
        Wait(250)
        for id, r in pairs(recording) do
            local p = Open77.players.position(id)
            local last = r.points[#r.points]
            if p and p.bucket == r.bucket and #r.points < MAX_POINTS and (not last or dist(last, p) >= STEP) then
                r.points[#r.points + 1] = { x = p.x, y = p.y, z = p.z, car = carHeight(id) }
                TriggerClientEvent("gm_events:ground", id, #r.points, p.x, p.y, p.z)
            end
        end
    end
end)

RegisterNetEvent("gm_events:groundIs", function(index, z)
    local r = recording[tonumber(source)]
    local p = r and r.points[math.tointeger(tonumber(index)) or 0]
    z = tonumber(z)
    if p and z and z == z and math.abs(z - p.z) < 4 then p.ground = z end
end)

core.command("gm.lift", function(_, args)
    if not route then return false, "no route" end
    local by = tonumber(args[1])
    if by then route.lift = math.max(-2, math.min(2, route.lift + by)) end
    return true, ("cars ride %.2f m above the measured road"):format(route.lift)
end)

core.command("gm.route", function(source, args)
    local me, why = core.freshPlayer(source)
    if not me then return false, why end
    if args[1] == "start" then
        recording[source] = { points = {}, bucket = me.bucket or 0 }
        return true, "recording: drive the whole way, then gm.route end"
    elseif args[1] == "end" then
        local r = recording[source]
        if not r then return false, "nothing is being recorded; gm.route start" end
        Wait(600) -- the last heights are on their way
        recording[source] = nil
        finishRoute(r)
        if r.length < 150 then return false, ("only %.0f m recorded; drive at least 150 m"):format(r.length) end
        route = r
        return true, ("route saved: %.0f m, road height known at %d of %d points, car origin %.2f m up. Go back to the start and run gm.convoy"):format(
            r.length, r.measured, #r.points, r.lift)
    end
    if recording[source] then return true, #recording[source].points .. " points so far" end
    return true, route and ("route of %.0f m"):format(route.length) or "no route; gm.route start"
end)

-- The route point at a distance from its start.
local function along(r, d)
    d = math.max(0, math.min(r.length, d))
    for i = 2, #r.points do
        local a, b = r.points[i - 1], r.points[i]
        if b.d >= d then
            local t = b.d > a.d and (d - a.d) / (b.d - a.d) or 0
            return { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t, z = a.z + (b.z - a.z) * t, yaw = b.yaw }
        end
    end
    return r.points[#r.points]
end

-- How far along the route a car is: the nearest point a little ahead of where it was,
-- so a route that crosses itself never makes it jump.
local function progress(r, car)
    local best, bestD
    local from = car.index or 1
    for i = math.max(1, from - 4), math.min(#r.points, from + 25) do
        local d = dist(r.points[i], car.p)
        if not bestD or d < bestD then best, bestD = i, d end
    end
    car.index, car.off = best, bestD
    return r.points[best].d
end

-- -------------------------------------------------------------------- driving

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

for _, name in ipairs({ "arrived", "failed", "cancelled", "blocked", "resumed", "waypointReached" }) do
    Open77.vehicles.ai.on(name, function(state)
        local c = convoy
        if not c then return end
        for i, car in ipairs(c.cars) do
            if tostring(car.id) == tostring(state.vehicleId) then
                if name == "arrived" then car.arrived = true end
                say(c, ("car %d %s%s"):format(i, name, (state.reason or "") ~= "" and (" (" .. tostring(state.reason) .. ")") or ""))
            end
        end
    end)
end

-- Short legs from wherever the car is to its own place at the end of the line.
local function order(c, i)
    local car = c.cars[i]
    car.speed = c.speed
    local points = {}
    local finish = c.route.length - (i - 1) * SPACING
    local d = (car.d or 0) + LEG
    while d < finish - LEG * 0.5 and #points < 62 do
        local p = along(c.route, d)
        points[#points + 1] = { x = p.x, y = p.y, z = p.z }
        d = d + LEG
    end
    local last = along(c.route, finish)
    points[#points + 1] = { x = last.x, y = last.y, z = last.z }
    return Open77.vehicles.ai.followRoute(car.id, {
        points = points, loop = false, speed = c.speed, arrivalRadius = 12,
        timeoutMilliseconds = 30 * 60000, behavior = "normal",
    })
end

local function setSpeed(car, wanted)
    wanted = math.max(2, math.min(35, wanted))
    if car.speed and math.abs(car.speed - wanted) < 1.5 then return end
    local ok, why = Open77.vehicles.ai.setSpeed(car.id, wanted)
    if ok then car.speed = wanted else car.speedProblem = tostring(why) end
end

-- Told to drive but standing still: ask again, then put it back on the route
-- behind the car ahead.
local function unstick(c, i, car, now)
    if not car.launched or car.arrived then return end
    if not car.restAt or dist(car.p, car.restAt) > 2 then
        car.restAt, car.restSince, car.unstuck = car.p, now, 0
        return
    end
    local still = now - car.restSince
    if still > 8000 and car.unstuck == 0 then
        car.unstuck = 1
        local task, why = order(c, i)
        say(c, ("car %d is not moving, asked again: %s"):format(i, task and "ok" or tostring(why)))
    elseif still > 18000 and car.unstuck == 1 then
        car.unstuck = 2
        local want = car.d + 6
        local front = c.cars[i - 1]
        if front and front.d then want = math.min(want, front.d - SPACING) end
        local spot = along(c.route, want)
        for k, other in ipairs(c.cars) do
            if k ~= i and other.p and dist(spot, other.p) < 8 then return say(c, ("car %d is stuck behind another"):format(i)) end
        end
        local ok, why = Open77.vehicles.setTransform(car.id, { x = spot.x, y = spot.y, z = spot.z + 0.4, yaw = spot.yaw })
        say(c, ("car %d put back on the route: %s"):format(i, ok and "ok" or tostring(why)))
        if ok then
            car.restAt = nil
            car.d = math.max(0, want)
            order(c, i)
        end
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
            car.d = progress(c.route, car)
            if ahead and ahead.d then
                car.gap = ahead.d - car.d
                if car.launched and not ahead.arrived and car.status == "running" then
                    widest = math.max(widest, car.gap)
                    local base = math.min(ahead.speed or c.speed, c.speed * 1.1)
                    if car.gap < 0 then base = base * 0.4
                    elseif car.gap < GAP_LOW then base = base * 0.5
                    elseif car.gap > GAP_HIGH then base = c.speed * 1.35 end
                    setSpeed(car, base)
                end
            end
            unstick(c, i, car, now)
            if car.launched and (car.status == "failed" or car.status == "cancelled") and (car.retries or 0) < 5
                and now - (car.askedAt or 0) > 4000 then
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

-- ---------------------------------------------------------------- server-driven

local ACCEL, BRAKE, GRIP = 2.5, 5, 3.5 -- m/s2; GRIP is how hard it may corner

local function turn(from, to) return (to - from + 180) % 360 - 180 end

-- A smooth pose between two rows of recorded points: no corners in the corners.
local function pose(r, d)
    d = math.max(0, math.min(r.length, d))
    local function mid(offset) return along(r, d + offset) end
    local a, b, e = mid(-4), mid(0), mid(4)
    local back, front = mid(-2.5), mid(2.5)
    return {
        x = (a.x + 2 * b.x + e.x) / 4, y = (a.y + 2 * b.y + e.y) / 4, z = (a.z + 2 * b.z + e.z) / 4,
        yaw = dist(back, front) > 0.5 and math.deg(math.atan(-(front.x - back.x), front.y - back.y)) or b.yaw,
    }
end

-- The fastest a car may go at a place, looking ahead far enough to brake for corners.
local function cornerLimit(r, d, top)
    local limit = top
    for ahead = 0, 60, 10 do
        if d + ahead < r.length - 12 then
            local bend = math.abs(math.rad(turn(pose(r, d + ahead - 6).yaw, pose(r, d + ahead + 6).yaw))) / 12
            local safe = bend > 0.004 and math.sqrt(GRIP / bend) or top
            limit = math.min(limit, math.sqrt(safe * safe + 2 * BRAKE * 0.6 * ahead))
        end
    end
    return math.max(2.5, math.min(top, limit))
end

-- Never run anyone over: somebody close in front stops the line.
local function someoneAhead(c, car, speed)
    local reach = 9 + speed * speed / (2 * BRAKE)
    local a = math.rad(car.pose.yaw)
    for _, id in ipairs(Open77.players.all()) do
        local p = not core.isGhost(id) and Open77.players.position(id) or nil
        if p and p.bucket == c.route.bucket and math.abs(p.z - car.pose.z) < 4 then
            local dx, dy = p.x - car.pose.x, p.y - car.pose.y
            local forward, side = -math.sin(a) * dx + math.cos(a) * dy, math.cos(a) * dx + math.sin(a) * dy
            if forward > 0 and forward < reach and math.abs(side) < 2.6 then return true end
        end
    end
    return false
end

local function rail(c)
    local count, speed = #c.cars, 0
    local head = 10 + (count - 1) * SPACING -- where the first car stands
    for i, car in ipairs(c.cars) do
        local ok, why = Open77.vehicles.setFrozen(car.id, true)
        if not ok then say(c, ("car %d not held: %s"):format(i, tostring(why))) end
        pcall(Open77.vehicles.setEngineHold, car.id, true)
        car.pose = pose(c.route, head - (i - 1) * SPACING)
    end
    local last, report, waiting, frames = GetGameTimer(), 0, false, 0
    local began, shownLift = last, c.route.lift
    while convoy == c do
        Wait(33)
        local now = GetGameTimer()
        local dt = math.min(0.2, (now - last) / 1000)
        last = now
        local blocked = false
        for _, car in ipairs(c.cars) do blocked = blocked or someoneAhead(c, car, speed) end
        if blocked ~= waiting then
            waiting = blocked
            say(c, blocked and "someone is in the way, waiting" or "the way is clear")
        end
        local left = c.route.length - head
        local want = blocked and 0 or c.speed
        for i = 1, count do -- every car has to make its own corner
            want = math.min(want, cornerLimit(c.route, head - (i - 1) * SPACING, c.speed))
            if blocked then want = 0 end
        end
        want = math.min(want, math.sqrt(math.max(0, 2 * BRAKE * 0.5 * left)))
        if speed < want then speed = math.min(want, speed + ACCEL * dt) else speed = math.max(want, speed - BRAKE * dt) end
        head = math.min(c.route.length, head + speed * dt)
        for i, car in ipairs(c.cars) do
            if not car.gone then
                local to = pose(c.route, head - (i - 1) * SPACING)
                to.z = to.z + c.route.lift
                car.pose = to
                if not Open77.vehicles.get(car.id) then
                    car.gone = true
                    say(c, ("car %d is gone"):format(i))
                elseif (speed > 0.02 or now - began < 1500 or c.route.lift ~= shownLift) and not Open77.vehicles.setTransform(car.id, { x = to.x, y = to.y, z = to.z, yaw = to.yaw }) then
                    car.gone = true
                    say(c, ("car %d could not be moved"):format(i))
                end
            end
        end
        shownLift = c.route.lift
        frames = frames + 1
        if now - report > 6000 then
            say(c, ("%.0f of %.0f m, %.0f m/s, %d steps/s"):format(head, c.route.length, speed, report > 0 and frames * 1000 // (now - report) or 0))
            report, frames = now, 0
        end
        if left < 1 and speed < 0.3 then
            say(c, "arrived")
            for _, car in ipairs(c.cars) do
                if not car.gone then Open77.vehicles.setFrozen(car.id, false) end
            end
            c.arrived = true
            return
        end
    end
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
    if convoy ~= c then return end
    if c.mode == "rail" then return rail(c) end
    local beat, nextCar = 0, 1
    while convoy == c do
        keepTogether(c)
        -- one by one: each leaves when the car ahead has room
        local car, front = c.cars[nextCar], c.cars[nextCar - 1]
        if car and car.p and (not front or (front.d and front.d - front.startD > 15) or GetGameTimer() - front.launched > 45000) then
            car.launched, car.startD = GetGameTimer(), car.d
            local task, reason = order(c, nextCar)
            say(c, task and ("car %d sets off"):format(nextCar) or ("car %d refused: %s"):format(nextCar, tostring(reason)))
            nextCar = nextCar + 1
        end
        if beat % 3 == 0 then
            local parts = {}
            for n, one in ipairs(c.cars) do
                parts[n] = one.p and ("%d %s at %.0f of %.0f m%s, %.0f m/s, %.0f m off route%s"):format(n, one.status, one.d, c.route.length,
                    one.gap and (", gap %.0f"):format(one.gap) or "", one.speed or 0, one.off or 0,
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
    if not route then return false, "record a route first: gm.route start, drive it, gm.route end" end
    local me, why = core.freshPlayer(source)
    if not me then return false, why end
    if (me.bucket or 0) ~= route.bucket then return false, "the route is in another world" end
    local away = dist(me.position, route.points[1])
    if away > 120 then return false, ("go back to the start of the route, %.0f m away"):format(away) end
    local count = math.max(1, math.min(5, math.floor(tonumber(args[1]) or 3)))
    local c = {
        owner = source, route = route, cars = {}, mode = args[3] == "ai" and "ai" or "rail", began = GetGameTimer(),
        speed = math.max(3, math.min(30, tonumber(args[2]) or 12)),
    }
    convoy = c
    for i = 1, count do
        local at = along(route, 10 + (count - i) * SPACING) -- on the very lane that was driven
        local a = math.rad(at.yaw)
        local id, refused = Open77.vehicles.create({
            record = RECORDS[(i - 1) % #RECORDS + 1], position = { x = at.x, y = at.y, z = at.z + route.lift + 0.1 }, yaw = at.yaw,
            bucket = route.bucket, ttlMs = 30 * 60000,
        })
        if not id then
            GM.clearConvoy()
            return false, "car refused: " .. tostring(refused)
        end
        c.cars[i] = { id = id }
        local npc, noDriver = Open77.npcs.create({
            record = DRIVER, position = { x = at.x + math.cos(a) * 3, y = at.y + math.sin(a) * 3, z = at.z },
            yaw = at.yaw, bucket = route.bucket, health = 100, maxHealth = 100,
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
    return true, ("convoy of %d: starting in about 10 s"):format(count)
end)

AddEventHandler("onPlayerDisconnected", function(id)
    local playerId = tonumber(id)
    if playerId then recording[playerId] = nil end
end)
