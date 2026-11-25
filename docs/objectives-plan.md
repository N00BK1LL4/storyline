# Plan: custom objectives for world events (0.8.0)

Status: built in 0.8.0; tested on a throwaway server, in-game test pending.

## What it does

Staff write a set of objectives. When it starts, it is tied to a place with a radius.
A player who enters the radius gets the objectives on their screen, and progress counts
from then on. Progress is shared by everyone taking part.

## How players experience it

1. Walk into the radius: a "new objective" message, and a tracker on the side of the screen.
2. The tracker shows each objective, its progress and any time limit.
3. A map marker shows where to go, for objectives that have a place.
4. Finished objectives are ticked off. At the end: "Event complete" or "Event failed".
5. Walk out: a countdown to return (10 s by default), then the tracker disappears.
   Group progress is kept. Coming back shows it again.

Late arrivals get the current progress. Dead players stay enrolled but do not count for
holding an area. Ghosted staff are never enrolled; staff watch progress in the panel.

## Objective types, first version

| Type | Done when |
|---|---|
| Defeat the enemies | Every enemy that came with this event is down |
| Kill a number | N of this event's enemies are down |
| Defeat the boss | This event's boss or Chimera is beaten |
| Reach a place | Someone taking part gets within X m of the point |
| Hold the area | Living players stay in the point for N seconds in total (can require a minimum number) |
| Survive | N seconds pass with at least one living player in the radius |
| Custom | Staff tick it in the panel. Any text: "Negotiate with the gang" |

Every type has its own text. Types can be mixed, up to 8 per set.

Set options: name, radius (10 to 250 m), in order or all at once, time limit (none by
default, starting when the first player enters), messages for start, success and failure,
and what failure means (time ran out, or everyone taking part is dead).

## In the staff panel

- New **Objectives** tab: list, editor, save, delete, start here (or at the mark, or a player).
- **AV crash**, **Squads** and **Bosses** get an "Objectives" choice, so one Spawn starts
  everything together. A crash starts its objectives at impact.
- **Live** gets the running sets: who is taking part, progress, and buttons to tick one,
  complete the set, fail it or end it quietly.
- Points for "reach" and "hold" are the centre of the event, or a distance and direction
  from it, so a saved set works anywhere on the map.

## Rewards

The mod cannot know a server's money or item system. It raises
`gm_events:objectives` (started, entered, left, progress, completed, failed) with the
list of players taking part and how long each was present. Owners hook rewards to it.
An optional export call, set up like announcements, can follow.

## How it is built

- `server/objectives.lua` (new): one 500 ms loop over player positions, decided entirely
  on the server, so players cannot fake progress. Leaving uses a slightly larger radius
  than entering, so nobody flickers at the edge. An unreadable position pauses, never resets.
- Enemies are tagged with the event that spawned them. Deaths are counted in the existing
  `onDefeat`, which already handles the Chimera's staged death and prevents double counting.
- `client/objectives.lua`, `ui/objectives.rml|rcss` (new): display only, the same technique
  as the boss bar.
- Map marker: `op77_map3d` when present, shown only to players taking part. Otherwise the
  game's own marker, which needs one new permission: `ui.vanilla.map`.
- `server/panel.lua`, `web/`: a fourth preset kind, `objectives`, plus `objectivesId` on the
  other three. New right: `command.gm.objectives` to start one; `gm_events.edit` to save.
- Up to 5 sets at once. Overlapping areas: the player sees the nearest one, and counts in it.
- **Stop everything** ends sets quietly: no success, no failure, no reward event.

## Cases the build must handle

- An enemy that never appears, or is cleaned up by staff, must not make a set unwinnable:
  it is taken out of the total.
- Objectives attached to a crash must not complete before the enemies have spawned.
- "Defeat the enemies" with no enemies in the event is refused when starting.
- A deleted set referenced by a crash shows "Missing" and refuses, like squads do now.
- Restarting the mod ends running sets and removes every tracker and marker.

## Order of work

1. Server: enrolment, types, timers, events. Test on the throwaway server.
2. Tracker and marker. Test in your game.
3. Panel tab, attachments, Live controls.
4. Throwaway-server tests for every case above, README, package 0.8.0.

## Left for later

- Press-a-key objectives (hack, plant, open). Needs the `open77_interactions` resource,
  which is not in this server's load list, so it would add a dependency for owners.
- Escort, collect items, individual progress and scoreboards.
- Squad waves and a full scene builder. Objectives are designed so those can trigger on
  "objective complete" later.

## Not testable alone

Shared progress, minimum player counts and "everyone is dead" need a second player.
