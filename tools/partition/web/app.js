let D,
  S,
  base,
  preview = null,
  selected = new Set(),
  picked = new Set(),
  fn = null,
  scope = null,
  history = [],
  future = [],
  level = 38,
  exact = false,
  kval = 4,
  serial = 0,
  view = "graph",
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
  render();
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
  const gs = visible(),
    m = Engine.metrics(D, gs),
    current = Engine.metrics(D, S.groups),
    scoped = gs.filter(inScope),
    members = new Set(scoped.flatMap((g) => g.members));
  $("undo").disabled = !history.length;
  $("redo").disabled = !future.length;
  $("heading").innerHTML =
    `<div class="eyebrow">${scope ? "PARTITION WORKSPACE" : "GLOBAL CALL GRAPH"}</div><h1>${esc(scope ? scope.name : "Every file is a starting group.")}</h1><p style="margin-bottom:0">${scope ? "Split, combine, or move functions. The rest of the project stays connected." : "Choose a group to explore its structure. Select several groups to combine them."}</p>`;
  let internal = 0,
    scopeCut = 0;
  const map = Engine.membership(gs, D.functions.length);
  for (const [a, b, w] of D.edges)
    if (members.has(a) && members.has(b)) {
      internal += w;
      if (map[a] !== map[b]) scopeCut += w;
    }
  $("metrics").innerHTML =
    metric("Groups in " + (scope ? "view" : "project"), scoped.length) +
    metric("Global crossing call sites", fmt(m.cut), m.cut - base.cut) +
    metric(
      "New private boundaries",
      m.exposed.filter((v) => !base.exposed.includes(v)).length,
    ) +
    (scope
      ? metric("Crossing within this view", fmt(scopeCut))
      : metric("Functions", fmt(D.functions.length)));
  $("toolbar").innerHTML =
    `${scope ? `<button id="back">\u2190 ${scopeStack.length ? "Parent group" : "Project"}</button>` : ""}<button id="split" ${selected.size !== 1 || preview ? "disabled" : ""}>Preview split</button><button id="merge" ${selected.size < 2 || preview ? "disabled" : ""}>Merge ${selected.size > 1 ? selected.size + " groups" : "groups"}</button>${preview ? '<span class="previewbadge">Tentative split</span>' : ""}${scope ? `<button id="toggle-view">${view === "graph" ? "Function list" : "Call graph"}</button>` : ""}<small>${scope ? "Click to select \u00b7 drag a selected function to move it" : "Lines show aggregated calls \u00b7 hover to trace connections"}</small>`;
  $("back")?.addEventListener("click", () => {
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
  $("toggle-view")?.addEventListener("click", () => {
    view = view === "graph" ? "list" : "graph";
    render();
  });
  renderNav();
  if (scope) {
    if (view === "graph") renderGraph(scoped, map);
    else renderBoard(scoped, map);
  } else renderMap(gs, m);
  if (!skipInspector) renderInspector(m, current);
  $("status").textContent = preview
    ? "Preview only \u00b7 accept to change the plan"
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
                `<div class="fnrow ${v === fn ? "selected" : ""}" draggable="${!preview}" data-drag="${v}"><input type="checkbox" aria-label="Select function ${esc(D.functions[v].n)}" data-pick="${v}" ${picked.has(v) ? "checked" : ""} ${preview ? "disabled" : ""}><span class="vis ${D.functions[v].s ? "" : "pub"}">${D.functions[v].k ? "TOP" : D.functions[v].s ? "PVT" : "API"}</span><button data-fn="${v}" title="${esc(D.functions[v].n)}">${esc(D.functions[v].n)}</button>${S.ties.some((t) => t.includes(v)) ? '<span title="Kept together">\u2301</span>' : ""}<span class="cross" title="Incoming plus outgoing crossing call sites">${crosses.get(v) || "\u00b7"}</span></div>`,
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
  const g = group([...selected][0]);
  if (!g || g.members.length < 2) {
    toast("This group has fewer than two functions.");
    return;
  }
  if (!scope) scope = { name: g.name, members: g.members.slice() };
  fn = null;
  picked.clear();
  preview = { target: g.id };
  updatePreview();
}
function updatePreview(skipInspector = false) {
  fn = null;
  const g = group(preview.target),
    count = exact ? kval : 2 + Math.round((level / 100) * 6),
    parts = Engine.partition(D, g.members, count, level / 100, S.ties);
  preview = {
    target: g.id,
    parts,
    groups: S.groups
      .filter((x) => x.id !== g.id)
      .concat(
        parts.map((members, i) => ({
          id: "preview-" + i,
          name: g.name.replace(/\.x$/, "") + "." + (i + 1) + ".x",
          members,
        })),
      ),
  };
  render(skipInspector);
}
function applyPreview() {
  const p = preview;
  change(`Accepted ${p.parts.length} groups`, () => {
    const g = group(p.target);
    S.groups = S.groups
      .filter((x) => x.id !== g.id)
      .concat(
        p.parts.map((members, i) => ({
          id: "part-" + Date.now() + "-" + ++serial,
          name: g.name.replace(/\.x$/, "") + "." + (i + 1) + ".x",
          members,
        })),
      );
  });
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
function renderInspector(m, current) {
  if (preview && fn === null) {
    const target = group(preview.target),
      sizes = preview.parts.map((p) => p.length),
      delta = m.cut - current.cut;
    $("inspector").innerHTML =
      `<div class="paneltag">SPLIT PREVIEW</div><h2>${esc(target.name)}</h2><p>Explore a tentative split. Accept it when the boundaries make sense.</p><div class="control"><label for="level">Partition detail <span style="float:right">${level}</span></label><input id="level" type="range" min="0" max="100" value="${level}"><div class="scale"><span>Fewer / uneven</span><span>More / balanced</span></div></div><div class="spread"><label><input id="exact" type="checkbox" ${exact ? "checked" : ""}> Fix group count</label><input id="k" class="number" aria-label="Exact group count" type="number" min="2" max="${Math.min(target.members.length, 30)}" value="${kval}" ${exact ? "" : "disabled"}></div><p class="note">${exact ? "Count stays fixed. The slider adjusts the preference for similar sizes." : "One exploration path changes both group count and the preference for similar sizes."}</p><h3>${sizes.length} proposed groups</h3><div class="sizes">${sizes.map((n, i) => `<i style="flex:${n};background:${colors[i % 8]}" title="${n} functions"></i>`).join("")}</div><div class="spread"><small>${sizes.join(" / ")} functions</small></div><div class="rule"></div><div class="costrow"><span>Global cut change</span><strong>${delta >= 0 ? "+" : ""}${fmt(delta)} call sites</strong></div><div class="costrow"><span>Private targets crossing</span><strong>${m.exposed.length}</strong></div><div class="costrow"><span>Keep-together sets</span><strong>${S.ties.filter((t) => t.some((v) => target.members.includes(v))).length} respected</strong></div><button id="accept" class="primary wide">Accept ${sizes.length} groups</button><button id="cancel" class="quiet wide">Discard preview</button><div class="hint note">A lower cut is evidence, not a design decision. Inspect API entry points before accepting.</div>`;
    $("level").oninput = (e) => {
      level = +e.target.value;
      updatePreview(true);
    };
    $("level").onchange = () => updatePreview();
    $("exact").onchange = (e) => {
      exact = e.target.checked;
      updatePreview();
    };
    $("k").oninput = (e) => {
      kval = Math.max(
        2,
        Math.min(30, target.members.length, Math.round(+e.target.value) || 2),
      );
      updatePreview();
      $("k").focus();
    };
    $("accept").onclick = applyPreview;
    $("cancel").onclick = () => {
      preview = null;
      render();
    };
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
    `<div class="paneltag">${chosen.length ? "GROUP INSPECTOR" : "START WITH STRUCTURE"}</div><h2>${chosen.length === 1 ? esc(chosen[0].name) : chosen.length ? chosen.length + " groups selected" : "Files become editable groups"}</h2><p>${chosen.length ? "Preview a split of one group, or select several groups to merge them." : "Open a file on the map. Explore its call graph as possible new files, then adjust the boundaries yourself."}</p>${chosen.length === 1 ? `<button id="inspect-split" class="primary wide">Preview split \u2192</button>` : ""}${chosen.length > 1 ? '<button id="inspect-merge" class="primary wide">Merge selected groups</button>' : ""}<h3>Current plan vs. original files</h3><div class="costrow"><span>Crossing call sites</span><strong>${fmt(m.cut)}</strong></div><div class="costrow"><span>Original crossing call sites</span><strong>${fmt(base.cut)}</strong></div><div class="costrow"><span>Directed crossing pairs</span><strong>${fmt(m.pairs)}</strong></div><div class="costrow"><span>New private boundaries</span><strong>${m.exposed.filter((v) => !base.exposed.includes(v)).length}</strong></div>${chosen.length === 1 ? groupConnections(chosen[0]) : `<h3>A reversible workflow</h3><p class="note">1. Open a group and preview a split.<br>2. Accept the groups you want.<br>3. Split again, merge, or drag functions.<br>4. Export the plan when ready.</p>`}<div class="hint note">${chosen.length === 1 ? "Check functions to keep an API and its helper together. That choice survives later splits." : "Group boundaries are tentative file boundaries. No source files are changed."}</div><h3>Graph coverage</h3><p class="note">${fmt(D.stats.externalCalls)} unresolved/external and ${fmt(D.stats.indirectCalls)} indirect calls are outside the resolved graph. Cut cost counts static call sites, not execution frequency.</p>`;
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
function renderFunction(m) {
  const f = D.functions[fn],
    owner = S.groups.find((g) => g.members.includes(fn)),
    set = tied(fn),
    links = D.edges
      .filter(([a, b]) => a === fn || b === fn)
      .sort((a, b) => b[2] - a[2]);
  $("inspector").innerHTML =
    `<div class="paneltag">FUNCTION INSPECTOR</div><h2 class="fnname">${esc(f.n)}</h2><p>${f.s ? "Private function" : f.k ? "File initializer" : "Public API"} \u00b7 ${esc(D.files[f.f].id)}</p><h3>Current group</h3><select id="destination" aria-label="Move function to group">${S.groups.map((g) => `<option value="${g.id}" ${g.id === owner.id ? "selected" : ""}>${esc(g.name)}</option>`).join("")}</select><button id="move" class="wide">Move ${set.length > 1 ? set.length + " linked functions" : "function"}</button>${set.length > 1 ? '<button id="release" class="quiet wide">Release keep-together set</button>' : ""}<button id="peek" class="quiet wide">Peek at source \u2197</button>${callRelationships(fn)}`;
  $("move").onclick = () => move(fn, $("destination").value);
  $("release")?.addEventListener("click", () =>
    change(
      "Released keep-together set",
      () => (S.ties = S.ties.filter((t) => !t.some((v) => set.includes(v)))),
    ),
  );
  $("peek").onclick = peek;
  wireFunctions();
}
async function peek() {
  const f = D.functions[fn];
  $("source-content").innerHTML =
    `<div class="paneltag">SOURCE PEEK \u00b7 FUTURE INTEGRATION</div><h2 class="fnname">${esc(f.n)}</h2><p>${esc(D.files[f.f].id)} \u00b7 graph snapshot ${D.revision}</p><div class="hint">The graph export supplies function identity, but no exact source range. This drawer reserves the source-reading workflow.</div><p>The production adapter should provide the matching revision, declaration, and body range. Selecting a call here will navigate to that function while preserving the partition.</p><h3>Available identity</h3><pre>${esc(JSON.stringify({ file: D.files[f.f].id, source_name: f.n, emitted_name: f.e, source_order: f.o }, null, 2))}</pre>`;
  $("source").showModal();
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
    revision: D.revision,
    generated: D.generated,
    groups: S.groups.map((g) => ({
      name: g.name,
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
    const initial = makeInitial();
    base = Engine.metrics(D, initial.groups);
    try {
      S =
        JSON.parse(localStorage.getItem("partition-" + D.revision)) || initial;
    } catch {
      S = initial;
    }
    render();
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
