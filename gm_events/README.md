# gm_events

A staff toolkit for running live world events on an OPEN//77 server: bosses with
health bars, hostile squads, AV crashes, cinematic scenes and an invisible staff
mode, all from one in-game panel.

## Install

1. Install from the Workshop in Warden, or unzip so that `gm_events/open77.lua`
   sits inside your server's `resources` folder.
2. If you unzipped it by hand, add `"gm_events"` to `resources.load` in
   `server.jsonc` (after `"open77_notifications"`) and restart the server.
3. Give your staff rights in Warden under **Players -> Rights**:

   | Right | Lets staff |
   |---|---|
   | `command.gm.*` | Open the panel and run events |
   | `gm_events.edit` | Also create, change and delete presets |
   | `gm_events.loot` | Also run events that give loot, and edit loot tables |

4. Join, press **Home** (or run `gm.panel`), then run `gm.check` once. It lists
   anything that still needs attention.

## The panel

**World Events** holds enemies and arrivals; **Custom Scenes** holds characters, bookmarks,
objectives and interactables. Live, Loot and Announcements belong to both. Presets can be
searched, duplicated and put in folders.

## Settings

Everything an owner tunes is in Warden's **Tuning** tab under `gm_events`:
health scaling, boss bar distance, announcements, placement, limits. Changes
apply at once and survive updates. Presets and model notes are made in the panel
and saved by the server.

## AV crash events

An AV crash preset can bring a squad, a boss or the Chimera with it, a few seconds
after impact, with its own warning, arrival message and camera shot. It refers to
your saved presets, so editing a squad changes every crash that uses it.

## Supply drops

An AV flies over, lets a crate go and leaves. The crate comes down gently, hovers where it
lands and is opened by standing next to it for a few seconds. It can give loot (to
everyone close by, or only the opener) and bring a squad, boss or objectives. Starting one
needs `command.gm.drop`, which `command.gm.*` includes; a drop with loot also needs
`gm_events.loot`.

## Falling objects

The **Falling** tab drops an orbital capsule, escape pod, rocket or cargo container
from the sky (the container and the craters need `open77_props`), with a fire trail, an optional warning and camera shot, smaller pieces
landing around it, and the same squads, bosses and objectives a crash can bring.
Starting one needs `command.gm.fall`, which `command.gm.*` includes.

## Objectives

Make objective sets in the panel's **Objectives** tab and start them on their own, or
attach them to a boss, squad, Chimera or AV crash. Players who enter the radius get an on-screen
tracker and a map marker. Progress is shared. A set started on its own uses event NPCs
already standing in its radius.

Types: defeat the enemies, kill a number, defeat the boss, reach a place, hold an area,
survive, and custom (staff tick it in the **Live** tab). Starting sets needs
`command.gm.objectives`, which `command.gm.*` includes.

Rewards are yours to give. A server script in any resource can listen:

```lua
AddEventHandler("gm_events:objectives", function(e)
    if e.phase ~= "completed" then return end
    for _, p in ipairs(e.players) do -- everyone who took part
        if p.seconds >= 30 then MyEconomy.pay(p.id, 500) end
    end
end)
```

`e.phase` is started, entered, left, objective, completed, failed or ended (stopped by
staff, no result). Only players still online are listed.

## Loot

Make loot tables in the panel's **Loot** tab and choose one on a boss, squad, Chimera or
objective set. This mod decides who earned what. Your server hands it out, by the method
you choose in the same tab.

| Method | What happens |
|---|---|
| event | `gm_events:loot` is raised; your script gives the items (default) |
| export | Your own resource's export is called and must answer `true` |
| ground | Items drop in the world through `open77_loot` (item names must be `Items.*`) |
| off | Nobody earns loot |

`examples/loot_bridge.lua` is a ready-made server script: copy it into a resource of yours
and change the marked lines. The shortest version:

```lua
AddEventHandler("gm_events:loot", function(award)
    if award.phase ~= "award" or award.handled then return end
    for _, i in ipairs(award.items) do
        MyInventory.add(award.playerId, i.item, i.amount, award.id)
    end
end)
```

An award has `phase`, `id`, `source` (enemy, boss, objectives, drop, interact or test), `name`, `table`,
`playerId`, `playerName`, `items` (`item`, `label`, `amount`), `position`, `method` and
`handled`.

- **`id` is unique, and a retry sends the same id.** Remember paid ids and you can never
  pay twice. Failed awards are in `gm.loot`; `gm.loot retry <id>` sends one again.
- **Ground drops:** the award has `handled = true` and no player. When one is picked up you
  get a second event with `phase = "pickup"` and the player. Save the item then.
- **Your item list:** tell the panel about your items and staff can choose from a list:

```lua
exports.gm_events:registerItems({ { id = "medkit", label = "Medkit" }, { id = "cash", label = "Eddies" } })
```

  Call it when your resource starts and again when gm_events restarts. An award can be
  checked with `exports.gm_events:getAward(id)`.

Bosses pay every player who hurt them; enemies pay everyone who did, or only the last
(your choice); objectives pay everyone who was there long enough. Ghosted staff and players
who left never earn anything. Nothing is given for bodies staff clean up.

## Story characters and bookmarks

**Cast tab.** Save characters with a model, a starting pose and up to ten lines, place them,
and direct them live: type a line and it appears over their head and as a subtitle for
players in range (whisper 6 m, normal 18 m, shout 50 m), with an optional voice bark from
the game. They can walk, follow, pose and face players, never fight, and cannot be hurt
unless you allow it. What staff say through them is written to the server log. Needs
`command.gm.cast`, and `command.gm.say` to speak; `command.gm.*` includes both.

