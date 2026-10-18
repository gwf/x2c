let D,
  anchorMetrics,
  S,
  base,
  preview = null,
  selected = new Set(),
  picked = new Set(),
  fn = null,
  scope = null,
  history = [],
  future = [],
  serial = 0,
  view = "groups",
  previewGroup = null,
  scopeStack = [];
const $ = (id) => document.getElementById(id),
  esc = (s) =>
    String(s).replace(
      /[&<>"']/g,
      (c) =>
        ({
          "&": "&amp;",
          "<": "&lt;",
          ">": "&gt;",
          '"': "&quot;",
          "'": "&#39;",
        })[c],
    ),
  fmt = (n) => n.toLocaleString();
const colors = [
  "#b5dba0",
  "#9abfce",
  "#d2b693",
  "#b6abd0",
  "#91c6b9",
  "#d09eaa",
  "#bfc794",
  "#97b4db",
];
const clone = (x) => JSON.parse(JSON.stringify(x));
const group = (id) => S.groups.find((g) => g.id === id);
const visible = () => (preview ? preview.groups : S.groups);
const inScope = (g) =>
  !scope || g.members.some((v) => scope.members.includes(v));
function toast(s) {
  $("toast").textContent = s;
  $("toast").classList.add("show");
  clearTimeout(window.toastTimer);
  window.toastTimer = setTimeout(
    () => $("toast").classList.remove("show"),
    3000,
  );
}
function save() {
  try {
    localStorage.setItem("partition-" + D.revision, JSON.stringify(S));
  } catch {
    toast("Browser storage unavailable. Export your plan to retain it.");
  }
}
function change(label, action) {
  history.push(clone(S));
  future = [];
  action();
  S.groups = S.groups.filter(
    (g) =>
      g.members.length ||
      (g.id.startsWith("file-") && D.files[+g.id.slice(5)].functions === 0),
  );
  preview = null;
  selected.clear();
  picked.clear();
  fn = null;
  save();
  render();
  toast(label);
}
function makeInitial() {
  return {
    groups: D.files.map((f, i) => ({
      id: "file-" + i,
      name: f.id,
      members: D.functions
        .map((v, j) => (v.f === i ? j : -1))
        .filter((j) => j >= 0),
    })),
    ties: [],
  };
}
function enter(id) {
  const g = group(id);
  if (!g) return;
  preview = null;
  previewGroup = null;
  view = "responsibilities";
  if (
    scope &&
    !(
      scope.members.length === g.members.length &&
      g.members.every((v) => scope.members.includes(v))
    )
  )
    scopeStack.push(clone(scope));
  scope = { name: g.name, members: g.members.slice() };
  selected = new Set([id]);
  picked.clear();
  fn = null;
  openResponsibilityResult();
  $("workspace").scrollTop = 0;
}
function project() {
  scopeStack = [];
  scope = null;
  preview = null;
  selected.clear();
  picked.clear();
  fn = null;
  render();
}
function metric(label, value, delta) {
  return `<div class="metric"><b>${value}</b>${delta ? `<em>${delta > 0 ? "+" : ""}${fmt(delta)}</em>` : ""}<label>${label}</label></div>`;
}
function render(skipInspector = false) {
  if (!preview) previewGroup = null;
  const gs = visible(),
    m = Engine.metrics(D, gs),
    current = Engine.metrics(D, S.groups),
    scoped = gs.filter(inScope),
    members = new Set(scoped.flatMap((g) => g.members));
  $("undo").disabled = !history.length;
  $("redo").disabled = !future.length;
  $("heading").innerHTML =
    `<div class="eyebrow">${scope ? "PARTITION WORKSPACE" : "GLOBAL CALL GRAPH"}</div><h1>${esc(scope ? scope.name : "Every file is a starting group.")}</h1><p style="margin-bottom:0">${scope ? (view === "responsibilities" ? "Analyze source, inspect the proposed responsibilities, and adjust their boundaries." : "Split, combine, or move functions. The rest of the project stays connected.") : "Choose a group to explore its structure. Select several groups to combine them."}</p>`;
  let internal = 0,
    scopeCut = 0;
  const map = Engine.membership(gs, D.functions.length);
  for (const [a, b, w] of D.edges)
    if (members.has(a) && members.has(b)) {
      internal += w;
      if (map[a] !== map[b]) scopeCut += w;
    }
  $("metrics").hidden = !!scope && view === "responsibilities";
  $("metrics").innerHTML =
    metric("Groups in " + (scope ? "view" : "project"), scoped.length) +
    metric("Global crossing call sites", fmt(m.cut), m.cut - base.cut) +
    metric(
      preview?.moduleArrangement ? "Private helpers shared across members" : "New private boundaries",
      m.exposed.filter((v) => !base.exposed.includes(v)).length,
    ) +
    metric(
      "File statics needing module",
      m.toModule.filter((v) => !base.toModule.includes(v)).length,
    ) +
    (scope
      ? metric("Crossing within this view", fmt(scopeCut))
      : metric("Functions", fmt(D.functions.length)));
  $("toolbar").innerHTML =
    `${scope ? `<button id="back">\u2190 ${previewGroup ? "Group arrangement" : scopeStack.length ? "Parent group" : "Project"}</button>` : ""}<button id="split" ${scope ? "hidden" : ""} ${selected.size !== 1 || preview ? "disabled" : ""}>Build responsibilities</button><button id="merge" ${view === "responsibilities" && scope ? "hidden" : ""} ${selected.size < 2 || preview ? "disabled" : ""}>Merge ${selected.size > 1 ? selected.size + " groups" : "groups"}</button>${preview ? '<span class="previewbadge">Tentative split</span>' : ""}${scope ? `<button id="view-responsibilities" ${preview ? "disabled" : ""}>Responsibilities</button><button id="view-groups">Group arrangement</button><button id="view-graph">Functions</button><button id="view-files">Member files</button><button id="view-list">Function list</button>` : ""}<small>${scope ? "Open groups or switch to Functions to move members" : "Lines show aggregated calls \u00b7 hover to trace connections"}</small>`;
  $("back")?.addEventListener("click", () => {
    if (previewGroup) {
      previewGroup = null;
      render();
      return;
    }
    view = "groups";
    if (scopeStack.length) {
      scope = scopeStack.pop();
      preview = null;
      selected.clear();
      picked.clear();
      fn = null;
      render();
    } else project();
  });
  $("split").onclick = startPreview;
  $("merge").onclick = merge;
  for (const mode of ["responsibilities", "groups", "graph", "files", "list"])
    $("view-" + mode)?.addEventListener("click", () => {
      view = mode;
      previewGroup = null;
      render();
    });
  renderNav();
  if (scope) {
    const shown = previewGroup
      ? scoped.filter((g) => g.id === previewGroup)
      : scoped;
    if (view === "responsibilities") renderResponsibilities();
    else if (view === "groups" && shown.length > 1) renderMap(shown);
    else if (view === "files") renderMemberFiles(shown);
    else if (view === "list") renderBoard(shown, map);
    else renderGraph(shown, map);
  } else renderMap(gs);
  if (!skipInspector) renderInspector(m, current);
  $("status").textContent = preview
    ? (preview.moduleArrangement ? "Module-member proposal: private symbols stay in one translation unit" : "Preview only \u00b7 accept to change the plan")
    : `${S.groups.length} groups \u00b7 ${S.ties.length} keep-together sets \u00b7 saved in this browser`;
  $("snapshot").textContent =
    `Snapshot ${D.revision} \u00b7 static calls, not runtime traffic`;
}
function renderNav() {
  const q = $("search").value.toLowerCase();
  $("group-count").textContent = S.groups.length;
  $("groups").innerHTML = S.groups
    .filter(
      (g) =>
        !q ||
        g.name.toLowerCase().includes(q) ||
        g.members.some((v) => D.functions[v].n.toLowerCase().includes(q)),
    )
    .map(
      (g) =>
        `<div class="navrow ${selected.has(g.id) ? "active" : ""}"><input type="checkbox" aria-label="Select ${esc(g.name)}" data-select="${g.id}" ${selected.has(g.id) ? "checked" : ""} ${preview ? "disabled" : ""}><button data-open="${g.id}" title="${esc(g.name)}">${esc(g.name)}</button><small>${g.members.length}</small></div>`,
    )
    .join("");
  document.querySelectorAll("[data-select]").forEach(
    (e) =>
      (e.onchange = () => {
        e.checked
          ? selected.add(e.dataset.select)
          : selected.delete(e.dataset.select);
        fn = null;
        render();
      }),
  );
  document
    .querySelectorAll("[data-open]")
    .forEach((e) => (e.onclick = () => enter(e.dataset.open)));
}
function renderBoard(gs, map) {
  const crosses = new Map();
  for (const [a, b, w] of D.edges)
    if (map[a] !== map[b]) {
      crosses.set(a, (crosses.get(a) || 0) + w);
      crosses.set(b, (crosses.get(b) || 0) + w);
    }
  const pairs = [];
  gs.forEach((a, i) =>
    gs.forEach((b, j) => {
      if (i >= j) return;
      const ai = new Set(a.members),
        bi = new Set(b.members);
      let count = 0;
      for (const [u, v, w] of D.edges)
        if ((ai.has(u) && bi.has(v)) || (bi.has(u) && ai.has(v))) count += w;
      if (count) pairs.push([i, j, count]);
    }),
  );
  let mini = "";
  if (gs.length > 1) {
    const width = Math.max(600, gs.length * 150);
    mini =
      `<svg class="minimap" viewBox="0 0 ${width} 105" aria-label="Calls between groups">` +
      pairs
        .map(
          ([a, b, w]) =>
            `<path d="M${75 + a * 150} 70 Q${75 + (a + b) * 75} ${Math.max(0, 60 - (b - a) * 18)} ${75 + b * 150} 70" fill="none" stroke="#a8c6b5" opacity=".6" stroke-width="${Math.min(5, 1 + Math.sqrt(w) / 3)}"/><text x="${75 + (a + b) * 75}" y="${Math.max(12, 58 - (b - a) * 9)}" text-anchor="middle" fill="#d5c198" font-size="10">${w}</text>`,
        )
        .join("") +
      gs
        .map(
          (g, i) =>
            `<circle cx="${75 + i * 150}" cy="70" r="6" fill="${colors[i % 8]}"/><text x="${75 + i * 150}" y="96" text-anchor="middle" fill="#9cabae" font-size="10">Group ${i + 1} \u00b7 ${g.members.length}</text>`,
        )
        .join("") +
      "</svg>";
  }
  $("workspace").innerHTML =
    mini +
    `<div class="board">` +
    gs
      .map(
        (g, i) =>
          `<section class="groupcard ${preview ? "preview" : ""}" style="--accent:${colors[i % 8]}" data-drop="${g.id}"><div class="grouphead"><div class="spread"><label><input type="checkbox" data-board-select="${g.id}" aria-label="Select group ${esc(g.name)}" ${selected.has(g.id) ? "checked" : ""} ${preview ? "disabled" : ""}> Group ${i + 1}</label><button data-focus="${g.id}" ${preview ? "disabled" : ""}>Explore \u2197</button></div><input class="rename" aria-label="Rename ${esc(g.name)}" value="${esc(g.name)}" data-rename="${g.id}" ${preview ? "disabled" : ""}><div class="groupstats"><span>${g.members.length} functions</span><span>${g.members.filter((v) => D.functions[v].s).length} private</span></div></div>${g.members
            .slice()
            .sort((a, b) => D.functions[a].o - D.functions[b].o)
            .map(
              (v) =>
                `<div class="fnrow ${v === fn ? "selected" : ""}" draggable="${!preview}" data-drag="${v}"><input type="checkbox" aria-label="Select function ${esc(D.functions[v].n)}" data-pick="${v}" ${picked.has(v) ? "checked" : ""} ${preview ? "disabled" : ""}><span class="vis ${D.functions[v].s ? "" : "pub"}">${D.functions[v].k ? "TOP" : { static: "STA", module: "MOD", public: "API" }[D.functions[v].v]}</span><button data-fn="${v}" title="${esc(D.functions[v].n)}">${esc(D.functions[v].n)}</button>${S.ties.some((t) => t.includes(v)) ? '<span title="Kept together">\u2301</span>' : ""}<span class="cross" title="Incoming plus outgoing crossing call sites">${crosses.get(v) || "\u00b7"}</span></div>`,
            )
            .join("")}</section>`,
      )
      .join("") +
    "</div>";
  document.querySelectorAll("[data-board-select]").forEach(
    (e) =>
      (e.onchange = () => {
        e.checked
          ? selected.add(e.dataset.boardSelect)
          : selected.delete(e.dataset.boardSelect);
        fn = null;
        render();
      }),
  );
  document
    .querySelectorAll("[data-focus]")
    .forEach((e) => (e.onclick = () => enter(e.dataset.focus)));
  document.querySelectorAll("[data-rename]").forEach(
    (e) =>
      (e.onchange = () => {
        const name = e.value.trim();
        if (name)
          change("Group renamed", () => (group(e.dataset.rename).name = name));
      }),
  );
  document.querySelectorAll("[data-fn]").forEach(
    (e) =>
      (e.onclick = () => {
        fn = +e.dataset.fn;
        renderInspector(
          Engine.metrics(D, visible()),
          Engine.metrics(D, S.groups),
        );
        document
          .querySelectorAll("[data-drag]")
          .forEach((r) =>
            r.classList.toggle("selected", +r.dataset.drag === fn),
          );
      }),
  );
  document.querySelectorAll("[data-pick]").forEach(
    (e) =>
      (e.onchange = () => {
        e.checked
          ? picked.add(+e.dataset.pick)
          : picked.delete(+e.dataset.pick);
        fn = null;
        renderInspector(
          Engine.metrics(D, visible()),
          Engine.metrics(D, S.groups),
        );
      }),
  );
  document.querySelectorAll("[data-drag]").forEach((e) => {
    let start = null;
    e.draggable = false;
    e.onpointerdown = (ev) => {
      if (preview || ev.target.type === "checkbox") return;
      start = { x: ev.clientX, y: ev.clientY };
      e.setPointerCapture(ev.pointerId);
    };
    e.onpointermove = (ev) => {
      if (!start || Math.hypot(ev.clientX - start.x, ev.clientY - start.y) < 8)
        return;
      e.style.opacity = ".5";
      const target = document
        .elementsFromPoint(ev.clientX, ev.clientY)
        .map((n) => n.closest("[data-drop]"))
        .find(Boolean);
      document
        .querySelectorAll("[data-drop]")
        .forEach((n) => n.classList.toggle("dragover", n === target));
      if (target) dragCost(+e.dataset.drag, target.dataset.drop);
    };
    e.onpointerup = (ev) => {
      if (!start) return;
      const moved = Math.hypot(ev.clientX - start.x, ev.clientY - start.y) > 8;
      start = null;
      e.style.opacity = "";
      if (moved) {
        const target = document
          .elementsFromPoint(ev.clientX, ev.clientY)
          .map((n) => n.closest("[data-drop]"))
          .find(Boolean);
        if (target) move(+e.dataset.drag, target.dataset.drop);
      }
      document
        .querySelectorAll("[data-drop]")
        .forEach((n) => n.classList.remove("dragover"));
    };
  });
  document.querySelectorAll("[data-drop]").forEach((e) => {
    e.ondragover = (ev) => {
      if (preview) return;
      ev.preventDefault();
      e.classList.add("dragover");
    };
    e.ondragleave = () => e.classList.remove("dragover");
    e.ondrop = (ev) => {
      ev.preventDefault();
      e.classList.remove("dragover");
      const raw = ev.dataTransfer.getData("text/plain");
      if (!/^\d+$/.test(raw)) return;
      move(+raw, e.dataset.drop);
    };
  });
}
function startPreview() {
  if (!scope) {
    const g = group([...selected][0]);
    if (!g) return;
    scope = { name: g.name, members: g.members.slice() };
  }
  preview = null;
  fn = null;
  view = "responsibilities";
  render();
}
function merge() {
  const gs = S.groups.filter((g) => selected.has(g.id));
  if (gs.length < 2) return;
  const name = gs[0].name.replace(/\.x$/, "") + "-merged.x";
  change(`Merged ${gs.length} groups`, () => {
    const members = gs.flatMap((g) => g.members);
    S.groups = S.groups.filter((g) => !selected.has(g.id));
    S.groups.push({ id: "merged-" + Date.now(), name, members });
    if (scope) scope.members = [...new Set([...scope.members, ...members])];
  });
}
function tied(v) {
  let result = new Set([v]),
    again = true;
  while (again) {
    again = false;
    for (const t of S.ties)
      if (t.some((i) => result.has(i)))
        for (const i of t)
          if (!result.has(i)) {
            result.add(i);
            again = true;
          }
  }
  return [...result];
}
function move(v, id) {
  if (preview || !group(id) || !D.functions[v]) return;
  const members = tied(v);
  if (members.every((i) => group(id).members.includes(i))) return;
  const effect = Engine.moveEvaluator(D, S.groups).impact(members, id);
  change(
    `Moved ${members.length} function${members.length === 1 ? "" : "s"}`,
    () => {
      S.groups.forEach(
        (g) => (g.members = g.members.filter((i) => !members.includes(i))),
      );
      group(id).members.push(...members);
      if (scope)
        scope.members = [...new Set([...scope.members, ...group(id).members])];
    },
  );
  renderMoveFeedback(members, effect);
}
function keep() {
  const values = [...picked];
  const map = Engine.membership(S.groups, D.functions.length);
  if (new Set(values.map((v) => map[v])).size > 1) {
    toast("Move these functions into one group before keeping them together.");
    return;
  }
  change("Functions will stay together in future splits", () =>
    S.ties.push(values),
  );
}
function peel() {
  const values = [...new Set([...picked].flatMap(tied))];
  change("Created a group from selected functions", () => {
    S.groups.forEach(
      (g) => (g.members = g.members.filter((v) => !values.includes(v))),
    );
    S.groups.push({
      id: "peeled-" + Date.now(),
      name: "new-group.x",
      members: values,
    });
  });
}
function moveImpactMarkup(effect) {
  const names = (values) => values.map((v) => esc(D.functions[v].n)).join(", ");
  return `<h3>Cut change</h3><p><strong>${effect.delta > 0 ? "+" : ""}${fmt(effect.delta)} crossing call sites${effect.delta === 0 ? " (unchanged)" : ""}</strong><br>Global cut: ${fmt(effect.beforeCut)} \u2192 ${fmt(effect.afterCut)}<br>${effect.removedCalls} removed; ${effect.addedCalls} introduced</p><h3>Private visibility opportunities</h3><p>${effect.localized.length} gained; ${effect.delocalized.length} lost</p>${effect.localized.length ? `<p>New candidates: ${names(effect.localized)}</p>` : ""}${effect.delocalized.length ? `<p>Now have outside callers: ${names(effect.delocalized)}</p>` : ""}<p class="note">Candidates have no known callers outside their group. Check callbacks, exported uses, and unresolved references before making them private. Source visibility is unchanged.</p><p>Existing private targets crossing: +${effect.added.length} / -${effect.removed.length}</p><p class="note">Of the new crossings, ${effect.added.filter((v) => D.functions[v].v === "static").length} file statics would need module storage if the groups stay member files of one module unit. All ${effect.added.length} would need public storage in separate units.</p>`;
}
function renderMoveFeedback(members, effect) {
  $("inspector").innerHTML =
    `<div class="paneltag">MOVE RESULT</div><h2>Moved ${members.length} function${members.length === 1 ? "" : "s"}</h2>${moveImpactMarkup(effect)}<h3>Remaining outside callers</h3>${effect.remaining.map(({ v, callers }) => `<p><strong>${esc(D.functions[v].n)}</strong>: ${callers.length}${callers.length ? `<br>${callers.map((a) => esc(D.functions[a].n) + " (" + esc(S.groups.find((g) => g.members.includes(a)).name) + ")").join("<br>")}` : ""}</p>`).join("")}<p class="note">Undo restores the previous plan.</p>`;
}
function renderInspector(m, current) {
  if (preview?.responsibility && fn === null) {
    renderResponsibilityPreview();
    return;
  }
  if (scope && view === "responsibilities") {
    $("inspector").innerHTML =
      '<div class="paneltag">RESPONSIBILITY WORKSPACE</div><h2>Decide by purpose</h2><p>Select Analyze source. The agent reads bodies and callers, proposes responsibilities, and checks private dependencies. Inspect or adjust the result.</p><p>Graph views remain available for tracing callers and helpers.</p><p>Export the manifest to preserve descriptions, constraints, and merge reasons in version control.</p>';
    return;
  }
  if (fn !== null) {
    renderFunction(m);
    if (preview) {
      $("move").disabled = true;
      const back = document.createElement("button");
      back.className = "wide";
      back.textContent = "\u2190 Split preview";
      back.onclick = () => {
        fn = null;
        renderInspector(m, current);
      };
      $("inspector").prepend(back);
    }
    return;
  }
  if (picked.size) {
    $("inspector").innerHTML =
      `<div class="paneltag">SELECTED FUNCTIONS</div><h2>${picked.size} functions</h2><p>Keep an API with its implementation, or extract these functions into a new group.</p><button id="keep" class="primary wide" ${picked.size < 2 ? "disabled" : ""}>Keep together</button><button id="peel" class="wide">Make a separate group</button><h3>Selection</h3>${[...picked].map((v) => `<div class="connection">${esc(D.functions[v].n)}</div>`).join("")}<button id="clear-pick" class="quiet wide">Clear selection</button>`;
    $("keep").onclick = keep;
    $("peel").onclick = peel;
    $("clear-pick").onclick = () => {
      picked.clear();
      render();
    };
    return;
  }
  const chosen = S.groups.filter((g) => selected.has(g.id));
  $("inspector").innerHTML =
    `<div class="paneltag">${chosen.length ? "GROUP INSPECTOR" : "START WITH STRUCTURE"}</div><h2>${chosen.length === 1 ? esc(chosen[0].name) : chosen.length ? chosen.length + " groups selected" : "Files become editable groups"}</h2><p>${chosen.length ? "Analyze one group, or select several groups to merge them." : "Open a file and select Analyze source to get a proposed decomposition."}</p>${chosen.length === 1 ? `<button id="inspect-split" class="primary wide">Build responsibilities \u2192</button>` : ""}${chosen.length > 1 ? '<button id="inspect-merge" class="primary wide">Merge selected groups</button>' : ""}<h3>Current plan vs. original files</h3><div class="costrow"><span>Crossing call sites</span><strong>${fmt(m.cut)}</strong></div><div class="costrow"><span>Original crossing call sites</span><strong>${fmt(base.cut)}</strong></div><div class="costrow"><span>Directed crossing pairs</span><strong>${fmt(m.pairs)}</strong></div><div class="costrow"><span>New private boundaries</span><strong>${m.exposed.filter((v) => !base.exposed.includes(v)).length}</strong></div>${chosen.length === 1 ? groupConnections(chosen[0]) : `<h3>A reversible workflow</h3><p class="note">1. Ask the agent to analyze a file.<br>2. Inspect its proposed responsibilities.<br>3. Adjust names, membership, and boundaries.<br>4. Export the proposal and evidence.</p>`}<div class="hint note">${chosen.length === 1 ? "Check functions to keep an API and its helper together. That choice survives later splits." : "Group boundaries are tentative file boundaries. No source files are changed."}</div><h3>Graph coverage</h3><p class="note">${fmt(D.stats.externalCalls)} unresolved/external and ${fmt(D.stats.indirectCalls)} indirect calls are outside the resolved graph. Cut cost counts static call sites, not execution frequency.</p>`;
  $("inspect-split")?.addEventListener("click", startPreview);
  $("inspect-merge")?.addEventListener("click", merge);
  wireFunctions();
}
function groupConnections(g) {
  const members = new Set(g.members),
    links = new Map(),
    map = Engine.membership(S.groups, D.functions.length);
  for (const [a, b, w] of D.edges) {
    if (members.has(a) === members.has(b)) continue;
    const other = members.has(a) ? map[b] : map[a],
      key = other + ":" + (members.has(a) ? "out" : "in");
    links.set(key, (links.get(key) || 0) + w);
  }
  return (
    "<h3>Calls across this boundary</h3>" +
    [...links]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 8)
      .map(([key, w]) => {
        const [i, dir] = key.split(":");
        return `<div class="connection"><span>${dir === "out" ? "\u2192" : "\u2190"}</span><button data-neighbor="${S.groups[i].id}">${esc(S.groups[i].name)}</button><b>${w}</b></div>`;
      })
      .join("")
  );
}
function wireFunctions() {
  document
    .querySelectorAll("[data-neighbor]")
    .forEach((e) => (e.onclick = () => enter(e.dataset.neighbor)));
  document.querySelectorAll("[data-related]").forEach(
    (e) =>
      (e.onclick = () => {
        fn = +e.dataset.related;
        renderInspector(
          Engine.metrics(D, visible()),
          Engine.metrics(D, S.groups),
        );
        if ($("graph-svg")) window.refreshGraphSelection?.(fn);
      }),
  );
}
function anchorDetails(v) {
  const a = anchorMetrics[v],
    shared = new Set(a.shared);
  return `<h3>File anchoring <strong>${a.score.toFixed(1)} / 100</strong></h3>
    <div class="costrow"><span>External callers (E)</span><strong>${a.callers.length}</strong></div>
    <div class="costrow"><span>Static dependencies (D)</span><strong>${a.dependencies.size}</strong></div>
    <div class="costrow"><span>Shared static dependencies</span><strong>${a.shared.length}</strong></div>
    <p class="note">ln(1 + E) x ln(1 + D), scaled to the snapshot maximum. Original files, not tentative groups. Directed static-only paths; cycles count once. Resolved calls only. This estimates attachment, not a requirement to stay public.</p>
    ${
      a.dependencies.size
        ? `<button id="show-dependencies" class="wide">Show all dependency groups</button><details><summary>All ${a.dependencies.size} static dependencies</summary>${[
            ...a.dependencies,
          ]
            .sort((x, y) => D.functions[x].n.localeCompare(D.functions[y].n))
            .map(
              (id) =>
                `<div class="connection"><button data-related="${id}">${esc(D.functions[id].n)}</button><small>${shared.has(id) ? "shared" : ""}</small></div>`,
            )
            .join(
              "",
            )}</details><p class="note">Shared helpers have callers outside this function and its dependency set. Highlighted paths follow static dependencies; immediate neighbors remain visible.</p>`
        : ""
    }`;
}
function renderFunction(m) {
  const f = D.functions[fn],
    owner = S.groups.find((g) => g.members.includes(fn)),
    set = tied(fn),
    links = D.edges
      .filter(([a, b]) => a === fn || b === fn)
      .sort((a, b) => b[2] - a[2]);
  $("inspector").innerHTML =
    `<div class="paneltag">FUNCTION INSPECTOR</div><h2 class="fnname">${esc(f.n)}</h2><p>${functionVisibility(fn)} \u00b7 ${esc(f.p)}${f.p === D.files[f.f].id ? "" : " in " + esc(D.files[f.f].id)}</p><p class="note">${f.k ? "" : f.r ? `Its resolved callers need ${f.r} storage${widerThanNeeded(f) ? `, narrower than ${f.v}` : ""}.` : "No resolved callers."}</p>${anchorDetails(fn)}<h3>Current group</h3><select id="destination" aria-label="Move function to group">${S.groups.map((g) => `<option value="${g.id}" ${g.id === owner.id ? "selected" : ""}>${esc(g.name)}</option>`).join("")}</select><button id="move" class="wide">Move ${set.length > 1 ? set.length + " linked functions" : "function"}</button>${set.length > 1 ? '<button id="release" class="quiet wide">Release keep-together set</button>' : ""}<button id="peek" class="quiet wide">Peek at source \u2197</button>${callRelationships(fn)}`;
  $("move").onclick = () => move(fn, $("destination").value);
  $("release")?.addEventListener("click", () =>
    change(
      "Released keep-together set",
      () => (S.ties = S.ties.filter((t) => !t.some((v) => set.includes(v)))),
    ),
  );
  $("peek").onclick = peek;
  $("show-dependencies")?.addEventListener("click", () => {
    if (scope) scopeStack.push(clone(scope));
    scope = {
      name: D.functions[fn].n + " dependency groups",
      members: [fn, ...anchorMetrics[fn].dependencies],
    };
    previewGroup = null;
    view = "graph";
    render();
  });
  wireFunctions();
}
function peek() {
  showSource(fn);
}
$("close-source").onclick = () => $("source").close();
$("home").onclick = (e) => {
  e.preventDefault();
  project();
};
$("project").onclick = project;
$("search").oninput = renderNav;
$("undo").onclick = () => {
  future.push(clone(S));
  S = history.pop();
  preview = null;
  fn = null;
  picked.clear();
  selected.clear();
  save();
  render();
  toast("Undone");
};
$("redo").onclick = () => {
  history.push(clone(S));
  S = future.pop();
  preview = null;
  fn = null;
  picked.clear();
  selected.clear();
  save();
  render();
  toast("Redone");
};
$("export").onclick = () => {
  const out = {
    format: "partition-concept-v1",
    responsibilities: S.responsibilities || {},
    revision: D.revision,
    generated: D.generated,
    groups: S.groups.map((g) => ({
      name: g.name,
      classification: g.classification,
      moduleMembers: g.moduleMembers,
      functions: g.members.map((v) => ({
        file: D.files[D.functions[v].f].id,
        name: D.functions[v].n,
        emitted: D.functions[v].e,
      })),
    })),
    keepTogether: S.ties.map((t) =>
      t.map((v) => ({
        file: D.files[D.functions[v].f].id,
        emitted: D.functions[v].e,
      })),
    ),
    crossingCallSites: Engine.metrics(D, S.groups).cut,
  };
  const a = document.createElement("a");
  a.href = URL.createObjectURL(
    new Blob([JSON.stringify(out, null, 2)], { type: "application/json" }),
  );
  a.download = "x2c-partition-plan.json";
  a.click();
  URL.revokeObjectURL(a.href);
  toast("Plan exported");
};
fetch("graph.json", { cache: "no-store" })
  .then((r) => r.json())
  .then((data) => {
    D = data;
    anchorMetrics = Engine.anchors(D);
    const initial = makeInitial();
    base = Engine.metrics(D, initial.groups);
    try {
      S =
        JSON.parse(localStorage.getItem("partition-" + D.revision)) || initial;
    } catch {
      S = initial;
    }
    render();
    watchAnalysisJobs();
  })
  .catch((e) => {
    $("workspace").textContent =
      "Could not load the graph snapshot: " + e.message;
  });
