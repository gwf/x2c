/* Evidence-backed assignments. Components constrain translation units, not responsibilities. */
const Responsibilities = (() => {
  const key = (data, v) =>
    data.files[data.functions[v].f].id + ":" + data.functions[v].e;
  function create(data, members) {
    return {
      format: "partition-responsibilities-v1",
      revision: data.revision,
      scope: members.map((v) => key(data, v)),
      operations: {},
      responsibilities: [],
      constraints: [],
      references: [],
      resolutions: {},
      history: [],
      coverage: "",
    };
  }
  function analyze(data, manifest, ties = []) {
    if (
      manifest.format !== "partition-responsibilities-v1" ||
      !Array.isArray(manifest.scope) ||
      !Array.isArray(manifest.responsibilities) ||
      !Array.isArray(manifest.constraints) ||
      !Array.isArray(manifest.references) ||
      !manifest.operations ||
      !manifest.resolutions ||
      !Array.isArray(manifest.history)
    )
      throw Error("Incomplete responsibility manifest.");
    if (
      manifest.responsibilities.some(
        (r) => typeof r.id !== "string" || !r.id.trim(),
      ) ||
      new Set(manifest.responsibilities.map((r) => r.id)).size !==
        manifest.responsibilities.length
    )
      throw Error("Duplicate responsibility IDs.");
    const ids = new Map(data.functions.map((_, v) => [key(data, v), v]));
    const members = manifest.scope.map((k) => ids.get(k));
    if (
      manifest.revision !== data.revision ||
      members.some((v) => v === undefined) ||
      new Set(members).size !== members.length
    )
      throw Error("Manifest snapshot or function membership does not match.");
    const inside = new Set(members),
      adjacency = data.functions.map(() => []),
      relations = [];
    const bind = (a, b, kind) => {
      relations.push([a, b]);
      adjacency[a].push({ v: b, kind });
      adjacency[b].push({ v: a, kind });
    };
    for (const [a, b] of Engine.privacyTies(data)) bind(a, b, "static call");
    for (const r of [...(data.references || []), ...manifest.references]) {
      const a = typeof r.from === "number" ? r.from : ids.get(r.from),
        b = typeof r.to === "number" ? r.to : ids.get(r.to);
      if (a === undefined || b === undefined)
        throw Error("Reference has an unknown endpoint.");
      if (data.functions[b].s && data.functions[a].f === data.functions[b].f)
        bind(a, b, "function value: " + (r.evidence || "exported reference"));
    }
    for (const c of manifest.constraints) {
      if (
        !["unresolved", "reviewed", "keep-together"].includes(c.status) ||
        !c.evidence?.trim()
      )
        throw Error("Constraint requires a decision and source evidence.");
      if (
        c.status === "keep-together" &&
        (!Array.isArray(c.functions) || c.functions.length < 2)
      )
        throw Error(
          "Keep-together constraints require at least two functions.",
        );
      const affected = (c.functions || []).map((k) => ids.get(k));
      if (affected.some((v) => v === undefined))
        throw Error("Constraint has an unknown function.");
      if (c.status === "keep-together")
        for (const v of affected.slice(1))
          bind(affected[0], v, c.kind + ": " + c.symbol);
    }
    for (const t of ties)
      for (const v of t.slice(1)) bind(t[0], v, "explicit keep-together");
    const all = Engine.atoms(
      data.functions.map((_, v) => v),
      relations,
    );
    const labels = new Map(manifest.responsibilities.map((r) => [r.id, r]));
    const operation = (v) => manifest.operations[key(data, v)];
    const roleComplete = (id) =>
      labels.has(id) &&
      ["name", "description", "evidence"].every(
        (k) =>
          typeof labels.get(id)[k] === "string" && labels.get(id)[k].trim(),
      );
    const complete = (v) => {
      const o = operation(v);
      return (
        o &&
        ["operation", "state", "phase", "section", "evidence"].every(
          (k) => typeof o[k] === "string" && o[k].trim(),
        ) &&
        roleComplete(o.responsibility)
      );
    };
    const path = (a, b) => {
      const queue = [a],
        seen = new Map([[a, null]]);
      for (let i = 0; i < queue.length && !seen.has(b); i++)
        for (const e of adjacency[queue[i]])
          if (!seen.has(e.v)) {
            seen.set(e.v, { from: queue[i], kind: e.kind });
            queue.push(e.v);
          }
      const steps = [];
      for (let v = b; v !== a; ) {
        const e = seen.get(v);
        if (!e) return [];
        steps.unshift({ from: e.from, to: v, kind: e.kind });
        v = e.from;
      }
      return steps;
    };
    const components = all
      .filter((c) => c.some((v) => inside.has(v)))
      .map((c) => {
        const local = c
          .filter((v) => inside.has(v))
          .sort((a, b) => data.functions[a].o - data.functions[b].o);
        const id =
          "component:" +
          c
            .map((v) => key(data, v))
            .sort()
            .join("|");
        const publicOps = local.filter(
          (v) => !data.functions[v].s && !data.functions[v].k,
        );
        const roles = [
          ...new Set(
            publicOps
              .map((v) => operation(v)?.responsibility)
              .filter((id) => labels.has(id)),
          ),
        ];
        const attachment = manifest.resolutions[id];
        if (
          !publicOps.length &&
          labels.has(attachment?.responsibility) &&
          attachment?.reason?.trim()
        )
          roles.push(attachment.responsibility);
        const conflicts = [];
        for (let i = 0; i < roles.length; i++)
          for (let j = i + 1; j < roles.length; j++) {
            const a = publicOps.find(
                (v) => operation(v)?.responsibility === roles[i],
              ),
              b = publicOps.find(
                (v) => operation(v)?.responsibility === roles[j],
              );
            conflicts.push({ a, b, path: path(a, b) });
          }
        const helperOnly = !publicOps.length;
        const resolution = manifest.resolutions[id];
        const unresolved =
          c.length !== local.length ||
          publicOps.some((v) => !complete(v)) ||
          !roles.length ||
          roles.some((id) => !roleComplete(id)) ||
          (roles.length > 1 &&
            (resolution?.kind !== "module" || !resolution.reason?.trim())) ||
          (helperOnly && !resolution?.reason?.trim());
        return {
          id,
          members: local,
          publicOps,
          helpers: local.filter((v) => data.functions[v].s),
          roles,
          conflicts,
          outside: c.filter((v) => !inside.has(v)),
          unresolved,
          helperOnly,
        };
      });
    // Responsibilities sharing any private component stay in one translation unit.
    const roleIndex = new Map(
      manifest.responsibilities.map((r, i) => [r.id, i]),
    );
    const roleBlocks = Engine.atoms(
      [...roleIndex.values()],
      components.map((c) => c.roles.map((r) => roleIndex.get(r))),
    );
    const roleUnit = new Map();
    roleBlocks.forEach((block, i) =>
      block.forEach((r) => roleUnit.set(manifest.responsibilities[r].id, i)),
    );
    const units = new Map();
    for (const c of components) {
      const unit = c.unresolved
        ? "unresolved:" + c.id
        : "unit:" + roleUnit.get(c.roles[0]);
      if (!units.has(unit))
        units.set(unit, {
          id: unit,
          members: [],
          components: [],
          roles: [],
          classification: c.unresolved
            ? "Unassigned or unresolved"
            : "Separate translation-unit candidate",
        });
      const u = units.get(unit);
      u.members.push(...c.members);
      u.components.push(c.id);
      u.roles = [...new Set([...u.roles, ...c.roles])];
    }
    const results = [...units.values()].map((u) => {
      const unresolvedConstraints = manifest.constraints.filter(
        (c) =>
          c.status === "unresolved" &&
          (!c.functions?.length ||
            c.functions.some((k) => u.members.includes(ids.get(k)))),
      );
      return {
        ...u,
        name:
          u.roles.map((r) => labels.get(r).name).join(" / ") || "Unassigned",
        unresolvedConstraints,
        classification:
          u.classification === "Unassigned or unresolved" ||
          !manifest.coverage?.trim() ||
          unresolvedConstraints.length
            ? "Unassigned or unresolved"
            : u.classification,
        moduleMembers:
          u.roles.length > 1
            ? u.roles.map((r) => ({
                responsibility: r,
                classification: "Module-member candidate",
              }))
            : [],
      };
    });
    const assigned = results.flatMap((u) => u.members);
    const valid =
      assigned.length === members.length &&
      new Set(assigned).size === members.length;
    const metrics = Engine.decomposition(
      data,
      results.map((u) => u.members),
    );
    return {
      members,
      components,
      units: results,
      metrics,
      valid,
      unreviewed: members.filter(
        (v) => !data.functions[v].s && !data.functions[v].k && !complete(v),
      ),
      unresolvedConstraints: manifest.constraints.filter(
        (c) => c.status === "unresolved",
      ),
      canApply:
        valid &&
        !results.some((u) => u.classification === "Unassigned or unresolved") &&
        !components.some((c) => c.unresolved) &&
        !metrics.privateEdges.length &&
        !metrics.outsidePrivate.length,
    };
  }
  function merge(manifest, ids, name, description, reason, componentIds) {
    if (!name.trim() || !description.trim() || !reason.trim() || ids.length < 2)
      throw Error(
        "Name, description, reason, and two responsibilities are required.",
      );
    const id = ids[0];
    manifest.responsibilities = manifest.responsibilities
      .filter((r) => !ids.includes(r.id) || r.id === id)
      .map((r) =>
        r.id === id ? { ...r, name, description, evidence: reason } : r,
      );
    if (manifest.moduleArrangement) {
      const combined = manifest.moduleArrangement.filter(g => ids.includes(g.responsibility));
      manifest.moduleArrangement = manifest.moduleArrangement.filter(g => !ids.includes(g.responsibility));
      if (combined.length) manifest.moduleArrangement.push({responsibility:id,
        members:combined.flatMap(g => g.members), evidence:reason});
    }
    for (const o of Object.values(manifest.operations))
      if (ids.includes(o.responsibility)) o.responsibility = id;
    for (const resolution of Object.values(manifest.resolutions))
      if (ids.includes(resolution.responsibility))
        resolution.responsibility = id;
    manifest.history.push({
      action: "merge responsibilities",
      components: componentIds,
      responsibilities: ids,
      name,
      reason,
    });
  }
  function moduleUnits(data, manifest) {
    if (!manifest.moduleArrangement) return null;
    const ids = new Map(data.functions.map((_, v) => [key(data, v), v]));
    const roles = new Map(manifest.responsibilities.map(r => [r.id, r]));
    const assigned = manifest.moduleArrangement.flatMap(g => g.members);
    if (assigned.length !== manifest.scope.length || new Set(assigned).size !== assigned.length ||
        assigned.some(k => !manifest.scope.includes(k)))
      throw Error('Module arrangement must assign every function exactly once.');
    return manifest.moduleArrangement.map(g => {
      const r = roles.get(g.responsibility);
      if (!r || !g.evidence?.trim()) throw Error('Module ownership requires a responsibility and evidence.');
      return {id:r.id, name:r.name, description:r.description, evidence:g.evidence,
        extraction:g.extraction || "", members:g.members.map(k => ids.get(k)), classification:'Module-member candidate (same translation unit)', moduleMembers:[]};
    });
  }
  return { key, create, analyze, merge, moduleUnits };
})();
if (typeof module !== "undefined") module.exports = Responsibilities;
