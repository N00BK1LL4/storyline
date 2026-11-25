-- Boss bar (NativeUI) and the name card over the boss. Display only.
local EMPTY = { active = false, low = false, name = "", percent = 0, note = "" }
local hud, hudFailed
local card, cardNpc, cardEntity
local coreId, lastCoreHit = nil, 0

local function ensureHud()
    if hud or hudFailed then return hud end
    if type(Open77.ui) ~= "table" or type(Open77.ui.create) ~= "function" then
        hudFailed = true
        print("[gm] NativeUI is not available on this client")
        return nil
    end
    local doc, why = Open77.ui.create({
        document = "ui/boss.rml", layer = "hud", zIndex = 20, visible = true, models = { boss = EMPTY },
    })
    if not doc then
        hudFailed = true
        print("[gm] boss bar refused: " .. tostring(why))
        return nil
    end
    doc:onEvent("error", function(name, detail)
        print("[gm] boss bar " .. tostring(name) .. ": " .. tostring(detail and detail.message))
    end)
    hud = doc
    return hud
end

local function dropCard()
    if card then Open77.anchors.remove(card) end
    card, cardNpc, cardEntity = nil, nil, nil
end

-- The entity handle changes when the body streams out and back in.
local function updateCard(state)
    local id = math.tointeger(tonumber(state.id))
    local entity = id and Open77.npcs.entity(id) or nil
    if not entity then return dropCard() end
    local presentation = { -- always the whole table: it is never patched by field
        label = state.name,
        sublabel = state.percent .. "%",
        color = "#F2F2F2",
        accent = "#FF4D3D",
        background = "#12080AE0",
        progress = state.percent / 100,
        showDistance = true,
    }
    if card and cardNpc == state.id and cardEntity == entity then
        Open77.anchors.update(card, { presentation = presentation })
        return
    end
    dropCard()
    local made, why = Open77.anchors.create({
        entity = entity,
        offset = { x = 0, y = 0, z = state.height or 2.4 },
        maxDistance = 90.0,
        render = "card",
        presentation = presentation,
    })
    if made then
        card, cardNpc, cardEntity = made, state.id, entity
    else
        print("[gm] name card refused: " .. tostring(why))
    end
end

RegisterNetEvent("gm_events:boss", function(state)
    local doc = ensureHud()
    if type(state) ~= "table" then
        if doc then doc:merge("boss", EMPTY) end
        dropCard()
        coreId = nil
        return
    end
    if doc then
        doc:merge("boss", {
            active = true,
            low = state.percent <= 25,
            name = state.name,
            percent = state.percent,
            note = (state.players > 1 and (state.players .. " players engaged") or "solo")
                .. ((state.extra or "") ~= "" and (" / " .. state.extra) or ""),
        })
    end
    updateCard(state)
    coreId = state.extra == "core" and tostring(state.id) or nil
end)

-- Tell the server about hits on an exposed Chimera core (see server/chimera.lua).
AddEventHandler("open77:npcHit", function(npcId)
    if not coreId or tostring(npcId) ~= coreId then return end
    local now = GetGameTimer()
    if now - lastCoreHit < 50 then return end
    lastCoreHit = now
    TriggerServerEvent("gm_events:coreHit", coreId)
end)

-- The client says why part of the Chimera could not be shown (for example
-- chimera_collapse_apply_failed). Pass it on: nothing else listens for it.
local reported, reports = {}, 0
AddEventHandler("open77:chimeraError", function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    local line = table.concat(parts, " "):sub(1, 200)
    if reported[line] or reports >= 40 then return end
    reported[line], reports = true, reports + 1
    print("[gm] chimera: " .. line)
    TriggerServerEvent("gm_events:chimeraError", line)
end)
