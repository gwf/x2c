/* Pure partition operations. Directed edge weights count static call sites. */
const Engine = (() => {
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
    // One exploration control increases group count (in the UI) and balance penalty.
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
  return { membership, metrics, partition, atoms };
})();
if (typeof module !== "undefined") module.exports = Engine;
