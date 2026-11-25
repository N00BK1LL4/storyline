-- The label over a supply drop. Display only.
local cards = {}

RegisterNetEvent("gm_events:drop", function(id, state)
    local card = cards[id]
    if type(state) ~= "table" then
        if card then Open77.anchors.remove(card.anchor) end
        cards[id] = nil
        return
    end
    local presentation = {
        label = tostring(state.label), sublabel = tostring(state.text), color = "#F2F2F2", accent = "#FFD23D",
        background = "#12080AE0", progress = (tonumber(state.percent) or 0) / 100, showDistance = true,
    }
    if card then
        Open77.anchors.update(card.anchor, { presentation = presentation })
        return
    end
    local anchor, why = Open77.anchors.create({
        position = { x = state.x, y = state.y, z = state.z }, maxDistance = 70.0, render = "card", presentation = presentation,
    })
    if anchor then cards[id] = { anchor = anchor } else print("[gm] drop label refused: " .. tostring(why)) end
end)
