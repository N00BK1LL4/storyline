# Testing Storyline 0.17.1

Thank you for testing. Use a **test server**, not your main one.

## Install

1. Unzip so that `resources/gm_events/open77.lua` exists. For the Chimera, also
   `resources/gm_chimera/open77.lua`, and take `open77_chimera` out of your load list.
2. In `server.jsonc`, add `"gm_events"` (and `"gm_chimera"` before it) to `resources.load`,
   after `"open77_notifications"`. Recommended: `open77_props`, `op77_map3d`.
3. Restart the server. In Warden, under Players, give staff `command.gm.*`. Give trusted
   staff `gm_events.edit` and `gm_events.loot`. The owner already has everything.
4. Join, press **Home**, run `gm.check`, and follow the first setup.

## Please try, in this order

Parts marked **new** have never been played by anyone.

| # | Try | Look for |
|---|---|---|
| 1 | Spawn a boss and a squad | Appear, fight, die, health over the boss's head |
| 2 | AV crash with a squad | Warning first, then the AV, then the squad |
| 3 | Two or more players in one fight | Boss health grows; nothing strange with **ghost mode** |
| 4 | **new** Objectives: *Hold the ground* | Tracker, marker, progress shared by everyone inside |
| 5 | **new** Supply drop | AV passes over, crate falls gently, hovers, opens when you stand close |
| 6 | **new** Interact: *Hack the terminal*, *Blow the generator* | E prompt, holding, letting go, explosion |
| 7 | **new** Cast: place someone and speak | Line over the head and as a subtitle; walking, following, posing |
| 8 | **new** Bookmarks | Use one as Target; still there after a restart |
| 9 | **new** Loot: *Try it on me*, then a boss with loot | Console line `[gm] loot ...` |
| 10 | Falling: every object | Visible? Trail and crater? |
| 11 | Every AV in the AV crash tab | Press Mark tested or Mark broken, and send us the list |
| 12 | **Stop everything** in the middle of each | Nothing is left behind |

## Report

Copy this, one per problem:

```
Storyline version:
Server build and client build:
Other resources that may matter:
Players online:
What I did:
What I expected:
What happened:
Every time, or sometimes:
gm.check output:
Server console lines with [gm]:
```

Remove license keys, player names, IP addresses and anything private before posting.

## Going back

Remove `gm_events` and `gm_chimera` from `resources.load`, restart, and delete the folders.
Presets are stored with the resource and go with it.