**Bookmarks** (Live tab, needs `gm_events.edit`) are named places. They appear under
**Target**, so any event can start there, and scripts may use their names.

## Interactables

Make things players use by holding a key (E, rebindable) in the panel's **Interact** tab:
hack, search, plant a charge, rescue. Choose how long it takes, how many players it needs,
what happens, its loot and an alarm squad. Place one on its own, or let a crash, falling
object, supply drop, boss or squad bring it. The objective type **Use interactables**
counts them. Placing one needs `command.gm.interact`, which `command.gm.*` includes.

Your scripts can listen to `gm_events:interact`: `phase` (used, finished, ended), `id`,
`name`, `players`, `left`, `total`.

## Your own objectives and interactions

Server owners can plug in at three levels. `examples/hooks_bridge.lua` shows all of them.

**1. Show things your way** (Warden, Tuning tab)

- *Who shows objectives* = event: no tracker or marker from this mod. Your script gets
  `gm_events:objectiveState` with `playerId` and `state` (`title`, `status`, `time`, `items`,
  `outcome`, `away`, `marker`), or `state = false` when it ends for that player.
- *Who shows the prompt* = event: no label or key. Your script gets `gm_events:interactPoint`
  (`phase` placed, finished, fuse or removed, with `id`, `position`, `prompt`, `seconds`,
  `players`, `model`) and calls `exports.gm_events:useInteract(id, { playerId })` when your own
  menu or minigame is done. Distance, cooldown and the number of players are still checked.

**2. Add your own types**; staff then find them in the panel

```lua
exports.gm_events:registerObjectiveTypes({ { id = "deliver", label = "Deliver the goods" } })
AddEventHandler("gm_events:objectiveHook", function(e)
    if e.hook ~= "my_jobs:deliver" then return end
    -- e.phase is "start" or "stop"; e.players are those taking part
    if e.phase == "start" then MyJobs.begin(e.id, e.index, e.position) end
end)
-- later
exports.gm_events:setObjective(runId, index, { note = "2/5" })
exports.gm_events:setObjective(runId, index, { done = true })

exports.gm_events:registerInteractChecks({ { id = "lockpick", label = "Lockpick minigame", export = "lockpick" } })
exports("lockpick", function(point) -- may wait for the player
    return MyMinigame.play(point.playerId), "The lock held" -- true, or false and why
end)
```

**3. Run things from scripts**

| Export | Does |
|---|---|
| `start(kind, preset, at)` | Starts an `"objectives"` or `"interact"` preset by id or name at `{ x, y, z, heading, bucket }` |
| `getObjectives()` / `getInteracts()` | What is running now |
| `setObjective(id, index, patch)` | `done` and `note` of hooked and custom objectives |
| `completeObjectives(id)`, `failObjectives(id)`, `endObjectives(id)` | Ends a set |
| `useInteract(pointId, players)`, `removeInteract(groupId)` | Uses or removes an interactable |

Every event has a rising `seq`, because events sent together may arrive in another order.
Register again when gm_events restarts. These exports are for server scripts, which you
trust; they are written to the server log.

## Announcements

Use the panel's **Announcements** tab (needs `gm_events.edit`) or Warden's Tuning
tab to choose how players are told and to reword every message. Messages may use
`{boss}`, `{percent}` and `{players}`.

| Method | What happens |
|---|---|
| notification | On-screen toast (default) |
| chat | A line in chat |
| export | Calls a function in your own resource |
| event | Shows nothing; your server script handles it |
| none | Off |

**Export.** Set the resource and function names. Yours receives one table:

```lua
-- your resource, server side
exports("worldEvent", function(a)
    -- a.kind, a.title, a.text, a.seconds, and a.boss, a.percent, a.players when known
    MyAnnouncer.show(a.title, a.text)
    return true -- return false, "why" and the toast is used instead
end)
```

**Event.** Raised for every method except `none`, so a log or relay can listen too:

```lua
AddEventHandler("gm_events:announcement", function(a)
    if a.method ~= "event" then return end -- already shown another way
    MyAnnouncer.show(a.title, a.text)
end)
```

If your export fails, players get the standard toast and the server console says why.

## Needs

- `open77_notifications` (part of the Freeroam template)
- Optional: `op77_map3d` for map markers
- Optional: `open77_chimera` for the Chimera tab. Every player fighting it needs
  Phantom Liberty. With the standard package, staff ghost mode cannot make the Chimera
  ignore you, and a beaten Chimera stands back up instead of staying down.

## If event NPCs do not appear

Each player's game can only show a limited number of characters. The default
pedestrian crowd can use most of that, and then event NPCs wait for a free
place. `gm.check` warns about it. In `server.jsonc`:

```jsonc
"convars": {
  "open77_pedestrians_crowd_density": "4",
  "open77_pedestrians_crowd_max_near_player": "100",
  "open77_pedestrians_max_near_player": "128"
}
```

## Good to know

- Open ground works best. Nothing checks for walls or uneven ground.
- AVs other than the Manticore are marked untested.
- Event blasts do no scripted damage unless you raise it.
- Ghost mode hides staff and stops this mod's own NPCs. Pedestrians, police and
  other mods' NPCs may still react, and voice chat can still be heard.
- `gm.stop` clears everything this mod spawned.

The model catalogue in `web/models.js` is generated from OPEN//77's
`open77_admin` resource. Unofficial fan work, not affiliated with CD PROJEKT RED.
