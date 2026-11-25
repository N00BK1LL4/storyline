# Storyline

Run live world events and custom story scenes on your OPEN//77 server, all from one in-game panel.

**This is a public test.** Please try it on a test server first. The [mod's README](gm_events/README.md) lists what has been tested and what hasn't.

## What you need

| Resource | Needed for |
|---|---|
| `open77_notifications` | Required (comes with the Freeroam template) |
| `open77_props` | Craters and objects (recommended) |
| `op77_map3d` | Map markers (recommended) |
| `open77_loot` | Loot on the ground (optional) |

Anyone fighting the Chimera also needs Phantom Liberty.

## Installation

1. Download `storyline-0.17.1.zip` from [Releases](../../releases).
2. Unzip it into your server's `resources` folder, so you have `resources/gm_events/open77.lua` and `resources/gm_chimera/open77.lua`. Keep those folder names.
3. Open `server.jsonc` and add both to `resources.load`, next to what you already have. They go after `open77_notifications`:

   ```jsonc
   "open77_notifications",
   "gm_chimera",
   "gm_events"
   ```

   Using the standard `open77_chimera`? Take it out, since the two shouldn't run together. If you don't want the Chimera, leave out `gm_chimera`.
4. Restart your server.
5. In Warden, go to **Players**, then **Rights**, and give your staff access:

   | Right | What it does |
   |---|---|
   | `command.gm.*` | Open the panel and run events |
   | `gm_events.edit` | Make and change presets and bookmarks |
   | `gm_events.loot` | Run events that give loot, and edit loot tables |
   | `gm_events.owner` | Hooks and settings. The owner role should already have it |

6. Join your server and press **Home**. The owner gets a short setup checklist the first time, and all of it is optional.
7. Run `gm.check` to see if anything still needs attention.

## Updating and removing

Back up `resources/gm_events/data` first, since your presets live there. To update, replace the files in both folders but keep `data`, then restart. To remove it, take `gm_events` and `gm_chimera` out of your load list, restart, and delete the folders.

## More

- [Full documentation](gm_events/README.md): settings, loot, hooks and everything else
- [Tester guide](docs/TESTER-GUIDE.md): what to try and how to report problems
- [Loot example](gm_events/examples/loot_bridge.lua) and [hooks example](gm_events/examples/hooks_bridge.lua) for connecting your own systems

## For developers

| Folder | What's in it |
|---|---|
| `gm_events` | The mod |
| `gm_chimera` | The Chimera boss, changed from OPEN//77's MIT `open77_chimera` |
| `docs` | Tester guide, Workshop text, to-do list, set-aside experiments |
| `tests` | Server tests with simulated players |
| `tools` | How the soldier list was made |

`python build.py` makes the packages. `pull.py` copies the mod from a live server into this repository.

## License

See [gm_events/LICENSE](gm_events/LICENSE). Contact NOOB_KILLA before you change or fork it. `gm_chimera` is MIT.

Unofficial fan project, not affiliated with CD PROJEKT RED or OPEN//77.
