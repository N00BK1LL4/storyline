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

4. Join, press **Home** (or run `gm.panel`), then run `gm.check` once. It lists
   anything that still needs attention.

## Settings

Everything an owner tunes is in Warden's **Tuning** tab under `gm_events`:
health scaling, boss bar distance, announcements, placement, limits. Changes
apply at once and survive updates. Presets and model notes are made in the panel
and saved by the server.

## AV crash events

An AV crash preset can bring a squad, a boss or the Chimera with it, a few seconds
after impact, with its own warning, arrival message and camera shot. It refers to
your saved presets, so editing a squad changes every crash that uses it.

## Objectives

Make objective sets in the panel's **Objectives** tab and start them on their own, or
attach them to a boss, squad or AV crash. Players who enter the radius get an on-screen
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
