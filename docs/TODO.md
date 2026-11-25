# gm_events TODO

Current version: 0.17.1 (2026-11-25). Nothing published.

## Next: your ideas

### 1. More AV models (0.9.1)
- [x] Arasaka AV found: `Vehicle.q112_arasaka_av`; 18 more added (Trauma Team, MaxTac, NCPD, Kang Tao...).
- [x] Tested / broken notes for AVs, shared by all staff.
- [ ] Try each AV in-game and mark it. Only the Manticore is confirmed.

### 2. Convoy: drive from A to B (SET ASIDE 2026-11-25)
Tried: platform follow (wiggles, fails), one far destination, recorded route with stops, server-driven
cars (floated, looked worse), destination within 1000 m. Each native version stalled somewhere; some
test points were off the main road network or needed a 1.1 km detour, but others were good and still
stalled. Code kept in `experiments/`. Reconsider if OPEN//77 improves vehicle AI.
- [ ] Cheaper alternative: a parked, guarded convoy to ambush or defend (no driving needed).

### 3. Something falling from space (0.10.1)
- [x] Falling tab: orbital capsule + airdrop crate (confirmed), escape pod, rocket, container; craters; trail, warning, camera,
      blast, smaller pieces, squads, bosses, objectives.
- [ ] Try each in-game and mark it tested.
- [ ] Possible: loot straight from the crash site; longer meteor shower.

### 4. Toolbox before the UI pass
- [x] Supply drops (0.11.0): AV flyby, hovering crate, loot.
- [x] Interactables (0.12.0): hold E to hack, search, plant; alarm squads, loot, objectives.
- [x] Owner hooks for objectives and interactions (0.13.0).
- [x] Bookmarks and story characters that speak (0.14.0).
- [ ] Atmosphere (weather, time, slow motion), waves, police response.
- [ ] Sound.
- [x] UI pass (0.15.0): World Events and Custom Scenes, folders, search, sections.
- [x] Settings tab, hooks on moments, owner-only first setup (0.16.0).
- [ ] Event chains (steps, waits, branches).
- [ ] After the UI: event log, journal, player flags.

## To confirm in-game

- [ ] Supply drop, interactables, owner hooks, bookmarks, story characters (0.11.0 to 0.14.0): nothing seen in-game yet.
- [ ] Loot: "Try it on me" and a boss with a loot table (0.9.0).
- [ ] Objectives: tracker, map marker, completion, return countdown, Chimera tab.
- [ ] A saved preset survives a full server restart.
- [ ] `bossfight` scene button.
- [ ] Which Arasaka/Militech models were confirmed, so they ship as tested.

## Needs something first

- [ ] Second player: ghost mode, boss scaling, shared objectives, loot sharing, Chimera.
      Needs the server opened beyond this PC, with your OK.
- [ ] Real ground loot and pickups: needs `open77_loot`, a download to approve.
- [ ] Find out why the live server stopped by itself on 24 November.

## Before release (name: Storyline; event chains on hold until feedback)

- [x] Name, licence (contact first for changes and forks), Chimera bundled as gm_chimera.
- [x] TESTER-GUIDE.md, WORKSHOP-LISTING.md, changelog, third-party notices, build with checks.
- [x] Handle filled in, final build made.
- [ ] Screenshots and cover image.
- [ ] Publish, or share the ZIP with testers.
- [ ] Decide whether to send `chimera-collapse-report.md` to the OPEN//77 team.

## Ideas for later

- Scene builder, enemy waves, boss stages, spawn where I aim.
- Objectives: press-a-key (hack, plant), escort, collect items.
- AV-following camera.
