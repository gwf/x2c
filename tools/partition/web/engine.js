/* Pure partition operations. Directed edge weights count static call sites. */
const Engine = (() => {
  // Original-file attachment is independent of the tentative partition.
  function anchors(data) {
    const outgoing = data.functions.map(() => new Set()),
      incoming = data.functions.map(() => new Set());
    for (const [a, b] of data.edges) {
      outgoing[a].add(b);
      incoming[b].add(a);
    }
    const rows = data.functions.map((f, root) => {
      const dependencies = new Set(),
        seen = new Set([root]),
        stack = [root];
      while (stack.length) {
        for (const v of outgoing[stack.pop()]) {
          if (
            seen.has(v) ||
            !data.functions[v].s ||
            data.functions[v].f !== f.f
          )
            continue;
          seen.add(v);
          dependencies.add(v);
          stack.push(v);
        }
      }
      const callers = [...incoming[root]].filter(
          (v) => data.functions[v].f !== f.f,
        ),
        shared = [...dependencies].filter((v) =>
          [...incoming[v]].some((a) => a !== root && !dependencies.has(a)),
        ),
        raw = Math.log1p(callers.length) * Math.log1p(dependencies.size);
      return { callers, dependencies, shared, raw };
    });
    const maximum = Math.max(0, ...rows.map((r) => r.raw));
    return rows.map((r) => ({
      ...r,
      score: maximum ? (100 * r.raw) / maximum : 0,
    }));
  }
  function privacyTies(data) {
    return data.edges
      .filter(
        ([a, b]) =>
          data.functions[b].s && data.functions[a].f === data.functions[b].f,
      )
      .map(([a, b]) => [a, b]);
  }
  function decomposition(data, parts) {
    const owner = membership(
        parts.map((members) => ({ members })),
        data.functions.length,
      ),
      inside = new Set(parts.flat()),
      privateEdges = [],
      publicEdges = [],
      topEdges = [],
      outsidePrivate = [];
    for (const edge of data.edges) {
      const [a, b] = edge;
      if (!inside.has(a) && !inside.has(b)) continue;
      if (data.functions[a].k || data.functions[b].k) topEdges.push(edge);
      if (!inside.has(a) || !inside.has(b)) {
        if (data.functions[b].s) outsidePrivate.push(edge);
      } else if (owner[a] !== owner[b]) {
        (data.functions[b].s ? privateEdges : publicEdges).push(edge);
      }
    }
    const members = [...inside];
    return {
      privateEdges,
      publicEdges,
      topEdges,
      outsidePrivate,
      privateTargets: new Set(privateEdges.map((e) => e[1])).size,
      pairs: privateEdges.length + publicEdges.length,
      calls: [...privateEdges, ...publicEdges].reduce((n, e) => n + e[2], 0),
      authored: members.filter((v) => !data.functions[v].k).length,
      topLevel: members.filter((v) => data.functions[v].k),
      unresolved: members.reduce((n, v) => n + (data.functions[v].x || 0), 0),
      indirect: members.reduce((n, v) => n + (data.functions[v].i || 0), 0),
    };
  }
  function membership(groups, n) {
    const a = new Int32Array(n).fill(-1);
    groups.forEach((g, i) => g.members.forEach((v) => (a[v] = i)));
    return a;
  }
  function metrics(data, groups) {
    const m = membership(groups, data.functions.length),
      exposed = new Set();
    let cut = 0,
      pairs = 0;
    const links = new Map();
    for (const [a, b, w] of data.edges) {
      if (m[a] === m[b]) continue;
      cut += w;
      pairs++;
      if (data.functions[b].s) exposed.add(b);
      const key = m[a] + ":" + m[b];
      links.set(key, (links.get(key) || 0) + w);
    }
    return { cut, pairs, exposed: [...exposed], links };
  }
  function atoms(members, ties) {
    const included = new Set(members),
      parent = new Map(members.map((v) => [v, v]));
    function root(v) {
      while (parent.get(v) !== v) v = parent.get(v);
      return v;
    }
    for (const tie of ties) {
      const list = tie.filter((v) => included.has(v));
      for (const v of list) parent.set(root(v), root(list[0]));
    }
    const blocks = new Map();
    for (const v of members) {
      const r = root(v);
      if (!blocks.has(r)) blocks.set(r, []);
      blocks.get(r).push(v);
    }
    return [...blocks.values()];
  }
  function partition(data, members, k, t, ties = []) {
    const blocks = atoms(members, ties),
      n = blocks.length;
    k = Math.min(Math.max(1, k), n);
    if (k === 1) return [members.slice()];
    const index = new Map();
    blocks.forEach((b, i) => b.forEach((v) => index.set(v, i)));
    const adj = Array.from({ length: n }, () => new Map());
    let weight = 0;
    for (const [a, b, w] of data.edges) {
      const i = index.get(a),
        j = index.get(b);
      if (i === undefined || j === undefined || i === j) continue;
      adj[i].set(j, (adj[i].get(j) || 0) + w);
      adj[j].set(i, (adj[j].get(i) || 0) + w);
      weight += w;
    }
    const sizes = blocks.map((b) => b.length),
      degree = adj.map((a) => [...a.values()].reduce((s, v) => s + v, 0));
    // Balance penalizes squared group sizes independently of the requested count.
    const penalty =
      (6 * t * t * Math.max(weight, 1)) /
      Math.max(1, (members.length * members.length) / k);
    let best = null;
    for (let trial = 0; trial < 6; trial++) {
      const order = Array.from({ length: n }, (_, i) => i).sort(
        (a, b) => degree[b] - degree[a] || a - b,
      );
      const labels = new Int32Array(n).fill(-1),
        loads = Array(k).fill(0),
        counts = Array(k).fill(0);
      let seed = order[trial % order.length];
      for (let c = 0; c < k; c++) {
        if (c) {
          let score = Infinity;
          for (const v of order) {
            if (labels[v] >= 0) continue;
            let linked = 0;
            for (const [u, w] of adj[v]) if (labels[u] >= 0) linked += w;
            const q = linked / (degree[v] + 1);
            if (q < score) {
              score = q;
              seed = v;
            }
          }
        }
        labels[seed] = c;
        loads[c] += sizes[seed];
        counts[c]++;
      }
      for (const v of order) {
        if (labels[v] >= 0) continue;
        let bc = 0,
          bs = -Infinity;
        for (let c = 0; c < k; c++) {
          let aff = 0;
          for (const [u, w] of adj[v]) if (labels[u] === c) aff += w;
          const score =
            aff - penalty * (2 * loads[c] * sizes[v] + sizes[v] * sizes[v]);
          if (score > bs) {
            bs = score;
            bc = c;
          }
        }
        labels[v] = bc;
        loads[bc] += sizes[v];
        counts[bc]++;
      }
      for (let pass = 0; pass < 25; pass++) {
        let changed = false;
        for (const v of order) {
          const from = labels[v];
          if (counts[from] === 1) continue;
          const aff = Array(k).fill(0);
          for (const [u, w] of adj[v]) aff[labels[u]] += w;
          let dest = from,
            delta = 0;
          for (let c = 0; c < k; c++) {
            if (c === from) continue;
            const size = sizes[v],
              d =
                aff[from] -
                aff[c] +
                penalty * 2 * size * (loads[c] - loads[from] + size);
            if (d < delta - 1e-8) {
              delta = d;
              dest = c;
            }
          }
          if (dest !== from) {
            labels[v] = dest;
            loads[from] -= sizes[v];
            loads[dest] += sizes[v];
            counts[from]--;
            counts[dest]++;
            changed = true;
          }
        }
        if (!changed) break;
      }
      let cut = 0;
      for (let v = 0; v < n; v++)
        for (const [u, w] of adj[v]) if (labels[v] !== labels[u]) cut += w / 2;
      const score = cut + penalty * loads.reduce((s, x) => s + x * x, 0);
      if (!best || score < best.score) {
        const groups = Array.from({ length: k }, () => []);
        blocks.forEach((b, i) => groups[labels[i]].push(...b));
        best = { score, groups };
      }
    }
    return best.groups.sort((a, b) => b.length - a.length);
  }
  function moveEvaluator(data, groups) {
    const owners = membership(groups, data.functions.length);
    const incident = data.functions.map(() => []),
      crossing = data.functions.map(() => 0);
    data.edges.forEach(([a, b], i) => {
      incident[a].push(i);
      if (a !== b) incident[b].push(i);
      if (owners[a] !== owners[b]) crossing[b]++;
    });
    const beforeCut = metrics(data, groups).cut;
    function impact(members, destination) {
      const to = groups.findIndex((g) => g.id === destination),
        moved = new Set(members);
      const owner = (v) => (moved.has(v) ? to : owners[v]);
      const changes = new Map();
      let addedCalls = 0,
        removedCalls = 0;
      for (const i of new Set(members.flatMap((v) => incident[v]))) {
        const [a, b, w] = data.edges[i],
          before = owners[a] !== owners[b],
          after = owner(a) !== owner(b);
        if (!before && after) addedCalls += w;
        if (before && !after) removedCalls += w;
        changes.set(b, (changes.get(b) || 0) + Number(after) - Number(before));
      }
      const added = [],
        removed = [],
        localized = [],
        delocalized = [];
      for (const [v, d] of changes) {
        const before = crossing[v],
          after = before + d;
        if (data.functions[v].s) {
          if (!before && after) added.push(v);
          if (before && !after) removed.push(v);
        } else if (!data.functions[v].k) {
          if (before && !after) localized.push(v);
          if (!before && after) delocalized.push(v);
        }
      }
      const remaining = members.map((v) => ({
        v,
        callers: [
          ...new Set(
            incident[v].flatMap((i) => {
              const [a, b] = data.edges[i];
              return b === v && owner(a) !== owner(b) ? [a] : [];
            }),
          ),
        ],
      }));
      return {
        beforeCut,
        afterCut: beforeCut + addedCalls - removedCalls,
        delta: addedCalls - removedCalls,
        addedCalls,
        removedCalls,
        added,
        removed,
        localized,
        delocalized,
        remaining,
      };
    }
    return { owners, incident, impact };
  }
  function suggestMoves(data, groups, ties = [], focus = null, mode = "cut") {
    const { owners, incident, impact } = moveEvaluator(data, groups);
    const blocks = atoms(
      data.functions.map((_, i) => i),
      ties,
    );
    const blockOf = new Map();
    blocks.forEach((b, i) => b.forEach((v) => blockOf.set(v, i)));
    const seen = new Set(),
      results = [];
    for (const block of blocks) {
      const from = owners[block[0]];
      if (
        from < 0 ||
        block.some((v) => owners[v] !== from || data.functions[v].k) ||
        (focus && !block.some((v) => focus.has(v)))
      )
        continue;
      const neighbors = new Map();
      for (const v of block)
        for (const index of incident[v]) {
          const [a, b, w] = data.edges[index],
            u = a === v ? b : a,
            other = blockOf.get(u);
          if (other !== blockOf.get(v) && owners[u] === from)
            neighbors.set(other, (neighbors.get(other) || 0) + w);
        }
      const neighbor = [...neighbors]
        .sort((a, b) => b[1] - a[1] || a[0] - b[0])
        .find(([i]) =>
          blocks[i].every((v) => owners[v] === from && !data.functions[v].k),
        );
      const bundles = [block];
      if (neighbor) bundles.push([...block, ...blocks[neighbor[0]]]);
      for (const members of bundles) {
        if (members.length >= groups[from].members.length) continue;
        const edges = new Set(members.flatMap((v) => incident[v])),
          destinations = new Set();
        for (const i of edges)
          for (const v of data.edges[i].slice(0, 2))
            if (owners[v] >= 0 && owners[v] !== from)
              destinations.add(owners[v]);
        for (const to of destinations) {
          const key =
            members
              .slice()
              .sort((a, b) => a - b)
              .join(",") +
            ":" +
            to;
          if (seen.has(key)) continue;
          seen.add(key);
          const effect = impact(members, groups[to].id);
          if (
            mode === "localize"
              ? effect.localized.length <= effect.delocalized.length
              : effect.delta >= 0
          )
            continue;
          results.push({
            members: members.slice(),
            from: groups[from].id,
            to: groups[to].id,
            ...effect,
          });
        }
      }
    }
    return results
      .sort(
        (a, b) =>
          (mode === "localize"
            ? b.localized.length -
              b.delocalized.length -
              (a.localized.length - a.delocalized.length)
            : 0) ||
          a.delta - b.delta ||
          a.added.length - b.added.length ||
          a.members.length - b.members.length,
      )
      .slice(0, 12);
  }
  return {
    membership,
    metrics,
    partition,
    atoms,
    suggestMoves,
    moveEvaluator,
    anchors,
    privacyTies,
    decomposition,
  };
})();
if (typeof module !== "undefined") module.exports = Engine;
