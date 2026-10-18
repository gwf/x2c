/* Member files of the view. Depth shows storage: a file static sits inside
   its file, a module function on its file's border, and a public function
   on the view's outer border. Lines aggregate calls between files. */
const TIER_COLOR = { static: "#edbc7a", module: "#c7a2e8", public: "#86c7ff" },
  TIER_RANK = { static: 0, module: 1, public: 2 };
function widerThanNeeded(f) {
  return !f.k && !f.g && !!f.r && TIER_RANK[f.v] > TIER_RANK[f.r];
}
function memberLayout(files, byFile) {
  const box = 230, gap = 46, pad = 56, dot = 9, perRow = 23,
    cols = Math.max(1, Math.ceil(Math.sqrt(files.length))),
    heights = files.map(
      (p) => 46 + Math.ceil(byFile.get(p).static.length / perRow) * dot + 14,
    ),
    rows = Math.ceil(files.length / cols),
    rowHeight = [...Array(rows)].map((_, r) =>
      Math.max(80, ...heights.slice(r * cols, r * cols + cols)),
    ),
    boxes = new Map(),
    points = new Map();
  let y = pad;
  files.forEach((p, i) => {
    const r = Math.floor(i / cols), c = i % cols;
    if (c === 0 && r) y += rowHeight[r - 1] + gap;
    const b = { x: pad + c * (box + gap), y, w: box, h: rowHeight[r] };
    boxes.set(p, b);
    byFile.get(p).static.forEach((v, j) =>
      points.set(v, {
        x: b.x + 12 + (j % perRow) * dot,
        y: b.y + 42 + Math.floor(j / perRow) * dot,
      }),
    );
    const modules = byFile.get(p).module,
      around = 2 * (b.w + b.h);
    modules.forEach((v, j) => {
      let t = ((j + 0.5) * around) / modules.length;
      const side = [b.w, b.h, b.w, b.h];
      let k = 0;
      while (t > side[k]) t -= side[k++];
      points.set(
        v,
        [
          { x: b.x + t, y: b.y },
          { x: b.x + b.w, y: b.y + t },
          { x: b.x + b.w - t, y: b.y + b.h },
          { x: b.x, y: b.y + b.h - t },
        ][k],
      );
    });
  });
  const width = pad * 2 + cols * box + (cols - 1) * gap,
    height = y + rowHeight[rows - 1] + pad,
    frame = { x: 18, y: 18, w: width - 36, h: height - 36 },
    ports = { top: [], right: [], bottom: [], left: [] };
  for (const p of files) {
    const b = boxes.get(p),
      cx = b.x + b.w / 2,
      cy = b.y + b.h / 2,
      distance = {
        top: cy - frame.y,
        bottom: frame.y + frame.h - cy,
        left: cx - frame.x,
        right: frame.x + frame.w - cx,
      },
      side = Object.keys(distance).sort((a, b) => distance[a] - distance[b])[0];
    byFile.get(p).public.forEach((v, j, all) =>
      ports[side].push({
        v,
        p,
        t: (side === "top" || side === "bottom" ? cx : cy) +
          (j - (all.length - 1) / 2) * dot,
      }),
    );
  }
  for (const [side, list] of Object.entries(ports)) {
    const horizontal = side === "top" || side === "bottom",
      start = horizontal ? frame.x + 8 : frame.y + 8,
      end = horizontal ? frame.x + frame.w - 8 : frame.y + frame.h - 8;
    list.sort((a, b) => a.t - b.t);
    list.forEach((e, i) => {
      if (i) e.t = Math.max(e.t, list[i - 1].t + dot);
    });
    const over = list.length ? list.at(-1).t - end : 0;
    if (over > 0) list.forEach((e) => (e.t = Math.max(start, e.t - over)));
    for (const e of list)
      points.set(
        e.v,
        horizontal
          ? { x: e.t, y: side === "top" ? frame.y : frame.y + frame.h, port: e.p }
          : { x: side === "left" ? frame.x : frame.x + frame.w, y: e.t, port: e.p },
      );
  }
  return { boxes, points, frame, width, height };
}
function shortNames(files) {
  const parts = files.map((p) => p.split("/")),
    common = parts.reduce((n, a) => {
      while (n && parts[0].slice(0, n).join("/") !== a.slice(0, n).join("/"))
        n--;
      return n;
    }, Math.min(...parts.map((a) => a.length - 1)));
  return new Map(files.map((p, i) => [p, parts[i].slice(common).join("/")]));
}
function memberCalls(ids) {
  const inside = new Set(ids),
    calls = new Map();
  for (const [a, b, w] of D.edges) {
    if (!inside.has(a) || !inside.has(b)) continue;
    const key = D.functions[a].p + "\n" + D.functions[b].p,
      row = calls.get(key) || { calls: 0, module: 0, public: 0, static: 0 };
    row.calls += w;
    row[D.functions[b].v] += w;
    calls.set(key, row);
  }
  return calls;
}
function renderMemberFiles(gs) {
  const host = $("workspace"),
    ids = gs.flatMap((g) => g.members).filter((v) => !D.functions[v].k),
    byFile = new Map();
  host.classList.remove("graph-workspace");
  for (const v of ids) {
    const p = D.functions[v].p;
    if (!byFile.has(p)) byFile.set(p, { static: [], module: [], public: [] });
    byFile.get(p)[D.functions[v].v].push(v);
  }
  const files = [...byFile.keys()].sort(),
    names = shortNames(files),
    calls = memberCalls(ids),
    wider = ids.filter((v) => widerThanNeeded(D.functions[v]));
  if (!files.length) {
    host.innerHTML = "<p>No authored functions in this view.</p>";
    return;
  }
  const L = memberLayout(files, byFile),
    center = (p) => {
      const b = L.boxes.get(p);
      return { x: b.x + b.w / 2, y: b.y + b.h / 2 };
    },
    links = [...calls]
      .map(([key, row]) => [...key.split("\n"), row])
      .filter(([from, to]) => from !== to),
    linkMarkup = links
      .map(([from, to, row]) => {
        const a = center(from), b = center(to),
          bend = 0.18,
          mx = (a.x + b.x) / 2 + (b.y - a.y) * bend,
          my = (a.y + b.y) / 2 - (b.x - a.x) * bend,
          color = row.public > row.module ? TIER_COLOR.public : TIER_COLOR.module;
        return `<path class="member-link" d="M${a.x} ${a.y}Q${mx} ${my} ${b.x} ${b.y}" stroke="${color}" stroke-width="${1 + Math.log2(row.calls)}" marker-end="url(#member-arrow)"><title>${esc(names.get(from))} → ${esc(names.get(to))}: ${row.calls} call sites (${row.module} to module, ${row.public} to public functions)</title></path>`;
      })
      .join(""),
    leaderMarkup = [...L.points]
      .filter(([, q]) => q.port)
      .map(([, q]) => {
        const b = L.boxes.get(q.port),
          x = Math.max(b.x, Math.min(q.x, b.x + b.w)),
          y = Math.max(b.y, Math.min(q.y, b.y + b.h));
        return `<line class="member-leader" x1="${x}" y1="${y}" x2="${q.x}" y2="${q.y}"/>`;
      })
      .join(""),
    boxMarkup = files
      .map((p) => {
        const b = L.boxes.get(p), t = byFile.get(p);
        return `<g class="member-box"><rect x="${b.x}" y="${b.y}" width="${b.w}" height="${b.h}" rx="6"/><text x="${b.x + 10}" y="${b.y + 20}">${esc(names.get(p))}</text><text class="member-counts" x="${b.x + 10}" y="${b.y + 34}">${t.static.length} static · ${t.module.length} module · ${t.public.length} public</text></g>`;
      })
      .join(""),
    dotMarkup = [...L.points]
      .map(([v, q]) => {
        const f = D.functions[v];
        return `<g class="member-dot" data-member-fn="${v}" transform="translate(${q.x} ${q.y})"><title>${esc(f.n)} · ${f.v}${f.r ? " · callers need " + f.r : " · no resolved callers"} · ${esc(f.p)}</title>${widerThanNeeded(f) ? '<circle class="member-wider" r="6.5"/>' : ""}<circle r="3.6" fill="${TIER_COLOR[f.v]}" class="${v === fn ? "selected" : ""}"/></g>`;
      })
      .join("");
  host.innerHTML = `<div class="member-view"><div class="member-legend"><span style="color:${TIER_COLOR.static}">● File static: inside its file</span><span style="color:${TIER_COLOR.module}">● Module: on its file's border</span><span style="color:${TIER_COLOR.public}">● Public: on the outer border</span><span><span class="member-ring">◌</span> Storage wider than its resolved callers need</span></div><svg class="member-svg" viewBox="0 0 ${L.width} ${L.height}" width="${L.width}" height="${L.height}" role="img" aria-label="Member files by storage tier"><defs><marker id="member-arrow" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="5" markerHeight="5" orient="auto"><path d="M0 0L8 4L0 8z" fill="#9aa9ad"/></marker></defs><rect class="member-frame" x="${L.frame.x}" y="${L.frame.y}" width="${L.frame.w}" height="${L.frame.h}" rx="10"/>${linkMarkup}${leaderMarkup}${boxMarkup}<g id="member-trace"></g>${dotMarkup}</svg>${memberMatrix(files, names, calls)}${memberWider(wider)}</div>`;
  const trace = host.querySelector("#member-trace");
  host.querySelectorAll("[data-member-fn]").forEach((e) => {
    const v = +e.dataset.memberFn;
    e.onmouseenter = () => {
      const from = L.points.get(v);
      trace.innerHTML = D.edges
        .filter(([a, b]) => (a === v || b === v) && a !== b)
        .map(([a, b]) => {
          const q = L.points.get(a === v ? b : a);
          return q
            ? `<line class="member-trace ${a === v ? "out" : "in"}" x1="${from.x}" y1="${from.y}" x2="${q.x}" y2="${q.y}"/>`
            : "";
        })
        .join("");
    };
    e.onmouseleave = () => (trace.innerHTML = "");
    e.onclick = () => selectMemberFunction(v);
  });
  host
    .querySelectorAll("[data-wider-fn]")
    .forEach((e) => (e.onclick = () => selectMemberFunction(+e.dataset.widerFn)));
}
function selectMemberFunction(v) {
  fn = v;
  renderInspector(Engine.metrics(D, visible()), Engine.metrics(D, S.groups));
  document
    .querySelectorAll(".member-dot circle.selected")
    .forEach((c) => c.classList.remove("selected"));
  document
    .querySelector(`[data-member-fn="${v}"] circle:last-child`)
    ?.classList.add("selected");
}
function memberMatrix(files, names, calls) {
  if (files.length < 2) return "";
  const cell = (from, to) => {
    const row = calls.get(from + "\n" + to);
    if (!row) return "<td>·</td>";
    return from === to
      ? `<td class="member-internal" title="Calls within the file">${row.calls}</td>`
      : `<td title="${row.module} to module, ${row.public} to public functions">${row.calls}</td>`;
  };
  return `<h3>Calls between member files</h3><p class="note">Rows call columns. Each cell counts resolved call sites; the diagonal counts calls within one file. Calls between files reach module or public functions.</p><div class="member-matrix-wrap"><table class="member-matrix"><thead><tr><th>Caller \\ callee</th>${files.map((p) => `<th>${esc(names.get(p))}</th>`).join("")}</tr></thead><tbody>${files.map((from) => `<tr><th>${esc(names.get(from))}</th>${files.map((to) => cell(from, to)).join("")}</tr>`).join("")}</tbody></table></div>`;
}
function memberWider(wider) {
  return `<h3>Storage wider than needed (${wider.length})</h3><p class="note">Every resolved caller would still reach these definitions with the narrower storage. Indirect references, callbacks, implicit conversions such as <code>T.var</code>, and published API are outside the resolved calls, so check the source before narrowing. Calls from external commands count; generated definitions are left out.</p>${wider
    .sort((a, b) => D.functions[a].p.localeCompare(D.functions[b].p) || D.functions[a].n.localeCompare(D.functions[b].n))
    .map((v) => {
      const f = D.functions[v];
      return `<div class="connection"><button data-wider-fn="${v}">${esc(f.n)}</button><small>${f.v} → ${f.r} · ${esc(f.p)}</small></div>`;
    })
    .join("")}`;
}
