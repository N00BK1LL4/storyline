-- What a story character says: a card over the head and a subtitle. Display only.
local hud, hudFailed
local cards = {} -- npc id -> { anchor, untilMs }
local queue, shownUntil = {}, 0

local function ensureHud()
    if hud or hudFailed then return hud end
    if type(Open77.ui) ~= "table" or type(Open77.ui.create) ~= "function" then
        hudFailed = true
        return nil
    end
    local doc, why = Open77.ui.create({
        document = "ui/speech.rml", layer = "hud", zIndex = 21, visible = true,
        models = { speech = { active = false, name = "", text = "" } },
    })
    if not doc then
        hudFailed = true
        print("[gm] subtitles refused: " .. tostring(why))
        return nil
    end
    hud = doc
    return hud
end

local function drop(npcId)
    if cards[npcId] then Open77.anchors.remove(cards[npcId].anchor) end
    cards[npcId] = nil
end

-- The card holds at most 192 bytes: cut between characters, never inside one.
local function short(text)
    if #text <= 180 then return text end
    local cut = 177
    while cut > 1 and (text:byte(cut + 1) & 0xC0) == 0x80 do cut = cut - 1 end
    return text:sub(1, cut) .. "..."
end

RegisterNetEvent("gm_events:say", function(npcId, name, text, ms, loud)
    npcId, name, text = tostring(npcId), tostring(name), tostring(text)
    ms = tonumber(ms) or 4000
    queue[#queue + 1] = { name = name, text = text, ms = ms }
    if #queue > 6 then table.remove(queue, 1) end
    local id = math.tointeger(tonumber(npcId))
    local entity = id and Open77.npcs.entity(id) or nil
    drop(npcId)
    if not entity then return end -- not loaded here: the subtitle is enough
    local anchor, why = Open77.anchors.create({
        entity = entity, offset = { x = 0, y = 0, z = 2.1 }, maxDistance = loud and 60.0 or 25.0, render = "card",
        presentation = {
            label = name, sublabel = short(text), color = "#F2F2F2", accent = "#8FC7FF", background = "#0A1220E0", progress = -1,
        },
    })
    if not anchor then return print("[gm] speech card refused: " .. tostring(why)) end
    cards[npcId] = { anchor = anchor, untilMs = GetGameTimer() + ms }
end)

CreateThread(function()
    local active = false
    while true do
        Wait(150)
        local now = GetGameTimer()
        for npcId, card in pairs(cards) do if now >= card.untilMs then drop(npcId) end end
        if now >= shownUntil then
            local nextLine = table.remove(queue, 1)
            if nextLine then
                shownUntil = now + (queue[1] and math.min(nextLine.ms, 2500) or nextLine.ms) -- hurry when more is waiting
                local doc = ensureHud()
                if doc then doc:merge("speech", { active = true, name = nextLine.name, text = nextLine.text }) end
                active = true
            elseif active then
                active = false
                if hud then hud:merge("speech", { active = false }) end
            end
        end
    end
end)
