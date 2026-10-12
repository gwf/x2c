// Preserved layout from the initial concept, for a like-for-like comparison.
module.exports = function previousLayout(gs, D) {
  const width = Math.max(820, gs.length * 245),
    height = 430,
    gap = 18,
    gw = (width - gap * (gs.length + 1)) / gs.length,
    positions = new Map(),
    local = new Map();
  gs.forEach((g, i) => {
    const ids = g.members
      .slice()
      .sort((a, b) => D.functions[a].o - D.functions[b].o);
    ids.forEach((v, j) => {
      const angle = j * 2.39996,
        r = Math.sqrt((j + 0.5) / ids.length);
      positions.set(v, {
        x: gap + i * (gw + gap) + gw / 2 + Math.cos(angle) * r * gw * 0.4,
        y: 260 + Math.sin(angle) * r * 125,
        group: i,
      });
    });
    local.set(g.id, i);
  });
  const edges = D.edges.filter(
    ([a, b]) => positions.has(a) && positions.has(b),
  );
  // Bounded local relaxation gives calls structure without changing membership.
  for (let iter = 0; iter < 75; iter++) {
    for (const [a, b, w] of edges) {
      if (a === b) continue;
      const p = positions.get(a),
        q = positions.get(b);
      if (p.group !== q.group) continue;
      const dx = q.x - p.x,
        dy = q.y - p.y,
        d = Math.hypot(dx, dy) || 1,
        f = (d - 35) * 0.007 * Math.min(3, Math.sqrt(w));
      p.x += (dx / d) * f;
      p.y += (dy / d) * f;
      q.x -= (dx / d) * f;
      q.y -= (dy / d) * f;
    }
    for (const g of gs) {
      for (let a = 0; a < g.members.length; a++)
        for (let b = a + 1; b < g.members.length; b++) {
          const p = positions.get(g.members[a]),
            q = positions.get(g.members[b]),
            dx = q.x - p.x,
            dy = q.y - p.y,
            d = Math.hypot(dx, dy) || 0.1;
          if (d > 45) continue;
          const f = (45 - d) * 0.022;
          p.x -= (dx / d) * f;
          p.y -= (dy / d) * f;
          q.x += (dx / d) * f;
          q.y += (dy / d) * f;
        }
    }
    for (const p of positions.values()) {
      const x = gap + p.group * (gw + gap);
      p.x = Math.max(x + 18, Math.min(x + gw - 18, p.x));
      p.y = Math.max(115, Math.min(height - 32, p.y));
    }
  }
  return {
    nodes: [...positions].map(([id, p]) => ({ id, ...p, width: 0 })),
    edges,
  };
};
