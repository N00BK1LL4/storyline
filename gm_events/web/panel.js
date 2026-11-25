/* The staff panel. It only asks: the server checks rights and values. */
(function () {
  "use strict";
  var bridge = window.Open77;
  var $ = function (id) { return document.getElementById(id); };
  var all = function (q) { return Array.prototype.slice.call(document.querySelectorAll(q)); };

  // An empty Lua table may arrive as {} instead of [].
  function arr(v) { return Array.isArray(v) ? v : v && typeof v === "object" ? Object.keys(v).map(function (k) { return v[k]; }) : []; }
  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined) n.textContent = text;
    return n;
  }
  function btn(text, cls, fn) {
    var b = el("button", cls, text);
    b.type = "button";
    b.addEventListener("click", fn);
    return b;
  }

  window.addEventListener("error", function (e) {
    if (bridge) bridge.emit("gm:error", { text: String(e.message).slice(0, 300) + " @" + e.lineno });
  });

  var state = { boss: [], squad: [], av: [], fall: [], fallModels: [], drop: [], interact: [], interactModels: [], hookTypes: [], hookChecks: [], cast: [], castPoses: [], castBarks: [], objectives: [], loot: [], lootItems: [], scenes: [], avModels: [], status: {}, maxSquad: 20, canEdit: false };
  var live = { bosses: [], players: [], hostiles: 0, ghost: false, mark: false };
  var drafts = { boss: null, squad: null, av: null, fall: null, drop: null, interact: null, cast: null, objectives: null, loot: null };
  var req = 0;

  /* ---------------------------------------------------------------- models */
  var data = window.GM_MODELS || { cats: [], risks: [], rows: "" };
  var models = [], riskOf = {};
  var factions = [["arasaka", "Arasaka"], ["militech", "Militech"], ["kangtao", "Kang Tao"], ["security", "Private security"],
    ["kurtz", "Barghest (Kurtz)"], ["ncpd", "NCPD"], ["maxtac", "MaxTac"], ["trauma", "Trauma Team"], ["netwatch", "NetWatch"],
    ["maelstrom", "Maelstrom"], ["tyger", "Tyger Claws"], ["valentino", "Valentinos"], ["sixthstreet", "6th Street"],
    ["animals", "Animals"], ["mox", "Mox"], ["voodoo", "Voodoo Boys"], ["scav", "Scavengers"], ["wraith", "Wraiths"],
    ["afterlife", "Afterlife mercs"], ["aldecaldo", "Aldecaldos"], ["adelcaldo", "Aldecaldos"]]
    .map(function (f) { return { key: f[0], name: f[1], test: new RegExp("(^|_)" + f[0]) }; });
  // The faction named first wins: arasaka_security is Arasaka.
  function factionOf(key) {
    var found = null, at = Infinity;
    factions.forEach(function (f) {
      var hit = key.search(f.test);
      if (hit >= 0 && hit < at) { found = f; at = hit; }
    });
    return found;
  }
  data.rows.split("\n").forEach(function (line) {
    var p = line.split("|");
    if (p.length !== 3) return;
    var m = { record: "Character." + p[0], cat: data.cats[+p[1]], risk: data.risks[+p[2]], key: p[0].toLowerCase() };
    m.faction = factionOf(m.key);
    m.main = m.faction && m.key.indexOf(m.faction.key) === 0 ? 0 : 1; // plain versions before district and quest copies
    models.push(m);
    riskOf[m.record] = m.risk;
  });

  function verdict(record) {
    var s = state.status && state.status[record];
    if (s === "tested" || s === "broken") return s;
    return riskOf[record] === "candidate" || riskOf[record] === "soldier" ? riskOf[record] : "risky";
  }
  function bodies(kind) { return kind === "fall" ? state.fallModels : state.avModels; }
  function avVerdict(m) {
    var s = state.status && state.status[m.record];
    return s === "tested" || s === "broken" ? s : m.tested ? "tested" : "untested";
  }
  function tag(record) {
    var v = verdict(record);
    var names = { tested: "Tested", broken: "Broken", candidate: "Candidate", soldier: "Soldier, untested", risky: "Risky" };
    return el("span", "tag " + v, names[v]);
  }
  function short(record) { return String(record || "").replace(/^(Character|Vehicle)\./, ""); }

  /* ------------------------------------------------------------- messaging */
  function call(op, body) {
    var message = { op: op, req: ++req, target: $("target").value };
    Object.keys(body || {}).forEach(function (k) { message[k] = body[k]; });
    result("Sending...", "");
    bridge.emit("gm:call", { json: JSON.stringify(message) });
  }
  function result(text, cls) {
    $("result").textContent = text;
    $("result").className = cls;
  }
  function confirmThen(text, fn) {
    $("confirmText").textContent = text;
    $("confirm").classList.add("on");
    $("confirmNo").focus();
    $("confirmYes").onclick = function () { $("confirm").classList.remove("on"); fn(); };
  }
  $("confirmNo").addEventListener("click", function () { $("confirm").classList.remove("on"); });

  // Warn once before spawning anything doubtful.
  function spawn(kind, def, body) {
    var records = kind === "squad" ? def.units.map(function (u) { return u.record; }) : kind === "boss" || kind === "cast" ? [def.record] : [];
    if (kind === "av" || kind === "fall" || kind === "drop") {
      var av = arr(bodies(kind)).filter(function (m) { return m.record === def.record; })[0];
      if (av && avVerdict(av) === "broken" && !body.sure) {
        body.sure = true;
        return confirmThen("This model is marked broken. Use it anyway?", function () { spawn(kind, def, body); });
      }
      var squad = original("squad", def.squadId), boss = original("boss", def.bossId);
      if (squad) records = records.concat(arr(squad.units).map(function (u) { return u.record; }));
      if (boss) records.push(boss.record);
    }
    var brought = kind === "interact" ? def : original("interact", def.interactId);
    var alarm = brought && original("squad", brought.squadId);
    if (alarm) records = records.concat(arr(alarm.units).map(function (u) { return u.record; }));
    var bad = records.filter(function (r) { var v = verdict(r); return v === "risky" || v === "broken"; });
    body.kind = kind;
    delete body.sure;
    var go = function () { call("spawn", body); };
    if (!bad.length) {
      var fresh = records.filter(function (r, i, a) { return verdict(r) === "soldier" && a.indexOf(r) === i; });
      if (!fresh.length) return go();
      return confirmThen("These soldiers have not been marked tested yet. Try them while no event is running: " +
        fresh.map(short).join(", "), go);
    }
    confirmThen("These models are marked risky or broken and may misbehave or crash players' games: " +
      bad.map(short).filter(function (v, i, a) { return a.indexOf(v) === i; }).join(", "), go);
  }

  /* ------------------------------------------------------------------ tabs */
  all("#tabs button").forEach(function (b) {
    b.addEventListener("click", function () {
      all("#tabs button").forEach(function (o) { o.classList.toggle("on", o === b); });
      all("section").forEach(function (s) { s.classList.toggle("on", s.dataset.view === b.dataset.tab); });
    });
  });

  all("[data-cmd]").forEach(function (b) {
    b.addEventListener("click", function () { call("command", { name: b.dataset.cmd, arg: b.dataset.arg }); });
  });
  $("ghost").addEventListener("click", function () { call("command", { name: "gm.ghost", arg: live.ghost ? "off" : "on" }); });
  $("stop").addEventListener("click", function () { call("command", { name: "gm.stop" }); });
  function sendAnnounce() {
    var t = $("announce").value.trim();
    if (!t) return result("Type a message first", "bad");
    call("command", { name: "gm.announce", arg: t });
    $("announce").value = "";
  }
  $("chSpawn").addEventListener("click", function () {
    var def = { name: $("chName").value, health: parseFloat($("chHealth").value), damage: parseFloat($("chDamage").value),
      scaling: $("chScale").checked, objectivesId: $("chObjectives").value, lootId: $("chLoot").value };
    confirmThen("Spawn the Chimera? It is a very large boss. Check the target is open ground.", function () {
      call("chimera", { def: def });
    });
  });
  all("[data-phase]").forEach(function (b) {
    b.addEventListener("click", function () { call("chimera", { phase: b.dataset.phase }); });
  });
  /* announcement settings */
  var dirty = false;
  function inputs() { return all("[data-set]"); }
  function announceView() {
    var method = document.querySelector('[data-set="announceMethod"]').value;
    all("[data-only]").forEach(function (f) { f.style.display = f.dataset.only === method ? "" : "none"; });
    $("announceHelp").textContent = {
      notification: "The standard toast in the corner of the screen.",
      chat: "A line in chat. Needs open77_chat.",
      export: "Calls your resource's export with one table: kind, title, text, seconds, boss, percent, players.",
      event: "Shows nothing itself. Your server script handles the gm_events:announcement event.",
      none: "No announcements at all, including ones staff type."
    }[method] || "";
  }
  function renderAnnounce() {
    document.querySelector('[data-tab="announce"]').style.display = state.canEdit ? "" : "none";
    if (dirty || !state.announce) return; // never overwrite what is being typed
    inputs().forEach(function (i) {
      var v = state.announce[i.dataset.set];
      i.value = v === "-" ? "" : v;
    });
    announceView();
  }
  inputs().forEach(function (i) {
    i.addEventListener("input", function () { dirty = true; announceView(); });
  });
  $("announceSave").addEventListener("click", function () {
    var values = {};
    inputs().forEach(function (i) { values[i.dataset.set] = i.type === "number" ? parseFloat(i.value) : i.value.trim(); });
    dirty = false;
    call("announceSave", { values: values });
  });
  $("announceTest").addEventListener("click", function () {
    if (dirty) return result("Save your changes first, then test", "bad");
    confirmThen("Send a test announcement to every player on the server?", function () { call("announceTest", {}); });
  });

  /* bookmarks and story characters */
  $("bmSave").addEventListener("click", function () {
    var name = $("bmName").value.trim();
    if (!name) return result("Give the bookmark a name", "bad");
    call("bookmark", { name: name, group: $("bmGroup").value.trim() });
    $("bmName").value = "";
  });
  function fill(select, options) {
    var sign = JSON.stringify(options), keep = select.value;
    if (select.dataset.sign === sign) return;
    select.dataset.sign = sign;
    select.textContent = "";
    options.forEach(function (o) { var n = el("option", "", o[1]); n.value = o[0]; select.appendChild(n); });
    if (options.some(function (o) { return o[0] === keep; })) select.value = keep;
  }
  function onStage() { return arr(live.cast).filter(function (c) { return String(c.id) === $("castWho").value; })[0]; }
  function renderStage() {
    var people = arr(live.cast);
    fill($("castWho"), people.length ? people.map(function (c) { return [String(c.id), c.name]; }) : [["", "Nobody is on stage"]]);
    fill($("castBark"), [["", "No voice"]].concat(arr(state.castBarks).map(function (b) { return [b, b.replace(/_/g, " ")]; })));
    fill($("castPose"), [["", "Choose a pose"]].concat(arr(state.castPoses).map(function (p) { return [p, p]; })));
    var who = onStage(), lines = who ? arr(who.lines) : [], box = $("castLines");
    $("castDoing").textContent = who ? who.doing : "Place a character from the list on the left.";
    var sign = who ? who.id + JSON.stringify(lines) : "";
    if (box.dataset.sign !== sign) {
      box.dataset.sign = sign;
      box.textContent = "";
      lines.forEach(function (line) { box.appendChild(btn(line, "", function () { speak(line); })); });
    }
  }
  $("castWho").addEventListener("change", renderStage);
  function speak(line) {
    var who = onStage();
    if (!who) return result("Place a character first", "bad");
    call("cast", { id: who.id, what: "say", text: line, volume: $("castVolume").value, bark: $("castBark").value });
  }
  $("castSay").addEventListener("click", function () {
    var line = $("castLine").value.replace(/\s+/g, " ").trim();
    if (!line) return result("Type a line first", "bad");
    speak(line);
    $("castLine").value = "";
  });
  $("castLine").addEventListener("keydown", function (e) {
    if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); $("castSay").click(); }
  });
  all("[data-cast]").forEach(function (b) {
    b.addEventListener("click", function () {
      var who = onStage();
      if (!who) return result("Place a character first", "bad");
      call("cast", { id: who.id, what: b.dataset.cast, pose: $("castPose").value, run: $("castRun").checked });
    });
  });

  /* loot settings */
  var lootDirty = false;
  function lootView() {
    var method = document.querySelector('[data-loot="lootMethod"]').value;
    all("[data-loot-only]").forEach(function (f) { f.style.display = f.dataset.lootOnly === method ? "" : "none"; });
    $("lootHelp").textContent = {
      event: "Your server script handles the gm_events:loot event. Nothing is given until one does.",
      export: "Calls your resource's export with the award. It must answer true.",
      ground: "Needs the open77_loot resource. Players pick items up where the enemy fell; objective rewards drop at each player's feet.",
      off: "Nobody earns loot."
    }[method] || "";
  }
  function renderLootSettings() {
    $("lootSettings").style.display = state.canEdit ? "" : "none";
    if (lootDirty || !state.lootSettings) return;
    all("[data-loot]").forEach(function (i) {
      var v = state.lootSettings[i.dataset.loot];
      i.value = v === "-" ? "" : v;
    });
    lootView();
  }
  all("[data-loot]").forEach(function (i) {
    i.addEventListener("input", function () { lootDirty = true; lootView(); });
  });
  $("lootSave").addEventListener("click", function () {
    var values = {};
    all("[data-loot]").forEach(function (i) { values[i.dataset.loot] = i.type === "number" ? parseFloat(i.value) : i.value.trim(); });
    lootDirty = false;
    call("lootSave", { values: values });
  });

  $("announceSend").addEventListener("click", sendAnnounce);
  $("announce").addEventListener("keydown", function (e) { if (e.key === "Enter") sendAnnounce(); });

  /* ------------------------------------------------------------------ live */
  function renderTarget() {
    var select = $("target"), keep = select.value || "front";
    var options = [["front", "In front of me"]];
    if (live.mark) options.push(["mark", "My mark"]);
    arr(live.bookmarks).forEach(function (b) { options.push(["b:" + b.id, (b.group ? b.group + ": " : "") + b.name]); });
    arr(live.players).forEach(function (p) { options.push([String(p.id), "Near " + p.name]); });
    var signature = JSON.stringify(options);
    if (select.dataset.signature === signature) return;
    select.dataset.signature = signature;
    select.textContent = "";
    options.forEach(function (o) {
      var n = el("option", "", o[1]);
      n.value = o[0];
      select.appendChild(n);
    });
    select.value = options.some(function (o) { return o[0] === keep; }) ? keep : "front";
  }
  function renderLive() {
    renderTarget();
    $("ghost").textContent = "Ghost: " + (live.ghost ? "on" : "off");
    $("ghost").setAttribute("aria-pressed", live.ghost ? "true" : "false");
    var box = $("bosses"), bosses = arr(live.bosses);
    box.textContent = "";
    if (!bosses.length) box.appendChild(el("p", "dim", "No bosses are active. Spawn one from the Bosses tab."));
    bosses.forEach(function (b) {
      var row = el("div", "bar");
      row.appendChild(el("div", "", b.name + "  " + b.percent + "%  (" + b.players + (b.players === 1 ? " player)" : " players)") + (b.extra ? "  " + b.extra : "")));
      var track = el("div", "track"), fill = el("div", "fill");
      fill.style.width = Math.max(0, Math.min(100, +b.percent || 0)) + "%";
      track.appendChild(fill);
      row.appendChild(track);
      box.appendChild(row);
    });
    $("hostiles").textContent = live.hostiles + (live.hostiles === 1 ? " hostile alive" : " hostiles alive");
    renderRuns();
    renderStage();
    var marks = arr(live.bookmarks), bmBox = $("bookmarks"), bmSign = JSON.stringify(marks);
    $("bookmarkBox").style.display = state.canEdit ? "" : "none";
    if (bmBox.dataset.sign !== bmSign) {
      bmBox.dataset.sign = bmSign;
      bmBox.textContent = "";
      marks.forEach(function (b) {
        var row = el("div", "row");
        row.appendChild(el("span", "", (b.group ? b.group + ": " : "") + b.name));
        row.appendChild(btn("Delete", "", function () {
          confirmThen("Delete the bookmark \"" + b.name + "\"?", function () { call("bookmark", { delete: b.id }); });
        }));
        bmBox.appendChild(row);
      });
    }
    var list = arr(live.interacts), inBox = $("interacts"), sign = JSON.stringify(list);
    if (inBox.dataset.sign !== sign) {
      inBox.dataset.sign = sign;
      inBox.textContent = "";
      list.forEach(function (i) {
        var row = el("div", "row");
        row.appendChild(el("span", "", i.name + "  " + i.done + "/" + i.total));
        row.appendChild(btn("Remove", "", function () { call("interacts", { id: i.id }); }));
        inBox.appendChild(row);
      });
    }
  }

  /* Rebuilt only when something structural changes, so a click is never lost. */
  function renderRuns() {
    var box = $("runs"), runs = arr(live.objectives);
    var shape = JSON.stringify(runs.map(function (r) {
      return [r.id, r.name, r.outcome, arr(r.items).map(function (i) { return [i.text, i.done]; })];
    }));
    if (box.dataset.shape !== shape) {
      box.dataset.shape = shape;
      box.textContent = "";
      runs.forEach(function (r) {
        var run = el("div", "run");
        run.appendChild(el("div", "head"));
        arr(r.items).forEach(function (item, i) {
          var row = el("div", "row");
          row.appendChild(el("span", "goalText"));
          if (!item.done && !r.outcome) {
            row.appendChild(btn("Tick", "", function () { call("objectives", { id: r.id, what: "tick", index: i + 1 }); }));
          }
          run.appendChild(row);
        });
        if (!r.outcome) {
          var buttons = el("div", "row");
          [["complete", "Complete"], ["fail", "Fail"], ["end", "End quietly"]].forEach(function (b) {
            buttons.appendChild(btn(b[1], "", function () { call("objectives", { id: r.id, what: b[0] }); }));
          });
          run.appendChild(buttons);
        }
        box.appendChild(run);
      });
    }
    runs.forEach(function (r, n) {
      var run = box.children[n];
      run.querySelector(".head").textContent = r.name + "  (" + r.players + (r.players === 1 ? " player)" : " players)") +
        (r.time ? "  " + r.time : "") + (r.outcome ? "  " + r.outcome : "");
      var texts = run.querySelectorAll(".goalText");
      arr(r.items).forEach(function (item, i) {
        texts[i].textContent = (item.done ? "Done: " : item.active ? "" : "Later: ") + item.text + (item.note ? "  " + item.note : "");
      });
    });
  }

  /* --------------------------------------------------------------- editors */
  var goalTypes = [["enemies", "Defeat the enemies"], ["kill", "Kill a number"], ["boss", "Defeat the boss"],
    ["reach", "Reach a place"], ["hold", "Hold an area"], ["survive", "Survive"], ["interact", "Use interactables"], ["custom", "Custom, ticked by staff"]];
  function newGoal(type, text) {
    var g = { type: type };
    if (text) g.text = text;
    if (type === "kill") g.count = 5;
    if (type === "interact") g.count = 1;
    if (type === "hold" || type === "survive") g.seconds = 60;
    if (type === "reach" || type === "hold") { g.size = 8; g.distance = 0; g.direction = 0; }
    if (type === "hold") g.players = 1;
    return g;
  }
  var blank = {
    boss: function () { return { name: "", record: "", health: 5, height: 2.4, scaling: true }; },
    squad: function () { return { name: "", units: [], pattern: "ring", radius: 6 }; },
    av: function () {
      var first = arr(state.avModels)[0];
      return { name: "", record: first ? first.record : "", distance: 110, height: 70, flightSeconds: 5, direction: 0,
        blastRadius: 12, blastDamage: 0, fireSeconds: 90 };
    },
    fall: function () {
      var first = arr(state.fallModels)[0];
      return { name: "", record: first ? first.record : "", distance: 60, height: 160, flightSeconds: 5, direction: 0, spin: 120,
        blastRadius: 14, blastDamage: 0, fireSeconds: 60, crater: 5, sink: 0.4, rim: 1, debris: 5, debrisRadius: 30 };
    },
    drop: function () {
      var first = arr(state.avModels)[0];
      return { name: "", record: first ? first.record : "", height: 45, run: 130, flySeconds: 9, fallSeconds: 8, direction: 0,
        hover: 0.8, openSeconds: 5, life: 15, share: "near" };
    },
    interact: function () {
      return { name: "", prompt: "Hold to use", model: "electronics.monitor.device", count: 1, spread: 8, seconds: 5, players: 1,
        uses: 1, cooldown: 0, effect: "none", fuse: 0, blastRadius: 8, blastDamage: 0, spawnDelay: 2 };
    },
    cast: function () { return { name: "", record: "", pose: "", lines: [] }; },
    objectives: function () { return { name: "", radius: 60, items: [newGoal("enemies")], ordered: true, timeLimit: 0 }; },
    loot: function () { return { name: "", entries: [{ item: "", min: 1, max: 1, chance: 100 }] }; }
  };
  function summary(kind, d) {
    if (kind === "squad") {
      var units = arr(d.units), total = units.reduce(function (n, u) { return n + (+u.count || 0); }, 0);
      return total + " units, " + d.pattern;
    }
    if (kind === "av" || kind === "fall" || kind === "drop") {
      var with_ = [];
      if (d.squadId) with_.push((original("squad", d.squadId) || { name: "missing squad" }).name);
      if (d.bossId) with_.push(d.bossId === "chimera" ? "Chimera" : (original("boss", d.bossId) || { name: "missing boss" }).name);
      return short(d.record) + (with_.length ? ", with " + with_.join(" and ") : "");
    }
    if (kind === "loot") {
      var e = arr(d.entries).length;
      return e + (e === 1 ? " item" : " items");
    }
    if (kind === "cast") return short(d.record) + (d.mortal ? ", can be killed" : "");
    if (kind === "interact") return d.prompt + ", " + d.seconds + " s" + (d.count > 1 ? ", " + d.count + " of them" : "");
    if (kind === "objectives") {
      var n = arr(d.items).length;
      return n + (n === 1 ? " objective, " : " objectives, ") + d.radius + " m";
    }
    return short(d.record) + (kind === "boss" ? ", " + d.health + "x health" : "");
  }

  function renderList(kind) {
    var box = document.querySelector('[data-list="' + kind + '"]');
    box.textContent = "";
    if (state.canEdit) box.appendChild(btn("New preset", "item", function () { drafts[kind] = blank[kind](); renderKind(kind); }));
    arr(state[kind]).forEach(function (d) {
      var on = drafts[kind] && drafts[kind].id === d.id;
      var b = btn(d.name + (d.builtin ? "  (built in)" : ""), "item" + (on ? " on" : ""), function () {
        drafts[kind] = JSON.parse(JSON.stringify(d));
        if (kind === "squad") drafts[kind].units = arr(drafts[kind].units);
        if (kind === "objectives") drafts[kind].items = arr(drafts[kind].items);
        if (kind === "cast") drafts[kind].lines = arr(drafts[kind].lines);
        if (kind === "loot") drafts[kind].entries = arr(drafts[kind].entries);
        renderKind(kind);
      });
      b.appendChild(el("small", "", summary(kind, d)));
      box.appendChild(b);
    });
  }

  function field(label, node, extra) {
    var f = el("label", "field");
    f.appendChild(el("span", "", label));
    f.appendChild(node);
    if (extra) f.appendChild(extra);
    return f;
  }
  function textInput(d, key, max) {
    var i = el("input");
    i.type = "text"; i.maxLength = max; i.value = d[key] || "";
    i.addEventListener("input", function () { d[key] = i.value; });
    return i;
  }
  function numberInput(d, key, low, high, step, onChange) {
    var i = el("input");
    i.type = "number"; i.min = low; i.max = high; i.step = step; i.value = d[key];
    i.addEventListener("input", function () {
      var v = parseFloat(i.value);
      if (isFinite(v)) d[key] = Math.max(low, Math.min(high, v));
      if (onChange) onChange();
    });
    return i;
  }
  function choice(d, key, options) {
    var s = el("select");
    options.forEach(function (o) { var n = el("option", "", o[1]); n.value = o[0]; s.appendChild(n); });
    s.value = d[key];
    s.addEventListener("change", function () { d[key] = s.value; });
    return s;
  }
  function modelRow(d, after) {
    var wrap = el("div", "row");
    wrap.appendChild(el("span", "record", d.record ? short(d.record) : "No model chosen"));
    if (d.record) wrap.appendChild(tag(d.record));
    wrap.appendChild(btn("Choose", "", function (e) {
      e.preventDefault();
      pick(function (record) { d.record = record; after(); });
    }));
    return wrap;
  }
  function noteButtons(record) {
    var wrap = el("div", "row");
    [["tested", "Mark tested"], ["broken", "Mark broken"], ["", "Clear note"]].forEach(function (o) {
      wrap.appendChild(btn(o[1], "", function () { call("status", { record: record, value: o[0] }); }));
    });
    return wrap;
  }

  // Solo estimate from one measured fight: 1x took about 19 s.
  function estimate(h) {
    var s = Math.round(h * 19);
    return s < 90 ? "about " + s + " s solo" : "about " + (s / 60).toFixed(1) + " min solo";
  }

  function presetOptions(kind, none, id, what) { // a deleted preset stays visible instead of silently changing
    var list = [["", none]].concat(arr(state[kind]).map(function (p) { return [p.id, p.name]; }));
    if (id && !list.some(function (o) { return o[0] === id; })) list.push([id, "Missing " + what]);
    return list;
  }
  function objectivesField(box, d, note) {
    d.objectivesId = d.objectivesId || "";
    box.appendChild(field("Objectives", choice(d, "objectivesId",
      presetOptions("objectives", "No objectives", d.objectivesId, "objectives"))));
    if (d.model === undefined) { // everything but an interactable itself can bring one
      d.interactId = d.interactId || "";
      box.appendChild(field("Interactable", choice(d, "interactId", presetOptions("interact", "None", d.interactId, "interactable"))));
    }
    if (note) box.appendChild(el("p", "dim", note));
  }
  function lootField(box, d, note) {
    d.lootId = d.lootId || "";
    box.appendChild(field("Loot", choice(d, "lootId", presetOptions("loot", "No loot", d.lootId, "loot table"))));
    if (note) box.appendChild(el("p", "dim", note));
  }
  function lootEditor(box, d, redraw) {
    box.appendChild(el("h2", "", "Items: " + d.entries.length + " of 12"));
    d.entries.forEach(function (e, i) {
      var card = el("div", "goal");
      var known = arr(state.lootItems);
      if (known.length) {
        var list = [["", "Choose from the server's items"]].concat(known.map(function (k) { return [k.id, k.label]; }));
        var pickItem = { id: known.some(function (k) { return k.id === e.item; }) ? e.item : "" };
        var select = choice(pickItem, "id", list);
        select.addEventListener("change", function () {
          if (!pickItem.id) return;
          e.item = pickItem.id;
          e.label = known.filter(function (k) { return k.id === pickItem.id; })[0].label.slice(0, 40);
          redraw();
        });
        card.appendChild(field("Server item", select));
      }
      card.appendChild(field("Item name", textInput(e, "item", 80)));
      card.appendChild(field("Shown as", textInput(e, "label", 40)));
      var amounts = el("div", "row");
      amounts.appendChild(numberInput(e, "min", 1, 1000000, 1));
      amounts.appendChild(el("span", "dim", "to"));
      amounts.appendChild(numberInput(e, "max", 1, 1000000, 1));
      card.appendChild(field("Amount", amounts));
      card.appendChild(field("Chance, %", numberInput(e, "chance", 0.1, 100, 1)));
      var remove = btn("Remove", "", function () { d.entries.splice(i, 1); redraw(); });
      remove.disabled = d.entries.length === 1;
      card.appendChild(remove);
      box.appendChild(card);
    });
    var add = btn("Add item", "", function () { d.entries.push({ item: "", min: 1, max: 1, chance: 100 }); redraw(); });
    add.disabled = d.entries.length >= 12;
    box.appendChild(add);
    box.appendChild(el("p", "dim", "Item name is the name your server's inventory uses. Ground drops need a game record such as Items.money. Each item is rolled separately."));
  }
  function tickBox(d, key) {
    var i = el("input");
    i.type = "checkbox"; i.checked = d[key] === true;
    i.addEventListener("change", function () { if (i.checked) d[key] = true; else delete d[key]; });
    return i;
  }
  function goalEditor(box, d, redraw) {
    box.appendChild(field("Radius, m", numberInput(d, "radius", 10, 250, 5)));
    box.appendChild(el("p", "dim", "Players inside this distance get the objectives. Progress is shared."));
    var order = { mode: d.ordered === false ? "all" : "order" };
    var orderSelect = choice(order, "mode", [["order", "One after another"], ["all", "All at once"]]);
    orderSelect.addEventListener("change", function () { d.ordered = order.mode === "order"; });
    box.appendChild(field("Objectives are given", orderSelect));
    box.appendChild(el("h2", "", "Objectives: " + d.items.length + " of 8"));
    d.items.forEach(function (g, i) {
      var card = el("div", "goal"), row = el("div", "row");
      // owners' own types sit in the same list, as hook|<resource:id>
      var kinds = goalTypes.concat(arr(state.hookTypes).map(function (h) { return ["hook|" + h.id, h.label + " (server's own)"]; }));
      var current = { value: g.type === "hook" ? "hook|" + g.hook : g.type };
      if (!kinds.some(function (k) { return k[0] === current.value; })) kinds.push([current.value, "Missing: " + g.hook]);
      var pickType = choice(current, "value", kinds);
      pickType.addEventListener("change", function () {
        var hook = current.value.indexOf("hook|") === 0 ? current.value.slice(5) : null;
        d.items[i] = newGoal(hook ? "hook" : current.value, g.text);
        if (hook) d.items[i].hook = hook;
        redraw();
      });
      row.appendChild(pickType);
      var up = btn("Up", "", function () { d.items.splice(i - 1, 0, d.items.splice(i, 1)[0]); redraw(); });
      up.disabled = i === 0;
      row.appendChild(up);
      var remove = btn("Remove", "", function () { d.items.splice(i, 1); redraw(); });
      remove.disabled = d.items.length === 1;
      row.appendChild(remove);
      card.appendChild(row);
      card.appendChild(field("Text players see", textInput(g, "text", 80)));
      if (g.type === "kill" || g.type === "interact") card.appendChild(field("How many", numberInput(g, "count", 1, 100, 1)));
      if (g.type === "hold" || g.type === "survive") card.appendChild(field("Seconds", numberInput(g, "seconds", 5, 1800, 5)));
      if (g.type === "hold") card.appendChild(field("Players needed", numberInput(g, "players", 1, 16, 1)));
      if (g.type === "reach" || g.type === "hold") {
        card.appendChild(field("Size of the spot, m", numberInput(g, "size", 2, 50, 1)));
        card.appendChild(field("Distance from centre, m", numberInput(g, "distance", 0, 250, 5)));
        card.appendChild(field("Direction, degrees", numberInput(g, "direction", -180, 180, 15)));
      }
      box.appendChild(card);
    });
    var add = btn("Add objective", "", function () { d.items.push(newGoal("reach")); redraw(); });
    add.disabled = d.items.length >= 8;
    box.appendChild(add);
    box.appendChild(el("p", "dim", "Empty text uses the usual wording. Direction 0 is straight ahead of you, 90 is to your right. A spot never lies outside the radius."));
    box.appendChild(el("h2", "", "Ending"));
    box.appendChild(field("Time limit, s (0 = none)", numberInput(d, "timeLimit", 0, 7200, 30)));
    box.appendChild(field("Fail if everyone is down", tickBox(d, "failOnWipe")));
    box.appendChild(el("h2", "", "Announcements to the whole server"));
    box.appendChild(field("When it starts", textInput(d, "intro", 160)));
    box.appendChild(field("When completed", textInput(d, "success", 160)));
    box.appendChild(field("When failed", textInput(d, "failure", 160)));
    box.appendChild(el("p", "dim", "Leave empty to say nothing. Players taking part always see the result."));
  }

  function renderEditor(kind) {
    var box = document.querySelector('[data-editor="' + kind + '"]'), d = drafts[kind];
    var redraw = function () { renderEditor(kind); };
    box.textContent = "";
    if (!d) return box.appendChild(el("p", "dim", "Choose a preset on the left" + (state.canEdit ? ", or create a new one." : ".")));

    box.appendChild(field("Name", textInput(d, "name", 32)));
    if (kind === "boss") {
      box.appendChild(field("Model", modelRow(d, redraw)));
      var guess = el("span", "dim", estimate(d.health));
      box.appendChild(field("Health multiplier", numberInput(d, "health", 0.1, 100, 0.5, function () { guess.textContent = estimate(d.health); }), guess));
      box.appendChild(el("p", "dim", "Rough guess from one Minotaur fight. Other models and weapons will differ."));
      box.appendChild(field("Name card height, m", numberInput(d, "height", 1, 8, 0.1)));
      var tick = el("input");
      tick.type = "checkbox"; tick.checked = d.scaling !== false;
      tick.addEventListener("change", function () { d.scaling = tick.checked; });
      box.appendChild(field("Scale with players", tick));
      objectivesField(box, d);
      lootField(box, d, "Goes to everyone who hurt the boss.");
      box.appendChild(field("Arrival message", textInput(d, "intro", 160)));
      box.appendChild(field("Defeat message", textInput(d, "outro", 160)));
      box.appendChild(el("p", "dim", "Leave empty to use the server's usual messages."));
    } else if (kind === "squad") {
      box.appendChild(field("Formation", choice(d, "pattern", [["ring", "Ring"], ["line", "Line"], ["cluster", "Cluster"]])));
      box.appendChild(field("Radius, m", numberInput(d, "radius", 2, 20, 1)));
      var total = d.units.reduce(function (n, u) { return n + (+u.count || 0); }, 0);
      box.appendChild(el("h2", "", "Units: " + total + " of " + state.maxSquad));
      d.units.forEach(function (u, i) {
        var row = el("div", "field");
        row.appendChild(numberInput(u, "count", 1, state.maxSquad, 1));
        row.appendChild(modelRow(u, redraw));
        if (state.canEdit && u.record && verdict(u.record) !== "tested") {
          row.appendChild(btn("Mark tested", "", function () { call("status", { record: u.record, value: "tested" }); }));
        }
        row.appendChild(btn("Remove", "", function () { d.units.splice(i, 1); redraw(); }));
        box.appendChild(row);
      });
      var add = btn("Add unit type", "", function () {
        pick(function (record) { d.units.push({ record: record, count: 1 }); redraw(); });
      });
      add.disabled = d.units.length >= 8;
      box.appendChild(add);
      objectivesField(box, d);
      lootField(box, d, "Rolled for every enemy in the squad.");
    } else if (kind === "cast") {
      box.appendChild(field("Model", modelRow(d, redraw)));
      box.appendChild(field("Starts by", choice(d, "pose", [["", "Standing"]].concat(arr(state.castPoses).map(function (p) { return [p, p]; })))));
      box.appendChild(field("Can be killed", tickBox(d, "mortal")));
      box.appendChild(el("h2", "", "Saved lines: " + d.lines.length + " of 10"));
      d.lines.forEach(function (line, i) {
        var holder = { t: line }, row2 = el("div", "field"), input = textInput(holder, "t", 160);
        input.addEventListener("input", function () { d.lines[i] = holder.t; });
        row2.appendChild(input);
        row2.appendChild(btn("Remove", "", function () { d.lines.splice(i, 1); redraw(); }));
        box.appendChild(row2);
      });
      var addLine = btn("Add line", "", function () { d.lines.push(""); redraw(); });
      addLine.disabled = d.lines.length >= 10;
      box.appendChild(addLine);
      box.appendChild(el("p", "dim", "Story characters never fight. They cannot be hurt unless you tick Can be killed."));
      if (state.canEdit && d.record) box.appendChild(field("Model note", noteButtons(d.record)));
    } else if (kind === "interact") {
      box.appendChild(field("What players do", textInput(d, "prompt", 40)));
      box.appendChild(field("Looks like", choice(d, "model", arr(state.interactModels).map(function (m) { return [m.model, m.name]; }))));
      [["count", "How many", 1, 8, 1], ["spread", "Placed in a ring of, m", 2, 40, 1], ["seconds", "Seconds to hold", 0.5, 120, 0.5],
        ["players", "Players needed at once", 1, 8, 1], ["uses", "Uses each (0 = no limit)", 0, 50, 1],
        ["cooldown", "Seconds between uses", 0, 600, 5]].forEach(function (f) {
        box.appendChild(field(f[1], numberInput(d, f[0], f[2], f[3], f[4])));
      });
      d.check = d.check || "";
      var tests = [["", "Holding the key is enough"]].concat(arr(state.hookChecks).map(function (c) { return [c.id, c.label]; }));
      if (d.check && !tests.some(function (t) { return t[0] === d.check; })) tests.push([d.check, "Missing: " + d.check]);
      box.appendChild(field("Server's own check", choice(d, "check", tests)));
      box.appendChild(field("Stays when finished", tickBox(d, "stays")));
      box.appendChild(el("p", "dim", "Players hold E next to it. With no use limit it never counts as finished. Objects need open77_props."));
      box.appendChild(el("h2", "", "What happens"));
      var effect = choice(d, "effect", [["none", "Nothing to see"], ["spark", "Sparks"], ["smoke", "Smoke"], ["blast", "Explosion"]]);
      effect.addEventListener("change", redraw);
      box.appendChild(field("Effect", effect));
      if (d.effect === "blast") {
        [["fuse", "Seconds until it blows", 0, 120, 1], ["blastRadius", "Blast radius, m", 3, 40, 1], ["blastDamage", "Blast damage", 0, 500, 10]].forEach(function (f) {
          box.appendChild(field(f[1], numberInput(d, f[0], f[2], f[3], f[4])));
        });
      }
      lootField(box, d, "For whoever used it.");
      d.squadId = d.squadId || "";
      box.appendChild(field("Alarm: squad", choice(d, "squadId", presetOptions("squad", "No alarm", d.squadId, "squad"))));
      box.appendChild(field("Seconds after the first use", numberInput(d, "spawnDelay", 0, 60, 1)));
      objectivesField(box, d);
      box.appendChild(el("h2", "", "Announcements to the whole server"));
      box.appendChild(field("When placed", textInput(d, "intro", 160)));
      box.appendChild(field("When the alarm squad comes", textInput(d, "arrival", 160)));
      box.appendChild(field("When all are finished", textInput(d, "done", 160)));
    } else if (kind === "objectives") {
      goalEditor(box, d, redraw);
      box.appendChild(el("h2", "", "Reward"));
      lootField(box, d, "Each player who took part rolls once when the set is completed.");
    } else if (kind === "loot") {
      lootEditor(box, d, redraw);
    } else {
      var falls = kind === "fall", drops = kind === "drop";
      var pickAv = choice(d, "record", arr(bodies(kind)).map(function (m) {
        var v = avVerdict(m);
        return [m.record, m.name + (v === "tested" ? "" : " (" + v + ")")];
      }));
      pickAv.addEventListener("change", redraw);
      box.appendChild(field(falls ? "What falls" : drops ? "Delivered by" : "AV", pickAv));
      if (state.canEdit) box.appendChild(field("Note for all staff", noteButtons(d.record)));
      if (falls && d.rim === undefined) d.rim = 1;
      (drops ? [["height", "Release height, m", 15, 90, 5], ["run", "AV flies in from, m", 60, 170, 10],
        ["flySeconds", "Flyby, s", 4, 20, 1], ["fallSeconds", "Crate comes down in, s", 3, 20, 1], ["hover", "Hovers at, m", 0, 3, 0.1]] :
        falls ? [["distance", "Comes in from, m", 0, 150, 5], ["height", "Start height, m", 40, 250, 10],
        ["flightSeconds", "Fall time, s", 2, 15, 0.5], ["spin", "Spin, degrees", -720, 720, 30]] :
        [["distance", "Start distance, m", 40, 200, 5], ["height", "Start height, m", 20, 150, 5],
        ["flightSeconds", "Flight time, s", 2, 15, 0.5]]).concat([["direction", "Approach angle, degrees", -180, 180, 15]].concat(drops ? [["openSeconds", "Seconds to open", 1, 60, 1],
        ["life", "Stays for, minutes", 1, 60, 1]] : [
        ["blastRadius", "Blast radius, m", 3, 40, 1], ["blastDamage", "Blast damage", 0, 500, 10],
        ["fireSeconds", "Fire, s", 0, 300, 10]]),
        falls ? [["crater", "Crater size, m", 0, 12, 1], ["rim", "Rim height, x", 0.3, 3, 0.1], ["sink", "Sunk into the ground, m", 0, 3, 0.1], ["debris", "Smaller pieces", 0, 12, 1], ["debrisRadius", "Pieces land within, m", 8, 60, 2]] : []).forEach(function (f) {
        box.appendChild(field(f[1], numberInput(d, f[0], f[2], f[3], f[4])));
      });
      if (drops) {
        box.appendChild(field("Loot goes to", choice(d, "share", [["near", "Everyone within 12 m"], ["opener", "Only the opener"]])));
        lootField(box, d, "Players open it by standing next to it. Ground loot drops one roll under the crate.");
      }
      if (falls) box.appendChild(field("Stays in one piece", tickBox(d, "intact")));
      box.appendChild(el("p", "dim", (falls ? "Untick to make it explode on impact. Crater 0 means none; craters need open77_props. Smaller pieces never hurt players. " : "") + "Angle 0 comes from your left. " + (drops ? "" : "Blast damage above 0 hurts players in the radius.")));

      box.appendChild(el("h2", "", "Who comes with it"));
      d.squadId = d.squadId || "";
      d.bossId = d.bossId || "";
      var bosses = presetOptions("boss", "No boss", d.bossId, "boss");
      if (state.chimera) {
        bosses = bosses.filter(function (o) { return o[0] !== "chimera"; });
        bosses.push(["chimera", "Militech Chimera"]);
      }
      box.appendChild(field("Squad", choice(d, "squadId", presetOptions("squad", "No squad", d.squadId, "squad"))));
      box.appendChild(field("Boss", choice(d, "bossId", bosses)));
      objectivesField(box, d, drops ? "Objectives begin when it lands." : "Objectives begin at impact.");
      if (d.spawnDelay === undefined) d.spawnDelay = 3;
      box.appendChild(field(drops ? "Seconds after landing" : "Seconds after impact", numberInput(d, "spawnDelay", 0, 60, 1)));
      box.appendChild(field("Message when they arrive", textInput(d, "arrival", 160)));
      box.appendChild(el("p", "dim", "Leave the message empty for the server's usual one. It is only sent when someone comes with the crash."));

      box.appendChild(el("h2", "", "Build-up"));
      box.appendChild(field("Warning before the flight", textInput(d, "warning", 160)));
      if (d.warningLead === undefined) d.warningLead = 6;
      box.appendChild(field("Seconds of warning", numberInput(d, "warningLead", 0, 60, 1)));
      var camera = el("input");
      camera.type = "checkbox"; camera.checked = d.cinematic === true;
      camera.addEventListener("change", function () { if (camera.checked) d.cinematic = true; else delete d.cinematic; });
      if (drops) box.appendChild(field("Message when opened", textInput(d, "opened", 160)));
      box.appendChild(field("Camera shot for players", camera));
    }

    var row = el("div", "row");
    var saved = d.id && JSON.stringify(strip(d)) === JSON.stringify(strip(original(kind, d.id)));
    if (kind === "loot") {
      row.appendChild(btn("Try it on me", "main", function () {
        var same = d.id && JSON.stringify(strip(d)) === JSON.stringify(strip(original(kind, d.id)));
        if (!same) return result("Save the table first, then try it", "bad");
        confirmThen("Give yourself one real roll of this table?", function () { call("lootTest", { id: d.id }); });
      }));
    } else row.appendChild(btn(kind === "objectives" ? "Start" : kind === "interact" || kind === "cast" ? "Place" : "Spawn", "main", function () {
      // Unchanged presets go by id, which needs no editor right.
      var unchanged = d.id && JSON.stringify(strip(d)) === JSON.stringify(strip(original(kind, d.id)));
      if (unchanged) return spawn(kind, d, { id: d.id });
      spawn(kind, d, { draft: strip(d) });
    }));
    if (state.canEdit) {
      row.appendChild(btn(d.builtin || !d.id ? "Save as new" : "Save changes", "", function () {
        call("save", { kind: kind, id: d.builtin ? undefined : d.id, def: strip(d) });
      }));
      if (d.id && !d.builtin) {
        row.appendChild(btn("Delete", "danger", function () {
          confirmThen("Delete the preset \"" + d.name + "\"? This cannot be undone.", function () {
            call("delete", { kind: kind, id: d.id });
            drafts[kind] = null;
            renderKind(kind);
          });
        }));
      }
    }
    box.appendChild(row);
    if (state.canEdit && kind === "boss" && d.record) {
      box.appendChild(el("h2", "", "Model note, shared with all staff"));
      box.appendChild(noteButtons(d.record));
    }
    return saved;
  }
  function strip(d) {
    var out = {};
    Object.keys(d || {}).sort().forEach(function (k) { if (k !== "id" && k !== "builtin" && (d[k] !== "" || k === "model") && !(k === "spawnDelay" && d[k] === 3) && !(k === "warningLead" && d[k] === 6)) out[k] = d[k]; });
    if (out.units) out.units = arr(out.units).map(function (u) { return { record: u.record, count: u.count }; });
    if (out.entries) out.entries = arr(out.entries).map(function (e) {
      var entry = {};
      Object.keys(e).sort().forEach(function (k) { if (e[k] !== "") entry[k] = e[k]; });
      return entry;
    });
    if (out.lines) out.lines = arr(out.lines).filter(function (l) { return l.trim(); });
    if (out.items) out.items = arr(out.items).map(function (g) {
      var item = {};
      Object.keys(g).sort().forEach(function (k) { if (g[k] !== "") item[k] = g[k]; });
      return item;
    });
    return out;
  }
  function original(kind, id) { return arr(state[kind]).filter(function (p) { return p.id === id; })[0]; }
  function renderKind(kind) { renderList(kind); renderEditor(kind); }

  function renderState() {
    renderAnnounce();
    var tab = document.querySelector('[data-tab="chimera"]');
    tab.style.display = state.chimera ? "" : "none";
    if (!state.chimera && tab.classList.contains("on")) document.querySelector('[data-tab="live"]').click();
    ["boss", "squad", "av", "fall", "drop", "interact", "cast", "objectives", "loot"].forEach(renderKind);
    renderLootSettings();
    [["chObjectives", "objectives", "No objectives", "objectives"], ["chLoot", "loot", "No loot", "loot table"]].forEach(function (c) {
      var select = $(c[0]), chosen = select.value;
      select.textContent = "";
      presetOptions(c[1], c[2], chosen, c[3]).forEach(function (o) {
        var n = el("option", "", o[1]);
        n.value = o[0];
        select.appendChild(n);
      });
      select.value = chosen;
    });
    var box = $("scenes");
    box.textContent = "";
    arr(state.scenes).forEach(function (s) {
      box.appendChild(btn(s, "", function () { call("command", { name: "gm.scene", arg: s }); }));
    });
  }

  /* ---------------------------------------------------------------- picker */
  var onPick = null;
  function pick(fn) {
    onPick = fn;
    $("picker").classList.add("on");
    $("search").focus();
    renderModels();
  }
  function closePicker() { $("picker").classList.remove("on"); onPick = null; }
  $("pickCancel").addEventListener("click", closePicker);
  [["", "All categories"]].concat(data.cats.map(function (c) { return [c, c.replace(/_/g, " ")]; })).forEach(function (o) {
    var n = el("option", "", o[1]); n.value = o[0]; $("category").appendChild(n);
  });
  var listed = {};
  [["", "All factions"]].concat(factions.map(function (f) { return [f.name, f.name]; })).forEach(function (o) {
    if (listed[o[1]]) return;
    listed[o[1]] = true;
    var n = el("option", "", o[1]); n.value = o[0]; $("faction").appendChild(n);
  });
  [["safe", "Tested, candidates and soldiers"], ["tested", "Tested only"], ["all", "Everything, including risky"]].forEach(function (o) {
    var n = el("option", "", o[1]); n.value = o[0]; $("risk").appendChild(n);
  });
  function renderModels() {
    var words = $("search").value.toLowerCase().split(/\s+/).filter(Boolean);
    var faction = $("faction").value, cat = $("category").value, risk = $("risk").value;
    var found = models.filter(function (m) {
      if (faction && (!m.faction || m.faction.name !== faction)) return false;
      if (cat && m.cat !== cat) return false;
      var v = verdict(m.record);
      if (risk === "safe" && v !== "tested" && v !== "candidate" && v !== "soldier") return false;
      if (risk === "tested" && v !== "tested") return false;
      return words.every(function (w) { return m.key.indexOf(w) >= 0; });
    });
    found.sort(function (a, b) { return a.main - b.main; });
    var box = $("models");
    box.textContent = "";
    $("found").textContent = found.length + " models" + (found.length > 150 ? ", showing the first 150. Search to narrow it down." : "");
    found.slice(0, 150).forEach(function (m) {
      var b = btn("", "model", function () { var fn = onPick; closePicker(); if (fn) fn(m.record); });
      b.appendChild(el("span", "", short(m.record)));
      b.appendChild(el("span", "dim", m.faction ? m.faction.name : m.cat.replace(/_/g, " ")));
      b.appendChild(tag(m.record));
      box.appendChild(b);
    });
  }
  $("search").addEventListener("input", renderModels);
  $("faction").addEventListener("change", renderModels);
  $("category").addEventListener("change", renderModels);
  $("risk").addEventListener("change", renderModels);

  /* -------------------------------------------------------------- open/close */
  function close() { bridge.emit("gm:close", {}); }
  $("close").addEventListener("click", close);
  document.addEventListener("keydown", function (e) {
    if (e.key !== "Escape") return;
    if ($("confirm").classList.contains("on")) return $("confirm").classList.remove("on");
    if ($("picker").classList.contains("on")) return closePicker();
    close();
  });

  function parse(p) { try { return JSON.parse(p.json); } catch (e) { return null; } }
  bridge.on("gm:show", function () { document.body.classList.add("open"); result("Ready", ""); });
  bridge.on("gm:hide", function () {
    document.body.classList.remove("open");
    $("confirm").classList.remove("on");
    dirty = false;
    lootDirty = false;
    closePicker();
  });
  bridge.on("gm:state", function (p) { var s = parse(p); if (s) { Object.keys(s).forEach(function (k) { if (k !== "part") state[k] = s[k]; }); state.status = state.status || {}; renderState(); } });
  bridge.on("gm:live", function (p) { var s = parse(p); if (s) { live = s; renderLive(); } });
  bridge.on("gm:result", function (p) { var r = parse(p); if (r) result(r.text, r.ok ? "ok" : "bad"); });

  renderState();
  renderLive();
  if (bridge.ready) bridge.ready();
  bridge.emit("gm:ready", {});
})();
