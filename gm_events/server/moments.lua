-- Moments: the points in an event where a server may want its own code to run. Owners
-- add hooks in the panel's Settings tab: at this moment, call that resource's function.
-- Each moment is also raised as gm_events:moment for scripts that prefer listening.
local MAX_HOOKS, ASK_MS, LOG = 40, 5000, 12

-- ask: the function answers true or false, and false stops the event from starting.
GM.moments = {
    { id = "beforeStart", label = "Before an event starts (may refuse it)", ask = true },
    { id = "eventStarted", label = "An event started" },
    { id = "impact", label = "A crash or falling object hit the ground" },
    { id = "dropLanded", label = "A supply drop landed" },
    { id = "dropOpened", label = "A supply drop was opened" },
    { id = "bossAppeared", label = "A boss appeared" },
    { id = "bossDefeated", label = "A boss was defeated" },
    { id = "enemyDefeated", label = "An event enemy was defeated" },
    { id = "playerJoined", label = "A player entered an objective area" },
    { id = "playerLeft", label = "A player left an objective area" },
    { id = "objectivesStarted", label = "An objective set started" },
    { id = "objectiveDone", label = "One objective was done" },
    { id = "objectivesCompleted", label = "An objective set was completed" },
    { id = "objectivesFailed", label = "An objective set failed" },
    { id = "interactUsed", label = "An interactable was used" },
    { id = "interactFinished", label = "All of an interactable was used up" },
    { id = "lootAwarded", label = "Loot was awarded" },
    { id = "characterSpoke", label = "A story character spoke" },
    { id = "stopped", label = "Staff stopped everything" },
}
local known = {}
for _, m in ipairs(GM.moments) do known[m.id] = m end

local hooks = {} -- id -> { moment, resource, export, on, last }
local sequence = 0

local function name(value)
    return type(value) == "string" and #value <= 64 and value:match("^[%w_%-]+$") or nil
end

-- The owner sets hooks up once; finishing locks them until the owner unlocks them.
local finished = Open77.kvp.get("setup:finished") == "yes"
function GM.setupFinished() return finished end
function GM.finishSetup(playerId, done)
    local ok, why = Open77.kvp.set("setup:finished", done and "yes" or "no")
    if not ok then return false, "not saved: " .. tostring(why) end
    finished = done
    print(("[gm] player %d %s the hooks"):format(playerId, done and "finished setup and locked" or "unlocked"))
    return true, done and "setup finished, hooks are locked" or "hooks unlocked", true
end
local LOCKED = "hooks are locked; press Unlock first"

local function load()
    local rows, why = Open77.kvp.find("hook:", 200)
    if not rows then return print("[gm] hooks not loaded: " .. tostring(why)) end
    for _, row in ipairs(rows) do
        local ok, h = pcall(json.decode, row.value)
        if ok and type(h) == "table" and known[h.moment] and name(h.resource) and name(h.export) then
            hooks[row.key:sub(6)] = { moment = h.moment, resource = h.resource, export = h.export, on = h.on ~= false }
        else
            print("[gm] skipped a bad hook: " .. tostring(row.key))
        end
    end
end

local function note(h, ok, text)
    h.last = { ok = ok, text = tostring(text):sub(1, 120) }
    if not ok then print(("[gm] hook %s -> %s:%s failed: %s"):format(h.moment, h.resource, h.export, tostring(text))) end
end

-- Must run in a thread. Returns whether the call itself worked, then what it answered.
local function call(h, payload)
    if GetResourceState(h.resource) ~= "running" then return false, h.resource .. " is not running" end
    local promise, refused = Open77.exports.call(h.resource, h.export, payload)
    if not promise then return false, tostring(refused) end
    local ok, a, b = pcall(function() return promise:await() end)
    if not ok then return false, tostring(a) end
    if a == nil and b ~= nil then return false, tostring(b) end -- the function itself failed
    return true, a, b
end

local function build(id, data)
    sequence = sequence + 1
    local payload = { moment = id, seq = sequence }
    for k, v in pairs(data or {}) do payload[k] = v end
    return payload
end

