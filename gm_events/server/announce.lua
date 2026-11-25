-- Every announcement goes through GM.say. How it is shown is the owner's choice:
--   notification  the standard on-screen toast (default)
--   chat          a line in open77_chat
--   export        exports.<resource>:<function>(payload) on the owner's own resource
--   event         nothing is shown; a server script handles gm_events:announcement
--   none          nothing at all
-- gm_events:announcement is raised for every method but none, so a log or Discord
-- relay can listen without changing how players see it. Payload:
--   { kind, title, text, seconds, method, boss?, percent?, players? }
-- kind: bossAppeared, bossHealth, bossDefeated, bossPhase, scene, staff, test

local METHODS = { notification = true, chat = true, export = true, event = true, none = true }

local function toast(p)
    return Open77.notifications.broadcast({
        type = "warning", title = p.title, message = p.text, durationMs = p.seconds * 1000,
    })
end

local show = {
    notification = function(p)
        local id, why = toast(p)
        return id ~= nil, why
    end,
    chat = function(p)
        return Open77.chat.broadcast({ type = "system", author = p.title, text = p.text, color = { 255, 77, 61 } })
    end,
    export = function(p)
        local resource, name = GM.announceResource, GM.announceExport
        if resource == "-" or name == "-" then return false, "set the export resource and function first" end
        if GetResourceState(resource) ~= "running" then return false, resource .. " is not running" end
        local ok, result, why = pcall(Open77.exports.callSync, resource, name, p)
        if not ok then return false, "export failed: " .. tostring(result) end
        -- Returning false means "I did not show it"; anything else counts as shown.
        if result == false then return false, tostring(why or "the export answered false") end
        return true
    end,
    event = function() return true end,
}

-- Fill {boss}, {percent}, {players}; unknown names are left as typed.
local function fill(template, vars)
    return (template:gsub("{(%a+)}", function(name)
        local value = vars[name]
        return value ~= nil and tostring(value) or nil
    end))
end

-- Returns true, or false and a reason. A failed method falls back to the toast,
-- so a broken integration never leaves players uninformed.
function GM.say(kind, template, vars)
    if type(template) ~= "string" or template == "" or template == "-" then return true end
    local method = GM.announceMethod
    if not METHODS[method] then method = "notification" end
    if method == "none" then
        -- Staff asked for it by hand: say why nobody will see it.
        if kind == "staff" or kind == "test" then return false, "announcements are turned off in the settings" end
        return true
    end
    vars = vars or {}
    local p = {
        kind = kind, title = GM.announceTitle, text = fill(template, vars), seconds = math.floor(vars.seconds or GM.announceSeconds),
        method = method, boss = vars.boss, percent = vars.percent, players = vars.players,
    }
    if p.title == "-" then p.title = "" end
    local ok, why = show[method](p)
    if not ok then
        print(("[gm] announcement by %s failed: %s"):format(method, tostring(why)))
        if method ~= "notification" then toast(p) end
    end
    local raised, reason = TriggerEvent("gm_events:announcement", p)
    if not raised then
        print("[gm] gm_events:announcement not raised: " .. tostring(reason))
        if method == "event" then toast(p) end
    end
    if not ok then return false, method .. ": " .. tostring(why) .. (method ~= "notification" and " (shown as a notification instead)" or "") end
    return true
end
