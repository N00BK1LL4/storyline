-- gm_events: staff-run world events, bosses and cinematic scenes.
resource "gm_events"
version "0.8.1"
auto_start true
dependency "open77_notifications"

server_script "server/config.lua"
server_script "server/settings.lua"
server_script "server/announce.lua"
server_script "server/main.lua"
server_script "server/bosshud.lua"
server_script "server/chimera.lua"
server_script "server/objectives.lua"
server_script "server/panel.lua"
client_script "client/main.lua"
client_script "client/boss.lua"
client_script "client/objectives.lua"
client_script "client/panel.lua"
files { "ui/boss.rml", "ui/boss.rcss", "ui/objectives.rml", "ui/objectives.rcss" }
web_ui_page "web/index.html"
web_ui_auto_create false
web_files { "web/**" }

permissions {
    "acl.read",         -- server: check staff rights on every panel click
    "input.actions",    -- client: the key that opens the panel
    "network.events",   -- cinematics and notifications
    "world.npcs",       -- bosses and waves
    "npcs.read",        -- client: find the boss body for its name card
    "world.vehicles",   -- the AV
    "world.effects",    -- fire and blasts
    "world.explosions", -- only needed when a blast has damage above 0
    -- Staff ghost mode.
    "players.life.read",
    "players.life.visibility",
    "players.life.ghost",
    "players.stats.read",
    "players.stats.apply",
    "camera.script",    -- client: cinematic camera
    "ui.vanilla.hud",   -- client: letterbox
    "ui.vanilla.map",   -- client: objective marker, when op77_map3d is not running
}
