/* Preserve every resolved edge with exactly one endpoint in the current view. */
const BoundaryGraph = {
  collect(data, ids, groups) {
    const owner = new Map();
    groups.forEach((g) => g.members.forEach((v) => owner.set(v, g)));
    const ports = new Map(),
      links = new Map(),
      functions = new Map();
    let incoming = 0,
      outgoing = 0;
    for (const [a, b, w] of data.edges) {
      const ai = ids.has(a),
        bi = ids.has(b);
      if (ai === bi) continue;
      const direction = bi ? "in" : "out",
        inside = bi ? b : a,
        outside = bi ? a : b,
        g = owner.get(outside),
        key = direction + ":" + g.id;
      if (bi) incoming += w;
      else outgoing += w;
      if (!ports.has(key))
        ports.set(key, {
          key,
          direction,
          group: g.id,
          name: g.name,
          calls: 0,
          edges: [],
        });
      const p = ports.get(key);
      p.calls += w;
      p.edges.push([a, b, w]);
      const linkKey = key + ":" + inside;
      if (!links.has(linkKey))
        links.set(linkKey, {
          key: linkKey,
          port: key,
          inside,
          direction,
          calls: 0,
          edges: [],
        });
      const l = links.get(linkKey);
      l.calls += w;
      l.edges.push([a, b, w]);
      if (!functions.has(inside)) functions.set(inside, { in: 0, out: 0 });
      functions.get(inside)[direction] += w;
    }
    return {
      ports: [...ports.values()],
      links: [...links.values()],
      functions,
      incoming,
      outgoing,
    };
  },
};
if (typeof module !== "undefined") module.exports = BoundaryGraph;
