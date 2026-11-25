-- Example: connect gm_events loot to your server's inventory.
-- Not loaded by gm_events. Copy into a resource of your own, for example
--   my_loot/open77.lua:   resource "my_loot"  version "1.0.0"  server_script "loot_bridge.lua"
-- and load it after gm_events. In the panel's Loot tab choose Method: My own script (event).

-- 1. CHANGE THIS: give one item. Answer true when it is really saved.
local function giveItem(playerId, item, amount, awardId)
    print(("[loot] would give player %s: %dx %s (%s)"):format(tostring(playerId), amount, item, awardId))
    return true -- for example: return exports.my_inventory:add(playerId, item, amount)
end

-- 2. CHANGE THIS: the items staff may choose from in the panel.
local items = {
    { id = "medkit", label = "Medkit" },
    { id = "cash", label = "Eddies" },
}

local paid = {} -- award id -> true. Keep this in your database to survive restarts.

AddEventHandler("gm_events:loot", function(award)
    -- "award": someone earned it. "pickup": someone took a ground drop.
    if award.phase == "award" and award.handled then return end -- lying on the ground, or given by an export
    if not award.playerId or paid[award.id] then return end
    paid[award.id] = true
    for _, i in ipairs(award.items) do
        if not giveItem(award.playerId, i.item, i.amount, award.id) then
            print("[loot] NOT given: " .. award.id .. " " .. i.item)
        end
    end
end)

local function register()
    if GetResourceState("gm_events") ~= "running" then return end
    local ok, count, why = pcall(function() return exports.gm_events:registerItems(items) end)
    if not ok or not count then print("[loot] items not registered: " .. tostring(ok and why or count)) end
end

CreateThread(function()
    Wait(1000)
    register()
end)
AddEventHandler("onResourceStart", function(name)
    if name == "gm_events" then SetTimeout(1000, register) end
end)
