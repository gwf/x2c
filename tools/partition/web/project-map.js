/* Weighted quotient graph: one node per current partition, one edge per directed group pair. */
function projectLayout(nodes, links) {
  const ps = nodes.map((n, i) => ({
    ...n,
    x: Math.cos(i * 2.39996) * Math.sqrt(i + 1) * 48,
    y: Math.sin(i * 2.39996) * Math.sqrt(i + 1) * 48,
  }));
  for (let t = 0; t < 450; t++) {
    const forces = ps.map(() => ({ x: 0, y: 0 }));
    for (let i = 0; i < ps.length; i++)
      for (let j = i + 1; j < ps.length; j++) {
        const a = ps[i],
          b = ps[j],
          dx = b.x - a.x,
          dy = b.y - a.y,
          d = Math.hypot(dx, dy) || 1,
          min = a.r + b.r + 24;
        const f = 1800 / (d * d) + Math.max(0, min - d) * 0.65;
        forces[i].x -= (dx / d) * f;
        forces[i].y -= (dy / d) * f;
        forces[j].x += (dx / d) * f;
        forces[j].y += (dy / d) * f;
      }
    for (const {
      ids: [i, j],
      w,
    } of links) {
      const a = ps[i],
        b = ps[j],
        dx = b.x - a.x,
        dy = b.y - a.y,
        d = Math.hypot(dx, dy) || 1;
      const f = (d - a.r - b.r - 65) * 0.006 * Math.log2(2 + w);
      forces[i].x += (dx / d) * f;
      forces[i].y += (dy / d) * f;
      forces[j].x -= (dx / d) * f;
      forces[j].y -= (dy / d) * f;
    }
    const temp = 9 * (1 - t / 450) + 0.25;
    ps.forEach((p, i) => {
      const f = forces[i];
      f.x -= p.x * 0.001;
      f.y -= p.y * 0.001;
      const d = Math.hypot(f.x, f.y) || 1;
      p.x += f.x * Math.min(1, temp / d);
      p.y += f.y * Math.min(1, temp / d);
    });
  }
  // Resolve remaining disk intersections without deleting weak edges.
  for (let t = 0; t < 150; t++)
    for (let i = 0; i < ps.length; i++)
      for (let j = i + 1; j < ps.length; j++) {
        const a = ps[i],
          b = ps[j],
          dx = b.x - a.x,
          dy = b.y - a.y,
          d = Math.hypot(dx, dy) || 1,
          over = a.r + b.r + 12 - d;
        if (over > 0) {
          a.x -= (dx / d) * over * 0.51;
          a.y -= (dy / d) * over * 0.51;
          b.x += (dx / d) * over * 0.51;
          b.y += (dy / d) * over * 0.51;
        }
      }
  const connected = new Set(links.flatMap((e) => e.ids)),
    core = ps.filter((p, i) => connected.has(i));
  ps.forEach((p) => (p.x *= 1.65));
  if (core.length) {
    const left = Math.min(...core.map((p) => p.x - p.r)),
      right = Math.max(...core.map((p) => p.x + p.r)),
      bottom = Math.max(...core.map((p) => p.y + p.r));
    let x = left,
      y = bottom + 60,
      row = 0;
    ps.forEach((p, i) => {
      if (connected.has(i)) return;
      if (x + 2 * p.r > right) {
        x = left;
        y += row + 30;
        row = 0;
      }
      p.x = x + p.r;
      p.y = y + p.r;
      x += 2 * p.r + 30;
      row = Math.max(row, 2 * p.r);
    });
  }
  return ps;
}
// Only calls between displayed groups become edges. Outside callers remain
// counted per group and are shown individually when the group is opened.
function aggregateGroupCalls(data, groups) {
  const membership = new Map();
  groups.forEach((g, i) => g.members.forEach((v) => membership.set(v, i)));
  const pairs = new Map(),
    callers = groups.map(() => new Set());
  const incoming = groups.map(() => 0);
  for (const [a, b, w] of data.edges) {
    const i = membership.get(a),
      j = membership.get(b);
    if (i === j) continue;
    if (j !== undefined) {
      callers[j].add(a);
      incoming[j] += w;
    }
    if (i === undefined || j === undefined) continue;
    const key = i + ":" + j;
    pairs.set(key, (pairs.get(key) || 0) + w);
  }
  return {
    links: [...pairs].map(([key, w]) => ({
      ids: key.split(":").map(Number),
      w,
    })),
    callers: callers.map((s) => s.size),
    incoming,
  };
}
function arrangementData(data, groups, allGroups) {
  const result = aggregateGroupCalls(data, groups);
  const inside = new Map(
    groups.flatMap((g, i) => g.members.map((v) => [v, i])),
  );
  const owner = new Map(allGroups.flatMap((g) => g.members.map((v) => [v, g])));
  const outside = new Map(),
    pairs = new Map();
  for (const [a, b, w] of data.edges) {
    if (inside.has(a) || !inside.has(b)) continue;
    const g = owner.get(a),
      j = inside.get(b),
      key = g.id + ":" + j;
    if (!outside.has(g.id))
      outside.set(g.id, { group: g, consumers: new Set() });
    outside.get(g.id).consumers.add(a);
    if (!pairs.has(key))
      pairs.set(key, { id: g.id, j, consumers: new Set(), calls: 0 });
    const pair = pairs.get(key);
    pair.consumers.add(a);
    pair.calls += w;
  }
  const displayed = groups.slice(),
    index = new Map();
  for (const [id, p] of outside) {
    index.set(id, displayed.length);
    displayed.push({
      ...p.group,
      outside: true,
      consumerCount: p.consumers.size,
    });
    result.callers.push(0);
    result.incoming.push(0);
  }
  for (const p of pairs.values())
    result.links.push({
      ids: [index.get(p.id), p.j],
      w: p.consumers.size,
      calls: p.calls,
      outside: true,
    });
  return { ...result, groups: displayed };
}
let projectMapCache = null;
function renderMap(gs) {
  graphWorker?.terminate();
  graphResize?.disconnect();
  const host = $("workspace");
  host.classList.add("graph-workspace");
  const arrangement = arrangementData(D, gs, scope ? visible() : gs);
  gs = arrangement.groups;
  const { links, callers, incoming } = arrangement;
  const labels = gs.map((g, i) => {
    if (g.outside) return "Outside: " + g.name;
    if (!scope) return g.name;
    const stem = scope.name.replace(/\.x$/, "");
    const name = g.name.startsWith(stem + ".")
      ? "Group " + g.name.slice(stem.length + 1).replace(/\.x$/, "")
      : g.name;
    return name + " / " + callers[i] + " callers";
  });
  const nodes = gs.map((g) => {
    const counts = new Map();
    g.members.forEach((v) => {
      const f = D.functions[v].f;
      counts.set(f, (counts.get(f) || 0) + 1);
    });
    const original =
      g.id.startsWith("file-") &&
      g.members.length === D.files[+g.id.slice(5)]?.functions &&
      g.members.every((v) => D.functions[v].f === +g.id.slice(5));
    const lines = original
      ? D.files[+g.id.slice(5)].lines
      : Math.round(
          [...counts].reduce(
            (n, [f, count]) =>
              n +
              (D.files[f].lines * count) / Math.max(1, D.files[f].functions),
            0,
          ),
        );
    return {
      lines,
      estimated: !original,
      r: scope
        ? 24 *
          Math.sqrt(Math.max(1, g.outside ? g.consumerCount : g.members.length))
        : Math.max(5, Math.sqrt(lines) * 0.72),
    };
  });
  const key =
    D.revision +
    Boolean(scope) +
    JSON.stringify(
      gs.map((g) => [g.id, g.members, !!g.outside, g.consumerCount]),
    );
  if (projectMapCache?.key !== key)
    projectMapCache = { key, ps: projectLayout(nodes, links) };
  const ps = projectMapCache.ps;
  host.innerHTML =
    '<div class="graph-tools"><button id="map-minus">\u2212</button><button id="map-fit">Fit groups</button><button id="map-plus">+</button><button id="map-calls" aria-expanded="false">Call details</button><span>' +
    (scope
      ? "Inside: functions; outside: callers"
      : "Circle area: source lines; count: functions") +
    ' \u00b7 Edges: call sites; outside edges: callers \u00b7 Thicker = more calls</span></div><svg id="project-map" style="flex:1;min-height:300px;width:100%;touch-action:none" aria-label="Groups and directed calls"></svg><div class="graph-legend"><span><span style="color:#59cfff">Source (blue)</span> \u2192 <span style="color:#ffb454">destination (orange)</span></span><span>Scroll to zoom \u00b7 drag background to pan \u00b7 click to explore \u00b7 Shift-click to select \u00b7 hover to isolate connections</span></div>';
  const details = document.createElement("div");
  details.hidden = true;
  details.style.cssText =
    "position:absolute;right:12px;top:48px;max-height:65%;max-width:90%;overflow:auto;background:#182125;border:1px solid #52666c;padding:12px;z-index:3;font-size:12px";
  details.innerHTML = `<strong>Directed calls between groups</strong><p>Inside links count static call sites. Outside links count distinct caller functions (c), not runtime frequency.</p><table><thead><tr><th>Source</th><th>Destination</th><th>Weight</th></tr></thead><tbody>${links
    .slice()
    .sort((a, b) => b.w - a.w)
    .map(
      ({ ids: [i, j], w, outside }) =>
        `<tr><td style="padding:5px 12px 5px 0">${esc(gs[i].name)}</td><td style="padding:5px 12px">${esc(gs[j].name)}</td><td style="text-align:right">${fmt(w)} ${outside ? "callers" : "call sites"}</td></tr>`,
    )
    .join("")}</tbody></table>`;
  host.append(details);
  $("map-calls").onclick = () => {
    details.hidden = !details.hidden;
    $("map-calls").setAttribute("aria-expanded", String(!details.hidden));
  };
  const svg = $("project-map");
  let camera = { x: 0, y: 0, k: 1 },
    drag = null,
    moved = false;
  svg.innerHTML =
    '<defs><marker id="map-arrow" viewBox="0 0 8 8" refX="7" refY="4" markerUnits="userSpaceOnUse" markerWidth="12" markerHeight="12" orient="auto"><path d="M0 0L8 4L0 8" fill="#ffb454"/></marker>' +
    links
      .map(({ ids: [i, j] }, n) => {
        const a = ps[i],
          b = ps[j],
          d = Math.hypot(b.x - a.x, b.y - a.y) || 1;
        const ux = (b.x - a.x) / d,
          uy = (b.y - a.y) / d;
        return `<linearGradient id="call-gradient-${n}" gradientUnits="userSpaceOnUse" x1="${a.x + ux * a.r}" y1="${a.y + uy * a.r}" x2="${b.x - ux * (b.r + 3)}" y2="${b.y - uy * (b.r + 3)}"><stop offset="0" stop-color="#59cfff"/><stop offset=".5" stop-color="#b797f5"/><stop offset="1" stop-color="#ffb454"/></linearGradient>`;
      })
      .join("") +
    '</defs><g id="map-scene">' +
    links
      .map(({ ids: [i, j], w, outside, calls }, n) => {
        const a = ps[i],
          b = ps[j],
          d = Math.hypot(b.x - a.x, b.y - a.y) || 1,
          ux = (b.x - a.x) / d,
          uy = (b.y - a.y) / d;
        return `<path data-map-edge="${i},${j}" d="M${a.x + ux * a.r} ${a.y + uy * a.r} Q${(a.x + b.x) / 2 - uy * 28} ${(a.y + b.y) / 2 + ux * 28} ${b.x - ux * (b.r + 3)} ${b.y - uy * (b.r + 3)}" fill="none" vector-effect="non-scaling-stroke" stroke="url(#call-gradient-${n})" stroke-width="${1.5 + Math.log2(w + 1) * 1.2}" opacity="${scope ? ".8" : ".2"}" marker-end="url(#map-arrow)"><title>${esc(gs[i].name)} to ${esc(gs[j].name)}: ${w} ${outside ? "caller functions / " + calls + " call sites" : "call sites"}</title></path>`;
      })
      .join("") +
    links
      .map(
        ({ ids: [i, j], w, outside }, n) =>
          `<text data-call-count="${n}" data-call-pair="${i},${j}" text-anchor="middle" fill="#fff" font-size="12" font-weight="600" paint-order="stroke" stroke="#11181c" stroke-width="5" style="pointer-events:none">${fmt(w)}${outside ? "c" : ""}</text>`,
      )
      .join("") +
    ps
      .map(
        (p, i) =>
          `<g data-map-node="${i}" tabindex="0" role="button" aria-label="Open ${esc(gs[i].name)}" style="cursor:pointer"><title>${esc(gs[i].name)}: ${p.estimated ? "approximately " : ""}${fmt(p.lines)} source lines; ${gs[i].members.length} functions; ${gs[i].outside ? `${gs[i].consumerCount} functions call into this view` : `${callers[i]} callers outside group / ${incoming[i]} incoming call sites`}${p.estimated ? " (size apportioned by function count)" : ""}</title><circle stroke-dasharray="${gs[i].outside ? "5 4" : "none"}" cx="${p.x}" cy="${p.y}" r="${p.r}" fill="${gs[i].name.startsWith("lib/") ? "#244553" : "#34482e"}" stroke="${selected.has(gs[i].id) ? "#fff" : gs[i].name.startsWith("lib/") ? "#9abfce" : "#b5dba0"}" stroke-width="${selected.has(gs[i].id) ? 3 : 1.2}"/><text data-function-count="${i}" text-anchor="middle" dominant-baseline="central" fill="#fff" font-size="15" font-weight="600" style="pointer-events:none">${gs[i].outside ? gs[i].consumerCount : gs[i].members.length}</text><text data-map-label="${i}" text-anchor="middle" fill="#e0e8e6" font-size="11" paint-order="stroke" stroke="#11181c" stroke-width="3">${esc(labels[i])}</text></g>`,
      )
      .join("") +
    "</g>";
  function paint() {
    svg.setAttribute("viewBox", `0 0 ${svg.clientWidth} ${svg.clientHeight}`);
    $("map-scene").setAttribute(
      "transform",
      `translate(${camera.x} ${camera.y}) scale(${camera.k})`,
    );
    const marker = $("map-arrow");
    marker.setAttribute("markerWidth", 12 / camera.k);
    marker.setAttribute("markerHeight", 12 / camera.k);
    svg.querySelectorAll("[data-function-count]").forEach((e) => {
      const p = ps[+e.dataset.functionCount];
      e.setAttribute(
        "transform",
        `translate(${p.x} ${p.y}) scale(${1 / camera.k})`,
      );
      e.style.opacity = scope || p.r * camera.k > 12 ? "1" : "0";
    });
    svg.querySelectorAll("[data-call-count]").forEach((e) => {
      const {
          ids: [i, j],
        } = links[+e.dataset.callCount],
        a = ps[i],
        b = ps[j];
      const d = Math.hypot(b.x - a.x, b.y - a.y) || 1;
      const ux = (b.x - a.x) / d,
        uy = (b.y - a.y) / d;
      const x = (a.x + b.x) / 2 + (ux * (a.r - b.r - 3)) / 4 - uy * 14;
      const y = (a.y + b.y) / 2 + (uy * (a.r - b.r - 3)) / 4 + ux * 14;
      e.setAttribute(
        "transform",
        `translate(${x} ${y}) scale(${1 / camera.k})`,
      );
      e.style.opacity = scope ? "1" : "0";
    });
    const occupied = [];
    [...svg.querySelectorAll("[data-map-label]")]
      .sort((a, b) => ps[+b.dataset.mapLabel].r - ps[+a.dataset.mapLabel].r)
      .forEach((e) => {
        const i = +e.dataset.mapLabel,
          p = ps[i],
          w = labels[i].length * 6.3,
          x = p.x * camera.k + camera.x,
          y = p.y * camera.k + camera.y + p.r * camera.k + 12;
        e.setAttribute(
          "transform",
          `translate(${p.x} ${p.y + p.r + 12 / camera.k}) scale(${1 / camera.k})`,
        );
        const box = { x: x - w / 2, y: y - 11, w, h: 14 };
        const show = !occupied.some(
          (b) =>
            box.x < b.x + b.w &&
            box.x + box.w > b.x &&
            box.y < b.y + b.h &&
            box.y + box.h > b.y,
        );
        e.style.opacity = show ? "1" : "0";
        if (show) occupied.push(box);
      });
  }
  function fit() {
    const width = svg.clientWidth,
      height = svg.clientHeight;
    if (!width || !height) return;
    const x = Math.min(...ps.map((p) => p.x - p.r)),
      y = Math.min(...ps.map((p) => p.y - p.r)),
      w = Math.max(...ps.map((p) => p.x + p.r)) - x,
      h = Math.max(...ps.map((p) => p.y + p.r)) - y;
    // Labels retain screen-pixel size while circles scale with the camera.
    const labelMargin = Math.min(
      width * 0.25,
      Math.max(...labels.map((name) => name.length * 6.3)) / 2 + 16,
    );
    camera.k = Math.max(
      0.01,
      Math.min(
        (width - 2 * labelMargin) / Math.max(1, w),
        (height - 64) / Math.max(1, h),
      ),
    );
    camera.x = (width - w * camera.k) / 2 - x * camera.k;
    camera.y = (height - 24 - h * camera.k) / 2 - y * camera.k;
    paint();
  }
  function zoom(f, x = svg.clientWidth / 2, y = svg.clientHeight / 2) {
    const k = Math.max(0.1, Math.min(5, camera.k * f)),
      q = k / camera.k;
    camera.x = x - (x - camera.x) * q;
    camera.y = y - (y - camera.y) * q;
    camera.k = k;
    paint();
  }
  $("map-minus").onclick = () => zoom(0.8);
  $("map-plus").onclick = () => zoom(1.25);
  $("map-fit").onclick = fit;
  svg.onwheel = (e) => {
    e.preventDefault();
    const b = svg.getBoundingClientRect();
    zoom(Math.exp(-e.deltaY * 0.0015), e.clientX - b.left, e.clientY - b.top);
  };
  svg.onpointerdown = (e) => {
    moved = false;
    if (e.target.closest("[data-map-node]")) return;
    drag = { x: e.clientX, y: e.clientY, cx: camera.x, cy: camera.y };
    svg.setPointerCapture(e.pointerId);
  };
  svg.onpointermove = (e) => {
    if (!drag) return;
    camera.x = drag.cx + e.clientX - drag.x;
    camera.y = drag.cy + e.clientY - drag.y;
    moved = true;
    paint();
  };
  svg.onpointerup = svg.onpointercancel = () => (drag = null);
  svg.querySelectorAll("[data-map-node]").forEach((e) => {
    const i = +e.dataset.mapNode;
    const open = (ev) => {
      if (moved) return;
      if (ev.shiftKey) {
        selected.has(gs[i].id)
          ? selected.delete(gs[i].id)
          : selected.add(gs[i].id);
        render();
      } else if (preview && gs[i].outside) {
        toast("Accept or discard the split before opening an outside group.");
      } else if (preview) {
        previewGroup = gs[i].id;
        render();
      } else enter(gs[i].id);
    };
    e.onclick = open;
    e.onkeydown = (ev) => {
      if (ev.key === "Enter") open(ev);
    };
    e.onpointerenter = e.onfocus = () => {
      svg
        .querySelectorAll("[data-map-edge]")
        .forEach((edge) =>
          edge.setAttribute(
            "opacity",
            edge.dataset.mapEdge.split(",").includes(String(i)) ? ".9" : ".025",
          ),
        );
      svg.querySelectorAll("[data-call-count]").forEach((label) => {
        label.style.opacity = label.dataset.callPair
          .split(",")
          .includes(String(i))
          ? "1"
          : ".08";
      });
      e.querySelector("[data-map-label]").style.opacity = "1";
    };
    e.onpointerleave = e.onblur = () => {
      svg
        .querySelectorAll("[data-map-edge]")
        .forEach((edge) => edge.setAttribute("opacity", scope ? ".8" : ".2"));
      paint();
    };
  });
  graphResize = new ResizeObserver(fit);
  graphResize.observe(svg);
  fit();
}
if (typeof module !== "undefined") {
  module.exports = projectLayout;
  module.exports.aggregateGroupCalls = aggregateGroupCalls;
  module.exports.arrangementData = arrangementData;
}
