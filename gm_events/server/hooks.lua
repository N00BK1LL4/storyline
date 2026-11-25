-- Where other resources plug in their own objective and interaction systems.
-- Everything here is for server scripts of the same server; players never reach it.
-- See README "Your own objectives and interactions" and examples/hooks_bridge.lua.
local core = GM.core
local MAX = 60

local types = {}  -- "resource:id" -> { id, label, resource }
local checks = {} -- "resource:id" -> { id, label, resource, export }

local function caller()
    local resource = GetInvokingResource()
    if not resource then return nil, "call this from another resource" end
    return resource
end

local function label(value, fallback)
    local text = type(value) == "string" and value:gsub("[%c<>]", ""):sub(1, 60) or ""
    return text ~= "" and utf8.len(text) and text or fallback
end

local function register(into, list, build)
    local resource, why = caller()
    if not resource then return nil, why end
    if type(list) ~= "table" then return nil, "give a list" end
    for key, entry in pairs(into) do if entry.resource == resource then into[key] = nil end end
    local made = 0
    for _, item in ipairs(list) do
        local id = type(item) == "table" and item.id
        if made < MAX and type(id) == "string" and #id <= 30 and id:match("^[%w_%-]+$") then
            local entry = build(item, resource)
            if entry then
                entry.id, entry.resource, entry.label = resource .. ":" .. id, resource, label(item.label, id)
                into[entry.id] = entry
                made = made + 1
            end
        end
    end
    print(("[gm] %s registered %d hook(s)"):format(resource, made))
    return made
end

exports("registerObjectiveTypes", function(list)
    return register(types, list, function() return {} end)
end)

exports("registerInteractChecks", function(list)
    return register(checks, list, function(item)
        local name = item.export
        if type(name) ~= "string" or not name:match("^[%w_%-]+$") then return nil end
        return { export = name }
    end)
end)

function GM.hookType(id) return types[id] end
function GM.hookCheck(id) return checks[id] end

local function sorted(from)
    local list = {}
    for _, entry in pairs(from) do list[#list + 1] = { id = entry.id, label = entry.label } end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end
function GM.hookList() return sorted(types), sorted(checks) end

-- Ask the owner's resource whether a use succeeds (a minigame, an item, a job...).
-- Calls back with true, or false and why. It may take its time.
function GM.runCheck(id, payload, done)
    local check = checks[id]
    if not check or GetResourceState(check.resource) ~= "running" then return done(false, "its resource is not running") end
    CreateThread(function()
        local promise, refused = Open77.exports.call(check.resource, check.export, payload)
        if not promise then return done(false, tostring(refused)) end
        local ok, result, why = pcall(function() return promise:await() end)
        if not ok then
            print("[gm] check " .. id .. " failed: " .. tostring(result))
            return done(false, "the check failed")
        end
        done(result == true, type(why) == "string" and why:sub(1, 40) or nil)
    end)
end

AddEventHandler("onResourceStop", function(name)
    for _, registry in ipairs({ types, checks }) do
        for key, entry in pairs(registry) do if entry.resource == name then registry[key] = nil end end
    end
end)

-- ------------------------------------------------------------ objective control

exports("getObjectives", function() return GM.objectiveList() end)

-- patch = { done = true, note = "2/5" }; for hooked and custom objectives.
exports("setObjective", function(runId, index, patch)
    local resource, why = caller()
    if not resource then return false, why end
    return GM.patchObjective(runId, index, type(patch) == "table" and patch or {})
end)

local function control(what)
    return function(runId)
        local resource, why = caller()
        if not resource then return false, why end
        local ok, text = GM.controlObjectives(runId, what)
        print(("[gm] %s: %s objectives %s: %s"):format(resource, what, tostring(runId), tostring(text)))
        return ok, text
    end
end
exports("completeObjectives", control("complete"))
exports("failObjectives", control("fail"))
exports("endObjectives", control("end"))

-- Start a saved or built-in preset from a script: kind "objectives" or "interact",
-- by its id or its name. at = { x, y, z, heading?, bucket? }
exports("start", function(kind, preset, at)
    local resource, why = caller()
    if not resource then return nil, why end
    if kind ~= "objectives" and kind ~= "interact" then return nil, "kind must be objectives or interact" end
    local x, y, z = tonumber(at and at.x), tonumber(at and at.y), tonumber(at and at.z)
    if not x or not y or not z then return nil, "at needs x, y and z" end
    local ok, text = GM.startPreset(kind, preset, {
        x = x, y = y, z = z, heading = tonumber(at.heading) or 0, bucket = math.tointeger(tonumber(at.bucket)) or 0, source = 0,
    })
    print(("[gm] %s started %s %s: %s"):format(resource, kind, tostring(preset), tostring(text)))
    if not ok then return nil, text end
    return true, text
end)

-- ------------------------------------------------------------- interact control

exports("getInteracts", function() return GM.interactPoints() end)

-- Your own prompt or menu decided that these players used a point. The wait and the
-- key are yours; reach, cooldown, uses and the number of players are still checked.
exports("useInteract", function(pointId, players)
    local resource, why = caller()
    if not resource then return false, why end
    return GM.useInteract(pointId, type(players) == "table" and players or { players })
end)

exports("removeInteract", function(groupId)
    local resource, why = caller()
    if not resource then return false, why end
    return GM.endInteract(groupId)
end)
