-- The staff panel's client half: a page, the mouse, and messages. No authority.
local page, ready, open, pending = nil, false, false, {}

local function push(event, payload)
    if page and ready then
        local ok, why = page:send(event, payload)
        if ok == false then print("[gm] panel send " .. event .. ": " .. tostring(why)) end
    else
        pending[#pending + 1] = { event, payload } -- in order, until the page is ready
        if #pending > 40 then table.remove(pending, 1) end
    end
end

local function close(tellServer)
    if page then
        page:setFocus(false, false)
        push("gm:hide", {})
    end
    pending = {}
    if open and tellServer then TriggerServerEvent("gm_events:panel:closed") end
    open = false
end

local function focus()
    local ok, why = page:setFocus(true, true)
    if ok == false then print("[gm] panel focus refused: " .. tostring(why)) end
end

local function ensure()
    if page then return true end
    local made, why = WebUI.create({
        entry = "web/index.html", layer = "menu", width = 1920, height = 1080, fps = 30,
        zIndex = 700, transparent = true,
        -- Created visible: a surface created hidden may never draw. The page
        -- itself is transparent until it is told to open.
        visible = true,
    })
    if not made then
        print("[gm] panel unavailable: " .. tostring(why))
        return false
    end
    page = made
    page:setFocus(false, false)
    page:on("gm:ready", function()
        ready = true
        local queued = pending
        pending = {}
        for _, item in ipairs(queued) do push(item[1], item[2]) end
        if open then
            push("gm:show", {})
            focus()
        end
    end)
    page:on("gm:close", function() close(true) end)
    page:on("gm:call", function(payload)
        if type(payload) == "table" and type(payload.json) == "string" then
            TriggerServerEvent("gm_events:panel:call", payload.json)
        end
    end)
    page:on("gm:error", function(payload)
        print("[gm] panel page: " .. tostring(type(payload) == "table" and payload.text or payload))
    end)
    return true
end

RegisterNetEvent("gm_events:panel:open", function()
    if open or not ensure() then return end
    open = true
    if ready then -- never take the mouse for a page that cannot draw yet
        push("gm:show", {})
        focus()
    end
end)

-- Long messages arrive in numbered parts.
local building = {}
local function assemble(name, done)
    RegisterNetEvent("gm_events:panel:" .. name, function(part, index, total, sequence)
        if type(part) ~= "string" then return end
        if total == 1 then return done(part) end
        local b = building[name]
        if not b or b.sequence ~= sequence then
            b = { sequence = sequence, parts = {}, count = 0 }
            building[name] = b
        end
        if not b.parts[index] then
            b.parts[index] = part
            b.count = b.count + 1
        end
        if b.count == total then
            building[name] = nil
            done(table.concat(b.parts))
        end
    end)
end
assemble("state", function(encoded) push("gm:state", { json = encoded }) end)
assemble("live", function(encoded)
    if open then push("gm:live", { json = encoded }) end
end)
assemble("result", function(encoded) push("gm:result", { json = encoded }) end)

local ok, key = RegisterKeyMapping("gm_events.panel", "Staff: open event panel", "HOME", function()
    if open then close(true) else TriggerServerEvent("gm_events:panel:request") end
end)
if not ok then print("[gm] panel key not registered (" .. tostring(key) .. "); use gm.panel") end
