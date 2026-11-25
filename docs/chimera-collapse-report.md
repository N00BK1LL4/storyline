# Chimera stands up and idles after death

**Package:** `open77_chimera` 1.0.0 from `open77-resources` main, with two added exports
(`setPlayerAttitude` and `holdDown`, below). The deaths below were logged before `holdDown` existed.
**Server:** 2.50.0+op77.261, Windows x64
**Client:** (fill in the version shown in the launcher)
**Game:** Cyberpunk 2077 2.5 with Phantom Liberty

## What happens

In the core phase the boss collapses. When it then dies, it stands up and plays idle
animations instead of staying down.

## What I expected

The body stays down and leaves a wreck, as the Chimera guide describes.

## Steps

1. Create a Chimera through the `create` export.
2. Kill it, by player fire or with the `kill` export.
3. Watch the body on the client hosting its AI.

Four deaths were logged on one client; in each case I looked at, the body did not collapse.
At least one was a player kill. It was not confirmed that phase jumps (`setPhase`) are
irrelevant, and it was only tested with one player connected.

## Evidence

Each death is logged as taken by the client:

```
[npc] canonical death projected npc=17179869238 revision=5824: ok (record god mode ok)
```

A client script listening to `open77:chimeraError` was running for the last death. It received
another Chimera error during that fight, so it was working:

```
18:22:44 npc 17179869238 chimera_beam_endpoint_unavailable
18:24:04 canonical death projected npc=17179869238: ok
```

No `chimera_collapse_apply_failed` (or any other) error arrived at the death. The collapse
therefore seems to be undone or skipped rather than refused.

## A workaround that holds it down

Not killing it. At zero, the boss is made invulnerable and kept in its repairing state, and the
60-second repair timer is not allowed to end it. In my in-game test the body stayed down:

```lua
-- first line of restorePolicy
if encounter.heldDown then return end

exports("holdDown", function(id)
    local e, why = owned(id, caller()); if not e then return nil, why end
    local npc = current(e)
    if not npc or npc.health <= 0 then return nil, "boss_dead" end
    local ok, reason = Open77.npcs.setDamagePolicy(e.id, Open77.npcs.damage.invulnerable)
    if not ok then return nil, reason or "boss_policy_refused" end
    e.heldDown, e.repairing, e.gas = true, true, false
    changed(e)
    return state(e)
end)
```

This suggests the collapse is tied to the status effects that phase 4 clears or replaces.
A supported "stay down" would be better than this.

## Also noticed

- On two earlier bosses in one session, the server position stayed the same for the boss's whole
  life, so they may not have been able to move where they were placed.
- Nothing in the published client script listens to `open77:chimeraError`. Logging it would
  make reports like this easier.
- A supported way to set a Chimera's attitude towards one player would help staff tools; that
  is why the export above was added.
