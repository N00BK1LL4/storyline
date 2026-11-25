-- The Chimera boss from OPEN//77's open77_chimera, changed for Storyline. Do not load both.
resource "gm_chimera"
version "1.0.0-storyline.1"
auto_start true
server_script "server.lua"
client_script "client.lua"
permissions { "world.npcs", "npcs.read", "world.query", "players.life.read", "players.damage.apply", "network.events" }
