let graphWorker = null,
  graphResize = null,
  graphCache = new Map(),
  graphCamera = null,
  graphScope = "",
  graphGeneration = 0,
  graphLastKey = "";
function functionColor(id) {
  const f = D.functions[id];
  return f.k ? "#a5adb7" : TIER_COLOR[f.v];
}
function functionVisibility(id) {
  const f = D.functions[id];
  return f.k
    ? "File initializer"
    : { static: "File static", module: "Module function", public: "Public function" }[f.v];
}
function renderGraph(gs, map) {
  graphWorker?.terminate();
  graphResize?.disconnect();
  const generation = ++graphGeneration;
  const host = $("workspace");
  host.classList.add("graph-workspace");
  host.innerHTML = `<div class="graph-tools"><button id="zoom-out" aria-label="Zoom out">\u2212</button><button id="fit-graph">Fit graph</button><button id="zoom-in" aria-label="Zoom in">+</button><span id="zoom-value"></span><button id="focus-function" disabled>Focus function</button><button id="relayout">Arrange again</button><button id="boundary-summary" title="Inspect all calls across the view boundary"></button><span id="layout-state">Arranging connected functions\u2026</span></div><svg id="graph-svg" aria-label="Interactive function call graph"></svg><div class="graph-legend"><span><span style="color:#edbc7a">\u25cf File static</span> &nbsp; <span style="color:#c7a2e8">\u25cf Module</span> &nbsp; <span style="color:#86c7ff">\u25cf Public</span> &nbsp; <span style="color:#a5adb7">\u25cf Initializer</span> \u00b7 Green paths: static dependencies \u00b7 Size: public = outside consumers; static = inside consumers</span><span id="label-count"></span></div><div id="graph-tooltip"></div>`;
  const svg = $("graph-svg"),
    bounds = () => ({
      width: svg.clientWidth || 800,
      height: svg.clientHeight || 500,
    }),
    size = bounds();
  const ids = new Set(gs.flatMap((g) => g.members)),
    edges = D.edges.filter(([a, b]) => ids.has(a) && ids.has(b)),
    scopeKey = [...ids].sort((a, b) => a - b).join(",");
  const boundary = BoundaryGraph.collect(D, ids, visible());
  const incomingGroups = new Map(
    gs.map((g) => {
      const members = new Set(g.members),
        edges = D.edges.filter(([a, b]) => members.has(b) && !members.has(a));
      return [
        "group-in:" + g.id,
        {
          ...g,
          edges,
          callers: new Set(edges.map((e) => e[0])).size,
          calls: edges.reduce((sum, e) => sum + e[2], 0),
        },
      ];
    }),
  );
  $("boundary-summary").textContent =
    `Outside callers: ${boundary.incoming} call sites`;
  const owner = new Map(gs.flatMap((g) => g.members.map((v) => [v, g.id]))),
    consumers = new Map(
      [...ids].map((v) => [
        v,
        { internal: new Set(), external: new Set(), calls: 0 },
      ]),
    );
  for (const [a, b, w] of D.edges) {
    if (!ids.has(b)) continue;
    const t = consumers.get(b);
    if (owner.get(a) === owner.get(b)) t.internal.add(a);
    else {
      t.external.add(a);
      t.calls += w;
    }
  }
  const nodeRadius = (v) =>
    4 +
    Math.sqrt(
      (D.functions[v].s ? consumers.get(v).internal : consumers.get(v).external)
        .size,
    ) *
      2;
  const key =
    gs.map((g) => g.id + ":" + g.name + ":" + g.members.join(",")).join("|") +
    "@" +
    Math.round((size.width / size.height) * 10);
  if (scopeKey !== graphScope || key !== graphLastKey) {
    graphCamera = null;
    graphScope = scopeKey;
    graphLastKey = key;
  }
  window.refreshGraphSelection = (v) => {
    active = v;
    if (scene) {
      paintLabels();
      $("focus-function").disabled = v === null;
    }
  };
  const input = {
    groups: gs.map((g) => ({
      id: g.id,
      name: g.name,
      nodes: g.members.map((id) => ({ id, name: D.functions[id].n })),
    })),
    edges,
    aspect: size.width / size.height,
  };
  let layout = null,
    byId = null,
    hovered = null,
    gesture = null,
    active = fn,
    scene = null,
    activePort = null;
  function gutters() {
    return { left: boundary.incoming ? 245 : 20, right: 20 };
  }
  function fit() {
    if (!layout) return;
    const s = bounds(),
      g = gutters(),
      k = Math.min(
        (s.width - g.left - g.right - 40) / layout.width,
        (s.height - 108) / layout.height,
      );
    graphCamera = {
      k,
      x: g.left + 20 + (s.width - g.left - g.right - 40 - layout.width * k) / 2,
      y: 84 + (s.height - 108 - layout.height * k) / 2,
    };
    paintCamera();
  }
  function zoom(factor, x = bounds().width / 2, y = bounds().height / 2) {
    if (!graphCamera) return;
    const old = graphCamera.k,
      k = Math.max(0.08, Math.min(4, old * factor));
    graphCamera.x = x - ((x - graphCamera.x) * k) / old;
    graphCamera.y = y - ((y - graphCamera.y) * k) / old;
    graphCamera.k = k;
    paintCamera();
  }
  function focus(v) {
    if (!byId?.has(v)) return;
    const p = byId.get(v),
      s = bounds(),
      k = Math.max(0.9, graphCamera.k);
    graphCamera = { k, x: s.width / 2 - p.x * k, y: s.height / 2 - p.y * k };
    paintCamera();
  }
  function inspector() {
    activePort = null;
    fn = active;
    renderInspector(Engine.metrics(D, visible()), Engine.metrics(D, S.groups));
    $("focus-function").disabled = !ids.has(active);
  }
  function receive(result) {
    if (generation !== graphGeneration || !svg.isConnected) return;
    layout = result;
    byId = new Map(layout.nodes.map((n) => [n.id, n]));
    draw();
    if (!graphCamera) fit();
    else paintCamera();
    $("layout-state").textContent =
      `${layout.nodes.length} functions \u00b7 layout ready`;
    svg.dataset.crossings = layout.after.crossings;
    svg.dataset.labelOverlaps = layout.after.overlaps;
    svg.dataset.beforeCrossings = layout.before.crossings;
  }
  function draw() {
    svg.innerHTML =
      `<defs><marker id="arrow2" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="5" markerHeight="5" orient="auto"><path d="M0 0 L8 4 L0 8" fill="#a8bab3"/></marker></defs><g id="boundary-links"></g><g id="graph-scene">` +
      layout.regions
        .map(
          (r, i) =>
            `<g class="region" data-region="${r.id}"><rect class="region-box" x="${r.x}" y="${r.y}" width="${r.w}" height="${r.h}" rx="14" fill="${colors[i % 8]}" fill-opacity=".045" stroke="${colors[i % 8]}" stroke-opacity=".5" vector-effect="non-scaling-stroke" ${preview ? 'stroke-dasharray="7 5"' : ""}/><g class="region-title" data-rindex="${i}"><text fill="${colors[i % 8]}" y="0">${esc(r.name)}</text><text class="region-subtitle" fill="#97a7ab" y="21">${r.count} functions${r.prefix ? " \u00b7 names omit " + esc(r.prefix) : ""}</text>${!preview ? `<g data-region-select="${r.id}" tabindex="0" role="button" aria-label="Select graph group ${esc(r.name)}"><rect x="0" y="31" width="62" height="25" rx="4" fill="${selected.has(r.id) ? "#415739" : "#263137"}"/><text x="9" y="48" fill="#d9e5df">${selected.has(r.id) ? "Selected" : "Select"}</text></g><g data-region-enter="${r.id}" tabindex="0" role="button" aria-label="Explore graph group ${esc(r.name)}"><rect x="70" y="31" width="64" height="25" rx="4" fill="#263137"/><text x="79" y="48" fill="#d9e5df">Explore</text></g>` : ""}</g></g>`,
        )
        .join("") +
      edges
        .filter(([a, b]) => a !== b)
        .map(([a, b, w]) => {
          const p = byId.get(a),
            q = byId.get(b);
          return `<path class="graph-edge" data-edge-a="${a}" data-edge-b="${b}" d="${route(p, q)}" stroke="${p.group === q.group ? "#809997" : "#d9b879"}" stroke-width="${Math.min(2.5, 0.65 + Math.sqrt(w) * 0.23)}" fill="none" vector-effect="non-scaling-stroke" marker-end="url(#arrow2)"/>`;
        })
        .join("") +
      layout.nodes
        .map(
          (p) =>
            `<g class="graph-node" data-node="${p.id}" transform="translate(${p.x} ${p.y})" role="button" tabindex="0" aria-label="Inspect ${esc(p.name)}"><title>${functionVisibility(p.id)}: ${esc(p.name)}; ${D.functions[p.id].s ? consumers.get(p.id).internal.size + " internal" : consumers.get(p.id).external.size + " external"} consumers</title><circle class="node-dot" r="4" fill="${functionColor(p.id)}"/><g class="node-name"><rect x="-5" y="-12" rx="4" width="${p.label.length * 7.2 + 19}" height="25" fill="#172126" fill-opacity=".96"/><text x="7" y="4" fill="${functionColor(p.id)}">${esc(p.label)}</text></g></g>`,
        )
        .join("") +
      '</g><g id="boundary-ports"></g>';
    scene = $("graph-scene");
    svg.querySelectorAll("[data-region-select]").forEach((e) => {
      e.onclick = () => {
        selected.has(e.dataset.regionSelect)
          ? selected.delete(e.dataset.regionSelect)
          : selected.add(e.dataset.regionSelect);
        fn = null;
        render();
      };
      e.onkeydown = (ev) => {
        if (ev.key === "Enter") e.onclick();
      };
    });
    svg.querySelectorAll("[data-region-enter]").forEach((e) => {
      e.onclick = () => enter(e.dataset.regionEnter);
      e.onkeydown = (ev) => {
        if (ev.key === "Enter") e.onclick();
      };
    });
    svg.querySelectorAll("[data-node]").forEach((e) => {
      const v = +e.dataset.node;
      e.onpointerenter = () => {
        hovered = v;
        paintLabels();
        const t = $("graph-tooltip");
        const traffic = boundary.functions.get(v) || { in: 0, out: 0 };
        t.textContent = `${byId.get(v).name} \u00b7 ${functionVisibility(v)} \u00b7 ${D.functions[v].s ? consumers.get(v).internal.size + " internal" : consumers.get(v).external.size + " external"} consumers \u00b7 outside view: ${traffic.in} incoming / ${traffic.out} outgoing call sites`;
        t.style.display = "block";
      };
      e.onpointerleave = () => {
        hovered = null;
        if (!gesture) {
          $("graph-tooltip").style.display = "none";
          paintLabels();
        }
      };
      e.onfocus = () => {
        hovered = v;
        paintLabels();
      };
      e.onblur = () => {
        hovered = null;
        paintLabels();
      };
      e.onkeydown = (ev) => {
        if (ev.key === "Enter") {
          active = v;
          inspector();
          paintLabels();
        }
        if (ev.key === " ") {
          ev.preventDefault();
          focus(v);
        }
      };
      e.ondblclick = (ev) => {
        ev.stopPropagation();
        active = v;
        focus(v);
        inspector();
      };
    });
  }
  function route(a, b) {
    const dx = b.x - a.x,
      dy = b.y - a.y,
      d = Math.hypot(dx, dy) || 1,
      offset = edges.some((e) => e[0] === b.id && e[1] === a.id) ? 12 : 0;
    return `M${a.x + (dx / d) * 7} ${a.y + (dy / d) * 7} Q${(a.x + b.x) / 2 - (dy / d) * offset} ${(a.y + b.y) / 2 + (dx / d) * offset} ${b.x - (dx / d) * 9} ${b.y - (dy / d) * 9}`;
  }
  function paintCamera() {
    if (!scene || !graphCamera) return;
    const c = graphCamera;
    scene.setAttribute("transform", `translate(${c.x} ${c.y}) scale(${c.k})`);
    svg.setAttribute("viewBox", `0 0 ${bounds().width} ${bounds().height}`);
    svg.querySelectorAll(".region-title").forEach((e) => {
      const r = layout.regions[+e.dataset.rindex];
      e.setAttribute(
        "transform",
        `translate(${r.x + 18 / c.k} ${r.y + 25 / c.k}) scale(${1 / c.k})`,
      );
    });
    $("zoom-value").textContent = Math.round(c.k * 100) + "%";
    paintLabels();
  }
  function paintLabels() {
    if (!scene) return;
    const c = graphCamera,
      s = bounds(),
      focusId = hovered ?? active,
      dependencies =
        focusId === null ? new Set() : anchorMetrics[focusId].dependencies,
      near = new Set(dependencies);
    if (focusId !== null)
      for (const [a, b] of D.edges) {
        if (a === focusId) near.add(b);
        if (b === focusId) near.add(a);
      }
    if (incomingGroups.has(activePort))
      for (const [a, b] of incomingGroups.get(activePort).edges) {
        near.add(a);
        near.add(b);
      }
    if (activePort)
      for (const l of boundary.links)
        if (l.port === activePort || activePort === l.direction + ":*")
          near.add(l.inside);
    const rail = gutters();
    const order = layout.nodes
        .slice()
        .sort(
          (a, b) =>
            (b.id === focusId ? 1e6 : near.has(b.id) ? 1e5 : 0) -
              (a.id === focusId ? 1e6 : near.has(a.id) ? 1e5 : 0) ||
            a.id - b.id,
        ),
      occupied = layout.regions.map((r) => ({
        x: r.x * c.k + c.x,
        y: r.y * c.k + c.y,
        w: r.w * c.k,
        h: preview ? 49 : 80,
      })),
      shown = new Map();
    for (const p of order) {
      const x = p.x * c.k + c.x,
        y = p.y * c.k + c.y,
        w = p.label.length * 7.2 + 26,
        r = layout.regions[p.group];
      if (x < 0 || x > s.width || y < 0 || y > s.height) continue;
      const candidates = [
        { x: x + nodeRadius(p.id) + 6, y: y - 12, w, h: 25 },
        { x: x - w - nodeRadius(p.id) - 6, y: y - 12, w, h: 25 },
        { x: x - w / 2, y: y + 10, w, h: 25 },
        { x: x - w / 2, y: y - 37, w, h: 25 },
      ];
      let chosen = candidates.find(
        (box) =>
          box.x >= rail.left &&
          box.x + box.w <= s.width - rail.right &&
          box.y >= 76 &&
          box.y + 25 <= s.height - 4 &&
          !occupied.some(
            (b) =>
              box.x < b.x + b.w &&
              box.x + box.w > b.x &&
              box.y < b.y + b.h &&
              box.y + box.h > b.y,
          ),
      );
      if (!chosen && p.id === focusId)
        chosen = {
          x: Math.max(4, Math.min(s.width - w - 4, x + 10)),
          y: Math.max(4, Math.min(s.height - 29, y - 12)),
          w,
          h: 25,
        };
      if (chosen) {
        shown.set(p.id, { x: chosen.x - x + 5, y: chosen.y - y + 12 });
        occupied.push(chosen);
      }
    }
    svg.querySelectorAll(".graph-node").forEach((e) => {
      const v = +e.dataset.node,
        p = byId.get(v),
        name = e.querySelector(".node-name"),
        selectedNode = v === active;
      e.style.cursor = selectedNode && !preview ? "grab" : "pointer";
      e.classList.toggle("selected-node", selectedNode);
      e.style.opacity =
        (focusId === null && !activePort) || v === focusId || near.has(v)
          ? 1
          : 0.32;
      e.querySelector("circle").setAttribute(
        "r",
        (nodeRadius(v) + (selectedNode ? 2 : 0)) / c.k,
      );
      const offset = shown.get(v) || { x: 9, y: 0 };
      name.setAttribute(
        "transform",
        `translate(${offset.x / c.k} ${offset.y / c.k}) scale(${1 / c.k})`,
      );
      name.style.display = shown.has(v) ? "" : "none";
      name
        .querySelector("rect")
        .setAttribute("stroke", selectedNode ? "#e8f1db" : "none");
    });
    svg.querySelectorAll(".graph-edge").forEach((e) => {
      const dependencyEdge =
        (+e.dataset.edgeA === focusId || dependencies.has(+e.dataset.edgeA)) &&
        dependencies.has(+e.dataset.edgeB);
      const related =
        dependencyEdge ||
        +e.dataset.edgeA === focusId ||
        +e.dataset.edgeB === focusId ||
        incomingGroups
          .get(activePort)
          ?.edges.some(
            ([a, b]) => a === +e.dataset.edgeA && b === +e.dataset.edgeB,
          );
      e.classList.toggle("dependency-edge", dependencyEdge);
      e.style.stroke = dependencyEdge ? "#b5dba0" : "";
      e.style.opacity =
        focusId === null && !activePort ? 0.48 : related ? 0.95 : 0.045;
    });
    paintBoundary(focusId);
    $("label-count").textContent =
      `${shown.size}/${layout.nodes.length} names visible \u00b7 zoom in for more`;
  }

  function paintBoundary(focusId) {
    if (!layout) return;
    const c = graphCamera;
    const regions = layout.regions;
    let rail = $("caller-rail");
    if (!rail) {
      rail = document.createElement("div");
      rail.id = "caller-rail";
      host.appendChild(rail);
    }
    const callerGroups = boundary.ports
      .filter((p) => p.direction === "in")
      .sort(
        (a, b) => b.consumers - a.consumers || a.name.localeCompare(b.name),
      );
    const scroll = rail.scrollTop;
    rail.innerHTML =
      "<strong>CALLER GROUPS OUTSIDE VIEW</strong><p>Caller functions / call sites.<br>Click a group to inspect targets.</p>" +
      callerGroups
        .map(
          (p) =>
            `<button data-caller-group="${esc(p.key)}" title="${esc(p.name)}: ${p.consumers} caller functions, ${p.calls} call sites"><span>${esc(p.name)}</span><b>${p.consumers} / ${p.calls}</b></button>`,
        )
        .join("");
    rail.hidden = !callerGroups.length;
    rail.scrollTop = scroll;
    rail.querySelectorAll("[data-caller-group]").forEach(
      (e) =>
        (e.onclick = () => {
          activePort = e.dataset.callerGroup;
          active = null;
          hovered = null;
          boundaryInspector(activePort, null);
          paintLabels();
        }),
    );
    let portMarkup = "";
    for (const r of regions) {
      const key = "group-in:" + r.id,
        p = incomingGroups.get(key),
        x = r.x * c.k + c.x + 12,
        y = (r.y + r.h) * c.k + c.y + 14;
      portMarkup += `<g data-boundary-port="${esc(key)}" role="button" tabindex="0" aria-label="${p.callers} callers into ${esc(p.name)}"><title>${p.callers} distinct functions outside this group, ${p.calls} incoming call sites. Click to inspect.</title><rect x="${x}" y="${y - 12}" width="160" height="24" rx="4" fill="#1d2b30" stroke="#537c76"/><text x="${x + 8}" y="${y + 4}" class="boundary-port-name" fill="#8dd4c8">${p.callers} callers \u00b7 ${p.calls} calls</text></g>`;
    }
    const rect = svg.getBoundingClientRect(),
      railRect = rail.getBoundingClientRect();
    $("boundary-links").innerHTML = callerGroups
      .flatMap((callerGroup) => {
        const el = rail.querySelector(
            `[data-caller-group="${callerGroup.key}"]`,
          ),
          box = el.getBoundingClientRect();
        if (box.top < railRect.top || box.bottom > railRect.bottom) return [];
        const A = {
          x: railRect.right - rect.left + 4,
          y: (box.top + box.bottom) / 2 - rect.top,
        };
        return regions.flatMap((r) => {
          const members = new Set(gs.find((g) => g.id === r.id).members);
          const edges = callerGroup.edges.filter(([, b]) => members.has(b));
          if (!edges.length) return [];
          const count = new Set(edges.map(([a]) => a)).size,
            calls = edges.reduce((n, e) => n + e[2], 0);
          const x = r.x * c.k + c.x,
            y = (r.y + r.h / 2) * c.k + c.y;
          const related =
            (!activePort ||
              activePort === callerGroup.key ||
              activePort === "in:*" ||
              activePort === "group-in:" + r.id) &&
            (focusId === null || edges.some(([, b]) => b === focusId));
          return [
            `<g opacity="${related ? (preview && !activePort ? 0.12 : 0.85) : 0.08}"><title>${esc(callerGroup.name)} to ${esc(r.name || gs.find((g) => g.id === r.id).name)}: ${count} caller functions, ${calls} call sites</title><path class="boundary-edge" d="M${A.x} ${A.y} C${A.x + 40} ${A.y} ${x - 40} ${y} ${x - 3} ${y}" stroke="#86c7ff" stroke-width="${1 + Math.sqrt(count)}" fill="none" marker-end="url(#arrow2)"/><text x="${(A.x + x) / 2}" y="${(A.y + y) / 2 - 5}" fill="#dcecff" font-size="12" paint-order="stroke" stroke="#11181c" stroke-width="3">${count}</text></g>`,
          ];
        });
      })
      .join("");
    rail.onscroll = () => paintBoundary(hovered ?? active);
    $("boundary-ports").innerHTML = portMarkup;
    svg.querySelectorAll("[data-boundary-port]").forEach((e) => {
      const open = () => {
        activePort = e.dataset.boundaryPort;
        hovered = null;
        boundaryInspector(activePort, active);
        paintLabels();
      };
      e.onpointerdown = (ev) => {
        ev.preventDefault();
        ev.stopPropagation();
        open();
      };
      e.onkeydown = (ev) => {
        if (ev.key === "Enter") {
          ev.preventDefault();
          open();
        }
      };
    });
  }
  function boundaryInspector(key = null, selectedFunction = null) {
    if (incomingGroups.has(key)) {
      const group = incomingGroups.get(key),
        owner = new Map(
          visible().flatMap((g) => g.members.map((v) => [v, g.name])),
        );
      $("inspector").innerHTML =
        `<div class="paneltag">GROUP CALLERS</div><h2>${esc(group.name)}</h2><p>${group.callers} distinct functions outside this group call into it, through ${group.calls} call sites. Includes callers in other visible groups.</p><div class="boundary-details">${group.edges.map(([a, b, w]) => `<div class="boundary-detail"><span class="boundary-direction">${w} call site${w === 1 ? "" : "s"}</span><button data-boundary-function="${a}">${esc(D.functions[a].n)}</button><span class="boundary-arrow">calls</span><button data-boundary-function="${b}">${esc(D.functions[b].n)}</button><small>Caller group: ${esc(owner.get(a) || "Outside view")}</small></div>`).join("") || "<p>No resolved callers outside this group.</p>"}</div><button id="return-graph-inspector" class="wide">Back to group inspector</button>`;
      $("return-graph-inspector").onclick = () => {
        activePort = null;
        active = null;
        inspector();
        paintLabels();
      };
      document.querySelectorAll("[data-boundary-function]").forEach(
        (e) =>
          (e.onclick = () => {
            active = +e.dataset.boundaryFunction;
            activePort = null;
            inspector();
            paintLabels();
          }),
      );
      return;
    }
    const ports = (
        key
          ? boundary.ports.filter(
              (p) => p.key === key || key === p.direction + ":*",
            )
          : boundary.ports
      )
        .map((p) => ({
          ...p,
          edges:
            selectedFunction === null
              ? p.edges
              : p.edges.filter(
                  ([a, b]) => a === selectedFunction || b === selectedFunction,
                ),
        }))
        .filter((p) => p.edges.length)
        .map((p) => ({
          ...p,
          calls: p.edges.reduce((sum, e) => sum + e[2], 0),
        })),
      rows = ports
        .flatMap((p) => p.edges.map((edge) => ({ p, edge })))
        .sort((a, b) => b.edge[2] - a.edge[2]),
      name =
        key && !key.endsWith(":*") && !key.endsWith(":more")
          ? ports[0].name
          : "Calls across this view";
    $("inspector").innerHTML =
      `<div class="paneltag">OUTSIDE CONNECTIONS</div><h2>${esc(name)}</h2><p>${key ? (ports[0].direction === "in" ? "These outside functions call into this view." : "These functions in this view call outside.") : "All resolved calls with one endpoint outside the current view."}</p><div class="costrow"><span>Incoming call sites</span><strong>${ports.filter((p) => p.direction === "in").reduce((s, p) => s + p.calls, 0)}</strong></div><div class="costrow"><span>Outgoing call sites</span><strong>${ports.filter((p) => p.direction === "out").reduce((s, p) => s + p.calls, 0)}</strong></div><h3>${rows.length} directed function pairs</h3><div class="boundary-details">${rows.map(({ p, edge: [a, b, w] }) => `<div class="boundary-detail"><span class="boundary-direction">${p.direction === "in" ? "INCOMING" : "OUTGOING"} \u00b7 ${w} call site${w === 1 ? "" : "s"}</span><button data-boundary-function="${a}">${esc(D.functions[a].n)}</button><span class="boundary-arrow">\u2193 calls</span><button data-boundary-function="${b}">${esc(D.functions[b].n)}</button><small>Outside group: ${esc(p.name)}</small></div>`).join("") || "<p>No resolved calls cross this view boundary.</p>"}</div><button id="return-graph-inspector" class="wide">${preview ? "\u2190 Split preview" : "\u2190 Group inspector"}</button>`;
    $("return-graph-inspector").onclick = () => {
      activePort = null;
      active = null;
      fn = null;
      renderInspector(
        Engine.metrics(D, visible()),
        Engine.metrics(D, S.groups),
      );
      paintLabels();
    };
    document.querySelectorAll("[data-boundary-function]").forEach(
      (e) =>
        (e.onclick = () => {
          active = +e.dataset.boundaryFunction;
          activePort = null;
          inspector();
          paintLabels();
        }),
    );
  }
  const point = (ev) => {
    const r = svg.getBoundingClientRect();
    return { x: ev.clientX - r.left, y: ev.clientY - r.top };
  };
  const world = (p) => ({
    x: (p.x - graphCamera.x) / graphCamera.k,
    y: (p.y - graphCamera.y) / graphCamera.k,
  });
  svg.onwheel = (ev) => {
    ev.preventDefault();
    const p = point(ev);
    zoom(Math.exp(-ev.deltaY * 0.0015), p.x, p.y);
  };
  svg.onpointerdown = (ev) => {
    if (
      !layout ||
      ev.target.closest(
        "[data-region-select],[data-region-enter],[data-boundary-port]",
      )
    )
      return;
    const node = ev.target.closest("[data-node]"),
      v = node ? +node.dataset.node : null,
      p = point(ev);
    gesture = {
      start: p,
      camera: { ...graphCamera },
      v,
      canMove: v !== null && v === active && !preview,
      moved: false,
    };
    svg.setPointerCapture(ev.pointerId);
    svg.classList.add("grabbing");
  };
  svg.onpointermove = (ev) => {
    const p = point(ev);
    if (!gesture) return;
    const dx = p.x - gesture.start.x,
      dy = p.y - gesture.start.y;
    if (Math.hypot(dx, dy) > 5) gesture.moved = true;
    if (gesture.v === null) {
      graphCamera.x = gesture.camera.x + dx;
      graphCamera.y = gesture.camera.y + dy;
      paintCamera();
    } else if (gesture.canMove && gesture.moved) {
      const q = byId.get(gesture.v),
        el = svg.querySelector(`[data-node="${gesture.v}"]`);
      el.setAttribute(
        "transform",
        `translate(${q.x + dx / graphCamera.k} ${q.y + dy / graphCamera.k})`,
      );
      const w = world(p),
        target = layout.regions.find(
          (r) =>
            w.x >= r.x && w.x <= r.x + r.w && w.y >= r.y && w.y <= r.y + r.h,
        );
      svg
        .querySelectorAll(".region-box")
        .forEach((e, i) =>
          e.classList.toggle("drop-region", target === layout.regions[i]),
        );
      if (target) dragCost(gesture.v, target.id);
    }
  };
  svg.onpointerup = (ev) => {
    if (!gesture) return;
    const g = gesture;
    gesture = null;
    svg.classList.remove("grabbing");
    svg
      .querySelectorAll(".region-box")
      .forEach((e) => e.classList.remove("drop-region"));
    if (g.v !== null) {
      if (g.canMove && g.moved) {
        const w = world(point(ev)),
          target = layout.regions.find(
            (r) =>
              w.x >= r.x && w.x <= r.x + r.w && w.y >= r.y && w.y <= r.y + r.h,
          );
        const p = byId.get(g.v);
        svg
          .querySelector(`[data-node="${g.v}"]`)
          .setAttribute("transform", `translate(${p.x} ${p.y})`);
        if (target && target.id !== gs[p.group].id) {
          move(g.v, target.id);
          return;
        }
      } else if (!g.moved) {
        if (ev.shiftKey && !preview) {
          picked.has(g.v) ? picked.delete(g.v) : picked.add(g.v);
          active = null;
        } else active = g.v;
        inspector();
      } else
        toast(
          preview
            ? "Accept the split before moving functions."
            : "Click the function first, then drag it to another group.",
        );
    } else if (!g.moved) {
      active = null;
      inspector();
    }
    paintLabels();
  };
  svg.onpointercancel = () => {
    gesture = null;
    svg.classList.remove("grabbing");
    if (layout) (draw(), paintCamera());
  };
  $("zoom-in").onclick = () => zoom(1.35);
  $("zoom-out").onclick = () => zoom(1 / 1.35);
  $("fit-graph").onclick = fit;
  $("focus-function").onclick = () => focus(active);
  $("boundary-summary").onclick = () => {
    activePort = null;
    active = null;
    fn = null;
    hovered = null;
    boundaryInspector("in:*");
    paintLabels();
  };
  $("relayout").onclick = () => {
    graphCache.delete(key);
    graphCamera = null;
    renderGraph(gs, map);
  };
  svg.tabIndex = 0;
  svg.onkeydown = (ev) => {
    if (ev.target !== svg) return;
    if (ev.key === "+" || ev.key === "=") zoom(1.2);
    if (ev.key === "-") zoom(1 / 1.2);
    if (ev.key === "0") fit();
    if (ev.key === "Escape") {
      active = null;
      inspector();
      paintLabels();
    }
    const dirs = {
      ArrowLeft: [40, 0],
      ArrowRight: [-40, 0],
      ArrowUp: [0, 40],
      ArrowDown: [0, -40],
    };
    if (dirs[ev.key]) {
      ev.preventDefault();
      graphCamera.x += dirs[ev.key][0];
      graphCamera.y += dirs[ev.key][1];
      paintCamera();
    }
  };
  graphResize = new ResizeObserver(() => {
    if (layout) paintCamera();
  });
  graphResize.observe(svg);
  if (graphCache.has(key)) receive(graphCache.get(key));
  else {
    graphWorker = new Worker("layout-worker.js");
    graphWorker.onmessage = ({ data }) => {
      if (data.error) {
        $("layout-state").textContent = "Layout failed: " + data.error;
        return;
      }
      graphCache.set(key, data.layout);
      if (graphCache.size > 20)
        graphCache.delete(graphCache.keys().next().value);
      receive(data.layout);
    };
    graphWorker.onerror = () =>
      ($("layout-state").textContent = "Layout worker failed.");
    graphWorker.postMessage(input);
  }
}
