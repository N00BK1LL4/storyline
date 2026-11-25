-- Feeds the boss bar, the name card and the 3D map marker. Runs after main.lua,
-- which shares its NPC registry through GM.living().
local shown = {}   -- playerId -> last state sent
local blips = {}   -- npc key -> map blip id

local function map(method, ...)
    local ok, value, reason = pcall(Open77.exports.callSync, "op77_map3d", method, ...)
    if not ok then return nil, tostring(value) end
    return value, reason
end

local mapFailed = false
local function mapProblem(reason)
    if GetResourceState("op77_map3d") ~= "running" then return end -- optional, not a problem
    if mapFailed then return end
    mapFailed = true
    print("[gm] boss map marker unavailable: " .. tostring(reason))
end

local function bosses()
    local list = {}
    for key, n in pairs(GM.living()) do
        local npc = n.boss and GM.readNpc(n) or nil
        if npc and npc.health > 0 then list[#list + 1] = { key = key, n = n, npc = npc } end
    end
    return list
end

local function updateMap(list)
    local alive = {}
    for _, b in ipairs(list) do
        -- The map has no notion of instances: only mark bosses in the main world.
        if b.npc.bucket == 0 and GM.mapMarker then
            alive[b.key] = true
            local position = { x = b.npc.x, y = b.npc.y, z = b.npc.z }
            if blips[b.key] then
                map("updateBlip", blips[b.key], { position = position })
            else
                local id, why = map("addBlip", -1, {
                    id = "boss-" .. b.key, position = position, icon = "skull", color = "#FF4D3D",
                    label = b.n.name, description = "World event boss", pulse = true, edge = true, scale = 1.4,
                })
                if id then blips[b.key] = id else mapProblem(why) end
            end
        end
    end
    for key, id in pairs(blips) do
        if not alive[key] then
            blips[key] = nil
            map("removeBlip", id)
        end
    end
end

local function same(a, b)
    return a and b and a.id == b.id and a.percent == b.percent and a.players == b.players and a.extra == b.extra and a.style == b.style
end

local function updatePlayers(list)
    local range = GM.bossBarRadius
    local online = {}
    for _, playerId in ipairs(Open77.players.all()) do
        online[playerId] = true
        local p = Open77.players.position(playerId)
        local best, bestD
        if p then
            for _, b in ipairs(list) do
                if b.npc.bucket == p.bucket then
                    local dx, dy, dz = b.npc.x - p.x, b.npc.y - p.y, b.npc.z - p.z
                    local d = dx * dx + dy * dy + dz * dz
                    if d <= range * range and (not bestD or d < bestD) then best, bestD = b, d end
                end
            end
        end
        local state
        if best then
            state = {
                id = tostring(best.n.id), -- 64-bit ids travel as text
                name = best.n.name,
                percent = math.max(1, math.ceil(best.npc.health / best.npc.maxHealth * 100)),
                players = best.n.players or 1,
                height = best.n.height,
                style = GM.bossBarStyle,
                extra = best.npc.repairing and "repairing, shielded" or best.npc.phase or "",
            }
        end
        if state then
            -- Resend every few beats: the body may have streamed in since.
            local old = shown[playerId]
            local beats = old and old.beats or 0
            if not same(old, state) or beats >= 4 then
                TriggerClientEvent("gm_events:boss", playerId, state)
                beats = 0
            end
            state.beats = beats + 1
            shown[playerId] = state
        elseif shown[playerId] then
            shown[playerId] = nil
            TriggerClientEvent("gm_events:boss", playerId, false)
        end
    end
    for playerId in pairs(shown) do
        if not online[playerId] then shown[playerId] = nil end
    end
end

CreateThread(function()
    local beat = 0
    while true do
        Wait(500)
        local list = bosses()
        updatePlayers(list)
        beat = beat + 1
        if beat % 4 == 0 then updateMap(list) end
    end
end)
