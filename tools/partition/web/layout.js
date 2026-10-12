/* Layout changes coordinates only. Membership never follows layout forces. */
const GraphLayout = (() => {
  function solve(groups, edges, aspect = 1.5) {
    let seed = 71231;
    const random = () => {
      seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
      return seed / 4294967296;
    };
    const nodes = [],
      byId = new Map(),
      regions = groups.map((g, gi) => {
        const prefix =
          g.nodes.length > 1 ? commonOwner(g.nodes.map((n) => n.name)) : "";
        const maxLabel = Math.max(
          150,
          ...g.nodes.map((n) => (n.name.length - prefix.length) * 7.1 + 28),
        );
        const cols = Math.max(
          1,
          Math.ceil(Math.sqrt((g.nodes.length * 42 * 1.3) / maxLabel)),
        );
        const w = Math.max(300, cols * (maxLabel + 38) + 48),
          h = Math.max(200, Math.ceil(g.nodes.length / cols) * 48 + 100);
        g.nodes.forEach((n, j) => {
          const p = {
            id: n.id,
            name: n.name,
            label: prefix ? n.name.slice(prefix.length) : n.name,
            group: gi,
            x: 0,
            y: 0,
            lx: 30 + (j % cols) * (maxLabel + 38) + maxLabel / 2,
            ly: 92 + Math.floor(j / cols) * 48,
            width: maxLabel,
            height: 25,
          };
          nodes.push(p);
          byId.set(n.id, p);
        });
        return {
          id: g.id,
          name: g.name,
          count: g.nodes.length,
          prefix,
          w,
          h,
          x: 0,
          y: 0,
        };
      });
    const calls = edges.filter(
        ([a, b]) => a !== b && byId.has(a) && byId.has(b),
      ),
      links = Array.from({ length: groups.length }, () =>
        Array(groups.length).fill(0),
      );
    for (const [a, b, w] of calls) {
      const A = byId.get(a).group,
        B = byId.get(b).group;
      if (A !== B)
        ((links[A][B] += Math.sqrt(w)), (links[B][A] += Math.sqrt(w)));
    }
    // Choose a packing for the actual viewport, then anneal the group order by connectivity.
    let best = null;
    function packing(order, columns) {
      const pos = [];
      let y = 0;
      for (let start = 0; start < order.length; start += columns) {
        let x = 0,
          rowh = 0;
        for (const i of order.slice(start, start + columns)) {
          pos[i] = { x, y };
          x += regions[i].w + 90;
          rowh = Math.max(rowh, regions[i].h);
        }
        y += rowh + 90;
      }
      const W = Math.max(...regions.map((r, i) => pos[i].x + r.w), 1),
        H = Math.max(...regions.map((r, i) => pos[i].y + r.h), 1);
      let spring = 0;
      for (let a = 0; a < regions.length; a++)
        for (let b = a + 1; b < regions.length; b++)
          spring +=
            links[a][b] *
            Math.hypot(
              pos[a].x + regions[a].w / 2 - pos[b].x - regions[b].w / 2,
              pos[a].y + regions[a].h / 2 - pos[b].y - regions[b].h / 2,
            );
      const fit = Math.max(W / aspect, H);
      return {
        pos,
        W,
        H,
        score: fit * fit + spring * 5,
        order: order.slice(),
        columns,
      };
    }
    for (let cols = 1; cols <= Math.min(regions.length, 8); cols++) {
      let order = regions
          .map((r, i) => i)
          .sort((a, b) => regions[b].count - regions[a].count),
        current = packing(order, cols);
      if (!best || current.score < best.score) best = current;
      for (let trial = 0; trial < 160; trial++) {
        const a = Math.floor(random() * order.length),
          b = Math.floor(random() * order.length);
        [order[a], order[b]] = [order[b], order[a]];
        const next = packing(order, cols),
          temp = current.score * 0.03 * (1 - trial / 160);
        if (
          next.score < current.score ||
          random() < Math.exp((current.score - next.score) / Math.max(1, temp))
        )
          current = next;
        else [order[a], order[b]] = [order[b], order[a]];
        if (current.score < best.score) best = current;
      }
    }
    // Fill a short final row rather than reserving an unused quadrant.
    const remainder = regions.length % best.columns;
    if (remainder && regions.length > best.columns) {
      const last = best.order.slice(-remainder),
        oldWidth = last.reduce((n, i) => n + regions[i].w, 0),
        available = best.W - 90 * (remainder - 1);
      for (const i of last) {
        const r = regions[i],
          area = r.w * (r.h - 80);
        r.w *= available / oldWidth;
        r.h = Math.max(200, area / r.w + 80);
      }
    }
    best = packing(best.order, best.columns);
    regions.forEach((r, i) => {
      r.x = best.pos[i].x;
      r.y = best.pos[i].y;
      const ns = nodes.filter((n) => n.group === i),
        cell = ns[0]?.width || 150,
        cols = Math.max(1, Math.floor((r.w - 40) / (cell + 28)));
      r.h = Math.max(r.h, Math.ceil(ns.length / cols) * 45 + 100);
      ns.forEach((p, j) => {
        p.lx = 20 + (((j % cols) + 0.5) * (r.w - 40)) / cols;
        p.ly = 95 + Math.floor(j / cols) * 45;
      });
    });
    best = packing(best.order, best.columns);
    regions.forEach((r, i) => {
      r.x = best.pos[i].x;
      r.y = best.pos[i].y;
    });
    nodes.forEach((p) => {
      const r = regions[p.group];
      p.x = r.x + p.lx;
      p.y = r.y + p.ly;
    });
    const start = quality(nodes, calls, byId);
    // Weighted springs, distance repulsion, label-box collision, and containment.
    for (let step = 0; step < 320; step++) {
      const forces = nodes.map(() => ({ x: 0, y: 0 })),
        idx = new Map(nodes.map((n, i) => [n.id, i]));
      for (let i = 0; i < nodes.length; i++)
        for (let j = i + 1; j < nodes.length; j++) {
          const a = nodes[i],
            b = nodes[j];
          if (a.group !== b.group) continue;
          let dx = b.x - a.x,
            dy = b.y - a.y;
          if (Math.abs(dx) + Math.abs(dy) < 0.01) dx = 0.1;
          const d2 = Math.max(100, dx * dx + dy * dy),
            d = Math.sqrt(d2),
            f = Math.min(8, 2200 / d2);
          forces[i].x -= (dx / d) * f;
          forces[i].y -= (dy / d) * f;
          forces[j].x += (dx / d) * f;
          forces[j].y += (dy / d) * f;
          const ox = (a.width + b.width) / 2 + 22 - Math.abs(dx),
            oy = 40 - Math.abs(dy);
          if (ox > 0 && oy > 0) {
            if (ox < oy) {
              const f = Math.sign(dx || 1) * ox * 0.3;
              forces[i].x -= f;
              forces[j].x += f;
            } else {
              const f = Math.sign(dy || 1) * oy * 0.3;
              forces[i].y -= f;
              forces[j].y += f;
            }
          }
        }
      for (const [u, v, w] of calls) {
        const a = byId.get(u),
          b = byId.get(v),
          i = idx.get(u),
          j = idx.get(v),
          dx = b.x - a.x,
          dy = b.y - a.y,
          d = Math.hypot(dx, dy) || 1;
        const horizontal = Math.abs(dx) / d,
          ideal = 55 + (horizontal * (a.width + b.width)) / 2;
        const strength = a.group === b.group ? 0.016 : 0.0025,
          f = (d - ideal) * strength * Math.min(2, Math.sqrt(w));
        forces[i].x += (dx / d) * f;
        forces[i].y += (dy / d) * f;
        forces[j].x -= (dx / d) * f;
        forces[j].y -= (dy / d) * f;
      }
      const cap = 7 * (1 - step / 400);
      nodes.forEach((p, i) => {
        const r = regions[p.group],
          f = forces[i];
        p.x += Math.max(-cap, Math.min(cap, f.x));
        p.y += Math.max(-cap, Math.min(cap, f.y));
        p.x = Math.max(
          r.x + p.width / 2 + 20,
          Math.min(r.x + r.w - p.width / 2 - 20, p.x),
        );
        p.y = Math.max(r.y + 95, Math.min(r.y + r.h - 25, p.y));
      });
    }
    // Anneal position swaps within a partition. Energy explicitly prices crossings.
    const incident = new Map(nodes.map((p) => [p.id, []]));
    calls.forEach((e, i) => {
      incident.get(e[0]).push(i);
      incident.get(e[1]).push(i);
    });
    function localEnergy(a, b) {
      const affected = new Set([...incident.get(a.id), ...incident.get(b.id)]);
      let cost = 0;
      for (const i of affected) {
        const [u, v, w] = calls[i],
          p = byId.get(u),
          q = byId.get(v);
        cost += Math.hypot(p.x - q.x, p.y - q.y) * Math.sqrt(w) * 0.03;
        for (let j = 0; j < calls.length; j++) {
          if (j === i || (affected.has(j) && j < i)) continue;
          const [x, y] = calls[j];
          if (u === x || u === y || v === x || v === y) continue;
          if (cross(p, q, byId.get(x), byId.get(y))) cost += 9;
        }
      }
      return cost;
    }
    const preAnneal = quality(nodes, calls, byId),
      bestPositions = () => nodes.map((p) => [p.x, p.y]);
    let saved = bestPositions(),
      bestScore = preAnneal.crossings * 9 + preAnneal.length * 0.03;
    const trials = Math.min(1500, nodes.length * 10);
    if (calls.length <= 1800) {
      for (let t = 0; t < trials; t++) {
        const a = nodes[Math.floor(random() * nodes.length)],
          same = nodes.filter((n) => n.group === a.group);
        if (same.length < 2) continue;
        const b = same[Math.floor(random() * same.length)];
        if (a === b) continue;
        const before = localEnergy(a, b);
        [a.x, b.x] = [b.x, a.x];
        [a.y, b.y] = [b.y, a.y];
        const after = localEnergy(a, b),
          temp = 3 * (1 - t / trials);
        if (
          after > before &&
          random() > Math.exp((before - after) / Math.max(0.01, temp))
        ) {
          [a.x, b.x] = [b.x, a.x];
          [a.y, b.y] = [b.y, a.y];
        }
        if (t % 80 === 0) {
          const q = quality(nodes, calls, byId),
            score = q.crossings * 9 + q.length * 0.03;
          if (score < bestScore) {
            bestScore = score;
            saved = bestPositions();
          }
        }
      }
      const q = quality(nodes, calls, byId);
      if (q.crossings * 9 + q.length * 0.03 < bestScore)
        saved = bestPositions();
      nodes.forEach((p, i) => ([p.x, p.y] = saved[i]));
    }
    // Separate label boxes after the spring stage; swapping equal-width boxes preserves this.
    for (let step = 0; step < 100; step++) {
      let collisions = 0;
      for (let i = 0; i < nodes.length; i++)
        for (let j = i + 1; j < nodes.length; j++) {
          const a = nodes[i],
            b = nodes[j];
          if (a.group !== b.group) continue;
          const dx = b.x - a.x,
            dy = b.y - a.y,
            ox = (a.width + b.width) / 2 + 12 - Math.abs(dx),
            oy = 31 - Math.abs(dy);
          if (ox > 0 && oy > 0) {
            collisions++;
            const f = oy * 0.51,
              sign = Math.sign(dy || j - i);
            a.y -= f * sign;
            b.y += f * sign;
          }
        }
      if (!collisions) break;
    }
    // Exact final sweep removes residual label overlaps without moving membership.
    regions.forEach((r, i) => {
      const ns = nodes.filter((n) => n.group === i).sort((a, b) => a.y - b.y);
      for (let a = 0; a < ns.length; a++)
        for (let b = 0; b < a; b++) {
          const p = ns[a],
            q = ns[b];
          if (
            Math.abs(p.x - q.x) < (p.width + q.width) / 2 + 12 &&
            p.y - q.y < 32
          )
            p.y = q.y + 32;
        }
    });
    // Expand boundaries around labels if separation needed extra room. Repack to prevent overlap.
    regions.forEach((r, i) => {
      const ns = nodes.filter((n) => n.group === i);
      if (!ns.length) return;
      const minY = Math.min(...ns.map((n) => n.y));
      if (minY < r.y + 95) {
        const shift = r.y + 95 - minY;
        ns.forEach((n) => (n.y += shift));
      }
      r.h = Math.max(r.h, Math.max(...ns.map((n) => n.y)) - r.y + 35);
    });
    const finalPack = packing(best.order, best.columns);
    regions.forEach((r, i) => {
      const dx = finalPack.pos[i].x - r.x,
        dy = finalPack.pos[i].y - r.y;
      nodes
        .filter((n) => n.group === i)
        .forEach((n) => {
          n.x += dx;
          n.y += dy;
        });
      r.x += dx;
      r.y += dy;
    });
    return {
      nodes,
      regions,
      width: finalPack.W,
      height: finalPack.H,
      before: start,
      after: quality(nodes, calls, byId),
    };
  }
  function commonOwner(names) {
    const p = names[0].includes(".") ? names[0].split(".")[0] + "." : "";
    return p && names.every((n) => n.startsWith(p)) ? p : "";
  }
  function cross(a, b, c, d) {
    const side = (p, q, r) =>
      (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x);
    return (
      side(a, b, c) * side(a, b, d) < 0 && side(c, d, a) * side(c, d, b) < 0
    );
  }
  function quality(nodes, edges, byId = new Map(nodes.map((n) => [n.id, n]))) {
    let crossings = 0,
      length = 0,
      overlaps = 0;
    for (let i = 0; i < edges.length; i++) {
      const [a, b, w] = edges[i],
        p = byId.get(a),
        q = byId.get(b);
      length += Math.hypot(p.x - q.x, p.y - q.y) * Math.sqrt(w);
      for (let j = i + 1; j < edges.length; j++) {
        const [c, d] = edges[j];
        if (a === c || a === d || b === c || b === d) continue;
        if (cross(p, q, byId.get(c), byId.get(d))) crossings++;
      }
    }
    for (let i = 0; i < nodes.length; i++)
      for (let j = i + 1; j < nodes.length; j++) {
        const a = nodes[i],
          b = nodes[j];
        if (
          Math.abs(a.x - b.x) < (a.width + b.width) / 2 &&
          Math.abs(a.y - b.y) < 25
        )
          overlaps++;
      }
    return { crossings, length, overlaps };
  }
  return { solve, quality };
})();
if (typeof module !== "undefined") module.exports = GraphLayout;
