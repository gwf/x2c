/* Inspection of constrained partitions; source evidence stays snapshot-bound. */
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
      return `<div class="connection"><span>${f.k ? "TOP" : f.v}</span><button data-source="${v}">${esc(f.n)}</button><small>order ${f.o}</small></div>`;
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
function showSource(v) {
  const previous = [...$("source-content").childNodes];
  const f = D.functions[v],
    file = D.files[f.f],
    path = f.p || file.id,
    source = path === file.id ? file.source : file.members?.[path];
  $("source-content").innerHTML =
    `<div class="paneltag">SNAPSHOT SOURCE ${esc(D.revision)}</div><h2>${esc(f.n)}</h2><p>${esc(path)}${path === file.id ? "" : ` in ${esc(file.id)}`} &middot; source order ${f.o}. Exact definition range unavailable; search matches can include declarations and uses.</p><label>Find in source <input id="source-find" value="${esc(f.n)}"></label><button id="source-next">Next match</button><span id="source-matches"></span><div class="source-lines">${
      source === undefined
        ? "Source text unavailable in this snapshot. Regenerate graph data."
        : source
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
