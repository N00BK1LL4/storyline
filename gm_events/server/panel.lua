-- The staff panel's server half. The page holds no authority: every message is
-- checked against the ACL and every value is validated here.
--   command.gm.panel   open the panel
--   command.gm.<x>     the same right the typed command needs
--   gm_events.edit     create, change or delete presets (not part of command.gm.*)
local core = GM.core
local EDIT = "gm_events.edit"
local LOOT = "gm_events.loot" -- spawn things that give loot; also not part of command.gm.*
local MAX_PRESETS, MAX_STATUS = 30, 300 -- per kind; keeps each message small

local viewers = {}  -- playerId -> true while the panel is open
local lastCall = {} -- playerId -> ms

local SCRIPT = {} -- stands for another resource's server script, which the owner trusts
local function allowed(playerId, right)
    if playerId == SCRIPT then return true end
    return Open77.acl.isAllowed(playerId, right) == true
end

-- ---------------------------------------------------------------- validation

local function number(value, low, high, default)
    local n = tonumber(value)
    if not n or n ~= n then return default end
    return math.max(low, math.min(high, n))
end

-- One printable line of at most `max` characters, or nil.
local function text(value, max)
    if type(value) ~= "string" or #value > max * 4 then return nil end
    local clean = value:gsub("[%c<>]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    local length = utf8.len(clean)
    if not length or length == 0 or length > max then return nil end
    return clean
end

local function character(value)
    if type(value) ~= "string" or #value > 160 then return nil end
    local lower = value:lower()
    if lower:find("child", 1, true) or lower:find("kid", 1, true) then return nil end -- never in combat events
    return value:match("^Character%.[%w_%-%.]+$")
end

local avNames = {}
for _, av in ipairs(GM.avModels) do avNames[av.record] = true end
local fallNames = {}
for _, body in ipairs(GM.fallModels) do
    fallNames[body.record] = true
    avNames[body.record] = true -- notes are shared; clean.fall checks its own list
end

-- A reference to a saved or built-in preset.
local function presetId(value)
    if type(value) ~= "string" or #value > 48 then return nil end
    return value:match("^[%w:_%-]+$")
end

local clean = {}

local DEFAULT_SIZE = 8
local function itemName(value)
    if type(value) ~= "string" or #value > 80 then return nil end
    return value:match("^[%w_%.:%-/]+$")
end

function clean.loot(d)
    local name = text(d.name, 32)
    if not name then return nil, "table name: 1 to 32 characters" end
    local entries = {}
    if type(d.entries) == "table" then
        for i = 1, math.min(#d.entries, 12) do
            local e = d.entries[i]
            local item = type(e) == "table" and itemName(e.item) or nil
            if not item then return nil, "entry " .. i .. ": item name with letters, numbers and _ . : - / only" end
            local low = math.floor(number(e.min, 1, 1000000, 1))
            entries[i] = {
                item = item, label = text(e.label, 40), min = low,
                max = math.max(low, math.floor(number(e.max, 1, 1000000, low))), chance = number(e.chance, 0.1, 100, 100),
            }
        end
    end
    if #entries == 0 then return nil, "add at least one item" end
    return { name = name, entries = entries }
end

function clean.objectives(d)
    local name = text(d.name, 32)
    if not name then return nil, "set name: 1 to 32 characters" end
    local radius = math.floor(number(d.radius, 10, 250, 60))
    local items = {}
    if type(d.items) == "table" then
        for i = 1, math.min(#d.items, 8) do
            local o = d.items[i]
            if type(o) ~= "table" or not GM.objectiveTypes[o.type] then return nil, "objective " .. i .. ": choose a type" end
            local item = { type = o.type, text = text(o.text, 80) }
            if o.type == "hook" then
                item.hook = type(o.hook) == "string" and #o.hook <= 100 and o.hook:match("^[%w_%-]+:[%w_%-]+$") or nil
                if not item.hook then return nil, "objective " .. i .. ": choose a type" end
            end
            if o.type == "custom" and not item.text then return nil, "objective " .. i .. ": write what players must do" end
            if o.type == "kill" or o.type == "interact" then item.count = math.floor(number(o.count, 1, 100, 5)) end
            if o.type == "hold" or o.type == "survive" then item.seconds = math.floor(number(o.seconds, 5, 1800, 60)) end
            if o.type == "reach" or o.type == "hold" then
                item.size = number(o.size, 2, 50, DEFAULT_SIZE)
                item.distance = number(o.distance, 0, radius, 0)
                item.direction = number(o.direction, -180, 180, 0)
            end
            if o.type == "hold" then item.players = math.floor(number(o.players, 1, 16, 1)) end
            items[i] = item
        end
    end
    if #items == 0 then return nil, "add at least one objective" end
    return {
        name = name, radius = radius, items = items, ordered = d.ordered ~= false,
        timeLimit = math.floor(number(d.timeLimit, 0, 7200, 0)), failOnWipe = d.failOnWipe == true or nil,
        lootId = presetId(d.lootId),
        intro = text(d.intro, 160), success = text(d.success, 160), failure = text(d.failure, 160),
    }
end

function clean.boss(d)
    local name, record = text(d.name, 32), character(d.record)
    if not name then return nil, "boss name: 1 to 32 characters" end
    if not record then return nil, "choose a boss model" end
    return {
        interactId = presetId(d.interactId), objectivesId = presetId(d.objectivesId), lootId = presetId(d.lootId),
        name = name, record = record,
        health = number(d.health, 0.1, 100, 5),
        height = number(d.height, 1, 8, 2.4),
        scaling = d.scaling ~= false,
        intro = text(d.intro, 160), outro = text(d.outro, 160), -- nil: the usual message
    }
end

function clean.squad(d)
    local name = text(d.name, 32)
    if not name then return nil, "squad name: 1 to 32 characters" end
    if type(d.units) ~= "table" then return nil, "add at least one unit" end
    local units, total = {}, 0
    for i = 1, math.min(8, #d.units) do
        local u = d.units[i]
        local record = type(u) == "table" and character(u.record) or nil
        if not record then return nil, "unit " .. i .. ": choose a model" end
        local count = math.floor(number(u.count, 1, GM.maxSquad, 1))
        units[#units + 1] = { record = record, count = count }
        total = total + count
    end
    if total == 0 then return nil, "add at least one unit" end
    if total > GM.maxSquad then return nil, ("%d units: the limit is %d"):format(total, GM.maxSquad) end
    local pattern = (d.pattern == "line" or d.pattern == "cluster") and d.pattern or "ring"
    return { name = name, units = units, pattern = pattern, radius = number(d.radius, 2, 20, 6),
        interactId = presetId(d.interactId), objectivesId = presetId(d.objectivesId), lootId = presetId(d.lootId) }
end

function clean.av(d)
    local name = text(d.name, 32)
    if not name then return nil, "crash name: 1 to 32 characters" end
    if not avNames[d.record] or fallNames[d.record] then return nil, "choose an AV" end
    return {
        name = name, record = d.record,
        distance = number(d.distance, 40, 200, 110),
        height = number(d.height, 20, 150, 70),
        flightSeconds = number(d.flightSeconds, 2, 15, 5),
        direction = number(d.direction, -180, 180, 0),
        blastRadius = number(d.blastRadius, 3, 40, 12),
        blastDamage = number(d.blastDamage, 0, 500, 0),
        fireSeconds = number(d.fireSeconds, 0, 300, 90),
        squadId = presetId(d.squadId), bossId = presetId(d.bossId), -- nil: nobody
        interactId = presetId(d.interactId), objectivesId = presetId(d.objectivesId),
        spawnDelay = number(d.spawnDelay, 0, 60, 3), warningLead = number(d.warningLead, 0, 60, 6),
        cinematic = d.cinematic == true or nil,
        warning = text(d.warning, 160), arrival = text(d.arrival, 160),
    }
end

function clean.fall(d)
    local name = text(d.name, 32)
    if not name then return nil, "name: 1 to 32 characters" end
    if not fallNames[d.record] then return nil, "choose what falls" end
    return {
        name = name, record = d.record,
        distance = number(d.distance, 0, 150, 60), height = number(d.height, 40, 250, 160),
        flightSeconds = number(d.flightSeconds, 2, 15, 5), direction = number(d.direction, -180, 180, 0),
        spin = number(d.spin, -720, 720, 120), intact = d.intact == true or nil,
        blastRadius = number(d.blastRadius, 3, 40, 14), blastDamage = number(d.blastDamage, 0, 500, 0),
        fireSeconds = number(d.fireSeconds, 0, 300, 60),
        crater = number(d.crater, 0, 12, 5), sink = number(d.sink, 0, 3, 0.4), rim = number(d.rim, 0.3, 3, 1),
        debris = math.floor(number(d.debris, 0, 12, 0)), debrisRadius = number(d.debrisRadius, 8, 60, 30),
        squadId = presetId(d.squadId), bossId = presetId(d.bossId), interactId = presetId(d.interactId), objectivesId = presetId(d.objectivesId),
        spawnDelay = number(d.spawnDelay, 0, 60, 3), warningLead = number(d.warningLead, 0, 60, 6),
        cinematic = d.cinematic == true or nil, warning = text(d.warning, 160), arrival = text(d.arrival, 160),
    }
end

function clean.drop(d)
    local name = text(d.name, 32)
    if not name then return nil, "name: 1 to 32 characters" end
    if not avNames[d.record] or fallNames[d.record] then return nil, "choose an AV" end
    return {
        name = name, record = d.record,
        height = number(d.height, 15, 90, 45), run = number(d.run, 60, 170, 130),
        flySeconds = number(d.flySeconds, 4, 20, 9), fallSeconds = number(d.fallSeconds, 3, 20, 8),
        direction = number(d.direction, -180, 180, 0), hover = number(d.hover, 0, 3, 0.8),
        openSeconds = number(d.openSeconds, 1, 60, 5), life = number(d.life, 1, 60, 15),
        share = d.share == "opener" and "opener" or "near",
        lootId = presetId(d.lootId), squadId = presetId(d.squadId), bossId = presetId(d.bossId),
        interactId = presetId(d.interactId), objectivesId = presetId(d.objectivesId), spawnDelay = number(d.spawnDelay, 0, 60, 3),
        warningLead = number(d.warningLead, 0, 60, 6), cinematic = d.cinematic == true or nil,
        warning = text(d.warning, 160), arrival = text(d.arrival, 160), opened = text(d.opened, 160),
    }
end

local interactNames = {}
for _, m in ipairs(GM.interactModels) do interactNames[m.model] = true end
local function hookId(value)
    if type(value) ~= "string" or #value > 100 then return nil end
    return value:match("^[%w_%-]+:[%w_%-]+$")
end
local interactEffects = { none = true, spark = true, smoke = true, blast = true }

function clean.interact(d)
    local name = text(d.name, 32)
    if not name then return nil, "name: 1 to 32 characters" end
    if not interactNames[d.model] then return nil, "choose how it looks" end
    local prompt = text(d.prompt, 40)
    if not prompt then return nil, "what players do: 1 to 40 characters" end
    return {
        name = name, prompt = prompt, model = d.model,
        count = math.floor(number(d.count, 1, 8, 1)), spread = number(d.spread, 2, 40, 8),
        seconds = number(d.seconds, 0.5, 120, 5), players = math.floor(number(d.players, 1, 8, 1)),
        uses = math.floor(number(d.uses, 0, 50, 1)), cooldown = number(d.cooldown, 0, 600, 0), stays = d.stays == true or nil,
        effect = interactEffects[d.effect] and d.effect or "none", fuse = number(d.fuse, 0, 120, 0),
        blastRadius = number(d.blastRadius, 3, 40, 8), blastDamage = number(d.blastDamage, 0, 500, 0),
        check = hookId(d.check),
        lootId = presetId(d.lootId), squadId = presetId(d.squadId), objectivesId = presetId(d.objectivesId),
        spawnDelay = number(d.spawnDelay, 0, 60, 2), intro = text(d.intro, 160), arrival = text(d.arrival, 160), done = text(d.done, 160),
    }
end

local poses, barks = { [""] = true }, { [""] = true }
for _, p in ipairs(GM.castPoses) do poses[p] = true end
for _, b in ipairs(GM.castBarks) do barks[b] = true end

function clean.cast(d)
    local name = text(d.name, 32)
    if not name then return nil, "name: 1 to 32 characters" end
    local record = character(d.record)
    if not record then return nil, "choose a model" end
    local lines = {}
    if type(d.lines) == "table" then
        for i = 1, math.min(#d.lines, 10) do
            local line = text(d.lines[i], 160)
            if line then lines[#lines + 1] = line end
        end
    end
    return { name = name, record = record, pose = poses[d.pose or ""] and d.pose or "", mortal = d.mortal == true or nil, lines = lines }
end

-- Every preset may sit in a folder, which only the panel's lists use.
for kind, check in pairs(clean) do
    clean[kind] = function(d)
        local def, bad = check(d)
        if def then def.folder = text(d.folder, 24) end
        return def, bad
    end
end

-- ------------------------------------------------------------------- presets

local presets = { boss = {}, squad = {}, av = {}, fall = {}, drop = {}, interact = {}, cast = {}, objectives = {}, loot = {} } -- kind -> id -> def
local status = {}                                  -- record -> "tested" | "broken"
local shipped = {}
for _, record in ipairs(GM.testedModels) do shipped[record] = "tested" end

local function load()
    local rows, why = Open77.kvp.find("preset:", 500)
    if not rows then return print("[gm] presets not loaded: " .. tostring(why)) end
    for _, row in ipairs(rows) do
        local kind, id = row.key:match("^preset:(%l+):([%w_%-]+)$")
        local ok, value = pcall(json.decode, row.value)
        local def = ok and kind and clean[kind] and type(value) == "table" and clean[kind](value) or nil
        if def then presets[kind][id] = def else print("[gm] skipped a bad preset: " .. tostring(row.key)) end
    end
    local marksRows = Open77.kvp.find("model:", 500) or {}
    for _, row in ipairs(marksRows) do
        local record = row.key:sub(7)
        record = avNames[record] and record or character(record)
        if record and (row.value == "tested" or row.value == "broken") then status[record] = row.value end
    end
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function listOf(kind)
    local list = {}
    if kind == "boss" then
        for id, b in pairs(GM.bosses) do
            list[#list + 1] = {
                id = "builtin:" .. id, builtin = true, name = b.name, record = b.record,
                health = b.health, height = b.height or 2.4, scaling = true,
            }
        end
    end
    if kind == "interact" then
        list[#list + 1] = {
            id = "builtin:hack", builtin = true, name = "Hack the terminal", prompt = "Hold to hack", model = "electronics.monitor.device",
            count = 1, spread = 8, seconds = 8, players = 1, uses = 1, cooldown = 0, effect = "spark", fuse = 0, blastRadius = 8,
            blastDamage = 0, spawnDelay = 2,
        }
        list[#list + 1] = {
            id = "builtin:search", builtin = true, name = "Search the cases", prompt = "Hold to search", model = "military.case.large",
            count = 3, spread = 8, seconds = 4, players = 1, uses = 1, cooldown = 0, effect = "none", fuse = 0, blastRadius = 8,
            blastDamage = 0, spawnDelay = 2, stays = true,
        }
        list[#list + 1] = {
            id = "builtin:charge", builtin = true, name = "Blow the generator", prompt = "Hold to plant a charge", model = "industrial.generator",
            count = 1, spread = 8, seconds = 6, players = 1, uses = 1, cooldown = 0, effect = "blast", fuse = 8, blastRadius = 8,
            blastDamage = 0, spawnDelay = 2,
        }
    end
    if kind == "drop" then
        list[#list + 1] = {
            id = "builtin:default", builtin = true, name = "Supply drop", record = GM.dropAv, height = 45, run = 130,
            flySeconds = 9, fallSeconds = 8, direction = 0, hover = 0.8, openSeconds = 5, life = 15, share = "near",
        }
    end
    if kind == "fall" then
        list[#list + 1] = {
            id = "builtin:wreck", builtin = true, name = "Burning wreck", record = "Vehicle.q306_orbital_capsule", crater = 6, sink = 1, rim = 1,
            distance = 60, height = 160, flightSeconds = 5, direction = 0, spin = 120, blastRadius = 14, blastDamage = 0,
            fireSeconds = 60, debris = 6, debrisRadius = 30,
        }
        list[#list + 1] = {
            id = "builtin:capsule", builtin = true, name = "Orbital capsule", record = "Vehicle.q306_orbital_capsule", crater = 5, sink = 0.4, rim = 1,
            distance = 60, height = 160, flightSeconds = 6, direction = 0, spin = 0, intact = true, blastRadius = 8,
            blastDamage = 0, fireSeconds = 20, debris = 0, debrisRadius = 30,
        }
    end
    if kind == "av" then
        list[#list + 1] = {
            id = "builtin:default", builtin = true, name = "Standard crash", record = GM.av.record,
            distance = GM.av.distance, height = GM.av.height, flightSeconds = GM.av.flightSeconds, direction = 0,
            blastRadius = GM.av.blastRadius, blastDamage = GM.av.blastDamage, fireSeconds = GM.av.fireSeconds,
        }
    end
    if kind == "objectives" then
        list[#list + 1] = {
            id = "builtin:clear", builtin = true, name = "Clear the area", radius = 60, ordered = true, timeLimit = 0,
            items = { { type = "enemies" } },
        }
        list[#list + 1] = {
            id = "builtin:hold", builtin = true, name = "Hold the ground", radius = 60, ordered = true, timeLimit = 0,
            items = {
                { type = "reach", size = 8, distance = 0, direction = 0 },
                { type = "hold", seconds = 60, size = 15, distance = 0, direction = 0, players = 1 },
            },
        }
    end
    if kind == "squad" then
        list[#list + 1] = {
            id = "builtin:default", builtin = true, name = "Maelstrom four", pattern = "ring", radius = 6,
            units = { { record = GM.minion, count = 4 } },
        }
    end
    if kind == "squad" then
        list[#list + 1] = {
            id = "builtin:arasaka", builtin = true, name = "Arasaka security", pattern = "cluster", radius = 6,
            units = {
                { record = "Character.arasaka_security1_ranged1_kenshin_ma", count = 3 },
                { record = "Character.arasaka_security1_melee1_baton_ma", count = 1 },
                { record = "Character.arasaka_soldier1_ranged3_masamune_mah_rare", count = 1 },
            },
        }
        list[#list + 1] = {
            id = "builtin:militech", builtin = true, name = "Militech patrol", pattern = "cluster", radius = 6,
            units = {
                { record = "Character.militech_ranger1_ranged1_saratoga_ma", count = 3 },
                { record = "Character.militech_ranger2_ranged2_ajax_ma", count = 1 },
                { record = "Character.militech_enforcer2_shotgun2_tactician_mah_rare", count = 1 },
            },
        }
    end
    for id, def in pairs(presets[kind]) do
        local row = { id = id }
        for k, v in pairs(def) do row[k] = v end
        list[#list + 1] = row
    end
    table.sort(list, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return list
end

local sequence = 0
local function send(playerId, event, value)
    local ok, encoded, why = pcall(json.encode, value)
    if not ok or type(encoded) ~= "string" then
        return print("[gm] panel encode failed: " .. tostring(ok and why or encoded))
    end
    -- One event string may hold 16 KiB: cut into parts, never inside a UTF-8 character.
    sequence = sequence + 1
    local cuts, at = {}, 1
    while at <= #encoded do
        local last = math.min(at + 11999, #encoded)
        while last < #encoded and (encoded:byte(last + 1) & 0xC0) == 0x80 do last = last - 1 end
        cuts[#cuts + 1] = encoded:sub(at, last)
        at = last + 1
    end
    for i, part in ipairs(cuts) do
        TriggerClientEvent(event, playerId, part, i, #cuts, sequence)
    end
end

local function sendState(playerId)
    local scenes = {}
    for id in pairs(GM.scenes) do scenes[#scenes + 1] = id end
    table.sort(scenes)
    -- One message per part: the page merges them.
    local hookTypes, hookChecks = GM.hookList()
    send(playerId, "gm_events:panel:state", { part = "hooks", hookTypes = hookTypes, hookChecks = hookChecks })
    send(playerId, "gm_events:panel:state", {
        part = "base", scenes = scenes, avModels = GM.avModels, fallModels = GM.fallModels, interactModels = GM.interactModels, castPoses = GM.castPoses, castBarks = GM.castBarks,
        maxSquad = GM.maxSquad, canEdit = allowed(playerId, EDIT),
        chimera = GetResourceState("open77_chimera") == "running",
    })
    local merged = {}
    for record, value in pairs(shipped) do merged[record] = value end
    for record, value in pairs(status) do merged[record] = value end
    send(playerId, "gm_events:panel:state", { part = "status", status = merged })
    if allowed(playerId, EDIT) then
        local settings = {}
        for _, key in ipairs({ "lootMethod", "lootResource", "lootExport", "lootShare", "lootMinSeconds", "lootGroundSeconds" }) do
            settings[key] = GM[key]
        end
        send(playerId, "gm_events:panel:state", { part = "lootInfo", lootItems = GM.lootItems(), lootSettings = settings })
        local values = {}
        for key in pairs(GM.announceKeys) do values[key] = GM[key] end
        send(playerId, "gm_events:panel:state", { part = "announce", announce = values })
    end
    for _, kind in ipairs({ "boss", "squad", "av", "fall", "drop", "interact", "cast", "objectives", "loot" }) do
        send(playerId, "gm_events:panel:state", { part = kind, [kind] = listOf(kind) })
    end
end

local function sendLive(playerId)
    local bosses, hostiles = {}, 0
    for _, n in pairs(GM.living()) do
        local npc = GM.readNpc(n)
        if npc and npc.health > 0 then
            if n.boss then
                if #bosses < 12 then
                    bosses[#bosses + 1] = {
                        name = n.name, players = n.players or 1,
                        extra = npc.repairing and "repairing" or npc.phase or "",
                        percent = math.max(1, math.ceil(npc.health / npc.maxHealth * 100)),
                    }
                end
            else
                hostiles = hostiles + 1
            end
        end
    end
    local players = {}
    for _, id in ipairs(Open77.players.all()) do
        if #players < 64 then players[#players + 1] = { id = id, name = Open77.players.name(id) or ("Player " .. id) } end
    end
    send(playerId, "gm_events:panel:live", {
        bosses = bosses, hostiles = hostiles, players = players,
        objectives = GM.objectiveList(), interacts = GM.interactList(),
        cast = GM.castList(), bookmarks = GM.bookmarkList(),
        ghost = core.isGhost(playerId), mark = core.mark(playerId) ~= nil,
    })
end

local function open(playerId)
    viewers[playerId] = true
    TriggerClientEvent("gm_events:panel:open", playerId)
    sendState(playerId)
    sendLive(playerId)
end

-- -------------------------------------------------------------------- target

local function target(playerId, data, distance)
    if data.target == "mark" then
        local mark = core.mark(playerId)
        local me, why = core.freshPlayer(playerId)
        if not me then return nil, why end
        if not mark or mark.bucket ~= (me.bucket or 0) then return nil, "no mark set here" end
        return mark
    end
    if type(data.target) == "string" and data.target:match("^b:") then
        return GM.bookmarkAnchor(data.target:sub(3), playerId)
    end
    local id = math.tointeger(tonumber(data.target))
    if id and id > 0 then
        local online = false
        for _, other in ipairs(Open77.players.all()) do online = online or other == id end
        if not online then return nil, "that player has left" end
        local anchor, why = core.anchorFor(id, 12, true)
        if not anchor then return nil, "that player: " .. tostring(why) end
        anchor.source = playerId -- reports go to the staff member
        return anchor
    end
    return core.anchorFor(playerId, distance, true)
end

-- ------------------------------------------------------------------- actions

-- op -> the typed command whose right it needs
local spawnRight = { boss = "command.gm.boss", squad = "command.gm.wave", av = "command.gm.av", fall = "command.gm.fall", drop = "command.gm.drop",
    interact = "command.gm.interact", cast = "command.gm.cast",
    objectives = "command.gm.objectives" }
local function spawnDistance(kind)
    return kind == "boss" and GM.npcDistance or kind == "squad" and GM.npcDistance + 6 or GM.eventDistance
end

local function find(kind, id)
    for _, def in ipairs(listOf(kind)) do
        if def.id == id then return def end
    end
end

-- The loot a thing gives, resolved as it is spawned.
local function attachLoot(playerId, def)
    if not def or not def.lootId then return true end
    if not allowed(playerId, LOOT) then return nil, "this gives loot: you need " .. LOOT end
    local found = find("loot", def.lootId)
    local set, bad = nil, "the attached loot table no longer exists"
    if found then set, bad = clean.loot(found) end
    if not set then return nil, bad end
    def.lootDef = set
    return true
end

-- Turn a crash's references into what to spawn. The same rights apply as for
-- spawning those things on their own.
local function attach(playerId, def)
    if def.squadId then
        if not allowed(playerId, spawnRight.squad) then return nil, "you need " .. spawnRight.squad end
        local found = find("squad", def.squadId)
        local squad, bad = nil, "the attached squad no longer exists"
        if found then squad, bad = clean.squad(found) end
        if not squad then return nil, bad end
        local paid, noLoot = attachLoot(playerId, squad)
        if not paid then return nil, noLoot end
        def.squadDef = squad
    end
    if def.bossId == "chimera" then
        if not allowed(playerId, "command.gm.chimera") then return nil, "you need command.gm.chimera" end
        if GetResourceState("open77_chimera") ~= "running" then return nil, "open77_chimera is not running" end
        def.withChimera = true
    elseif def.bossId then
        if not allowed(playerId, spawnRight.boss) then return nil, "you need " .. spawnRight.boss end
        local found = find("boss", def.bossId)
        local boss, bad = nil, "the attached boss no longer exists"
        if found then boss, bad = clean.boss(found) end
        if not boss then return nil, bad end
        local paid, noLoot = attachLoot(playerId, boss)
        if not paid then return nil, noLoot end
        def.bossDef = boss
    end
    return true
end

-- Anything can bring an interactable, which may bring its own loot and alarm squad.
local function attachInteract(playerId, def)
    if not def.interactId then return true end
    if not allowed(playerId, spawnRight.interact) then return nil, "you need " .. spawnRight.interact end
    local found = find("interact", def.interactId)
    local one, bad = nil, "the attached interactable no longer exists"
    if found then one, bad = clean.interact(found) end
    if not one then return nil, bad end
    one.objectivesId = nil -- the event it comes with has its own
    local squadOk, noSquad = attach(playerId, one)
    if not squadOk then return nil, noSquad end
    local paid, noLoot = attachLoot(playerId, one)
    if not paid then return nil, noLoot end
    def.interactDef = one
    return true
end

local function attachObjectives(playerId, def, comes)
    if not def.objectivesId then return true end
    if not allowed(playerId, spawnRight.objectives) then return nil, "you need " .. spawnRight.objectives end
    local found = find("objectives", def.objectivesId)
    local set, bad = nil, "the attached objectives no longer exist"
    if found then set, bad = clean.objectives(found) end
    if not set then return nil, bad end
    local never = GM.objectivesImpossible(set, comes)
    if never then return nil, set.name .. ": " .. never end
    local missing = GM.hooksMissing(set)
    if missing then return nil, set.name .. ": " .. missing end
    local can, full = GM.canStartObjectives()
    if not can then return nil, full end
    local paid, noLoot = attachLoot(playerId, set)
    if not paid then return nil, noLoot end
    def.objectivesDef = set
    return true
end

-- Run an action with a set (or none) started around it.
local function withObjectives(anchor, set, action, step)
    if not set then return action(anchor, step) end
    local run, problem = GM.startObjectives(anchor, set, true)
    if not run then return false, problem end
    local copy = {} -- the staff member's mark must not carry the event
    for k, v in pairs(anchor) do copy[k] = v end
    copy.event = run
    local ok, reason = action(copy, step)
    if ok then GM.objectivesReady(run) else GM.cancelObjectives(run) end
    return ok, reason
end

local ops = {}

-- For server/hooks.lua: a preset by its id or name, at a place a script chose.
function GM.startPreset(kind, wanted, anchor)
    local found
    for _, def in ipairs(listOf(kind)) do
        if def.id == wanted or def.name == wanted then found = found or def end
    end
    if not found then return false, "no such preset" end
    local def, bad = clean[kind](found)
    if not def then return false, bad end
    if kind == "interact" then
        local ok, why = attach(SCRIPT, def)
        if not ok then return false, why end
    end
    local paid, noLoot = attachLoot(SCRIPT, def)
    if not paid then return false, noLoot end
    if kind == "interact" then
        local linked, why = attachObjectives(SCRIPT, def, { interact = true })
        if not linked then return false, why end
    end
    local ok, why = withObjectives(anchor, def.objectivesDef, core.actions[kind], { def = def })
    return ok, why or def.name
end

function ops.bookmark(playerId, d)
    if not allowed(playerId, EDIT) then return false, "you need " .. EDIT end
    if d.delete ~= nil then return GM.deleteBookmark(playerId, tostring(d.delete)) end
    local name = text(d.name, 32)
    if not name then return false, "bookmark name: 1 to 32 characters" end
    return GM.saveBookmark(playerId, name, text(d.group, 24))
end

function ops.cast(playerId, d)
    if not allowed(playerId, spawnRight.cast) then return false, "you need " .. spawnRight.cast end
    local data = {}
    if d.what == "say" then
        if not allowed(playerId, "command.gm.say") then return false, "you need command.gm.say" end
        data.text = text(d.text, 160)
        if not data.text then return false, "line: 1 to 160 characters" end
        data.volume = (d.volume == "whisper" or d.volume == "shout") and d.volume or "normal"
    end
    if d.what == "say" or d.what == "bark" then
        data.bark = type(d.bark) == "string" and barks[d.bark] and d.bark or ""
        if d.what == "bark" and data.bark == "" then return false, "choose a voice first" end
    elseif d.what == "pose" then
        if type(d.pose) ~= "string" or d.pose == "" or not poses[d.pose] then return false, "choose a pose first" end
        data.pose = d.pose
    elseif d.what == "come" then
        local me, why = core.freshPlayer(playerId)
        if not me then return false, why end
        data.to = { x = me.position.x, y = me.position.y, z = me.position.z, bucket = me.bucket or 0 }
        data.run = d.run == true
    elseif d.what == "go" then
        local to, why = target(playerId, d, 10)
        if not to then return false, why end
        data.to, data.run = to, d.run == true
    elseif d.what == "follow" then
        data.player = playerId
        local id = math.tointeger(tonumber(d.target))
        if id and id > 0 then data.player = id end
    end
    return GM.directCast(playerId, d.id, d.what, data)
end

function ops.interacts(playerId, d)
    if not allowed(playerId, spawnRight.interact) then return false, "you need " .. spawnRight.interact end
    return GM.endInteract(d.id)
end

function ops.objectives(playerId, d)
    if not allowed(playerId, spawnRight.objectives) then return false, "you need " .. spawnRight.objectives end
    local ok, reason = GM.controlObjectives(d.id, d.what, d.index)
    if ok then print(("[gm] player %d: %s"):format(playerId, reason)) end
    return ok, reason
end

-- Spawn a saved preset, or an unsaved draft from the editor.
function ops.spawn(playerId, d)
    local right = spawnRight[d.kind]
    if not right then return false, "unknown kind" end
    if not allowed(playerId, right) then return false, "you need " .. right end
    local source = d.draft
    if source ~= nil then
        -- A draft is arbitrary content, so it needs the editor right too.
        if not allowed(playerId, EDIT) then return false, "you need " .. EDIT end
        if type(source) ~= "table" then return false, "bad draft" end
    else
        source = find(d.kind, d.id)
        if not source then return false, "that preset no longer exists" end
    end
    local def, bad = clean[d.kind](source)
    if not def then return false, bad end
    if d.kind == "interact" then
        local squadOk, noSquad = attach(playerId, def)
        if not squadOk then return false, noSquad end
    end
    local withOne, noOne = attachInteract(playerId, def)
    if not withOne then return false, noOne end
    local lands = d.kind == "av" or d.kind == "fall" or d.kind == "drop"
    if lands then
        local attached, missing = attach(playerId, def)
        if not attached then return false, missing end
    end
    local paid, noLoot = attachLoot(playerId, def)
    if not paid then return false, noLoot end
    local boss = d.kind == "boss" or def.bossDef ~= nil or def.withChimera == true
    local linked, notLinked = attachObjectives(playerId, def, {
        boss = boss, enemies = boss or d.kind == "squad" or (d.kind ~= "interact" and def.squadDef ~= nil),
        interact = d.kind == "interact" or def.interactDef ~= nil,
    })
    if not linked then return false, notLinked end
    local anchor, why = target(playerId, d, spawnDistance(d.kind))
    if not anchor then return false, why end
    -- A crash starts its own at impact; a boss or squad starts them with itself.
    local ok, reason = withObjectives(anchor, not lands and def.objectivesDef or nil, function(at, step)
        local done, what = core.actions[d.kind](at, step)
        if done and def.interactDef and not lands then
            local placed, problem = core.actions.interact(at, { def = def.interactDef, offset = 4 })
            if not placed then core.reply(playerId, nil, false, "interactable: " .. tostring(problem)) end
        end
        return done, what
    end, { def = def })
    return ok, reason or (def.name .. " started")
end

function ops.save(playerId, d)
    if not allowed(playerId, EDIT) then return false, "you need " .. EDIT end
    if not clean[d.kind] or type(d.def) ~= "table" then return false, "bad preset" end
    if d.kind == "loot" and not allowed(playerId, LOOT) then return false, "you need " .. LOOT end
    local def, bad = clean[d.kind](d.def)
    if not def then return false, bad end
    local id = type(d.id) == "string" and presets[d.kind][d.id] and d.id or nil
    if not id then
        if count(presets[d.kind]) >= MAX_PRESETS then return false, "preset limit reached (" .. MAX_PRESETS .. ")" end
        local n = 1
        while presets[d.kind]["p" .. n] do n = n + 1 end
        id = "p" .. n
    end
    local encoded, bad2 = json.encode(def)
    if type(encoded) ~= "string" then return false, "not saved: " .. tostring(bad2) end
    local ok, why = Open77.kvp.set("preset:" .. d.kind .. ":" .. id, encoded)
    if not ok then return false, "not saved: " .. tostring(why) end
    presets[d.kind][id] = def
    print(("[gm] player %d saved %s preset '%s'"):format(playerId, d.kind, def.name))
    return true, def.name .. " saved", true
end

function ops.delete(playerId, d)
    if not allowed(playerId, EDIT) then return false, "you need " .. EDIT end
    local def = clean[d.kind] and type(d.id) == "string" and presets[d.kind][d.id] or nil
    if not def then return false, "only saved presets can be deleted" end
    local ok, why = Open77.kvp.delete("preset:" .. d.kind .. ":" .. d.id)
    if not ok then return false, "not deleted: " .. tostring(why) end
    presets[d.kind][d.id] = nil
    print(("[gm] player %d deleted %s preset '%s'"):format(playerId, d.kind, def.name))
    return true, def.name .. " deleted", true
end

-- key -> longest text; the host checks type and choices as well
GM.announceKeys = {
    announceMethod = 20, announceResource = 64, announceExport = 64, announceTitle = 40, announceSeconds = 0,
    msgBossAppeared = 200, msgBossHealth = 200, msgBossDefeated = 200,
    msgCrashWarning = 200, msgCrashSurvivors = 200, msgBossfightIntro = 200,
    msgChimeraGas = 200, msgChimeraCore = 200,
}

function ops.announceSave(playerId, d)
    if not allowed(playerId, EDIT) then return false, "you need " .. EDIT end
    if type(d.values) ~= "table" then return false, "bad settings" end
    local changes = {}
    for key, longest in pairs(GM.announceKeys) do
        local value = d.values[key]
        if value ~= nil then
            if longest == 0 then
                value = math.floor(number(value, 2, 60, 8))
            elseif value == "" then
                value = "-" -- an emptied box turns the message off
            else
                value = text(value, longest)
                if not value then return false, key .. ": 1 to " .. longest .. " characters" end
            end
            if (key == "announceResource" or key == "announceExport") and not value:match("^[%w_%-]+$") then
                return false, key .. ": letters, numbers, _ and - only"
            end
            if value ~= GM[key] then changes[#changes + 1] = { key, value } end
        end
    end
    for _, change in ipairs(changes) do
        local ok, why = Open77.tunables.set(change[1], change[2])
        if not ok then return false, change[1] .. " not saved: " .. tostring(why), true end
    end
    if #changes > 0 then print(("[gm] player %d changed %d announcement settings"):format(playerId, #changes)) end
    return true, #changes == 0 and "nothing changed" or "announcements saved", #changes > 0
end

-- Everyone sees a test: it must travel the real path to prove anything.
function ops.announceTest(playerId)
    if not allowed(playerId, EDIT) then return false, "you need " .. EDIT end
    local ok, why = GM.say("test", GM.msgBossAppeared == "-" and "Test announcement" or GM.msgBossAppeared,
        { boss = "Test boss", players = 1, percent = 50 })
    return ok, why or ("sent by " .. GM.announceMethod)
end

local lootChoices = {
    lootMethod = { event = true, export = true, ground = true, off = true },
    lootShare = { everyone = true, killer = true },
}

function ops.lootSave(playerId, d)
    if not allowed(playerId, EDIT) then return false, "you need " .. EDIT end
    if not allowed(playerId, LOOT) then return false, "you need " .. LOOT end
    local v = type(d.values) == "table" and d.values or {}
    for key, choices in pairs(lootChoices) do
        if v[key] ~= nil and not choices[v[key]] then return false, key .. ": unknown choice" end
    end
    local wanted = {
        lootMethod = v.lootMethod, lootShare = v.lootShare,
        lootMinSeconds = v.lootMinSeconds and math.floor(number(v.lootMinSeconds, 0, 3600, 10)),
        lootGroundSeconds = v.lootGroundSeconds and math.floor(number(v.lootGroundSeconds, 10, 3600, 300)),
    }
    for _, key in ipairs({ "lootResource", "lootExport" }) do
        local value = v[key]
        if value == "" then value = "-" end
        if value ~= nil then
            if type(value) ~= "string" or #value > 64 or not value:match("^[%w_%-]+$") then
                return false, key .. ": letters, numbers, _ and - only"
            end
            wanted[key] = value
        end
    end
    for key, value in pairs(wanted) do
        if value ~= GM[key] then
            local ok, why = Open77.tunables.set(key, value)
            if not ok then return false, key .. " not saved: " .. tostring(why), true end
        end
    end
    print(("[gm] player %d saved loot settings"):format(playerId))
    return true, "loot settings saved", true
end

function ops.lootTest(playerId, d)
    if not allowed(playerId, EDIT) then return false, "you need " .. EDIT end
    if not allowed(playerId, LOOT) then return false, "you need " .. LOOT end
    if not find("loot", d.id) then return false, "save the table first" end
    return GM.lootTest(clean.loot(find("loot", d.id)), playerId)
end

local phases = { armored = true, exposed = true, gas = true, core = true, endrepair = true }

function ops.chimera(playerId, d)
    local right = "command.gm.chimera"
    if not allowed(playerId, right) then return false, "you need " .. right end
    if d.phase ~= nil then
        if not phases[d.phase] then return false, "unknown phase" end
        return core.actions.chimeraPhase(nil, { phase = d.phase })
    end
    if type(d.def) ~= "table" then return false, "bad settings" end
    local name = text(d.def.name, 32)
    if not name then return false, "boss name: 1 to 32 characters" end
    local link = { objectivesId = presetId(d.def.objectivesId), lootId = presetId(d.def.lootId) }
    local paid, noLoot = attachLoot(playerId, link)
    if not paid then return false, noLoot end
    local linked, notLinked = attachObjectives(playerId, link, { boss = true, enemies = true })
    if not linked then return false, notLinked end
    local anchor, why = target(playerId, d, GM.chimera.distance)
    if not anchor then return false, why end
    return withObjectives(anchor, link.objectivesDef, core.actions.chimera, { def = {
        name = name, health = number(d.def.health, 0.1, 100, 2), damage = number(d.def.damage, 0, 5, 0.8),
        scaling = d.def.scaling ~= false, lootDef = link.lootDef,
    } })
end

-- Shared verdict on a model, for every staff member.
function ops.status(playerId, d)
    if not allowed(playerId, EDIT) then return false, "you need " .. EDIT end
    local record = type(d.record) == "string" and avNames[d.record] and d.record or character(d.record)
    if not record then return false, "bad model" end
    local ok, why
    if d.value == "tested" or d.value == "broken" then
        if not status[record] and count(status) >= MAX_STATUS then return false, "too many model notes" end
        ok, why = Open77.kvp.set("model:" .. record, d.value)
        if ok then status[record] = d.value end
    else
        ok, why = true, nil
        if status[record] then ok, why = Open77.kvp.delete("model:" .. record) end
        if ok then status[record] = nil end
    end
    if not ok then return false, "not saved: " .. tostring(why) end
    return true, "model note updated", true
end

-- Buttons that are exactly a typed command.
local buttons = {
    ["gm.boom"] = true, ["gm.fire"] = true, ["gm.cinematic"] = true, ["gm.scene"] = true, ["gm.stop"] = true,
    ["gm.killboss"] = true, ["gm.bring"] = true, ["gm.ghost"] = true, ["gm.mark"] = true, ["gm.unmark"] = true,
    ["gm.announce"] = true, ["gm.clean"] = true,
}
local placedButtons = { ["gm.boom"] = true, ["gm.fire"] = true, ["gm.cinematic"] = true, ["gm.scene"] = true }

function ops.command(playerId, d)
    if not buttons[d.name] then return false, "unknown button" end
    local right = "command." .. d.name
    if not allowed(playerId, right) then return false, "you need " .. right end
    local args = {}
    if d.name == "gm.announce" then
        args[1] = text(d.arg, 160)
        if not args[1] then return false, "announcement: 1 to 160 characters" end
    elseif d.arg ~= nil then
        args[1] = tostring(d.arg):sub(1, 64)
    end
    args.n = #args
    local anchor
    if placedButtons[d.name] then
        local why
        anchor, why = target(playerId, d, GM.eventDistance)
        if not anchor then return false, why end
    end
    local ok, reason = core.withAnchor(anchor, core.handlers[d.name], playerId, args)
    return ok, reason or (ok and "done" or "failed")
end

-- ------------------------------------------------------------------- network

RegisterCommand("gm.panel", function(playerId)
    if playerId and playerId > 0 then open(playerId) end
end, true)

RegisterNetEvent("gm_events:panel:request", function()
    local playerId = tonumber(source)
    if not playerId or playerId <= 0 then return end
    local now = GetGameTimer()
    if now - (lastCall[playerId] or -1000) < 250 then return end
    lastCall[playerId] = now
    -- Silent for everyone else: the key does nothing without the right.
    if allowed(playerId, "command.gm.panel") then open(playerId) end
end)

RegisterNetEvent("gm_events:panel:closed", function()
    local playerId = tonumber(source)
    if playerId then viewers[playerId] = nil end
end)

RegisterNetEvent("gm_events:panel:call", function(encoded)
    local playerId = tonumber(source)
    if not playerId or playerId <= 0 then return end
    if type(encoded) ~= "string" or #encoded > 8192 then return end
    local now = GetGameTimer()
    if now - (lastCall[playerId] or -1000) < 150 then return end
    lastCall[playerId] = now
    if not allowed(playerId, "command.gm.panel") then return end

    local decoded, d = pcall(json.decode, encoded)
    local op = decoded and type(d) == "table" and type(d.op) == "string" and ops[d.op] or nil
    if not op then return end
    local ok, a, b, changed = pcall(op, playerId, d)
    if not ok then
        print("[gm] panel error: " .. tostring(a))
        a, b, changed = false, "internal error, see the server console", false
    end
    print(("[gm] panel player=%d op=%s ok=%s %s"):format(playerId, d.op, tostring(a == true), tostring(b or "")))
    send(playerId, "gm_events:panel:result", { ok = a == true, text = tostring(b or ""), id = tostring(d.req or "") })
    if changed then
        for viewer in pairs(viewers) do sendState(viewer) end
    end
    sendLive(playerId)
end)

AddEventHandler("onPlayerDisconnected", function(id)
    local playerId = tonumber(id)
    if playerId then viewers[playerId], lastCall[playerId] = nil, nil end
end)

CreateThread(function()
    while true do
        Wait(1000)
        for playerId in pairs(viewers) do
            if allowed(playerId, "command.gm.panel") then sendLive(playerId) else viewers[playerId] = nil end
        end
    end
end)

load()
print(("gm_events panel ready: %d boss, %d squad, %d AV, %d falling, %d drop, %d interactable, %d character, %d objective, %d loot presets"):format(
    count(presets.boss), count(presets.squad), count(presets.av), count(presets.fall), count(presets.drop), count(presets.interact), count(presets.cast), count(presets.objectives), count(presets.loot)))
