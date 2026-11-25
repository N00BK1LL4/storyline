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

  var state = { boss: [], squad: [], av: [], objectives: [], scenes: [], avModels: [], status: {}, maxSquad: 20, canEdit: false };
  var live = { bosses: [], players: [], hostiles: 0, ghost: false, mark: false };
  var drafts = { boss: null, squad: null, av: null, objectives: null };
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
    var records = kind === "squad" ? def.units.map(function (u) { return u.record; }) : kind === "boss" ? [def.record] : [];
    if (kind === "av") {
      var squad = original("squad", def.squadId), boss = original("boss", def.bossId);
      if (squad) records = records.concat(arr(squad.units).map(function (u) { return u.record; }));
      if (boss) records.push(boss.record);
    }
    var bad = records.filter(function (r) { var v = verdict(r); return v === "risky" || v === "broken"; });
    body.kind = kind;
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
      scaling: $("chScale").checked, objectivesId: $("chObjectives").value };
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

  $("announceSend").addEventListener("click", sendAnnounce);
  $("announce").addEventListener("keydown", function (e) { if (e.key === "Enter") sendAnnounce(); });

  /* ------------------------------------------------------------------ live */
  function renderTarget() {
    var select = $("target"), keep = select.value || "front";
    var options = [["front", "In front of me"]];
    if (live.mark) options.push(["mark", "My mark"]);
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
    ["reach", "Reach a place"], ["hold", "Hold an area"], ["survive", "Survive"], ["custom", "Custom, ticked by staff"]];
  function newGoal(type, text) {
    var g = { type: type };
    if (text) g.text = text;
    if (type === "kill") g.count = 5;
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
    objectives: function () { return { name: "", radius: 60, items: [newGoal("enemies")], ordered: true, timeLimit: 0 }; }
  };
  function summary(kind, d) {
    if (kind === "squad") {
      var units = arr(d.units), total = units.reduce(function (n, u) { return n + (+u.count || 0); }, 0);
      return total + " units, " + d.pattern;
    }
    if (kind === "av") {
      var with_ = [];
      if (d.squadId) with_.push((original("squad", d.squadId) || { name: "missing squad" }).name);
      if (d.bossId) with_.push(d.bossId === "chimera" ? "Chimera" : (original("boss", d.bossId) || { name: "missing boss" }).name);
      return short(d.record) + (with_.length ? ", with " + with_.join(" and ") : "");
    }
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
    if (note) box.appendChild(el("p", "dim", note));
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
      var pickType = choice(g, "type", goalTypes);
      pickType.addEventListener("change", function () { d.items[i] = newGoal(g.type, g.text); redraw(); });
      row.appendChild(pickType);
      var up = btn("Up", "", function () { d.items.splice(i - 1, 0, d.items.splice(i, 1)[0]); redraw(); });
      up.disabled = i === 0;
      row.appendChild(up);
      var remove = btn("Remove", "", function () { d.items.splice(i, 1); redraw(); });
      remove.disabled = d.items.length === 1;
      row.appendChild(remove);
      card.appendChild(row);
      card.appendChild(field("Text players see", textInput(g, "text", 80)));
      if (g.type === "kill") card.appendChild(field("How many", numberInput(g, "count", 1, 100, 1)));
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
    } else if (kind === "objectives") {
      goalEditor(box, d, redraw);
    } else {
      box.appendChild(field("AV", choice(d, "record", arr(state.avModels).map(function (m) {
        return [m.record, m.name + (m.tested ? "" : " (untested)")];
      }))));
      [["distance", "Start distance, m", 40, 200, 5], ["height", "Start height, m", 20, 150, 5],
        ["flightSeconds", "Flight time, s", 2, 15, 0.5], ["direction", "Approach angle, degrees", -180, 180, 15],
        ["blastRadius", "Blast radius, m", 3, 40, 1], ["blastDamage", "Blast damage", 0, 500, 10],
        ["fireSeconds", "Fire, s", 0, 300, 10]].forEach(function (f) {
        box.appendChild(field(f[1], numberInput(d, f[0], f[2], f[3], f[4])));
      });
      box.appendChild(el("p", "dim", "Angle 0 comes from your left. Blast damage above 0 hurts players in the radius."));

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
      objectivesField(box, d, "Objectives begin at impact.");
      if (d.spawnDelay === undefined) d.spawnDelay = 3;
      box.appendChild(field("Seconds after impact", numberInput(d, "spawnDelay", 0, 60, 1)));
      box.appendChild(field("Message when they arrive", textInput(d, "arrival", 160)));
      box.appendChild(el("p", "dim", "Leave the message empty for the server's usual one. It is only sent when someone comes with the crash."));

      box.appendChild(el("h2", "", "Build-up"));
      box.appendChild(field("Warning before the flight", textInput(d, "warning", 160)));
      var camera = el("input");
      camera.type = "checkbox"; camera.checked = d.cinematic === true;
      camera.addEventListener("change", function () { if (camera.checked) d.cinematic = true; else delete d.cinematic; });
      box.appendChild(field("Camera shot for players", camera));
    }

    var row = el("div", "row");
    var saved = d.id && JSON.stringify(strip(d)) === JSON.stringify(strip(original(kind, d.id)));
    row.appendChild(btn(kind === "objectives" ? "Start" : "Spawn", "main", function () {
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
    Object.keys(d || {}).sort().forEach(function (k) { if (k !== "id" && k !== "builtin" && d[k] !== "" && !(k === "spawnDelay" && d[k] === 3)) out[k] = d[k]; });
    if (out.units) out.units = arr(out.units).map(function (u) { return { record: u.record, count: u.count }; });
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
    ["boss", "squad", "av", "objectives"].forEach(renderKind);
    var select = $("chObjectives"), chosen = select.value;
    select.textContent = "";
    presetOptions("objectives", "No objectives", chosen, "objectives").forEach(function (o) {
      var n = el("option", "", o[1]);
      n.value = o[0];
      select.appendChild(n);
    });
    select.value = chosen;
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
