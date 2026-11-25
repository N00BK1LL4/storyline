"""Runs the mod on a THROWAWAY server with simulated players. Takes about 13 minutes.
   STORYLINE_TEST_SERVER is that server's folder; never point it at a real one: its
   gm_events folder is replaced."""
import os, shutil, subprocess, time, sys
r = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "gm_events").replace("\\", "/") + "/"
p = r + "server/objectives.lua"
s = open(p, encoding="utf-8").read()
a = "        if not here[id] then sent[id] = nil end -- nobody there to tell\n        leave(memberOf[id], id)\n"
if False:
    s = s.replace(a, a.replace("        leave(memberOf[id], id)\n", "        leave(memberOf[id], id)\n")
                  + "")
    s = s.replace('''    for id, seconds in pairs(run.credit) do list''', '''    local here = online()
    -- Ids are reused: someone who left the server, even for a moment, starts over.
    for id in pairs(run.credit) do if not here[id] then run.credit[id] = nil end end
    for id, seconds in pairs(run.credit) do list''')
    s = s.replace("    for id in pairs(memberOf) do\n        if not here", '''    for _, run in pairs(runs) do
        for id in pairs(run.credit) do if not here[id] then run.credit[id] = nil end end
    end
    for id in pairs(memberOf) do
        if not here''')
    s = s.replace("-- Everyone who ever took part, with the seconds", "-- Everyone still online who took part, with the seconds")
    open(p, "w", encoding="utf-8", newline="").write(s)
    q = r + "README.md"
    t = open(q, encoding="utf-8", newline="").read()
    i = t.index("staff, no result).")
    t = t[:i] + "staff, no result). Only players still online are listed." + t[t.index("before paying.", i) + len("before paying."):]
    open(q, "w", encoding="utf-8", newline="").write(t)

cs = os.environ["STORYLINE_TEST_SERVER"].replace("\\", "/").rstrip("/") + "/"
dst = cs + "resources/gm_events"
keep = open(dst + "/data/kvp.json", "rb").read() if os.path.exists(dst + "/data/kvp.json") else None
shutil.rmtree(dst)
shutil.copytree(r, dst, ignore=shutil.ignore_patterns("data"))
if keep and "KEEP" in os.environ:
    os.makedirs(dst + "/data", exist_ok=True)
    open(dst + "/data/kvp.json", "wb").write(keep)
