-- Loot: this mod decides who earned what; the server's own system hands it out.
-- lootMethod chooses how:
--   event    raise gm_events:loot and let the owner's script do the rest (default)
--   export   call exports.<resource>:<function>(award); it answers true, or false and why
--   ground   drop it with the platform's open77_loot
--   off      nobody earns anything
-- Every award also raises gm_events:loot, so logs can listen under any method.
--
-- award = {
--   phase    "award", or "pickup" when a ground drop was taken
--   id       unique; a retry sends the SAME id, so paying an id once is always safe
--   source   "enemy", "boss", "objectives", "drop" or "test"
--   name     what it came from; table: the loot table's name
--   playerId, playerName, items = { { item, label, amount } }, position = { x, y, z, bucket }
--   method, handled (true when the export or the ground already delivered it)
-- }
local core = GM.core
local MAX_HISTORY, MAX_ITEMS, MAX_DROPS = 50, 500, 400

local history = {}    -- newest last: { award, state, why }
local catalogue = {}  -- resource -> { { id, label } }
local drops = {}      -- tostring(dropId) -> { award, item }
local sequence = 0

-- Award ids must never repeat, not even after a restart: count the starts.
local boot = (math.tointeger(tonumber(Open77.kvp.get("loot:starts"))) or 0) + 1
local counted, countProblem = Open77.kvp.set("loot:starts", tostring(boot))
if not counted then -- no storage: a random mark is the next best thing
    print("[gm] loot start not counted: " .. tostring(countProblem))
    boot = "r" .. math.random(100000000, 999999999)
end

local function isOnline(playerId)
    for _, id in ipairs(Open77.players.all()) do if id == playerId then return true end end
    return false
end

-- ------------------------------------------------------------------- rolling

