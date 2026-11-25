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

  var state = { boss: [], squad: [], av: [], scenes: [], avModels: [], status: {}, maxSquad: 20, canEdit: false };
  var live = { bosses: [], players: [], hostiles: 0, ghost: false, mark: false };
  var drafts = { boss: null, squad: null, av: null };
  var req = 0;

  /* ---------------------------------------------------------------- models */
  var data = window.GM_MODELS || { cats: [], risks: [], rows: "" };
  var models = [], riskOf = {};
  data.rows.split("\n").forEach(function (line) {
    var p = line.split("|");
    if (p.length !== 3) return;
    var m = { record: "Character." + p[0], cat: data.cats[+p[1]], risk: data.risks[+p[2]], key: p[0].toLowerCase() };
    models.push(m);
    riskOf[m.record] = m.risk;
  });

  function verdict(record) {
    var s = state.status && state.status[record];
    if (s === "tested" || s === "broken") return s;
    return riskOf[record] === "candidate" ? "candidate" : "risky";
  }
  function tag(record) {
    var v = verdict(record);
    var names = { tested: "Tested", broken: "Broken", candidate: "Candidate", risky: "Risky" };
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
    if (!bad.length) return go();
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
      scaling: $("chScale").checked };
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
  }

  /* --------------------------------------------------------------- editors */
  var blank = {
    boss: function () { return { name: "", record: "", health: 5, height: 2.4, scaling: true }; },
    squad: function () { return { name: "", units: [], pattern: "ring", radius: 6 }; },
    av: function () {
      var first = arr(state.avModels)[0];
      return { name: "", record: first ? first.record : "", distance: 110, height: 70, flightSeconds: 5, direction: 0,
        blastRadius: 12, blastDamage: 0, fireSeconds: 90 };
    }
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
        row.appendChild(btn("Remove", "", function () { d.units.splice(i, 1); redraw(); }));
        box.appendChild(row);
      });
      var add = btn("Add unit type", "", function () {
        pick(function (record) { d.units.push({ record: record, count: 1 }); redraw(); });
      });
      add.disabled = d.units.length >= 8;
      box.appendChild(add);
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
      var options = function (kind2, none) {
        return [["", none]].concat(arr(state[kind2]).map(function (p) { return [p.id, p.name]; }));
      };
      var keep = function (list, id, what) { // a deleted preset stays visible instead of silently changing
        if (id && !list.some(function (o) { return o[0] === id; })) list.push([id, "Missing " + what]);
        return list;
      };
      d.squadId = d.squadId || "";
      d.bossId = d.bossId || "";
      var bosses = options("boss", "No boss");
      if (state.chimera) bosses.push(["chimera", "Militech Chimera"]);
      box.appendChild(field("Squad", choice(d, "squadId", keep(options("squad", "No squad"), d.squadId, "squad"))));
      box.appendChild(field("Boss", choice(d, "bossId", keep(bosses, d.bossId, "boss"))));
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
    row.appendChild(btn("Spawn", "main", function () {
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
    return out;
  }
  function original(kind, id) { return arr(state[kind]).filter(function (p) { return p.id === id; })[0]; }
  function renderKind(kind) { renderList(kind); renderEditor(kind); }

  function renderState() {
    renderAnnounce();
    var tab = document.querySelector('[data-tab="chimera"]');
    tab.style.display = state.chimera ? "" : "none";
    if (!state.chimera && tab.classList.contains("on")) document.querySelector('[data-tab="live"]').click();
    ["boss", "squad", "av"].forEach(renderKind);
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
  [["safe", "Tested and candidates"], ["tested", "Tested only"], ["all", "Everything, including risky"]].forEach(function (o) {
    var n = el("option", "", o[1]); n.value = o[0]; $("risk").appendChild(n);
  });
  function renderModels() {
    var words = $("search").value.toLowerCase().split(/\s+/).filter(Boolean);
    var cat = $("category").value, risk = $("risk").value;
    var found = models.filter(function (m) {
      if (cat && m.cat !== cat) return false;
      var v = verdict(m.record);
      if (risk === "safe" && v !== "tested" && v !== "candidate") return false;
      if (risk === "tested" && v !== "tested") return false;
      return words.every(function (w) { return m.key.indexOf(w) >= 0; });
    });
    var box = $("models");
    box.textContent = "";
    $("found").textContent = found.length + " models" + (found.length > 150 ? ", showing the first 150. Search to narrow it down." : "");
    found.slice(0, 150).forEach(function (m) {
      var b = btn("", "model", function () { var fn = onPick; closePicker(); if (fn) fn(m.record); });
      b.appendChild(el("span", "", short(m.record)));
      b.appendChild(el("span", "dim", m.cat.replace(/_/g, " ")));
      b.appendChild(tag(m.record));
      box.appendChild(b);
    });
  }
  $("search").addEventListener("input", renderModels);
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
