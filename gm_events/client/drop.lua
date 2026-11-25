-- Labels over supply drops and interactables, and the key that uses the latter.
-- The server decides who is close enough and what happens.
local cards = {}
local pressed = false

local function usable()
    for _, card in pairs(cards) do if card.key then return true end end
    return false
end

local ok, key = RegisterKeyMapping("gm_events.use", "Event: use (hold)", "E", function()
    if pressed or not usable() then return end
    pressed = true
    TriggerServerEvent("gm_events:use", true)
end, function()
    if not pressed then return end
    pressed = false
    TriggerServerEvent("gm_events:use", false)
end)
if not ok then print("[gm] use key not registered (" .. tostring(key) .. ")") end
local keyName = ok and tostring(key or "E"):sub(1, 8) or "E"

RegisterNetEvent("gm_events:drop", function(id, state)
    local card = cards[id]
    if type(state) ~= "table" then
        if card then Open77.anchors.remove(card.anchor) end
        cards[id] = nil
        return
    end
    local presentation = {
        label = tostring(state.label), sublabel = tostring(state.text), color = "#F2F2F2", accent = "#FFD23D",
        background = "#12080AE0", key = state.key and keyName or "", progress = (tonumber(state.percent) or 0) / 100, showDistance = true,
    }
    if card then
        card.key = state.key == true
        Open77.anchors.update(card.anchor, { presentation = presentation })
        return
    end
    local anchor, why = Open77.anchors.create({
        position = { x = state.x, y = state.y, z = state.z }, maxDistance = 70.0, render = "card", presentation = presentation,
    })
    if anchor then cards[id] = { anchor = anchor, key = state.key == true } else print("[gm] drop label refused: " .. tostring(why)) end
end)

-- Moving away drops the label with its key: that is letting go.
CreateThread(function()
    while true do
        Wait(300)
        if pressed and not usable() then
            pressed = false
            TriggerServerEvent("gm_events:use", false)
        end
    end
end)