-- Something happened. Never waits, never fails the event.
function GM.moment(id, data)
    local payload = build(id, data)
    TriggerEvent("gm_events:moment", payload)
    for _, h in pairs(hooks) do
        if h.on and h.moment == id then
            CreateThread(function()
                local ok, answer = call(h, payload)
                note(h, ok, ok and "answered " .. tostring(answer) or answer)
            end)
        end
    end
end

-- May this start? Every hook on beforeStart has to answer true; a broken one refuses,
-- so a server's own rules are never skipped by accident. Waits, so call it in a thread.
function GM.askStart(data)
    local payload
    for _, h in pairs(hooks) do
        if h.on and h.moment == "beforeStart" then
            payload = payload or build("beforeStart", data)
            local done, ok, answer, why = false, nil, nil, nil
            CreateThread(function()
                ok, answer, why = call(h, payload)
                done = true
            end)
            local began = GetGameTimer()
            while not done and GetGameTimer() - began < ASK_MS do Wait(50) end
            if not done then ok, answer = false, "no answer in time" end
            note(h, ok, ok and "answered " .. tostring(answer) or answer)
            if not ok then return false, ("the start check %s:%s failed: %s"):format(h.resource, h.export, tostring(answer)) end
            if answer ~= true then
                return false, type(why) == "string" and why:gsub("[%c<>]", ""):sub(1, 100) or "refused by " .. h.resource
            end
        end
    end
    return true
end

function GM.hookRows()
    local list = {}
    for id, h in pairs(hooks) do
        list[#list + 1] = {
            id = id, moment = h.moment, resource = h.resource, export = h.export, on = h.on,
            running = GetResourceState(h.resource) == "running", ok = h.last and h.last.ok, last = h.last and h.last.text or "not called yet",
        }
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

function GM.saveHook(playerId, d)
    if finished then return false, LOCKED end
    if not known[d.moment] then return false, "choose a moment" end
    local resource, export = name(d.resource), name(d.export)
    if not resource or not export then return false, "resource and function: letters, numbers, _ and - only" end
    if resource == GetCurrentResourceName() then return false, "choose another resource than this one" end
    local id = type(d.id) == "string" and hooks[d.id] and d.id or nil
    if not id then
        local count, n = 0, 1
        for _ in pairs(hooks) do count = count + 1 end
        if count >= MAX_HOOKS then return false, "hook limit reached (" .. MAX_HOOKS .. ")" end
        while hooks["h" .. n] do n = n + 1 end
        id = "h" .. n
    end
    local h = { moment = d.moment, resource = resource, export = export, on = d.on ~= false }
    local ok, why = Open77.kvp.set("hook:" .. id, json.encode(h))
    if not ok then return false, "not saved: " .. tostring(why) end
    hooks[id] = h
    print(("[gm] player %d saved hook %s -> %s:%s (%s)"):format(playerId, h.moment, resource, export, h.on and "on" or "off"))
    return true, "hook saved", true
end

function GM.deleteHook(playerId, id)
    if finished then return false, LOCKED end
    local h = hooks[id]
    if not h then return false, "no such hook" end
    local ok, why = Open77.kvp.delete("hook:" .. id)
    if not ok then return false, "not deleted: " .. tostring(why) end
    hooks[id] = nil
    print(("[gm] player %d deleted hook %s -> %s:%s"):format(playerId, h.moment, h.resource, h.export))
    return true, "hook deleted", true
end

-- The real call with sample data, marked test = true. Waits for the answer.
function GM.testHook(playerId, id)
    local h = hooks[id]
    if not h then return false, "save the hook first" end
    local payload = build(h.moment, {
        test = true, name = "Test", kind = "boss", playerId = playerId, players = { playerId }, staff = playerId,
        position = Open77.players.position(playerId),
    })
    local done, ok, answer = false, nil, nil
    CreateThread(function()
        ok, answer = call(h, payload)
        done = true
    end)
    local began = GetGameTimer()
    while not done and GetGameTimer() - began < ASK_MS do Wait(50) end
    if not done then ok, answer = false, "no answer in time" end
    note(h, ok, ok and "answered " .. tostring(answer) or answer)
    return ok, ok and ("it answered " .. tostring(answer)) or tostring(answer), true
end

load()
