/* Inspection of constrained partitions; source evidence stays snapshot-bound. */
function privacyControls() {
  return `<label><input id="privacy-mode" type="checkbox" ${preservePrivacy ? "checked" : ""}> Preserve private interfaces</label><p class="note">Join every same-file caller to its static helper, transitively. Public callees do not bind groups. ${preservePrivacy ? "Size balance cannot split these components." : "Unconstrained mode can expose static helpers."}</p>`;
}
function sourceOrder(a, b) {
  return (
    D.functions[a].f - D.functions[b].f || D.functions[a].o - D.functions[b].o
  );
}
function memberRows(members) {
  return members
    .slice()
    .sort(
      (a, b) =>
        D.functions[a].f - D.functions[b].f ||
        D.functions[a].o - D.functions[b].o,
    )
    .map((v) => {
      const f = D.functions[v];
      return `<div class="connection"><span>${f.k ? "TOP" : f.s ? "static" : "public"}</span><button data-source="${v}">${esc(f.n)}</button><small>order ${f.o}</small></div>`;
    })
    .join("");
}
function edgeRows(title, edges) {
  return `<details><summary>${title}: ${edges.length} pairs / ${edges.reduce((n, e) => n + e[2], 0)} call sites</summary>${edges.map(([a, b, w]) => `<div class="connection"><button data-source="${a}">${esc(D.functions[a].n)}</button><span> &rarr; </span><button data-source="${b}">${esc(D.functions[b].n)}</button><b>${w}</b></div>`).join("") || "None"}</details>`;
}
function coverageRows(m) {
  return `${edgeRows("Static targets crossing proposed groups", m.privateEdges)}${edgeRows("Existing public targets crossing proposed groups", m.publicEdges)}${edgeRows("Static calls across the inspected scope", m.outsidePrivate)}${edgeRows("Top-level references (including outside scope)", m.topEdges)}<p>${m.unresolved} unresolved/external call sites; ${m.indirect} indirect call sites.</p><p class="note">Zero static crossings is a resolved-call result. Callbacks, unresolved calls, private macros, private types, and file-local state still require source inspection. Open a function to read the snapshot's full source and section comments.</p>`;
}
function wireSourceButtons() {
  $("source-content")
    .querySelectorAll("[data-source]")
    .forEach((e) => (e.onclick = () => showSource(+e.dataset.source)));
}
function showDecomposition(
  parts,
  title,
  allMembers = parts.flat(),
  names = [],
) {
  const m = Engine.decomposition(D, parts),
    all = Engine.decomposition(D, [allMembers]);
  $("source-content").innerHTML =
    `<div class="paneltag">${esc(title)}</div><h2>${parts.length} groups / ${m.authored} authored functions / ${m.topLevel.length} top-level nodes</h2><p>${m.pairs} crossing pairs; ${m.calls} crossing call sites; ${m.privateTargets} distinct static targets crossing.</p>${coverageRows({ ...m, topEdges: all.topEdges })}<p class="note">Inspected top-level nodes: ${all.topLevel.length}; ${all.topLevel.reduce((n, v) => n + (D.functions[v].x || 0), 0)} unresolved/external and ${all.topLevel.reduce((n, v) => n + (D.functions[v].i || 0), 0)} indirect call sites. These require separate extraction review.</p>${parts.map((members, i) => `<details><summary>${esc(names[i] || "Group " + (i + 1))}: ${members.filter((v) => !D.functions[v].k && !D.functions[v].s).length} public / ${members.filter((v) => !D.functions[v].k && D.functions[v].s).length} static / ${members.filter((v) => D.functions[v].k).length} top-level</summary>${memberRows(members)}</details>`).join("")}`;
  wireSourceButtons();
  $("source").showModal();
}
async function showReference(g) {
  const r = await (
    await fetch("fixtures/compiler-responsibilities.json")
  ).json();
  if (
    !r.revision.startsWith(D.revision) ||
    !g.members.some((v) => D.files[D.functions[v].f].id === r.file)
  ) {
    toast(
      `Reference requires ${r.file} at ${r.revision.slice(0, 8)}; current snapshot is ${D.revision}.`,
    );
    return;
  }
  const ids = new Map(
    D.functions.map((f, v) => [D.files[f.f].id + "::" + f.e, v]),
  );
  const parts = r.groups.map((g) =>
    g.functions.map((f) => ids.get(r.file + "::" + f.e)),
  );
  if (parts.flat().some((v) => v === undefined)) {
    toast("Reference function identities do not match this snapshot.");
    return;
  }
  const all = D.functions.flatMap((f, v) =>
    D.files[f.f].id === r.file ? [v] : [],
  );
  showDecomposition(
    parts,
    "Source-informed reference (not inferred)",
    all,
    r.groups.map((g) => g.name),
  );
  const intro = document.createElement("p");
  intro.textContent =
    r.provenance +
    ` Revision ${r.revision}. Synthetic top-level nodes are excluded from the eight assignments; their references are reported above.`;
  $("source-content").prepend(intro);
  const section = document.createElement("details");
  section.innerHTML = `<summary>Reference source sections and line evidence</summary>${r.groups.flatMap((g) => g.functions.map((f) => `<div class="connection">${esc(f.n)} &middot; ${esc(f.section)} &middot; line ${f.line}</div>`)).join("")}`;
  $("source-content").append(section);
}
function showComponents(g) {
  const components = Engine.atoms(g.members, [...S.ties, ...privacyComponents])
      .map((c) => c.sort(sourceOrder))
      .sort((a, b) => sourceOrder(a[0], b[0])),
    selectedComponents = new Set();
  const fullMembers = new Set(g.members),
    missing = new Set(),
    blocked = new Set();
  for (const c of Engine.atoms(
    D.functions.map((_, v) => v),
    [...S.ties, ...privacyComponents],
  )) {
    if (
      !c.some((v) => fullMembers.has(v)) ||
      c.every((v) => fullMembers.has(v))
    )
      continue;
    for (const v of c) if (!fullMembers.has(v)) missing.add(v);
    components.forEach((part, i) => {
      if (part.some((v) => c.includes(v))) blocked.add(i);
    });
  }
  $("source-content").innerHTML =
    `<div class="paneltag">PRIVATE-INTERFACE COMPONENTS</div><h2>${esc(g.name)}: ${components.length} components</h2><p>${g.members.filter((v) => !D.functions[v].k).length} authored functions; ${g.members.filter((v) => D.functions[v].k).length} synthetic top-level nodes. Ordered by source order; expand to inspect actual names and source.</p><p>${missing.size} linked functions already live outside this group. ${missing.size ? "Partial components are disabled; combine their groups first. Complete components remain available." : "Components constrain legal partitions; names and source determine responsibilities."}</p><label>New group name <input id="semantic-name" value="semantic-group.x"></label><button id="combine-components" disabled>Combine selected components</button><button id="reference">Compare source-informed reference</button>${components.map((c, i) => `<section><label><input type="checkbox" data-component="${i}" ${blocked.has(i) ? "disabled" : ""}> ${blocked.has(i) ? "Partial component (linked outside)" : "Component"} ${i + 1} (${c.length} nodes)</label><details><summary>${esc(D.functions[c[0]].n)}${c.length > 1 ? " + " + (c.length - 1) : ""}</summary>${memberRows(c)}</details></section>`).join("")}`;
  $("reference").onclick = () => showReference(g);
  $("source-content")
    .querySelectorAll("[data-component]")
    .forEach(
      (e) =>
        (e.onchange = () => {
          e.checked
            ? selectedComponents.add(+e.dataset.component)
            : selectedComponents.delete(+e.dataset.component);
          $("combine-components").disabled = !selectedComponents.size;
        }),
    );
  $("combine-components").onclick = () => {
    const members = [...selectedComponents].flatMap((i) => components[i]),
      name = $("semantic-name").value.trim() || "semantic-group.x";
    $("source").close();
    change("Combined privacy components", () => {
      const moved = new Set(members);
      S.groups = S.groups.map((x) => ({
        ...x,
        members: x.members.filter((v) => !moved.has(v)),
      }));
      S.groups.push({
        id: "semantic-" + Date.now() + "-" + ++serial,
        name,
        members,
      });
    });
  };
  wireSourceButtons();
  $("source").showModal();
}
function showSource(v) {
  const previous = [...$("source-content").childNodes];
  const f = D.functions[v],
    file = D.files[f.f];
  $("source-content").innerHTML =
    `<div class="paneltag">SNAPSHOT SOURCE ${esc(D.revision)}</div><h2>${esc(f.n)}</h2><p>${esc(file.id)} &middot; source order ${f.o}. Exact definition range unavailable; search matches can include declarations and uses.</p><label>Find in source <input id="source-find" value="${esc(f.n)}"></label><button id="source-next">Next match</button><span id="source-matches"></span><div class="source-lines">${
      file.source === undefined
        ? "Source text unavailable in this snapshot. Regenerate graph data."
        : file.source
            .split("\n")
            .map(
              (line, i) =>
                `<div data-line="${i + 1}"><small>${i + 1}</small><code>${esc(line) || " "}</code></div>`,
            )
            .join("")
    }</div>`;
  if (previous.length && $("source").open) {
    const back = document.createElement("button");
    back.textContent = "Back to inspection";
    back.onclick = () => $("source-content").replaceChildren(...previous);
    $("source-content").prepend(back);
  }
  let matchIndex = -1;
  const find = () => {
    const q = $("source-find").value,
      rows = [...$("source-content").querySelectorAll("[data-line]")],
      matches = rows.filter(
        (e) => q && e.querySelector("code").textContent.includes(q),
      );
    rows.forEach((e) => e.classList.remove("source-match"));
    matches.forEach((e) => e.classList.add("source-match"));
    matchIndex = matches.length ? (matchIndex + 1) % matches.length : -1;
    $("source-matches").textContent = ` ${matches.length} matching lines`;
    matches[matchIndex]?.scrollIntoView({ block: "center" });
  };
  $("source-next").onclick = find;
  $("source-find").onchange = () => {
    matchIndex = -1;
    find();
  };
  $("source").showModal();
  find();
}