local function roll(set)
    local items = {}
    for _, entry in ipairs(set.entries) do
        if math.random() * 100 < entry.chance then
            items[#items + 1] = { item = entry.item, label = entry.label or entry.item, amount = math.random(entry.min, entry.max) }
        end
    end
    return items
end

-- ------------------------------------------------------------------ delivering

local function raise(award)
    local ok, why = TriggerEvent("gm_events:loot", award)
    if not ok then print("[gm] gm_events:loot not raised: " .. tostring(why)) end
    return ok, why
end

local function deliverExport(award)
    local resource, name = GM.lootResource, GM.lootExport
    if resource == "-" or name == "-" then return false, "set the loot resource and function first" end
    if GetResourceState(resource) ~= "running" then return false, resource .. " is not running" end
    -- Asynchronous, so an inventory that waits for its database works too.
    local promise, refused = Open77.exports.call(resource, name, award)
    if not promise then return false, tostring(refused) end
    local ok, result, why = pcall(function() return promise:await() end)
    if not ok then return false, tostring(result) end
    if result ~= true then return false, tostring(why or "the export did not answer true") end
    return true
end

local function deliverGround(award)
    if GetResourceState("open77_loot") ~= "running" then return false, "open77_loot is not running" end
    local live = 0
    for _ in pairs(drops) do live = live + 1 end
    if live + #award.items > MAX_DROPS then return false, "too many drops on the ground" end
    for _, i in ipairs(award.items) do
        if not i.item:match("^Items%.") then return false, i.item .. ": ground drops need an Items.* record" end
    end
    local made, last = {}, nil
    for n, i in ipairs(award.items) do
        local turn = n / #award.items * 2 * math.pi
        local id, why = Open77.loot.create({
            item = i.item, quantity = i.amount, label = i.label, radius = 2.0, ttlMs = GM.lootGroundSeconds * 1000,
            bucket = award.position.bucket,
            position = {
                x = award.position.x + math.cos(turn) * 0.8, y = award.position.y + math.sin(turn) * 0.8,
                z = award.position.z + 0.6,
            },
        })
        if id then
            made[#made + 1] = id
            drops[tostring(id)] = { award = award, item = i }
        else
            last = why
        end
    end
    if #made < #award.items then -- all or nothing, so a retry never doubles anything
        for _, id in ipairs(made) do
            drops[tostring(id)] = nil
            Open77.loot.remove(id)
        end
        return false, "drop refused: " .. tostring(last)
    end
    return true
end

local function deliver(entry)
    local award = entry.award
    entry.state = "sending"
    CreateThread(function()
        local ok, why = true, nil
        if award.method == "export" then
            ok, why = deliverExport(award)
        elseif award.method == "ground" then
            ok, why = deliverGround(award)
        end
        award.handled = ok and award.method ~= "event"
        if ok then
            local raised, reason = raise(award)
            if award.method == "event" and not raised then ok, why = false, reason end
        end
        entry.state, entry.why = ok and "sent" or "failed", why
        if not ok then
            print(("[gm] loot %s for player %s failed: %s (gm.loot retry %s)"):format(
                award.id, tostring(award.playerId), tostring(why), award.id))
        end
    end)
end

-- playerId may be nil for a ground drop with no owner.
local function give(set, source, name, playerId, position)
    if GM.lootMethod == "off" then return end
    local items = roll(set)
    if #items == 0 then return end
    sequence = sequence + 1
    local award = {
        phase = "award", id = "gm-" .. boot .. "-" .. sequence, source = source, name = name, table = set.name,
        playerId = playerId, playerName = playerId and Open77.players.name(playerId) or nil,
        items = items, position = position, method = GM.lootMethod, handled = false,
    }
    local entry = { award = award }
    history[#history + 1] = entry
    if #history > MAX_HISTORY then table.remove(history, 1) end
    local parts = {}
    for _, i in ipairs(items) do parts[#parts + 1] = i.amount .. "x " .. i.item end
    print(("[gm] loot %s: %s -> player %s from %s (%s)"):format(
        award.id, table.concat(parts, ", "), tostring(playerId or "-"), name, set.name))
    GM.moment("lootAwarded", { id = award.id, name = name, source = source, table = set.name, playerId = playerId, items = items })
    deliver(entry)
    return award.id
end

GM.lootGive = give -- server/drop.lua

-- ------------------------------------------------------------------- earning

-- "player:<id>" from the platform's damage events.
function GM.lootHit(n, from)
    local id = math.tointeger(tonumber(tostring(from or ""):match("^player:(%d+)$")))
    if not id or id <= 0 or core.isGhost(id) then return end
    n.by = n.by or {}
    n.by[id] = true
    n.lastBy = id
end

function GM.lootDeath(n, from)
    GM.lootHit(n, from)
    if not n.lootDef or n.paid then return end
    n.paid = true -- one body pays once, whatever happens to it later
    local body = GM.readNpc(n)
    local source, name = n.boss and "boss" or "enemy", n.name or "enemy"
    local position = body and { x = body.x, y = body.y, z = body.z, bucket = body.bucket } or nil
    if GM.lootMethod == "ground" then
        if n.lastBy and position then give(n.lootDef, source, name, nil, position) end -- nobody fought it: nothing
        return
    end
    local everyone = n.boss or GM.lootShare == "everyone"
    local earned = {}
    for id in pairs(n.by or {}) do
        if (everyone or id == n.lastBy) and isOnline(id) and not core.isGhost(id) then earned[#earned + 1] = id end
    end
    table.sort(earned)
    for _, id in ipairs(earned) do
        give(n.lootDef, source, name, id, position or Open77.players.position(id))
    end
end

function GM.lootObjectives(set, name, players)
    for _, p in ipairs(players) do
        if p.seconds >= GM.lootMinSeconds and isOnline(p.id) then
            give(set, "objectives", name, p.id, Open77.players.position(p.id))
        end
    end
end

-- Staff try a table on themselves, by the real path.
function GM.lootTest(set, playerId)
    if GM.lootMethod == "off" then return false, "loot is turned off in the settings" end
    local id = give(set, "test", "Test", playerId, Open77.players.position(playerId))
    if not id then return true, "nothing dropped this time" end
    local entry = history[#history]
    local waited = 0
    while entry.state == "sending" and waited < 5000 do
        Wait(100)
        waited = waited + 100
    end
    if entry.state == "failed" then return false, "failed: " .. tostring(entry.why) end
    if entry.state == "sending" then return false, "no answer yet from " .. GM.lootResource end
    local parts = {}
    for _, i in ipairs(entry.award.items) do parts[#parts + 1] = i.amount .. "x " .. i.label end
    return true, "sent by " .. GM.lootMethod .. ": " .. table.concat(parts, ", ")
end

function GM.clearLoot()
    for id in pairs(drops) do Open77.loot.remove(math.tointeger(tonumber(id)) or id) end
    drops = {}
end

AddEventHandler("onLootPickup", function(playerId, dropId, _, quantity, owner)
    if owner ~= GetCurrentResourceName() then return end
    local drop = drops[tostring(dropId)]
    if not drop then return end
    drops[tostring(dropId)] = nil
    local id = math.tointeger(tonumber(playerId))
    local a = drop.award
    raise({
        phase = "pickup", id = a.id .. "-" .. tostring(dropId), source = a.source, name = a.name, table = a.table,
        playerId = id, playerName = id and Open77.players.name(id) or nil, position = a.position, method = "ground",
        items = { { item = drop.item.item, label = drop.item.label, amount = math.tointeger(tonumber(quantity)) or drop.item.amount } },
        handled = false, -- the platform shows it in the game; saving it is the owner's
    })
end)

AddEventHandler("onLootRemoved", function(dropId, reason)
    if reason ~= "picked_up" then drops[tostring(dropId)] = nil end
end)

-- Ids are reused: the next player must not inherit someone else's fight.
AddEventHandler("onPlayerDisconnected", function(id)
    local playerId = tonumber(id)
    if not playerId then return end
    for _, n in pairs(GM.living()) do
        if n.by then n.by[playerId] = nil end
        if n.lastBy == playerId then n.lastBy = nil end
    end
end)

-- ---------------------------------------------------------- for other resources

-- The owner's item list, offered in the panel: { { id = "medkit", label = "Medkit" }, ... }
exports("registerItems", function(list)
    local resource = GetInvokingResource()
    if not resource then return nil, "call this from another resource" end
    if type(list) ~= "table" then return nil, "items must be a list" end
    local clean = {}
    for _, i in ipairs(list) do
        local id = type(i) == "table" and i.id or i
        if type(id) == "string" and #id <= 80 and id:match("^[%w_%.:%-/]+$") and #clean < MAX_ITEMS then
            local label = type(i) == "table" and type(i.label) == "string" and i.label:gsub("[%c<>]", ""):sub(1, 60) or id
            if not utf8.len(label) then label = id end
            clean[#clean + 1] = { id = id, label = label }
        end
    end
    catalogue[resource] = clean
    print(("[gm] %s registered %d loot items"):format(resource, #clean))
    return #clean
end)

-- Was this award made by this mod? For inventories that check before paying.
exports("getAward", function(id)
    for _, entry in ipairs(history) do
        if entry.award.id == id then return entry.award, entry.state end
    end
    return nil, "unknown award"
end)

AddEventHandler("onResourceStop", function(name)
    catalogue[name] = nil
    if name == GetCurrentResourceName() then GM.clearLoot() end
end)

function GM.lootProviders()
    local list = {}
    for resource, items in pairs(catalogue) do list[#list + 1] = { resource = resource, items = #items } end
    table.sort(list, function(a, b) return a.resource < b.resource end)
    return list
end

function GM.lootItems()
    local list = {}
    for _, items in pairs(catalogue) do
        for _, i in ipairs(items) do if #list < MAX_ITEMS then list[#list + 1] = i end end
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

core.command("gm.loot", function(_, args)
    if args[1] == "retry" then
        for _, entry in ipairs(history) do
            if entry.award.id == args[2] then
                if entry.state ~= "failed" then return false, "that award is " .. entry.state end
                -- The same id and method again; only its player may still be gone.
                if entry.award.playerId and not isOnline(entry.award.playerId) then return false, "that player has left" end
                deliver(entry)
                return true, "sent again: " .. entry.award.id
            end
        end
        return false, "no such award"
    end
    local lines = {}
    for i = math.max(1, #history - 9), #history do
        local e = history[i]
        lines[#lines + 1] = ("%s %s player %s %s%s"):format(
            e.award.id, e.award.name, tostring(e.award.playerId or "-"), e.state, e.why and (" (" .. e.why .. ")") or "")
    end
    return true, #lines > 0 and table.concat(lines, " | ") or ("no loot yet, method " .. GM.lootMethod)
end)
