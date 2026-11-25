-- The objective tracker and, without op77_map3d, a map marker. Display only.
local EMPTY = {
    active = false, won = false, lost = false, away = false, title = "", status = "", time = "",
    hasStatus = false, hasTime = false, items = { { text = "", note = "", done = false } },
}
local hud, hudFailed
local blip, blipKey, blipFailed

local function ensureHud()
    if hud or hudFailed then return hud end
    if type(Open77.ui) ~= "table" or type(Open77.ui.create) ~= "function" then
        hudFailed = true
        return nil
    end
    local doc, why = Open77.ui.create({
        document = "ui/objectives.rml", layer = "hud", zIndex = 19, visible = true, models = { objectives = EMPTY },
    })
    if not doc then
        hudFailed = true
        print("[gm] objective tracker refused: " .. tostring(why))
        return nil
    end
    doc:onEvent("error", function(name, detail)
        print("[gm] objective tracker " .. tostring(name) .. ": " .. tostring(detail and detail.message))
    end)
    hud = doc
    return hud
end

local function mark(marker)
    local key = marker and ("%.1f,%.1f,%s"):format(marker.x, marker.y, marker.label) or nil
    if key == blipKey then return end
    blipKey = key
    if blip then
        Open77.blips.remove(blip)
        blip = nil
    end
    if not marker then return end
    local id, why = Open77.blips.create({
        position = { x = marker.x, y = marker.y, z = marker.z }, sprite = "objective",
        title = marker.label, active = true, visibleThroughWalls = true,
    })
    if id then
        blip = id
    elseif not blipFailed then
        blipFailed = true
        print("[gm] objective marker refused: " .. tostring(why))
    end
end

RegisterNetEvent("gm_events:objectives", function(state)
    local doc = ensureHud()
    if type(state) ~= "table" then
        if doc then doc:merge("objectives", { active = false }) end
        return mark(nil)
    end
    mark(state.marker)
    if not doc then return end
    local items = {}
    for i, item in ipairs(state.items or {}) do
        items[i] = { text = tostring(item.text or ""), note = tostring(item.note or ""), done = item.done == true }
    end
    if #items == 0 then items = EMPTY.items end
    doc:merge("objectives", {
        active = true, won = state.outcome == "completed", lost = state.outcome == "failed",
        away = state.away == true, title = state.title or "", status = state.status or "", time = state.time or "",
        hasStatus = (state.status or "") ~= "", hasTime = (state.time or "") ~= "", items = items,
    })
end)