function dragCost(v, id) {
  const target = group(id);
  if (!target) return;
  const members = tied(v),
    hyp = S.groups.map((g) => ({
      ...g,
      members: g.members.filter((i) => !members.includes(i)),
    }));
  hyp.find((g) => g.id === id).members.push(...members);
  const before = Engine.metrics(D, S.groups).cut,
    after = Engine.metrics(D, hyp).cut;
  $("status").textContent =
    `Move to ${target.name}: ${after - before >= 0 ? "+" : ""}${after - before} crossing call sites`;
}

$("reset").onclick = () =>
  change("Restored original file groups; undo is available", () => {
    S = makeInitial();
    scope = null;
    scopeStack = [];
  });
function callRelationships(v) {
  const gs = visible(),
    ids = new Set(gs.filter(inScope).flatMap((g) => g.members)),
    owner = new Map();
  gs.forEach((g) => g.members.forEach((i) => owner.set(i, g.name)));
  let html = `<h3>Directed call relationships</h3><p class="note">All resolved callers and callees. Counts are static call sites. ${ids.has(v) ? "" : "This function is outside the current view."}</p>`;
  for (const incoming of [true, false]) {
    const edges = D.edges
        .filter(([a, b]) => (incoming ? b === v : a === v))
        .sort((a, b) => b[2] - a[2]),
      total = edges.reduce((s, e) => s + e[2], 0),
      outside = edges
        .filter((e) => !ids.has(e[incoming ? 0 : 1]))
        .reduce((s, e) => s + e[2], 0);
    html += `<details class="call-section" open><summary>${incoming ? "Incoming callers" : "Outgoing callees"} \u00b7 ${total} call sites <small>${outside} outside view</small></summary><div class="call-rows">${
      edges
        .map(([a, b, w]) => {
          const other = incoming ? a : b;
          return `<div class="call-row ${ids.has(other) ? "" : "outside-call"}"><div><button data-related="${other}">${esc(D.functions[other].n)}</button><strong>${w}</strong></div><small>${ids.has(other) ? "In view" : "Outside view"} \u00b7 ${esc(owner.get(other))}</small></div>`;
        })
        .join("") ||
      `<p class="note">No resolved ${incoming ? "incoming" : "outgoing"} calls in this snapshot.</p>`
    }</div></details>`;
  }
  const f = D.functions[v];
  if (f.x || f.i)
    html += `<p class="note">Also ${f.x} unresolved/external and ${f.i} indirect call sites; their targets are not available in this graph.</p>`;
  return html;
}
