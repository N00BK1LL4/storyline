-- Example: plug your own objective and interaction systems into gm_events.
-- Not loaded by gm_events. Copy into a resource of yours, for example
--   my_hooks/open77.lua:   resource "my_hooks"  version "1.0.0"  server_script "hooks_bridge.lua"
-- and load it after gm_events. The names below then appear in the event panel.

local ME = GetCurrentResourceName()

-- 1. YOUR OBJECTIVE TYPES --------------------------------------------------------------
local running = {} -- "runId:index" -> true

AddEventHandler("gm_events:objectiveHook", function(e)
    if e.hook ~= ME .. ":deliver" then return end
    local key = e.id .. ":" .. e.index
    if e.phase == "stop" then
        running[key] = nil
        return
    end
    running[key] = true
    -- CHANGE THIS: start your own job for e.players at e.position. Here it just takes 10 s.
    CreateThread(function()
        for i = 1, 5 do
            Wait(2000)
            if not running[key] then return end
            exports.gm_events:setObjective(e.id, e.index, { note = i .. "/5" })
        end
        exports.gm_events:setObjective(e.id, e.index, { done = true })
    end)
end)

-- 2. YOUR INTERACTION CHECKS -----------------------------------------------------------
-- CHANGE THIS: answer true when the player succeeds. You may wait for a minigame.
exports("luck", function(point)
    Wait(1500)
    print(("[hooks] player %s tries %s"):format(tostring(point.playerId), point.name))
    return math.random() < 0.5, "Try again"
end)

local function register()
    if GetResourceState("gm_events") ~= "running" then return end
    local ok, why = pcall(function()
        exports.gm_events:registerObjectiveTypes({ { id = "deliver", label = "Deliver the goods (example)" } })
        exports.gm_events:registerInteractChecks({ { id = "luck", label = "50% luck (example)", export = "luck" } })
    end)
    if not ok then print("[hooks] not registered: " .. tostring(why)) end
end

CreateThread(function()
    Wait(1000)
    register()
end)
AddEventHandler("onResourceStart", function(name)
    if name == "gm_events" then SetTimeout(1000, register) end
end)

-- 3. YOUR OWN DISPLAY (only when it is switched to "event" in Warden) -------------------
-- AddEventHandler("gm_events:objectiveState", function(e) MyHud.show(e.playerId, e.state) end)
-- AddEventHandler("gm_events:interactPoint", function(p)
--     if p.phase == "placed" then MyPrompts.add(p.id, p.position, p.prompt, function(playerId)
--         exports.gm_events:useInteract(p.id, { playerId })
--     end) else MyPrompts.remove(p.id) end
-- end)