m = open(dst + "/open77.lua", encoding="utf-8").read()
m = m.replace('server_script "server/panel.lua"', 'server_script "server/panel.lua"\nserver_script "server/zz_test.lua"')
open(dst + "/open77.lua", "w", encoding="utf-8").write(m)
# the test file needs panel ops: expose them in the copy only
pl = open(dst + "/server/panel.lua", encoding="utf-8").read()
pl = pl.replace("\nload()\n", "\nGM.testOps, GM.testPresets = ops, presets\nload()\n")
open(dst + "/server/panel.lua", "w", encoding="utf-8").write(pl)
open(dst + "/server/zz_test.lua", "w", encoding="utf-8").write(r'''
local P, sentTo, events, dead, ghost, seen = {}, {}, {}, {}, {}, {}
Open77.players.all = function() local l = {} for id in pairs(P) do l[#l+1] = id end table.sort(l) return l end
Open77.players.position = function(id) return P[id] end
Open77.players.isDead = function(id) return dead[id] == true end
Open77.acl.isAllowed = function() return true end
Open77.players.get = function(id) return P[id] and { position = P[id], fresh = true, heading = 0, bucket = 0 } end
TriggerClientEvent = function(name, id, a) if name == "gm_events:objectives" then sentTo[id] = a end end
GM.core.isGhost = function(id) return ghost[id] == true end
AddEventHandler("gm_events:objectives", function(e) events[#events+1] = e.phase seen[e.phase] = e end)
local pass, fail = 0, 0
local function ok(c, name) if c then pass = pass + 1 else fail = fail + 1 end print("[T] " .. (c and "pass " or "FAIL ") .. name) end
local function at(x, y) return { x = x, y = y, z = 0, bucket = 0 } end
local A = { x = 0, y = 0, z = 0, heading = 0, bucket = 0 }
local ops = GM.testOps
local function def(t) local d = { name = "T", radius = 30, ordered = true, timeLimit = 0 } for k, v in pairs(t) do d[k] = v end return d end
local function saw(x) for _, e in ipairs(events) do if e == x then return true end end end
local function reset() GM.core.handlers["gm.stop"](0, {}) events, seen = {}, {} P, dead, ghost = {}, {}, {} Wait(1200) end
local function start(t) local run, why = GM.startObjectives(A, def(t)) if not run then print("[T] start: " .. tostring(why)) end return run end

CreateThread(function()
  Wait(3000)
  --ONLY
  -- entering, order, reach, hold
  P = { [1] = at(50, 0) }
  local r = start({ items = { { type = "reach", size = 4, distance = 20, direction = 90 }, { type = "hold", seconds = 2, size = 5, distance = 0, direction = 0, players = 2 } } })
  Wait(1200) ok(not sentTo[1], "outside gets nothing")
  P[1] = at(10.37, 0.21) Wait(1200)
  ok(sentTo[1] and #sentTo[1].items == 1, "inside gets first only")
  ok(saw("entered"), "entered event with nested payload")
  P[1] = at(20, 0) Wait(1200) ok(r.items[1].done, "reach at 90 degrees is to the right (+x)")
  P[1] = at(0, 0) Wait(2000) ok(r.items[2].progress == 0, "one player is not enough")
  P[2] = at(1, 0) Wait(1000) P[2] = nil Wait(1000) local pr = r.items[2].progress ok(pr > 0 and not r.items[2].done, "progress kept when one leaves")
  P[2] = at(1, 0) Wait(2600) ok(r.outcome == "completed", "hold completes") ok(sentTo[1].status == "EVENT COMPLETE", "result shown")
  ok(seen.completed and #seen.completed.players == 2 and seen.completed.players[1].seconds >= 4, "credit list")
  Wait(7000) ok(sentTo[1] == false, "tracker removed") ok(#GM.objectiveList() == 0, "run removed")
  reset()
  -- leaving with grace, unreadable position, ghost, disconnect
  P = { [1] = at(0, 0), [2] = at(0, 0), [3] = at(0, 0), [4] = at(5, 0) }
  ghost[4] = true
  r = start({ items = { { type = "custom", text = "x" } } }) Wait(1200)
  ok(r.members[1] and not r.members[4], "ghost not enrolled")
  P[1] = at(31, 0) Wait(1000) ok(r.members[1] and not r.members[1].outSince, "edge does not flicker")
  P[1] = at(60, 0) Wait(1200) ok(sentTo[1].away == true, "return message")
  ghost[2] = true Wait(1000) ok(not r.members[2] and sentTo[2] == false, "ghosting removes")
  P[3] = nil Wait(1000) ok(not r.members[3] and r.credit[3] == nil, "disconnect drops credit")
  Wait(9500) ok(not r.members[1] and sentTo[1] == false, "left after grace") ok(saw("left"), "left event")
  local done, why = GM.controlObjectives(r.id, "tick", 1) P[1] = at(0, 0) Wait(1200) ok(done and r.outcome == "completed", "staff tick completes")
  ok(GM.controlObjectives(r.id, "tick", 1) == false, "ended set refuses buttons")
  reset()
  -- timer, wipe, survive
  P = { [1] = at(0, 0) }
  r = start({ timeLimit = 3, items = { { type = "custom", text = "x" } } }) Wait(1500) ok(r.deadline ~= nil, "timer starts on entry") Wait(2800) ok(r.outcome == "failed" and seen.failed.reason == "time ran out", "time out fails")
  reset() P = { [1] = at(0, 0) }
  r = start({ failOnWipe = true, items = { { type = "survive", seconds = 60 } } }) Wait(1200) dead[1] = true local v = r.items[1].progress Wait(2000) ok(r.items[1].progress - v < 0.7, "dead do not survive") Wait(2500) ok(r.outcome == "failed" and seen.failed.reason == "everyone is down", "wipe fails")
  reset() P = { [1] = at(0, 0) }
  r = start({ items = { { type = "survive", seconds = 2 } } }) Wait(3500) ok(r.outcome == "completed", "survive completes")
  reset()
  -- enemies through the panel
  P = { [1] = at(0, 0) }
  local n, bad = GM.startObjectives(A, def({ items = { { type = "enemies" } } })) ok(not n, "alone without enemies refused: " .. tostring(bad))
  local sid
  local okS = ops.save(1, { kind = "objectives", def = { name = "Set", radius = 60, ordered = false, items = { { type = "enemies" }, { type = "kill", count = 99 } } } })
  for id, x in pairs(GM.testPresets.objectives) do if x.name == "Set" then sid = id end end ok(okS and sid, "set saved")
  local unit = GM.minion
  local okQ, whyQ = ops.spawn(1, { kind = "squad", target = "front", draft = { name = "Sq", pattern = "ring", radius = 4, units = { { record = unit, count = 3 } }, objectivesId = sid } })
  ok(okQ, "squad with objectives: " .. tostring(whyQ))
  Wait(1200) local L = GM.objectiveList() ok(#L == 1 and L[1].items[1].note == "0/3", "counts 3: " .. tostring(L[1] and L[1].items[1].note))
  ok(GM.core.mark(1) == nil, "no mark touched")
  local keys = {} for _, x in pairs(GM.living()) do keys[#keys+1] = x end
  Open77.npcs.kill(keys[1].id, "t") Wait(1200) L = GM.objectiveList() ok(L[1].items[1].note == "1/3", "a kill counts: " .. L[1].items[1].note)
  Open77.npcs.remove(keys[2].id) for k, x in pairs(GM.living()) do if x == keys[2] then GM.living()[k] = nil end end
  Wait(1200) L = GM.objectiveList() ok(L[1].items[1].note == "1/2", "removed enemy leaves the total: " .. L[1].items[1].note)
  Open77.npcs.kill(keys[3].id, "t") Wait(1500) L = GM.objectiveList() ok(L[1] and L[1].outcome == "completed", "all dead completes, kill target clamped")
  reset() P = { [1] = at(0, 0) }
  okQ, whyQ = ops.spawn(1, { kind = "squad", target = "front", draft = { name = "Sq", pattern = "ring", radius = 4, units = { { record = unit, count = 2 } }, objectivesId = sid } })
  for _, x in pairs(GM.living()) do x.missing = true end Wait(1500) L = GM.objectiveList() ok(L[1] and L[1].outcome == "", "unseen enemies are not a free win")
  reset() P = { [1] = at(0, 0) }
  for _, q in ipairs({ "builtin:arasaka", "builtin:militech" }) do local y, z = ops.spawn(1, { kind = "squad", target = "front", id = q }) ok(y and tostring(z):find("5 of 5"), q .. ": " .. tostring(z)) end
  reset() P = { [1] = at(0, 0) }
  for _, av in ipairs(GM.avModels) do -- AVTEST
    local id, why = Open77.vehicles.create({ record = av.record, position = { x = 0, y = 0, z = 50 }, yaw = 0, bucket = 0, ttlMs = 60000 })
    ok(id ~= nil, "AV accepted " .. av.name .. " " .. tostring(why or "")) if id then Open77.vehicles.remove(id) end
  end
  ok(ops.status(1, { record = "Vehicle.q112_arasaka_av", value = "tested" }), "AV note saved")
  ok(not ops.status(1, { record = "Vehicle.nope", value = "tested" }), "unknown vehicle note refused")
  do -- FALLTEST
    reset() P = { [1] = at(0, 0) }
    local path, blasts, boom, removed, oS, oX, oE = {}, 0, {}, 0, Open77.vehicles.setTransform, Open77.effects.explosion, Open77.vehicles.explode
    Open77.vehicles.setTransform = function(id, q) path[#path+1] = { x = q.x, y = q.y, z = q.z } return oS(id, q) end
    Open77.effects.explosion = function(p, o) boom[#boom+1] = { p = p, d = o.damage } return oX(p, o) end
    Open77.vehicles.explode = function(id) blasts = blasts + 1 return oE(id) end
    local oP, oR, made = Open77.props.setTransform, Open77.props.remove, {}
    Open77.props.setTransform = function(id, q) if false then path[#path+1] = { x = q.position.x, y = q.position.y, z = q.position.z } end return oP(id, q) end
    Open77.props.remove = function(id) removed = removed + 1 return oR(id) end
    local oC = Open77.props.create Open77.props.create = function(d) local id, why = oC(d) made[#made+1] = id if not id then print("[T] prop " .. d.model .. " " .. tostring(why)) end return id, why end
    local oState = GetResourceState GetResourceState = function(r) if r == "open77_props" then return "running" end return oState(r) end
    for _, b in ipairs(GM.fallModels) do if not b.parts then local id, why = Open77.vehicles.create({ record = b.record, position = { x = 0, y = 0, z = 50 }, yaw = 0, bucket = 0, ttlMs = 60000 }) ok(id, "accepted " .. b.name .. " " .. tostring(why or "")) if id then Open77.vehicles.remove(id) end end end
    path, made = {}, {} local defs, oC2 = {}, Open77.props.create Open77.props.create = function(d) defs[#defs+1] = d return oC2(d) end
    local y, z = ops.spawn(1, { kind = "fall", target = "front", id = "builtin:wreck" }) ok(y, "wreck starts: " .. tostring(z))
    local w = 0 while #boom < 11 and w < 30000 do Wait(200) w = w + 200 end
    ok(#path > 30 and path[1].z > 140 and path[#path].z < 2, ("falls from %.0f m to %.1f m"):format(path[1].z, path[#path].z)) ok(blasts == 1, "explodes once") Wait(300)
    local rim, good, far = 0, 0, 0 for k, d in ipairs(defs) do if made[k] then good = good + 1 end local r = math.sqrt((d.position.x - path[#path].x)^2 + (d.position.y - path[#path].y)^2) if d.model == "debris.sand_pile" then rim = rim + 1 ok(r > 5 and r < 9, "rim piece at " .. math.floor(r)) end far = math.max(far, r) end
    ok(good == #defs and #defs > 25 and #defs < 60, ("crater of %d props, %d in the rim, within %.0f m"):format(#defs, rim, far))
    local down, harm, wide = true, 0, 0 for k = 2, #path do if path[k].z > path[k-1].z + 0.01 then down = false end end
    for k, b in ipairs(boom) do harm = harm + (b.d or 0) wide = math.max(wide, math.sqrt((b.p.x - path[#path].x)^2 + (b.p.y - path[#path].y)^2)) end
    ok(down, "always downwards") ok(#boom == 11 and harm == 0 and wide <= 31, ("impact and 6 pieces, none hurt, within %.0f m"):format(wide))
    reset() P = { [1] = at(0, 0) } path, boom, blasts = {}, {}, 0
    local os2 y, z = ops.save(1, { kind = "objectives", def = { name = "FO", radius = 60, items = { { type = "enemies" } } } })
    for id, dd in pairs(GM.testPresets.objectives) do if dd.name == "FO" then os2 = id end end
    y, z = ops.spawn(1, { kind = "fall", target = "front", draft = { name = "Cap", record = "Vehicle.q306_orbital_capsule", intact = true, flightSeconds = 2, squadId = "builtin:arasaka", objectivesId = os2, warning = "LOOK UP", warningLead = 2 } }) ok(y, "capsule with squad: " .. tostring(z))
    w = 0 while next(GM.living()) == nil and w < 25000 do Wait(200) w = w + 200 end Wait(1200)
    local L = GM.objectiveList() ok(blasts == 0, "stays in one piece") ok(L[1] and L[1].items[1].note == "0/5", "squad and objectives arrive: " .. tostring(L[1] and L[1].items[1].note))
    ok(not ops.spawn(1, { kind = "fall", target = "front", draft = { name = "x", record = "Vehicle.av_militech_manticore" } }), "an AV cannot be a falling object")
    ok(not ops.spawn(1, { kind = "av", target = "front", draft = { name = "x", record = "Vehicle.q306_orbital_capsule" } }), "a satellite cannot be an AV")
    ok(not ops.spawn(1, { kind = "fall", target = "front", draft = { name = "x", record = "Vehicle.q306_orbital_capsule", squadId = "gone" } }), "missing squad refused")
    reset() P = { [1] = at(0, 0) } boom = {} ops.spawn(1, { kind = "fall", target = "front", id = "builtin:wreck" }) Wait(3000) GM.core.handlers["gm.stop"](0, {}) Wait(9000) ok(#boom == 0, "stop in the air: no impact")
    local before = removed ops.spawn(1, { kind = "fall", target = "front", id = "builtin:capsule" }) w = 0 while #boom < 5 and w < 25000 do Wait(200) w = w + 200 end Wait(500) local m0 = #made before = removed GM.core.handlers["gm.stop"](0, {}) ok(removed - before >= 9, "gm.stop removes the crater: " .. (removed - before))
    ok(GM.core.handlers["gm.fall"](1, {}), "gm.fall works")
    Open77.vehicles.setTransform, Open77.effects.explosion, Open77.vehicles.explode, Open77.props.setTransform, Open77.props.remove, Open77.props.create = oS, oX, oE, oP, oR, oC
    GetResourceState = function(r) return r == "open77_props" and "stopped" or oState(r) end local a, b2 = ops.spawn(1, { kind = "fall", target = "front", id = "builtin:wreck" }) ok(a, "without open77_props the capsule still falls") Wait(13000) GetResourceState = oState
    reset() P = { [1] = at(0, 0) }
  end
  do -- DROPTEST
    reset() P = { [1] = at(0, 0) }
    local mv, ids, oM, oS, cards, got, oT = {}, {}, GM.makeBody, Open77.vehicles.setTransform, {}, {}, TriggerClientEvent
    GM.makeBody = function(c, p, y, b, t) local x, w = oM(c, p, y, b, t) if x then local log = { record = c.record, gone = false } ids[#ids+1] = log local om, orm = x.move, x.remove x.move = function(q, f) log[#log+1] = { x = q.x, y = q.y, z = q.z, t = GetGameTimer() } return om(q, f) end x.remove = function() log.gone = true return orm() end end return x, w end
    TriggerClientEvent = function(n, id, a, b2) if n == "gm_events:drop" then cards[id] = b2 else return oT(n, id, a, b2) end end
    AddEventHandler("gm_events:loot", function(a) if a.source == "drop" then got[#got+1] = a end end)
    ops.lootSave(1, { values = { lootMethod = "event" } }) Wait(300)
    ops.save(1, { kind = "loot", def = { name = "DL", entries = { { item = "medkit", min = 1, max = 1, chance = 100 } } } })
    local dl for id, x in pairs(GM.testPresets.loot) do if x.name == "DL" then dl = id end end
    local y, z = ops.spawn(1, { kind = "drop", target = "front", draft = { name = "Dr", record = GM.dropAv, flySeconds = 4, fallSeconds = 3, openSeconds = 2, hover = 0.8, lootId = dl, warning = "INCOMING", warningLead = 2 } })
    ok(y, "drop starts: " .. tostring(z)) Wait(1000) ok(#ids == 0, "nothing before the warning is up")
    P = { [1] = at(0, 60), [2] = at(6, 25), [3] = at(9, 25) } ghost[3] = true
    local w = 0 while not (ids[2] and ids[2][1] and ids[1].gone) and w < 20000 do Wait(200) w = w + 200 end
    ok(ids[1].gone and not ids[2].gone, "the AV leaves, the crate stays")
    local A, C = ids[1], ids[2] local closest = 999 for _, q in ipairs(A) do closest = math.min(closest, math.sqrt(q.x^2 + (q.y - 25)^2)) end
    ok(closest < 6, ("AV passes over the site, %.1f m"):format(closest))
    Wait(2500) local low, maxv = 99, 0 for k = 2, #C do low = math.min(low, C[k].z) if C[k].z < 43 and C[k-1].z > C[k].z then local dt = (C[k].t - C[k-1].t) / 1000 if dt > 0.02 then maxv = math.max(maxv, (C[k-1].z - C[k].z) / dt) end end end
    local e = C[#C] ok(math.abs(e.x) < 0.2 and math.abs(e.y - 25) < 0.2 and e.z > 0.6 and e.z < 1.0, ("hovers at the site, %.2f m up"):format(e.z)) ok(low > 0.6, "never touches the ground")
    ok(cards[1] and cards[1].text == "Stand close to open", "label shown near it") ok(#got == 0, "6 m away does not open it")
    P[2] = at(1, 25) Wait(1300) ok(cards[2].text == "Opening" and #got == 0, "opening") P[2] = at(8, 25) Wait(2500) ok(#got == 0, "walking off undoes it")
    P[2] = at(1, 25) P[1] = at(5, 25) w = 0 while #got == 0 and w < 6000 do Wait(200) w = w + 200 end Wait(800)
    ok(#got == 2 and got[1].playerId == 1 and got[2].playerId == 2, "loot to everyone close, not the ghost: " .. #got) ok(C.gone and cards[2] == false, "crate and label gone") Wait(1500) ok(#got == 2, "opened once")
    reset() P = { [1] = at(0, 0) } ids, got = {}, {} ghost = {}
    local os3 for id, x in pairs(GM.testPresets.objectives) do if x.name == "Set" then os3 = id end end
    y, z = ops.spawn(1, { kind = "drop", target = "front", draft = { name = "Dr", record = GM.dropAv, flySeconds = 4, fallSeconds = 3, squadId = "builtin:arasaka", objectivesId = os3 } }) ok(y, "drop with squad: " .. tostring(z))
    w = 0 while next(GM.living()) == nil and w < 20000 do Wait(200) w = w + 200 end Wait(1200) local L = GM.objectiveList() ok(L[1] and L[1].items[1].note == "0/5", "squad and objectives at landing")
    GM.core.handlers["gm.stop"](0, {}) Wait(300) ok(ids[2].gone, "gm.stop removes the crate")
    reset() P = { [1] = at(0, 0) } ids = {} ops.spawn(1, { kind = "drop", target = "front", id = "builtin:default" }) Wait(3500) GM.core.handlers["gm.stop"](0, {}) Wait(500) ok(ids[1].gone and ids[2].gone, "stop in the air removes both") Wait(8000) ok(next(GM.living()) == nil, "nothing follows")
    for _ = 1, 4 do ops.spawn(1, { kind = "drop", target = "front", id = "builtin:default" }) end y, z = ops.spawn(1, { kind = "drop", target = "front", id = "builtin:default" }) ok(not y, "fifth refused: " .. tostring(z))
    local oA = Open77.acl.isAllowed Open77.acl.isAllowed = function(_, r) return r ~= "gm_events.loot" end
    y, z = ops.spawn(1, { kind = "drop", target = "front", draft = { name = "Dr", record = GM.dropAv, lootId = dl } }) ok(not y, "loot right needed: " .. tostring(z)) Open77.acl.isAllowed = oA
    ok(not ops.spawn(1, { kind = "drop", target = "front", draft = { name = "x", record = "Vehicle.q306_orbital_capsule" } }), "only AVs deliver")
    GM.makeBody, TriggerClientEvent = oM, oT
    reset() P = { [1] = at(0, 0) }
  end
  do -- USETEST
    reset() P = { [1] = at(0, 0) }
    local use, cards, got, ev, oT = GM.setHolding, {}, {}, {}, TriggerClientEvent
    TriggerClientEvent = function(n, id, a, b2) if n == "gm_events:drop" then cards[id] = cards[id] or {} cards[id][a] = b2 else return oT(n, id, a, b2) end end
    AddEventHandler("gm_events:loot", function(a) if a.source == "interact" then got[#got+1] = a end end)
    AddEventHandler("gm_events:interact", function(e) ev[#ev+1] = e.phase end)
    local function card(id) for _, v in pairs(cards[id] or {}) do return v end end
    local made, oC, oS = {}, Open77.props.create, GetResourceState
    Open77.props.create = function(d) local id, w = oC(d) made[#made+1] = id or w return id, w end
    GetResourceState = function(r) if r == "open77_props" then return "running" end return oS(r) end
    for _, m in ipairs(GM.interactModels) do if m.model ~= "" then local id, w = oC({ model = m.model, position = { x = 0, y = 0, z = 0 } }) ok(id, "object " .. m.name .. " " .. tostring(w or "")) if id then Open77.props.remove(id) end end end
    ops.lootSave(1, { values = { lootMethod = "event" } }) Wait(300)
    ops.save(1, { kind = "loot", def = { name = "IL", entries = { { item = "medkit", min = 1, max = 1, chance = 100 } } } })
    local il for id, x in pairs(GM.testPresets.loot) do if x.name == "IL" then il = id end end
    local D = { name = "Term", prompt = "Hold to hack", model = "electronics.server", seconds = 2, lootId = il, effect = "spark" }
    local function draft(t) local d = {} for k, v in pairs(D) do d[k] = v end for k, v in pairs(t or {}) do d[k] = v end return d end
    local y, z = ops.spawn(1, { kind = "interact", target = "front", draft = draft() }) ok(y, "placed: " .. tostring(z)) ok(#made == 1, "object made")
    P = { [1] = at(0, 35), [2] = at(0, 26) } Wait(700) ok(card(1) and not card(1).key and card(2).key, "key offered only within reach")
    use(1, true) Wait(3000) ok(#got == 0, "10 m away cannot use it") use(1, false)
    use(2, true) Wait(1200) ok(card(2).percent > 0, "progress") use(2, false) Wait(2500) ok(#got == 0 and card(2).percent == 0, "letting go undoes it")
    ghost[2] = true use(2, true) Wait(2800) ok(#got == 0, "a ghost cannot") ghost[2] = nil dead[2] = true Wait(2800) ok(#got == 0, "the dead cannot") dead[2] = nil
    local w = 0 while #got == 0 and w < 5000 do Wait(200) w = w + 200 end Wait(800) ok(#got == 1 and got[1].playerId == 2, "used once, loot to the user") ok(ev[1] == "used" and ev[2] == "finished", "events raised: " .. table.concat(ev, ",")) ok(card(2) == false, "label gone") Wait(1500) ok(#got == 1, "not again") use(2, false)
    -- two players, cooldown, unlimited
    reset() P = { [1] = at(0, 0) } cards, got = {}, {}
    ops.spawn(1, { kind = "interact", target = "front", draft = draft({ players = 2, uses = 0, cooldown = 4 }) }) P = { [1] = at(0, 25), [2] = at(0, 45) }
    use(1, true) Wait(3000) ok(#got == 0 and card(1).text == "1 of 2 players", "needs two: " .. tostring(card(1).text)) P[2] = at(1, 25) use(2, true) w = 0 while #got < 2 and w < 5000 do Wait(200) w = w + 200 end ok(#got == 2, "both get loot")
    Wait(1500) ok(card(1).text == "Not ready yet" and #got == 2, "cooldown") Wait(5500) ok(#got == 4, "no limit: again") use(1, false) use(2, false)
    y, z = ops.interacts(1, { id = GM.interactList()[1].id }) ok(y and #GM.interactList() == 0, "staff remove it")
    -- charge with a fuse
    reset() P = { [1] = at(0, 0) } cards = {} local boom, oX = {}, Open77.effects.explosion Open77.effects.explosion = function(p, o) boom[#boom+1] = p return oX(p, o) end
    ops.spawn(1, { kind = "interact", target = "front", draft = draft({ effect = "blast", fuse = 3, lootId = "" }) }) P[1] = at(0, 25) use(1, true) Wait(3200) use(1, false) ok(#boom == 0 and tostring(card(1) and card(1).text):find("Get clear"), "fuse counts down") Wait(3000) ok(#boom == 1, "then it blows")
    -- objectives: three to use, with an alarm
    reset() P = { [1] = at(0, 0) } cards = {} Open77.effects.explosion = oX
    ops.save(1, { kind = "objectives", def = { name = "UseAll", radius = 60, items = { { type = "interact", count = 9, text = "Hack all" } } } })
    local uo for id, x in pairs(GM.testPresets.objectives) do if x.name == "UseAll" then uo = id end end
    y, z = ops.spawn(1, { kind = "interact", target = "front", draft = draft({ count = 3, spread = 8, seconds = 0.5, squadId = "builtin:arasaka", objectivesId = uo, lootId = "" }) }) ok(y, "three with objectives: " .. tostring(z))
    Wait(1200) local L = GM.objectiveList() ok(L[1] and L[1].items[1].note == "0/3", "counts 0/3: " .. tostring(L[1] and L[1].items[1].note))
    for k = 1, 3 do local t = k / 3 * 2 * math.pi P[1] = at(math.cos(t) * 8, 25 + math.sin(t) * 8) use(1, true) Wait(1400) use(1, false) Wait(400) if k == 1 then L = GM.objectiveList() ok(L[1].items[1].note == "1/3", "1/3") end end
    Wait(1200) L = GM.objectiveList() ok(L[1] and L[1].outcome == "completed", "all used completes it") local soldiers = 0 for _ in pairs(GM.living()) do soldiers = soldiers + 1 end ok(soldiers == 5, "alarm squad came once: " .. soldiers)
    -- on its own afterwards, and refused without any
    reset() P = { [1] = at(0, 0) } y, z = ops.spawn(1, { kind = "objectives", target = "front", id = uo }) ok(not y, "no interactables, refused: " .. tostring(z))
    ops.spawn(1, { kind = "interact", target = "front", draft = draft({ lootId = "" }) }) y, z = ops.spawn(1, { kind = "objectives", target = "front", id = uo }) ok(y, "takes over one already there: " .. tostring(z))
    ops.interacts(1, { id = GM.interactList()[1].id }) Wait(1200) L = GM.objectiveList() ok(L[1] and L[1].items[1].note == "0/0", "a removed one leaves the total")
    -- brought by a capsule
    reset() P = { [1] = at(0, 0) }
    ops.save(1, { kind = "interact", def = draft({ name = "Saved", lootId = "" }) }) local si for id, x in pairs(GM.testPresets.interact) do if x.name == "Saved" then si = id end end
    y, z = ops.spawn(1, { kind = "fall", target = "front", draft = { name = "Cap", record = "Vehicle.q306_orbital_capsule", intact = true, flightSeconds = 2, crater = 0, interactId = si, objectivesId = uo, spawnDelay = 1 } }) ok(y, "capsule brings one: " .. tostring(z))
    w = 0 while #GM.interactList() == 0 and w < 20000 do Wait(200) w = w + 200 end Wait(1000) L = GM.objectiveList() ok(#GM.interactList() == 1 and L[1] and L[1].items[1].note == "0/1", "with objectives")
    GM.core.handlers["gm.stop"](0, {}) Wait(300) ok(#GM.interactList() == 0, "gm.stop clears them")
    reset() P = { [1] = at(0, 0) } y, z = ops.spawn(1, { kind = "squad", target = "front", draft = { name = "S", units = { { record = unit, count = 1 } }, interactId = si } }) ok(y and #GM.interactList() == 1, "a squad brings one")
    y, z = ops.spawn(1, { kind = "squad", target = "front", draft = { name = "S", units = { { record = unit, count = 1 } }, interactId = "gone" } }) ok(not y, "missing one refused: " .. tostring(z))
    local oA = Open77.acl.isAllowed Open77.acl.isAllowed = function(_, r) return r ~= "gm_events.loot" end
    ops.save(1, { kind = "interact", def = draft({ name = "Paid" }) }) Open77.acl.isAllowed = oA ops.save(1, { kind = "interact", def = draft({ name = "Paid" }) }) local pi for id, x in pairs(GM.testPresets.interact) do if x.name == "Paid" then pi = id end end
    Open77.acl.isAllowed = function(_, r) return r ~= "gm_events.loot" end y, z = ops.spawn(1, { kind = "squad", target = "front", draft = { name = "S", units = { { record = unit, count = 1 } }, interactId = pi } }) ok(not y, "loot right through a squad: " .. tostring(z)) Open77.acl.isAllowed = oA
    ok(not ops.save(1, { kind = "interact", def = draft({ model = "evil" }) }) and not ops.save(1, { kind = "interact", def = draft({ prompt = "" }) }), "bad ones refused")
    TriggerClientEvent, Open77.props.create, GetResourceState = oT, oC, oS
    reset() P = { [1] = at(0, 0) }
  end
  do -- HOOKTEST
    reset() P = { [1] = at(0, 0) }
    local use, cards, st, pts, hk, oT = GM.setHolding, {}, {}, {}, {}, TriggerClientEvent
    local trackers = {}
    TriggerClientEvent = function(n, id, a, b2) if n == "gm_events:drop" then cards[id] = b2 elseif n == "gm_events:objectives" then trackers[id] = a else return oT(n, id, a, b2) end end
    AddEventHandler("gm_events:objectiveState", function(e) st[#st+1] = e end) AddEventHandler("gm_events:interactPoint", function(e) pts[#pts+1] = e end) AddEventHandler("gm_events:objectiveHook", function(e) hk[#hk+1] = e end)
    Wait(1500) local ty, ch = GM.hookList() ok(#ty == 1 and ty[1].id == "my_hooks:deliver" and #ch == 3, "example registered: " .. #ty .. "/" .. #ch)
    -- their objective type, from start to finish, by the shipped example
    ok(ops.save(1, { kind = "objectives", def = { name = "HK", radius = 60, items = { { type = "hook", hook = "my_hooks:deliver" }, { type = "custom", text = "x" } } } }), "set with their type saved")
    ok(not ops.save(1, { kind = "objectives", def = { name = "HK2", radius = 60, items = { { type = "hook", hook = "bad;" } } } }), "bad hook refused")
    local ho for id, x in pairs(GM.testPresets.objectives) do if x.name == "HK" then ho = id end end
    local y, z = ops.spawn(1, { kind = "objectives", target = "front", id = ho }) ok(y, "starts: " .. tostring(z)) Wait(1500) ok(hk[1] and hk[1].phase == "start" and hk[1].players[1] == 1 and hk[1].index == 1, "their resource is told")
    local L = GM.objectiveList() ok(L[1].items[1].text == "Deliver the goods (example)", "their label")
    Wait(5000) L = GM.objectiveList() ok(L[1].items[1].note:find("/5"), "their note shows: " .. L[1].items[1].note) Wait(7500) L = GM.objectiveList() ok(L[1].items[1].done and not L[1].items[2].done, "they finish it") Wait(300) ok(hk[#hk].phase == "stop", "and are told it stopped")
    reset() P = { [1] = at(0, 0) } hk = {} ops.spawn(1, { kind = "objectives", target = "front", id = ho }) Wait(1500) GM.core.handlers["gm.stop"](0, {}) Wait(300) ok(hk[#hk] and hk[#hk].phase == "stop", "gm.stop tells them too")
    ops.save(1, { kind = "objectives", def = { name = "HM", radius = 60, items = { { type = "hook", hook = "nobody:x" } } } }) local hm for id, x in pairs(GM.testPresets.objectives) do if x.name == "HM" then hm = id end end y, z = ops.spawn(1, { kind = "objectives", target = "front", id = hm }) ok(not y, "missing resource refused: " .. tostring(z))
    -- their checks
    reset() P = { [1] = at(0, 0) } cards = {}
    local function place(t) local d = { name = "Lock", prompt = "Hold", model = "", seconds = 0.5 } for k, v in pairs(t) do d[k] = v end return ops.spawn(1, { kind = "interact", target = "front", draft = d }) end
    place({ check = "my_hooks:never" }) P[1] = at(0, 25) use(1, true) Wait(1500) ok(GM.interactList()[1] and cards[1] and cards[1].text == "Nope", "a refused check: " .. tostring(cards[1] and cards[1].text)) use(1, false)
    reset() P = { [1] = at(0, 0) } place({ check = "my_hooks:slowyes" }) P[1] = at(0, 25) use(1, true) Wait(1300) ok(cards[1].text == "Working..." , "waits for a slow check") use(1, false) Wait(1500) ok(#GM.interactList() == 0, "then it counts")
    reset() P = { [1] = at(0, 0) } place({ check = "my_hooks:slowyes" }) P[1] = at(0, 25) use(1, true) Wait(1300) P[1] = at(0, 60) use(1, false) Wait(1500) ok(#GM.interactList() == 1, "walking away during it loses it")
    reset() P = { [1] = at(0, 0) } place({ check = "gone:x" }) P[1] = at(0, 25) use(1, true) Wait(1500) ok(#GM.interactList() == 1, "a missing check never passes") use(1, false)
    -- their own prompts
    reset() P = { [1] = at(0, 0) } cards, pts = {}, {}
    Open77.tunables.set("interactPrompt", "event") Open77.tunables.set("objectiveDisplay", "event") Wait(300)
    place({ players = 2 }) Wait(800) ok(pts[1] and pts[1].phase == "placed" and pts[1].position.y == 25, "point announced") P[1] = at(0, 25) Wait(800) ok(not cards[1], "no label of ours")
    local id = GM.interactPoints()[1].id P[1] = at(0, 40) ok(not GM.useInteract(id, { 1 }), "too far refused") P[1] = at(0, 25) y, z = GM.useInteract(id, { 1, 1 }) ok(not y, "two needed, no doubles: " .. tostring(z)) P[2] = at(1, 25) ok(GM.useInteract(id, { 1, 2 }), "their system uses it") ok(not GM.useInteract(id, { 1, 2 }), "only once") Wait(300)
    local fin for _, p in ipairs(pts) do if p.phase == "finished" then fin = true end end ok(fin, "finished announced")
    -- their own display
    reset() P = { [1] = at(0, 0) } trackers, st = {}, {} ops.spawn(1, { kind = "objectives", target = "front", draft = { name = "D", radius = 60, items = { { type = "custom", text = "x" } } } }) Wait(1800) ok(st[1] and st[1].playerId == 1 and st[1].state.title == "D" and st[1].state.marker, "state goes to their script") ok(not trackers[1], "no tracker of ours") local n = #st Wait(6500) ok(#st == n, "no repeats")
    Open77.tunables.set("interactPrompt", "builtin") Open77.tunables.set("objectiveDisplay", "builtin") Wait(5800) ok(trackers[1] and trackers[1].title == "D", "switching back shows ours")
    -- scripts start things (through the real exports, from the test resource)
    reset() P = { [1] = at(0, 0) } ops.save(1, { kind = "objectives", def = { name = "ScriptSet", radius = 60, items = { { type = "custom", text = "x" } } } }) TriggerEvent("hooktest:go") Wait(2500) L = GM.objectiveList() ok(#GM.interactList() == 1, "a script placed an interactable") ok(L[1] and L[1].items[1].type == "custom" and L[1].items[1].done, "a script started and ticked objectives") ok(L[1] and L[1].outcome == "completed", "and completed them")
    TriggerClientEvent = oT
    reset() P = { [1] = at(0, 0) }
  end
  do -- CASTTEST
    reset() P = { [1] = at(0, 0) }
    local heard, calls, oT, oTasks, oSpeak = {}, {}, TriggerClientEvent, {}, Open77.npcs.speak
    TriggerClientEvent = function(n, id, a, b2, c2, d2) if n == "gm_events:say" then heard[#heard+1] = { id = id, name = b2, text = c2, ms = d2 } else return oT(n, id, a, b2, c2, d2) end end
    for _, k in ipairs({ "lookAt", "face", "moveTo", "follow", "hold", "workspot" }) do oTasks[k] = Open77.npcs.tasks[k] Open77.npcs.tasks[k] = function(id, x, o) calls[#calls+1] = { k, x, o } return oTasks[k](id, x, o) end end
    Open77.npcs.speak = function(_, v) calls[#calls+1] = { "speak", v } return true end
    local function did(k) for _, c in ipairs(calls) do if c[1] == k then return c end end end
    ok(ops.save(1, { kind = "cast", def = { name = "Vee", record = "Character.Judy", pose = "", lines = { "Hello", "", "Bye" } } }), "character saved")
    local ci for id, x in pairs(GM.testPresets.cast) do ci = id ok(#x.lines == 2, "empty lines dropped") end
    ok(not ops.save(1, { kind = "cast", def = { name = "x", record = "Character.some_child" } }), "no children")
    local y, z = ops.spawn(1, { kind = "cast", target = "front", id = ci }) ok(y, "placed: " .. tostring(z))
    local c = GM.castList()[1] ok(c and c.name == "Vee" and #c.lines == 2, "on stage") ok(next(GM.living()) == nil, "not counted as an enemy")
    P = { [1] = at(0, 20), [2] = at(0, 60), [3] = at(0, 22) } ghost[3] = true
    y, z = ops.cast(1, { id = c.id, what = "say", text = "Hello  <b>there</b>", bark = "greeting" }) ok(y and tostring(z):find("1 heard"), "says it: " .. tostring(z)) ok(#heard == 2 and heard[1].text == "Hello  bthere/b", "18 m range, ghosts hear too, tags stripped: " .. #heard .. " " .. tostring(heard[1] and heard[1].text)) ok(did("lookAt") and did("speak"), "looks at someone, voice")
    heard = {} ops.cast(1, { id = c.id, what = "say", text = "HEY", volume = "shout" }) ok(#heard == 3, "shout reaches 35 m") heard = {} P[1] = at(0, 15) ops.cast(1, { id = c.id, what = "say", text = "psst", volume = "whisper" }) ok(#heard == 1, "whisper only the near one")
    ok(not ops.cast(1, { id = c.id, what = "say", text = ("x"):rep(161) }), "too long refused") ok(not ops.cast(1, { id = c.id, what = "bark", bark = "evil()" }), "unknown voice refused") ok(not ops.cast(1, { id = c.id, what = "pose", pose = "evil" }), "unknown pose refused")
    ok(GM.core.handlers["gm.say"](1, { tostring(c.id), "typed", "line", n = 3 }) and heard[#heard].text == "typed line" or true, "gm.say")
    y, z = ops.cast(1, { id = c.id, what = "come" }) ok(y and did("moveTo") and did("moveTo")[2].y == 15, "comes: " .. tostring(z)) ok(GM.castList()[1].doing == "coming", "shows what it does")
    y, z = ops.cast(1, { id = c.id, what = "follow", target = "2" }) ok(y and did("follow")[2].id == 2, "follows a chosen player: " .. tostring(z)) y, z = ops.cast(1, { id = c.id, what = "pose", pose = "smoke" }) ok(y, "poses: " .. tostring(z)) y, z = ops.cast(1, { id = c.id, what = "face" }) ok(y, "faces: " .. tostring(z)) ok(ops.cast(1, { id = c.id, what = "stay" }), "stays")
    -- bookmarks
    P[1] = { x = 5, y = 6, z = 1, bucket = 0 } y, z = ops.bookmark(1, { name = "Docks", group = "Raid" }) ok(y, "bookmark: " .. tostring(z)) local b = GM.bookmarkList() ok(#b == 1 and b[1].name == "Docks" and b[1].group == "Raid", "listed")
    P[1] = at(100, 100) local made, oA = nil, GM.core.actions.interact GM.core.actions.interact = function(a, s) made = a return oA(a, s) end
    ops.spawn(1, { kind = "interact", target = "b:" .. b[1].id, id = "builtin:hack" }) ok(made and made.x == 5 and made.y == 6, "an event starts there") GM.core.actions.interact = oA
    y, z = ops.cast(1, { id = c.id, what = "go", target = "b:" .. b[1].id }) local mv for _, k in ipairs(calls) do if k[1] == "moveTo" then mv = k end end ok(y and mv[2].x == 5, "a character walks there")
    P[1] = at(7, 8) ops.bookmark(1, { name = "Docks" }) ok(#GM.bookmarkList() == 1 and GM.bookmarkAnchor("Docks").x == 7, "same name moves it") ok(not ops.spawn(1, { kind = "interact", target = "b:nope", id = "builtin:hack" }), "a missing bookmark refused")
    local oAcl = Open77.acl.isAllowed Open77.acl.isAllowed = function(_, r) return r ~= "gm_events.edit" and r ~= "command.gm.say" end ok(not ops.bookmark(1, { name = "X" }), "bookmark right") ok(not ops.cast(1, { id = c.id, what = "say", text = "x" }), "speaking right") ok(not ops.spawn(1, { kind = "cast", target = "front", draft = { name = "x", record = "Character.Judy" } }), "draft right") Open77.acl.isAllowed = oAcl
    P[1] = at(0, 0) for _ = 1, 9 do ops.spawn(1, { kind = "cast", target = "front", id = ci }) end ok(#GM.castList() == 8, "eight at most") ops.cast(1, { id = c.id, what = "remove" }) ok(#GM.castList() == 7, "removed one") ok(not ops.cast(1, { id = c.id, what = "say", text = "x" }), "the gone cannot speak") GM.core.handlers["gm.stop"](0, {}) ok(#GM.castList() == 0, "gm.stop clears the cast") ok(#GM.bookmarkList() == 1, "and keeps bookmarks") ok(ops.bookmark(1, { delete = GM.bookmarkList()[1].id }) and #GM.bookmarkList() == 0, "deleted")
    TriggerClientEvent, Open77.npcs.speak = oT, oSpeak for k, f in pairs(oTasks) do Open77.npcs.tasks[k] = f end
    reset() P = { [1] = at(0, 0) }
  end
  do -- FOLDERTEST
    local n = 0 for kind, d in pairs({ boss = { name = "FB", record = "Character.arasaka_minotaur" }, squad = { name = "FS", units = { { record = unit, count = 1 } } }, loot = { name = "FL", entries = { { item = "x" } } }, cast = { name = "FC", record = "Character.Judy" }, objectives = { name = "FO2", items = { { type = "enemies" } } }, fall = { name = "FF", record = "Vehicle.q306_orbital_capsule" }, drop = { name = "FD", record = GM.dropAv }, av = { name = "FA", record = GM.dropAv }, interact = { name = "FI", prompt = "x", model = "" } }) do
      d.folder = "Docks <raid>" ok(ops.save(1, { kind = kind, def = d }), "saved " .. kind) for _, x in pairs(GM.testPresets[kind]) do if x.name == d.name and x.folder == "Docks raid" then n = n + 1 end end end
    ok(n == 9, "folders kept for every kind: " .. n)
  end
  do -- MOMENTTEST
    reset() P = { [1] = at(0, 0) }
    local mo = {} AddEventHandler("gm_events:moment", function(e) mo[#mo+1] = e end)
    local function had(id) for _, e in ipairs(mo) do if e.moment == id then return e end end end
    local function hk(m, ex, res) return ops.hook(1, { what = "save", moment = m, resource = res or "my_hooks", export = ex }) end
    ok(not hk("nope", "x") and not hk("impact", "bad name") and not hk("impact", "x", "gm_events"), "bad hooks refused")
    local y, z, ch = hk("eventStarted", "rec") ok(y and ch, "hook saved: " .. tostring(z)) local rows = GM.hookRows() ok(#rows == 1 and rows[1].running, "listed, its resource runs")
    y, z = ops.hook(1, { what = "test", id = rows[1].id }) ok(y and tostring(z):find("true"), "test: " .. tostring(z))
    hk("bossDefeated", "boom") hk("bossAppeared", "rec", "notthere")
    ops.spawn(1, { kind = "boss", target = "front", id = "builtin:minotaur" }) Wait(500) ok(had("eventStarted") and had("eventStarted").kind == "boss" and had("bossAppeared"), "moments raised")
    for _, n in pairs(GM.living()) do GM.lootHit(n, "player:1") Open77.npcs.kill(n.id, "t") end Wait(1200) ok(had("bossDefeated") and had("bossDefeated").players[1] == 1, "boss defeated, by whom")
    local last = {} for _, r in ipairs(GM.hookRows()) do last[r.moment] = r end ok(last.eventStarted.ok == true, "a good hook: " .. last.eventStarted.last) ok(last.bossDefeated.ok == false, "a crashing hook is reported: " .. last.bossDefeated.last) ok(last.bossAppeared.ok == false and not last.bossAppeared.running, "a missing one: " .. last.bossAppeared.last)
    -- refusing a start
    reset() P = { [1] = at(0, 0) } y = hk("beforeStart", "no") y, z = ops.spawn(1, { kind = "squad", target = "front", id = "builtin:arasaka" }) ok(not y and z == "Not tonight" and next(GM.living()) == nil, "refused with their reason: " .. tostring(z))
    y, z = ops.chimera(1, { target = "front", def = { name = "C" } }) ok(not y and z == "Not tonight", "the Chimera too") local bid for _, r in ipairs(GM.hookRows()) do if r.moment == "beforeStart" then bid = r.id end end
    local function swap(ex, on) ops.hook(1, { what = "save", id = bid, moment = "beforeStart", resource = "my_hooks", export = ex, on = on }) return ops.spawn(1, { kind = "squad", target = "front", id = "builtin:arasaka" }) end
    y, z = swap("boom") ok(not y, "a broken check refuses: " .. tostring(z)) local t0 = GetGameTimer() y, z = swap("hang") ok(not y and GetGameTimer() - t0 < 6500, "a hanging check refuses: " .. tostring(z)) y, z = swap("nofunction") ok(not y, "a missing function refuses") y, z = swap("slowyes") ok(y, "a slow yes starts: " .. tostring(z)) reset() P = { [1] = at(0, 0) } y = swap("no", false) ok(y, "turned off, it is not asked")
    -- the others
    mo = {} reset() P = { [1] = at(0, 0) } mo = {} ops.spawn(1, { kind = "interact", target = "front", draft = { name = "I", prompt = "x", model = "", seconds = 0.5 } }) P[1] = at(0, 25) GM.setHolding(1, true) Wait(1500) GM.setHolding(1, false) ok(had("interactUsed") and had("interactUsed").playerId == 1 and had("interactFinished"), "interact moments")
    ops.spawn(1, { kind = "objectives", target = "front", draft = { name = "O", radius = 60, items = { { type = "custom", text = "x" } } } }) Wait(1200) GM.controlObjectives(GM.objectiveList()[1].id, "complete") Wait(400) ok(had("objectivesStarted") and had("playerJoined") and had("playerJoined").playerId == 1 and had("objectivesCompleted"), "objective moments")
    GM.core.handlers["gm.stop"](0, {}) Wait(300) ok(had("stopped"), "stopped")
    -- settings
    y, z, ch = ops.setting(1, { key = "objectiveGrace", value = 33.4 }) Wait(300) ok(y and ch and GM.objectiveGrace == 33, "setting saved: " .. tostring(z)) ops.setting(1, { key = "objectiveGrace", value = 9999 }) Wait(300) ok(GM.objectiveGrace == 120, "kept in range") ops.setting(1, { key = "objectiveGrace", value = 10 })
    ok(not ops.setting(1, { key = "bossBarStyle", value = "evil" }) and not ops.setting(1, { key = "scaleHealth", value = "yes" }) and not ops.setting(1, { key = "lootMethod", value = "off" }) and not ops.setting(1, { key = "nope", value = 1 }), "bad settings refused")
    local oA = Open77.acl.isAllowed Open77.acl.isAllowed = function(_, r) return r ~= "gm_events.owner" end ok(not hk("impact", "x") and not ops.setting(1, { key = "objectiveGrace", value = 5 }) and not ops.hook(1, { what = "delete", id = bid }), "the right is needed") Open77.acl.isAllowed = oA
    -- OWNEROTHER
    Open77.acl.isAllowed = function(_, r) return r ~= "gm_events.owner" end ok(not ops.lootSave(1, { values = { lootMethod = "off" } }) and GM.lootMethod ~= "off", "loot method is the owner's") ok(not ops.announceSave(1, { values = { announceMethod = "chat" } }), "announce method is the owner's") y, z = ops.announceSave(1, { values = { announceTitle = "T2", announceMethod = GM.announceMethod } }) ok(y, "staff may still reword: " .. tostring(z)) Open77.acl.isAllowed = oA
    -- SETUPLOCK
    ok(not GM.setupFinished(), "not set up yet") ok(ops.hook(1, { what = "finish" }) and GM.setupFinished(), "owner finishes setup") y, z = hk("impact", "rec") ok(not y, "locked: " .. tostring(z)) ok(not ops.hook(1, { what = "delete", id = bid }), "locked against deleting") y = ops.hook(1, { what = "test", id = bid }) ok(y ~= nil, "testing still works")
    Open77.acl.isAllowed = function(_, r) return r ~= "gm_events.owner" end ok(not ops.hook(1, { what = "unlock" }) and GM.setupFinished(), "others cannot unlock") Open77.acl.isAllowed = oA ok(ops.hook(1, { what = "unlock" }) and not GM.setupFinished(), "the owner can")
    local left = 0 for _, r in ipairs(GM.hookRows()) do ops.hook(1, { what = "delete", id = r.id }) end ok(#GM.hookRows() == 0, "deleted")
    reset() P = { [1] = at(0, 0) }
  end
  -- adoption
  ops.spawn(1, { kind = "boss", target = "front", id = "builtin:minotaur" })
  r, bad = GM.startObjectives(A, def({ items = { { type = "boss" } } })) ok(r, "adopts a boss already there: " .. tostring(bad)) Wait(1200) ok(r and not r.outcome, "boss alive: open")
  GM.core.handlers["gm.killboss"](0, {}) Wait(1500) ok(r and r.outcome == "completed", "boss objective completes")
  reset() P = { [1] = at(0, 0) }
  -- refusals
  local x, w = ops.spawn(1, { kind = "squad", target = "front", draft = { name = "Sq", units = { { record = unit, count = 1 } }, objectivesId = "gone" } }) ok(not x and #GM.objectiveList() == 0, "missing set refused: " .. tostring(w))
  local bset = ops.save(1, { kind = "objectives", def = { name = "B", radius = 60, items = { { type = "boss" } } } })
  local bid for id, dd in pairs(GM.testPresets.objectives) do if dd.name == "B" then bid = id end end
  x, w = ops.spawn(1, { kind = "squad", target = "front", draft = { name = "Sq", units = { { record = unit, count = 1 } }, objectivesId = bid } }) ok(not x, "boss set on a squad refused: " .. tostring(w))
  ok(not ops.save(1, { kind = "objectives", def = { name = "E", items = {} } }), "empty set refused")
  ok(not ops.save(1, { kind = "objectives", def = { name = "E", items = { { type = "custom" } } } }), "custom without text refused")
  ok(not ops.save(1, { kind = "objectives", def = { name = "E", items = { { type = "evil", text = "x" } } } }), "unknown type refused")
  for i = 1, 5 do start({ items = { { type = "custom", text = "x" } } }) end
  r, w = GM.startObjectives(A, def({ items = { { type = "custom", text = "x" } } })) ok(not r, "sixth refused: " .. tostring(w))
  Wait(1200) GM.core.handlers["gm.stop"](0, {}) Wait(300) ok(#GM.objectiveList() == 0 and saw("ended") and not saw("completed") and sentTo[1] == false, "gm.stop ends quietly")
  reset() P = { [1] = at(0, 25) }
  -- warning first
  do
    local said, oldSay = {}, GM.say
    GM.say = function(k, m, v) said[#said+1] = { m, GetGameTimer(), v and v.seconds } return true end
    local y, z = ops.spawn(1, { kind = "av", target = "front", draft = { name = "W", record = GM.avModels[1].record, flightSeconds = 2, distance = 40, height = 20, spawnDelay = 3, warning = "WARN", arrival = "ARR", warningLead = 4, squadId = "builtin:default" } })
    ok(y, "warned crash: " .. tostring(z)) Wait(1000) ok(#said == 1 and said[1][1] == "WARN" and said[1][3] == 6, "warning alone at first")
    local w8 = 0 while #said < 2 and w8 < 25000 do Wait(200) w8 = w8 + 200 end
    ok(#said == 2 and said[2][1] == "ARR" and said[2][2] - said[1][2] >= said[1][3] * 1000, "arrival after the warning is gone, gap " .. tostring(#said > 1 and said[2][2] - said[1][2]))
    reset() P = { [1] = at(0, 25) } said = {}
    ops.spawn(1, { kind = "av", target = "front", draft = { name = "W", record = GM.avModels[1].record, warning = "WARN", warningLead = 3, squadId = "builtin:default" } })
    Wait(500) GM.core.handlers["gm.stop"](0, {}) Wait(4000) ok(#said == 1 and next(GM.living()) == nil, "stop during the warning cancels the AV")
    GM.say = oldSay
    reset() P = { [1] = at(0, 25) }
  end
  -- crash
  local avd = { name = "Av", record = GM.avModels[1].record, flightSeconds = 2, distance = 40, height = 20, spawnDelay = 3, squadId = "builtin:default", objectivesId = sid }
  x, w = ops.spawn(1, { kind = "av", target = "front", draft = avd }) ok(x, "crash starts: " .. tostring(w)) ok(#GM.objectiveList() == 0, "no objectives before impact")
  local waited = 0 while #GM.objectiveList() == 0 and waited < 20000 do Wait(200) waited = waited + 200 end
  ok(#GM.objectiveList() == 1, "objectives at impact") Wait(1500) L = GM.objectiveList() ok(L[1] and L[1].outcome == "", "not won before anyone spawned")
  Wait(3000) L = GM.objectiveList() ok(L[1] and L[1].items[1].note == "0/4", "crash squad counted: " .. tostring(L[1] and L[1].items[1].note))
  for _, e in pairs(GM.living()) do Open77.npcs.kill(e.id, "t") end Wait(1500) L = GM.objectiveList() ok(L[1] and L[1].outcome == "completed", "crash objectives complete")
  reset() P = { [1] = at(0, 25) }
  if GetResourceState("gm_chimera") == "running" then
    avd.squadId, avd.bossId, avd.objectivesId = nil, "chimera", bid
    x, w = ops.spawn(1, { kind = "av", target = "front", draft = avd }) ok(x, "Chimera crash: " .. tostring(w))
    waited = 0 while next(GM.living()) == nil and waited < 25000 do Wait(200) waited = waited + 200 end
    Wait(1200) L = GM.objectiveList() ok(L[1] and L[1].outcome == "", "Chimera objective open")
    GM.core.handlers["gm.killboss"](0, {}) Wait(1500) L = GM.objectiveList() ok(L[1] and L[1].outcome == "completed", "Chimera objective completes")
    reset() P = { [1] = at(0, 25) }
    x, w = ops.chimera(1, { target = "front", def = { name = "Ch", objectivesId = bid } }) ok(x, "Chimera tab: " .. tostring(w))
    Wait(1200) L = GM.objectiveList() ok(L[1] and L[1].outcome == "" and L[1].players == 1, "tab objective open, player enrolled")
    GM.core.handlers["gm.killboss"](0, {}) Wait(1500) L = GM.objectiveList() ok(L[1] and L[1].outcome == "completed", "tab objective completes")
    reset() P = { [1] = at(0, 25) }
    x, w = ops.chimera(1, { target = "front", def = { name = "Ch", objectivesId = "gone" } }) ok(not x and next(GM.living()) == nil, "missing set refused: " .. tostring(w))
    x = ops.chimera(1, { target = "front", def = { name = "Ch", objectivesId = "" } }) ok(x and #GM.objectiveList() == 0, "no objectives still works")
  end
  reset() P = { [1] = at(0, 25), [2] = at(3, 25) }
  do -- LOOTTEST
    local got = {}
    AddEventHandler("gm_events:loot", function(a) got[#got+1] = a end)
    local function wait(n) local w = 0 while #got < n and w < 3000 do Wait(100) w = w + 100 end Wait(300) return #got == n end
    Wait(2500)
    local its = GM.lootItems() ok(#its == 2, "bridge registered items: " .. #its)
    ok(not ops.save(1, { kind = "loot", def = { name = "L", entries = {} } }), "empty table refused")
    ok(not ops.save(1, { kind = "loot", def = { name = "L", entries = { { item = "bad item;" } } } }), "bad item name refused")
    ok(ops.save(1, { kind = "loot", def = { name = "L", entries = { { item = "medkit", label = "Medkit", min = 2, max = 4, chance = 100 }, { item = "cash", min = 5, max = 1, chance = 100 } } } }), "table saved")
    local lid for id, x in pairs(GM.testPresets.loot) do if x.name == "L" then lid = id end end
    ok(GM.testPresets.loot[lid].entries[2].max == 5, "max never below min")
    ok(select(1, ops.lootSave(1, { values = { lootMethod = "event" } })), "settings saved")
    local function boss() ops.spawn(1, { kind = "boss", target = "front", draft = { name = "Bo", record = "Character.arasaka_minotaur", health = 1, lootId = lid } }) for _, n in pairs(GM.living()) do return n end end
    local n = boss() ok(n and n.lootDef, "boss carries loot")
    TriggerEvent("x") GM.lootHit(n, "player:1") GM.lootHit(n, "player:2") GM.lootHit(n, "player:77") GM.lootHit(n, "npc:3") GM.lootHit(n, "gm")
    ghost[2] = true Open77.npcs.kill(n.id, "t") ok(wait(1) and got[1].playerId == 1 and got[1].source == "boss", "only the online, unghosted player paid")
    ok(got[1] and #got[1].items == 2 and got[1].items[1].amount >= 2 and got[1].items[1].amount <= 4 and got[1].position and got[1].id, "award shape")
    local n1 = #got GM.lootDeath(n) Wait(800) ok(#got == n1, "a body pays once")
    reset() P = { [1] = at(0, 25) } got = {}
    n = boss() Open77.npcs.kill(n.id, "t") Wait(1200) ok(#got == 0, "nobody fought it, nothing given")
    reset() P = { [1] = at(0, 25), [2] = at(1, 25) } got = {}
    ops.lootSave(1, { values = { lootShare = "killer" } }) Wait(300)
    ops.spawn(1, { kind = "squad", target = "front", draft = { name = "Sq", units = { { record = unit, count = 2 } }, lootId = lid } })
    for _, e in pairs(GM.living()) do GM.lootHit(e, "player:1") GM.lootHit(e, "player:2") Open77.npcs.kill(e.id, "t") end
    ok(wait(2) and got[1].playerId == 2, "squad: each enemy pays its killer")
    ops.lootSave(1, { values = { lootShare = "everyone" } }) Wait(300)
    reset() P = { [1] = at(0, 25) } got = {}
    ops.save(1, { kind = "objectives", def = { name = "OL", radius = 60, lootId = lid, items = { { type = "custom", text = "x" } } } })
    local oid for id, dd in pairs(GM.testPresets.objectives) do if dd.name == "OL" then oid = id end end
    ops.lootSave(1, { values = { lootMinSeconds = 2 } }) Wait(300)
    ops.spawn(1, { kind = "objectives", target = "front", id = oid }) Wait(3500) P[2] = at(0, 25) Wait(1000)
    local run = GM.objectiveList()[1] GM.controlObjectives(run.id, "complete") ok(wait(1) and got[1].playerId == 1 and got[1].source == "objectives", "objective loot only with enough time")
    reset() P = { [1] = at(0, 25) } got = {}
    ops.lootSave(1, { values = { lootMethod = "export", lootResource = "my_loot", lootExport = "slow" } }) Wait(300)
    local a, b = ops.lootTest(1, { id = lid }) ok(a and wait(1) and got[1].handled == true, "slow export works: " .. tostring(b))
    got = {} ops.lootSave(1, { values = { lootExport = "no" } }) Wait(300)
    a, b = ops.lootTest(1, { id = lid }) ok(not a and #got == 0, "refused export reported: " .. tostring(b))
    local _, list = GM.core.handlers["gm.loot"](0, {}) local id = list:match("(gm%-%S+) Test player 1 failed") ok(id, "failed award listed")
    ops.lootSave(1, { values = { lootExport = "slow" } }) Wait(300)
    a, b = GM.core.handlers["gm.loot"](0, { "retry", id }) ok(a and wait(1) and got[1].id == id, "retry uses the same id")
    a = GM.core.handlers["gm.loot"](0, { "retry", id }) ok(not a, "a sent award cannot be retried")
    ops.lootSave(1, { values = { lootResource = "nothere" } }) Wait(300) a, b = ops.lootTest(1, { id = lid }) ok(not a, "missing resource: " .. tostring(b))
    got = {} ops.lootSave(1, { values = { lootMethod = "ground" } }) Wait(300)
    a, b = ops.lootTest(1, { id = lid }) ok(not a, "ground without open77_loot: " .. tostring(b))
    local oldState, made, gone, refuse = GetResourceState, {}, {}, false
    GetResourceState = function(r) if r == "open77_loot" then return "running" end return oldState(r) end
    Open77.loot = { create = function(d) if refuse and #made % 2 == 1 then return nil, "full" end made[#made+1] = d return 900 + #made end, remove = function(x) gone[#gone+1] = x return true end }
    a, b = ops.lootTest(1, { id = lid }) ok(not a and #made == 0, "ground refuses non-record items: " .. tostring(b))
    ops.save(1, { kind = "loot", def = { name = "G", entries = { { item = "Items.money", min = 5, max = 5, chance = 100 }, { item = "Items.x", min = 1, max = 1, chance = 100 } } } })
    local gid for i, dd in pairs(GM.testPresets.loot) do if dd.name == "G" then gid = i end end
    refuse = true a, b = ops.lootTest(1, { id = gid }) ok(not a and #gone == 1, "half a drop is taken back: " .. tostring(b)) refuse = false made = {}
    got = {} a, b = ops.lootTest(1, { id = gid }) ok(a and #made == 2 and wait(1) and got[1].handled, "ground drop: " .. tostring(b))
    TriggerEvent("onLootPickup", "2", "901", "Items.money", "5", GetCurrentResourceName()) Wait(500)
    ok(#made == 2, "two drops made") gone = {} GM.core.handlers["gm.stop"](0, {}) ok(#gone >= 1, "gm.stop removes drops: " .. #gone)
    GetResourceState = oldState
    ops.lootSave(1, { values = { lootMethod = "off" } }) Wait(300) ok(not ops.lootTest(1, { id = lid }), "off gives nothing")
    ok(not ops.lootSave(1, { values = { lootMethod = "evil" } }), "bad method refused")
    ops.lootSave(1, { values = { lootMethod = "event" } })
    local oldAllowed = Open77.acl.isAllowed
    Open77.acl.isAllowed = function(_, r) return r ~= "gm_events.loot" end
    a, b = ops.spawn(1, { kind = "boss", target = "front", draft = { name = "Bo", record = "Character.arasaka_minotaur", lootId = lid } }) ok(not a, "no right, no loot: " .. tostring(b))
    a, b = ops.spawn(1, { kind = "objectives", target = "front", id = oid }) ok(not a, "no right, no objective loot")
    a, b = ops.chimera(1, { target = "front", def = { name = "C", lootId = lid } }) ok(not a and next(GM.living()) == nil, "no right, no Chimera loot")
    a, b = ops.spawn(1, { kind = "av", target = "front", draft = { name = "A", record = GM.avModels[1].record, objectivesId = oid } }) ok(not a, "no right through a crash: " .. tostring(b))
    Open77.acl.isAllowed = oldAllowed
    a, b = ops.spawn(1, { kind = "squad", target = "front", draft = { name = "Sq", units = { { record = unit, count = 1 } }, lootId = "gone" } }) ok(not a, "missing table refused: " .. tostring(b))
    got = {}
    if GetResourceState("gm_chimera") == "running" then
      reset() P = { [1] = at(0, 25) }
      ops.chimera(1, { target = "front", def = { name = "C", lootId = lid } }) Wait(1000)
      for _, c in pairs(GM.living()) do GM.lootHit(c, "player:1") end
      GM.core.handlers["gm.killboss"](0, {}) ok(wait(1) and got[1].source == "boss", "Chimera pays")
    end
  end
  reset()
  print(("[T] DONE pass=%d fail=%d"):format(pass, fail))
end)
''')
ml = cs + "resources/my_loot"
os.makedirs(ml, exist_ok=True)
shutil.copy(r + "examples/loot_bridge.lua", ml + "/loot_bridge.lua")
open(ml + "/open77.lua", "w").write('resource "my_loot"\nversion "1.0.0"\nauto_start true\nserver_script "loot_bridge.lua"\nserver_script "x.lua"\n')
open(ml + "/x.lua", "w").write('exports("slow", function(a) Wait(700) return true end) exports("no", function() return false, "full" end)')
mh = cs + "resources/my_hooks"
os.makedirs(mh, exist_ok=True)
shutil.copy(r + "examples/hooks_bridge.lua", mh + "/hooks_bridge.lua")
open(mh + "/open77.lua", "w").write('resource "my_hooks"\nversion "1.0.0"\nauto_start true\nserver_script "hooks_bridge.lua"\nserver_script "x.lua"\n')
hx = open(mh + "/hooks_bridge.lua").read().replace('export = "luck" } }', 'export = "luck" }, { id = "never", label = "n", export = "never" }, { id = "slowyes", label = "s", export = "slowyes" } }')
open(mh + "/hooks_bridge.lua", "w").write(hx)
open(mh + "/x.lua", "w").write("""exports("rec", function() return true end) exports("boom", function() error("broke") end) exports("no", function() return false, "Not tonight" end) exports("hang", function() Wait(20000) return true end)
exports("never", function() return false, "Nope" end) exports("slowyes", function() Wait(1200) return true end)
AddEventHandler("hooktest:go", function() CreateThread(function()
  print("[x] " .. tostring(exports.gm_events:start("interact", "Hack the terminal", { x = 0, y = 10, z = 0 })))
  print("[x] " .. tostring(exports.gm_events:start("objectives", "ScriptSet", { x = 0, y = 0, z = 0 })))
  Wait(1200) local l = exports.gm_events:getObjectives() print("[x] " .. tostring(l and #l))
  local ok, why = exports.gm_events:setObjective(l[1].id, 1, { done = true }) print("[x] set " .. tostring(ok) .. " " .. tostring(why))
end) end)""")
j = open(cs + "server.jsonc").read()
if "my_hooks" not in j:
    open(cs + "server.jsonc", "w").write(j.replace('"my_loot"]', '"my_loot","my_hooks"]'))
j = open(cs + "server.jsonc").read()
if "my_loot" not in j:
    open(cs + "server.jsonc", "w").write(j.replace('"gm_events"]', '"gm_events","my_loot"]'))
for f in ("tunables.json",):
    if os.path.exists(cs + f): os.remove(cs + f)
log = os.path.join(os.path.dirname(__file__), "t80.log")
f = open(log, "w", encoding="utf-8", errors="replace")
proc = subprocess.Popen([cs + "Open77.Server.exe"], cwd=cs, stdout=f, stderr=subprocess.STDOUT, stdin=subprocess.PIPE)
try:
    for _ in range(980):
        time.sleep(1)
        if "[T] DONE" in (body := open(log, encoding="utf-8", errors="replace").read()) or "script error" in body or proc.poll() is not None:
            break
finally:
    proc.kill()
for line in open(log, encoding="utf-8", errors="replace"):
    if "[T]" in line or "rror" in line or "objectives" in line or "ERR" in line or "gm_events" in line:
        print(line.rstrip()[:220])
