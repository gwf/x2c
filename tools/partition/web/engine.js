/* Pure partition operations. Directed edge weights count static call sites. */
const Engine = (() => {
  // Original-file attachment is independent of the tentative partition.
  // A file static moves with its file; a module function serves every file
  // of its unit, so it is not a dependency that must move.
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
            data.functions[v].v !== "static" ||
            data.functions[v].p !== f.p
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
  // `exposed` are private targets called across groups: separate units
  // would need them public. `toModule` are the file statics among them
  // called from their own unit: groups kept as member files of one module
  // unit would need them in module storage.
  function metrics(data, groups) {
    const m = membership(groups, data.functions.length),
      exposed = new Set(),
      toModule = new Set();
    let cut = 0,
      pairs = 0;
    const links = new Map();
    for (const [a, b, w] of data.edges) {
      if (m[a] === m[b]) continue;
      cut += w;
      pairs++;
      if (data.functions[b].s) exposed.add(b);
      if (
        data.functions[b].v === "static" &&
        data.functions[a].f === data.functions[b].f
      )
        toModule.add(b);
      const key = m[a] + ":" + m[b];
      links.set(key, (links.get(key) || 0) + w);
    }
    return { cut, pairs, exposed: [...exposed], toModule: [...toModule], links };
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
  return {
    membership,
    metrics,
    atoms,
    moveEvaluator,
    anchors,
    privacyTies,
    decomposition,
  };
})();
if (typeof module !== "undefined") module.exports = Engine;
