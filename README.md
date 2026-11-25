# Storyline

A staff toolkit for live world events and custom scenes on OPEN//77 servers.

| Folder | What |
|---|---|
| `gm_events` | The mod (see its README) |
| `gm_chimera` | The Chimera boss, changed from OPEN//77's MIT `open77_chimera` |
| `docs` | Tester guide, Workshop text, to-do list, set-aside experiments |
| `tests` | Server tests with simulated players; `panel-mock.js` fakes data for the panel page |
| `tools` | How the soldier list was made |

- `python build.py` makes the packages. It refuses while the author's handle is missing;
  `--draft` builds anyway.
- `pull.py` copies the mod from a live server into this repository.

Licence: `gm_events/LICENSE`; `gm_chimera` is MIT.
