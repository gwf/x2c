/* Main decomposition workflow. The graph remains an inspection surface. */
let responsibilityKey = null;
const responsibilityJobs = new Map();
function responsibilityManifest() {
  S.responsibilities ||= {};
  responsibilityKey = scope.members
    .map((v) => Responsibilities.key(D, v))
    .sort()
    .join("|");
  return (S.responsibilities[responsibilityKey] ||= Responsibilities.create(
    D,
    scope.members,
  ));
}
function recordResponsibility(action, detail) {
  const m = responsibilityManifest();
  m.history.push({ action, ...detail });
  save();
  render();
}
function responsibilityDialog(html, wire) {
  $("source-content").innerHTML = html;
  wire();
  wireSourceButtons();
  $("source").showModal();
}
function renderResponsibilities() {
  graphWorker?.terminate();
  graphResize?.disconnect();
  ++graphGeneration;
  const m = responsibilityManifest(),
    a = Responsibilities.analyze(D, m, S.ties),
    labels = new Map(m.responsibilities.map((r) => [r.id, r]));
  $("workspace").classList.remove("graph-workspace");
  $("workspace").innerHTML =
    `<div class="responsibility-workspace"><p>Inspect a source-informed proposal, then adjust the responsibilities.</p><div class="responsibility-actions"><button id="show-arrangement" class="primary" ${m.responsibilities.length ? "" : "hidden"}>Show proposed arrangement</button><button id="analyze-source">Analyze source</button><span id="analysis-status" role="status"></span></div><details class="analysis-tools"><summary>Evidence, saved analyses, and manifests</summary><div class="responsibility-actions"><button id="import-responsibilities">Import manifest</button><button id="export-responsibilities">Export manifest</button></div></details><p>${a.unreviewed.length ? `${a.unreviewed.length} public operations await agent analysis.` : "Public operations have source evidence."} ${a.components.length} private dependency components. ${m.constraints.length} non-function constraints.</p>
    <details class="workflow-stage" data-stage="operations"><summary>Public operations (${a.members.filter((v) => !D.functions[v].s && !D.functions[v].k).length})</summary><div class="operation-list">${a.members
      .filter((v) => !D.functions[v].s && !D.functions[v].k)
      .map((v) => {
        const o = m.operations[Responsibilities.key(D, v)];
        return `<button class="operation-row" data-operation="${v}"><strong>${esc(D.functions[v].n)}</strong><span>${esc(o?.operation || "Awaiting source analysis")}</span><small>${esc(labels.get(o?.responsibility)?.name || "Unassigned")}</small></button>`;
      })
      .join("")}</div></details>
    <details class="workflow-stage" data-stage="responsibilities"><summary>Responsibilities and attached helpers</summary><div class="responsibility-actions"><button id="add-responsibility">New responsibility</button><button id="merge-responsibilities">Combine responsibilities</button></div>${
      m.responsibilities
        .map((r) => {
          const ops = a.members.filter(
              (v) =>
                m.operations[Responsibilities.key(D, v)]?.responsibility ===
                r.id,
            ),
            cs = a.components.filter((c) => c.roles.includes(r.id));
          return `<section><h3>${esc(r.name)} <button data-edit-role="${esc(r.id)}">Edit</button></h3><p>${esc(r.description)}</p><p class="note">Evidence: ${esc(r.evidence)}</p><p>${ops.length} public operations; ${new Set(cs.flatMap((c) => c.helpers)).size} attached helpers; ${cs.filter(c => c.roles.length > 1).length} shared dependency components.</p>${m.constraints.filter(c => c.status === "unresolved" && (!c.functions?.length || cs.some(component => component.members.some(v => c.functions.includes(Responsibilities.key(D, v)))))).map(c => `<p class="hint">Unresolved ${esc(c.kind)}: ${esc(c.symbol)}. ${esc(c.evidence)}</p>`).join("")}<details><summary>Operations and helpers</summary>${memberRows([...new Set([...ops, ...cs.flatMap((c) => c.helpers)])])}</details></section>`;
        })
        .join("") ||
      "<p>Select Analyze source to have the agent read this scope and propose responsibility groups. You do not need to describe functions or create groups first.</p>"
    }</details>
    <details class="workflow-stage" data-stage="components"><summary>Shared dependencies and boundary decisions</summary><button id="dependency-review">Dependency constraints</button>${
      a.components
        .filter((c) => c.conflicts.length || c.unresolved || c.helperOnly)
        .map(
          (c) =>
            `<section><h3>Component: ${esc(D.functions[c.members[0]].n)} (${c.members.length} functions)</h3><p>${c.outside.length ? "Linked functions outside this scope: " + c.outside.map((v) => esc(D.functions[v].n)).join(", ") : ""}</p><p>${c.roles.map((r) => esc(labels.get(r).name)).join(" / ") || "No public responsibility assigned"}</p><details ${c.conflicts.length ? "" : "hidden"}><summary>${c.conflicts.length} helper paths connecting responsibilities</summary><p class="note">These are undirected keep-together paths, not execution order.</p>${c.conflicts.map((x) => `<p class="helper-path">${esc(D.functions[x.a].n)} joins ${esc(D.functions[x.b].n)}:<br>${x.path.map((s) => `${esc(D.functions[s.from].n)} &harr; ${esc(D.functions[s.to].n)} <small>(${esc(s.kind)})</small>`).join("<br>")}</p>`).join("")}</details><p>${esc(m.resolutions[c.id]?.reason || "A boundary decision is needed.")}</p><button data-resolve="${a.components.indexOf(c)}">${c.helperOnly ? "Explain and attach this component" : "Resolve or inspect component"}</button></section>`,
        )
        .join("") || "<p>Each component has one documented responsibility.</p>"
    }</details>
    <details class="workflow-stage" data-stage="proposal"><summary>Assignment details</summary><p>${a.valid ? "Every function is assigned exactly once." : "Assignment error."} ${a.metrics.privateEdges.length} static crossing pairs; ${a.metrics.publicEdges.length} existing public crossing pairs (${a.metrics.publicEdges.reduce((n, e) => n + e[2], 0)} call sites).</p><p>${a.metrics.unresolved} unresolved/external calls; ${a.metrics.indirect} indirect calls. ${a.unresolvedConstraints.length} unresolved non-function constraints.</p><p class="note">${esc(m.coverage)}</p>${a.units.map((u) => `<section><h3>${esc(u.name)}</h3><p>${esc(u.classification)}: ${u.members.length} functions</p>${u.moduleMembers.map((r) => `<p>Module-member candidate: ${esc(labels.get(r.responsibility).name)} (retained in this translation unit)</p>`).join("")}<details><summary>Exact membership</summary>${memberRows(u.members)}</details></section>`).join("")}<p class="hint">Candidates are not extraction proofs. Private types, macros, file-local state, function values, and unresolved uses must be reviewed before moving source.</p><button id="preview-responsibilities" ${a.valid ? "" : "disabled"}>Preview responsibility arrangement</button></details>
    <details><summary>Assignment and merge history (${m.history.length})</summary>${m.history.map((h) => `<p><strong>${esc(h.action)}</strong>: ${esc(h.reason || h.name || "")}<br><small>${esc((h.components || []).join("\n"))}</small></p>`).join("") || "No decisions recorded."}</details></div>`;
  document
    .querySelectorAll("[data-operation]")
    .forEach((e) => (e.onclick = () => editOperation(+e.dataset.operation)));
  document
    .querySelectorAll("[data-edit-role]")
    .forEach((e) => (e.onclick = () => editResponsibility(e.dataset.editRole)));
  document
    .querySelectorAll("[data-resolve]")
    .forEach(
      (e) =>
        (e.onclick = () =>
          resolveResponsibilityComponent(a.components[+e.dataset.resolve])),
    );
  document.querySelectorAll("#workspace [data-source]").forEach(
    (e) =>
      (e.onclick = () => {
        showSource(+e.dataset.source);
        $("source").showModal();
      }),
  );
  $("show-arrangement").onclick = () => previewResponsibilities(m, a);
  $("analyze-source").onclick = analyzeResponsibilitySource;
  updateResponsibilityJob();
  $("add-responsibility").onclick = () => editResponsibility();
  $("merge-responsibilities").onclick = mergeResponsibilities;
  $("dependency-review").onclick = editDependencyConstraints;
  $("export-responsibilities").onclick = () =>
    downloadResponsibilityManifest(m, a);
  $("import-responsibilities").onclick = importResponsibilityManifest;
  $("preview-responsibilities").onclick = () => previewResponsibilities(m, a);
}
function roleOptions(m, selected) {
  return (
    '<option value="">Unassigned</option>' +
    m.responsibilities
      .map(
        (r) =>
          `<option value="${esc(r.id)}" ${selected === r.id ? "selected" : ""}>${esc(r.name)}</option>`,
      )
      .join("")
  );
}
function editOperation(v) {
  const m = responsibilityManifest(),
    k = Responsibilities.key(D, v),
    o = m.operations[k] || {},
    callers = D.edges.filter((e) => e[1] === v).map((e) => e[0]),
    component = Responsibilities.analyze(D, m, S.ties).components.find((c) =>
      c.members.includes(v),
    );
  responsibilityDialog(
    `<h2>${esc(D.functions[v].n)}</h2><p>Read the body and relevant callers before describing this operation.</p><button data-source="${v}">Read source</button><details><summary>Private dependency component (${component.members.length} functions)</summary>${memberRows(component.members)}</details><details><summary>Resolved callers (${callers.length})</summary>${memberRows(callers)}</details><form id="operation-form">${[
      ["operation", "Operation performed"],
      ["state", "Object or state owned"],
      ["phase", "Phase or lifecycle"],
      ["section", "Source section"],
      ["evidence", "Body and caller evidence (include source lines)"],
    ]
      .map(
        ([id, label]) =>
          `<label>${label}<textarea name="${id}" required>${esc(o[id] || "")}</textarea></label>`,
      )
      .join(
        "",
      )}<label>Responsibility<select name="responsibility">${roleOptions(m, o.responsibility)}</select></label><button>Save operation</button></form>`,
    () => {
      $("operation-form").onsubmit = (e) => {
        e.preventDefault();
        m.operations[k] = Object.fromEntries(new FormData(e.target));
        $("source").close();
        recordResponsibility("describe operation", {
          name: D.functions[v].n,
          reason: m.operations[k].evidence,
        });
      };
    },
  );
}
function editResponsibility(id) {
  const m = responsibilityManifest(),
    r = m.responsibilities.find((r) => r.id === id) || {};
  responsibilityDialog(
    `<h2>${id ? "Edit" : "Name a"} responsibility</h2><form id="role-form">${[
      ["name", "Responsibility name"],
      ["description", "One sentence describing its work"],
      ["evidence", "Source behavior supporting this responsibility"],
    ]
      .map(
        ([k, l]) =>
          `<label>${l}<textarea name="${k}" required>${esc(r[k] || "")}</textarea></label>`,
      )
      .join("")}<button>Save responsibility</button></form>`,
    () => {
      $("role-form").onsubmit = (e) => {
        e.preventDefault();
        const values = Object.fromEntries(new FormData(e.target));
        if (id) Object.assign(r, values);
        else
          m.responsibilities.push({
            id: "responsibility-" + Date.now(),
            ...values,
          });
        $("source").close();
        recordResponsibility("name responsibility", {
          name: values.name,
          reason: values.evidence,
        });
      };
    },
  );
}
function resolveResponsibilityComponent(c) {
  const m = responsibilityManifest();
  responsibilityDialog(
    `<h2>Private dependency component</h2>${memberRows(c.members)}<p>${c.outside.length ? "This component extends outside the view. Open a scope containing all linked functions before proposing a split." : ""}</p><form id="resolve-form"><label>Decision<select name="kind">${c.helperOnly ? '<option value="attach">Attach helpers or initialization to a responsibility</option>' : '<option value="module">Retain responsibilities as module members in one translation unit</option><option value="merge">Merge these responsibilities under a broader name</option>'}</select></label>${c.helperOnly ? `<label>Responsibility<select name="responsibility" required>${roleOptions(m, "")}</select></label>` : '<label>Broader name (for a merge)<input name="name"></label><label>Work performed (for a merge)<textarea name="description"></textarea></label>'}<label>${c.helperOnly ? "How execution reaches this component and symbols remain accessible" : "Concrete reason for this decision"}<textarea name="reason" required></textarea></label><button>Record decision</button><p id="resolve-error"></p></form>`,
    () => {
      $("resolve-form").onsubmit = (e) => {
        e.preventDefault();
        const r = Object.fromEntries(new FormData(e.target));
        try {
          if (r.kind === "merge")
            Responsibilities.merge(
              m,
              c.roles,
              r.name,
              r.description,
              r.reason,
              [c.id],
            );
          else {
            m.resolutions[c.id] = r;
            m.history.push({
              action:
                r.kind === "module"
                  ? "retain module members"
                  : "attach component",
              components: [c.id],
              reason: r.reason,
            });
          }
          $("source").close();
          save();
          openResponsibilityResult();
        } catch (error) {
          $("resolve-error").textContent = error.message;
        }
      };
    },
  );
}
function editDependencyConstraints() {
  const m = responsibilityManifest();
  responsibilityDialog(
    `<h2>Private dependencies and coverage</h2><p>Resolved calls already constrain components. Add known function-value references and private declarations below. Unresolved constraints block completed extraction proposals.</p>${m.constraints.map((c, i) => `<section><strong>${esc(c.kind)}: ${esc(c.symbol)}</strong><p>${esc(c.evidence)}</p><p>${esc(c.recommendation || "")}</p><p>Status: ${esc(c.status)}</p><button data-edit-constraint="${i}">Review constraint</button></section>`).join("")}<details><summary>Function-value references (${m.references.length})</summary>${m.references.map((r) => `<p>${esc(r.from)} &rarr; ${esc(r.to)}<br>${esc(r.evidence)}</p>`).join("")}</details><button id="new-constraint">Add a dependency</button><form id="coverage-form"><label>Coverage review: what was checked and what remains unknown<textarea name="coverage" required>${esc(m.coverage)}</textarea></label><button>Save coverage review</button></form>`,
    () => {
      document
        .querySelectorAll("[data-edit-constraint]")
        .forEach(
          (e) => (e.onclick = () => editDependency(+e.dataset.editConstraint)),
        );
      $("new-constraint").onclick = () => editDependency();
      $("coverage-form").onsubmit = (e) => {
        e.preventDefault();
        m.coverage = new FormData(e.target).get("coverage");
        $("source").close();
        recordResponsibility("review coverage", { reason: m.coverage });
      };
    },
  );
}
function editDependency(index) {
  const m = responsibilityManifest(),
    c = m.constraints[index] || {},
    options = scope.members
      .map((v) => {
        const k = Responsibilities.key(D, v);
        return `<option value="${esc(k)}" ${(c.functions || []).includes(k) ? "selected" : ""}>${esc(D.functions[v].n)}</option>`;
      })
      .join("");
  $("source").close();
  responsibilityDialog(
    `<h2>${index === undefined ? "Add" : "Review"} dependency</h2><form id="dependency-form"><label>Kind<select name="kind">${["private-type", "macro", "file-local-state", "function-value", "other"].map((k) => `<option ${c.kind === k ? "selected" : ""}>${k}</option>`).join("")}</select></label><label>Symbol or declaration<input name="symbol" required value="${esc(c.symbol || "")}"></label><label>Source evidence and ownership decision<textarea name="evidence" required>${esc(c.evidence || "")}</textarea></label><label>Affected functions (select all consumers for a keep-together constraint)<select name="functions" multiple size="8">${options}</select></label><label>Decision<select name="status">${[
      ["unresolved", "Unresolved: ownership still needs review"],
      ["keep-together", "Keep selected functions in one translation unit"],
      ["reviewed", "Reviewed: no additional placement constraint"],
    ]
      .map(
        ([id, l]) =>
          `<option value="${id}" ${c.status === id ? "selected" : ""}>${l}</option>`,
      )
      .join(
        "",
      )}</select></label><fieldset><legend>For a function-value reference</legend><label>Referring function<select name="from"><option value="">Choose function</option>${options}</select></label><label>Static target<select name="to"><option value="">Choose helper</option>${options}</select></label></fieldset><button>Save dependency decision</button><p id="dependency-error"></p></form>`,
    () => {
      $("dependency-form").onsubmit = (e) => {
        e.preventDefault();
        try {
          const f = new FormData(e.target),
            next = clone(m),
            kind = f.get("kind"),
            evidence = f.get("evidence");
          if (kind === "function-value") {
            if (!f.get("from") || !f.get("to"))
              throw Error("Choose the referring function and static target.");
            const v = D.functions.findIndex(
              (_, v) => Responsibilities.key(D, v) === f.get("to"),
            );
            if (!D.functions[v].s)
              throw Error("The dependency target must be static.");
            next.references.push({
              from: f.get("from"),
              to: f.get("to"),
              evidence,
            });
            if (index !== undefined)
              next.constraints[index] = { ...c, status: "reviewed", evidence };
          } else {
            const value = {
              kind,
              symbol: f.get("symbol"),
              evidence,
              functions: f.getAll("functions"),
              status: f.get("status"),
            };
            if (value.status === "keep-together" && value.functions.length < 2)
              throw Error(
                "Choose at least two functions that must share this declaration.",
              );
            if (index === undefined) next.constraints.push(value);
            else next.constraints[index] = value;
          }
          Responsibilities.analyze(D, next, S.ties);
          Object.assign(m, next);
          $("source").close();
          recordResponsibility("review dependency", { reason: evidence });
        } catch (error) {
          $("dependency-error").textContent = error.message;
        }
      };
    },
  );
}
function mergeResponsibilities() {
  const m = responsibilityManifest(),
    a = Responsibilities.analyze(D, m, S.ties);
  responsibilityDialog(
    `<h2>Combine responsibilities by meaning</h2><p>Use a common task, state owner, or lifecycle. Existing public calls alone are not a reason to combine.</p><form id="merge-roles-form">${m.responsibilities.map((r) => `<label><span><input type="checkbox" name="roles" value="${esc(r.id)}"> ${esc(r.name)}</span></label>`).join("")}<label>Broader responsibility name<input name="name" required></label><label>One sentence describing the work<textarea name="description" required></textarea></label><label>Concrete source-based reason<textarea name="reason" required></textarea></label><button>Combine selected responsibilities</button><p id="merge-role-error"></p></form>`,
    () => {
      $("merge-roles-form").onsubmit = (e) => {
        e.preventDefault();
        const f = new FormData(e.target),
          ids = f.getAll("roles");
        try {
          Responsibilities.merge(
            m,
            ids,
            f.get("name"),
            f.get("description"),
            f.get("reason"),
            a.components
              .filter((c) => c.roles.some((r) => ids.includes(r)))
              .map((c) => c.id),
          );
          $("source").close();
          save();
          openResponsibilityResult();
        } catch (error) {
          $("merge-role-error").textContent = error.message;
        }
      };
    },
  );
}
function downloadResponsibilityManifest(m, a) {
  const out = {
    ...m,
    results: a.units.map((u) => ({
      ...u,
      members: u.members.map((v) => Responsibilities.key(D, v)),
    })),
    validation: {
      exactlyOnce: a.valid,
      staticCrossings: a.metrics.privateEdges,
      publicCrossings: a.metrics.publicEdges,
      unresolvedConstraints: a.unresolvedConstraints,
    },
  };
  const url = URL.createObjectURL(
      new Blob([JSON.stringify(out, null, 2)], { type: "application/json" }),
    ),
    link = document.createElement("a");
  link.href = url;
  link.download = "responsibilities.json";
  link.click();
  URL.revokeObjectURL(url);
}
function importResponsibilityManifest() {
  responsibilityDialog(
    '<h2>Import responsibility manifest</h2><p>Imports must match this snapshot and scope. Your graph plan is unchanged until you accept a proposal.</p><input id="manifest-file" type="file" accept=".json"><p id="import-error"></p>',
    () => {
      $("manifest-file").onchange = async (e) => {
        try {
          const m = JSON.parse(await e.target.files[0].text());
          if (m.format !== "partition-responsibilities-v1")
            throw Error("Unsupported manifest format.");
          Responsibilities.analyze(D, m, S.ties);
          if (m.scope.slice().sort().join("|") !== responsibilityKey)
            throw Error("Open the manifest scope first.");
          S.responsibilities[responsibilityKey] = m;
          $("source").close();
          save();
          openResponsibilityResult();
        } catch (error) {
          $("import-error").textContent = error.message;
        }
      };
    },
  );
}
function previewResponsibilities(m, a) {
  const modules = Responsibilities.moduleUnits(D, m), units = modules || a.units;
  previewGroup = null;
  fn = null;
  picked.clear();
  view = "groups";
  preview = {
    responsibility: true,
    manifestKey: responsibilityKey,
    moduleArrangement: !!modules,
    unresolvedConstraints: a.unresolvedConstraints,
    canApply: !modules && a.canApply,
    parts: units.map((u) => u.members),
    groups: S.groups
      .map((g) => ({
        ...g,
        members: g.members.filter((v) => !a.members.includes(v)),
      }))
      .filter(
        (g) =>
          g.members.length ||
          S.groups.find((original) => original.id === g.id)?.members.length ===
            0,
      )
      .concat(
        units.map((u, i) => ({
          id: "preview-" + i,
          name: u.name,
          members: u.members,
          classification: u.classification,
          moduleMembers: u.moduleMembers,
        })),
      ),
    units,
  };
  render();
}
function renderResponsibilityPreview() {
  if (preview.moduleArrangement) { renderModuleArrangement(); return; }
  $("inspector").innerHTML =
    `<div class="paneltag">RESPONSIBILITY PREVIEW</div><h2>${preview.parts.length} proposed groups</h2><p>${preview.canApply ? "Assignments and recorded constraints are complete." : "Review only: unresolved operations or dependencies remain. Inspect boundary details when you need them."}</p><p>Shared private components remain intact. Module members remain in the same translation unit.</p>${preview.units.map((u) => `<p><strong>${esc(u.name)}</strong><br>${esc(u.classification)}; ${u.members.length} functions; ${u.moduleMembers.length} module members</p>`).join("")}<button id="accept-responsibilities" class="primary wide" ${preview.canApply ? "" : "disabled"}>Accept arrangement</button><button id="edit-responsibilities">Evidence and adjustments</button><button id="responsibility-crossings">Inspect crossings</button>`;
  $("accept-responsibilities").onclick = () => {
    const p = preview;
    change("Accepted responsibility arrangement", () => {
      S.groups = p.groups.map((g) => ({
        ...g,
        id: g.id.startsWith("preview-")
          ? "responsibility-" + Date.now() + "-" + g.id
          : g.id,
      }));
    });
  };
  $("edit-responsibilities").onclick = () => {
    preview = null;
    view = "responsibilities";
    render();
  };
  $("responsibility-crossings").onclick = () =>
    showDecomposition(
      preview.parts,
      "Responsibility proposal",
      scope.members,
      preview.units.map((u) => u.name),
    );
}

function updateResponsibilityJob() {
  const job = responsibilityJobs.get(responsibilityKey);
  const status = $("analysis-status"), button = $("analyze-source");
  if (!status || !button) return;
  status.textContent = job?.message || "Uses the local agent; source files stay unchanged.";
  const running = [...responsibilityJobs.values()].find(j => j.status === 'running');
  button.disabled = !!running;
  if (running && running !== job && running.id !== job?.id) {
    status.textContent = `Analyzing ${[...new Set(running.scope.map(k => k.split(':')[0]))].join(', ')}. Follow it under Source analyses in the sidebar.`;
    button.textContent = 'Analysis in progress';
    return;
  }
  if (job?.manifest) {
    button.onclick = () => offerResponsibilityAnalysis(responsibilityKey, job);
    button.textContent = "Review new analysis";
    return;
  }
  button.textContent = job?.status === "running" ? "Analyzing source..." : "Analyze source";
}
async function analyzeResponsibilitySource() {
  const current = responsibilityManifest(), key = responsibilityKey, initial = JSON.stringify(current);
  const job = {status: "running", message: "Starting source analysis..."};
  responsibilityJobs.set(key, job);
  updateResponsibilityJob();
  try {
    const response = await fetch("/api/analysis", {
      method: "POST", headers: {"Content-Type": "application/json"},
      body: JSON.stringify({scope: current.scope, revision: D.revision}),
    });
    const started = await response.json();
    if (!response.ok) { await refreshAnalysisJobs(); throw Error(started.message); }
    job.id = started.id;
    job.initial = initial;
    await refreshAnalysisJobs();

  } catch (error) {
    Object.assign(job, {status: "failed", message: "Agent analysis unfinished: " + error.message});
    if (responsibilityKey === key) updateResponsibilityJob();
  }
}
function offerResponsibilityAnalysis(key, job) {
  responsibilityDialog(`<h2>New source analysis is ready</h2><p>Your existing proposal is preserved until you choose to replace it.</p><button id="save-old-analysis">Export existing proposal</button><button id="use-new-analysis">Use new proposal</button>`, () => {
    $("save-old-analysis").onclick = () => downloadResponsibilityManifest(S.responsibilities[key], Responsibilities.analyze(D, S.responsibilities[key], S.ties));
    $("use-new-analysis").onclick = () => {
      S.responsibilityArchive ||= [];
      S.responsibilityArchive.push({scope:key, manifest:clone(S.responsibilities[key])});
      S.responsibilities[key] = job.manifest;
      delete job.manifest;
      $("source").close(); save(); openResponsibilityResult();
    };
  });
}

function openResponsibilityResult() {
  const m = responsibilityManifest();
  if (m.responsibilities.length)
    previewResponsibilities(m, Responsibilities.analyze(D, m, S.ties));
  else render();
}

let analysisRefreshBusy = false;
async function refreshAnalysisJobs() {
  if (analysisRefreshBusy) return;
  analysisRefreshBusy = true;
  try {
    const response = await fetch('/api/analyses');
    if (!response.ok) throw Error('Cannot reconnect to the analysis server.');
    const jobs = await response.json();
    const relevant = Object.entries(jobs).filter(([id, j]) => (j.revision || j.manifest?.revision) === D.revision);
    for (const [id, result] of relevant) {
      const key = result.scope.slice().sort().join('|');
      const existing = responsibilityJobs.get(key);
      const job = {...existing, ...result, id};
      responsibilityJobs.set(key, job);
      if (result.status === 'complete' && existing?.status === 'running' && existing.initial) {
        S.responsibilities ||= {};
        const current = S.responsibilities[key];
        if (current && JSON.stringify(current) === existing.initial && !current.responsibilities.length) {
          Responsibilities.analyze(D, result.manifest, S.ties);
          S.responsibilities[key] = result.manifest;
          save();
          if (responsibilityKey === key && view === 'responsibilities') openResponsibilityResult();
        }
      }
    }
    $('analysis-jobs-list').innerHTML = relevant.reverse().map(([id,j]) => {
      const name = [...new Set(j.scope.map(k => k.split(':')[0]))].join(', ');
      const elapsed = j.started && j.status === 'running' ? ` (${Math.floor((Date.now()/1000-j.started)/60)} min elapsed)` : '';
      return `<div class="analysis-job"><strong>${esc(j.label || name)}</strong><span>${j.status === 'complete' ? 'Ready' : j.status === 'running' ? 'Running' : 'Unfinished'}${elapsed}</span><small>${esc(j.message)}</small><button data-analysis-job="${id}">${j.status === 'complete' ? 'Open result' : 'Open workspace'}</button></div>`;
    }).join('') || '<p>No source analyses yet.</p>';
    $('analysis-jobs-list').querySelectorAll('[data-analysis-job]').forEach(button => button.onclick = () => {
      const job = jobs[button.dataset.analysisJob];
      const ids = new Map(D.functions.map((_,v) => [Responsibilities.key(D,v),v]));
      scope = {name:[...new Set(job.scope.map(k => k.split(':')[0]))].join(', '), members:job.scope.map(k => ids.get(k))};
      preview = null; previewGroup = null; view = 'responsibilities'; selected.clear(); picked.clear(); fn = null;
      const current = responsibilityManifest();
      if (job.status === 'complete') {
        Responsibilities.analyze(D, job.manifest, S.ties);
        if (!current.responsibilities.length || JSON.stringify(current) === JSON.stringify(job.manifest)) {
          S.responsibilities[responsibilityKey] = job.manifest; save(); openResponsibilityResult();
        } else { render(); offerResponsibilityAnalysis(responsibilityKey, job); }
      } else render();
    });
    updateResponsibilityJob();
  } catch (error) {
    $('analysis-jobs-list').textContent = error.message + ' Retrying automatically.';
  } finally { analysisRefreshBusy = false; }
}
function watchAnalysisJobs() {
  refreshAnalysisJobs();
  setInterval(refreshAnalysisJobs, 3000);
}

function renderModuleArrangement() {
  const chosen = previewGroup ? preview.units[+previewGroup.replace('preview-', '')] : null;
  const units = preview.units;
  const unresolved = preview.unresolvedConstraints || [];
  const uncertainty = unresolved.length ? `<details class="hint"><summary>${unresolved.length} unresolved dependencies - extraction not verified</summary>${unresolved.map(c => `<p><strong>${esc(c.symbol)}</strong><br>${esc(c.evidence)}</p>`).join('')}</details>` : '';
  let detail = '<p>These are source-file responsibilities within one translation unit. Private symbols stay private. Select a group to inspect its public operations and exact private dependencies.</p>';
  if (chosen) {
    const inside = new Set(chosen.members);
    const crossing = D.edges.filter(([a,b]) => inside.has(a) !== inside.has(b) && D.functions[b].s && (inside.has(a) || inside.has(b)));
    const incoming = crossing.filter(([a,b]) => inside.has(b));
    const outgoing = crossing.filter(([a,b]) => inside.has(a));
    detail = `<h2>${esc(chosen.name)}</h2><p>${esc(chosen.description)}</p>${chosen.extraction ? `<p class="hint">${esc(chosen.extraction)}</p>` : ""}<h3>Public operations</h3>${chosen.members.filter(v => !D.functions[v].s && !D.functions[v].k).map(v => `<p><button data-module-source="${v}">${esc(D.functions[v].n)}</button></p>`).join('')}<p>${chosen.members.filter(v => D.functions[v].s && !D.functions[v].k).length} owned helpers</p><h3>Private dependencies across this boundary</h3><p>${outgoing.length} outgoing pairs; ${incoming.length} incoming pairs. These are legal between module members; separate compilation needs an explicit interface decision.</p><details ${crossing.length <= 5 ? 'open' : ''}><summary>Exact helper calls</summary>${crossing.map(([a,b,w]) => `<p>${esc(D.functions[a].n)} → ${esc(D.functions[b].n)} (${w} call sites)</p>`).join('')}</details><details><summary>Why this responsibility?</summary><p>${esc(chosen.evidence)}</p></details>`;
  }
  $('inspector').innerHTML = `<div class="paneltag">RESPONSIBILITY ARRANGEMENT</div>${chosen ? '' : `<h2>${units.length} module members</h2>`}${uncertainty}${detail}<h3>Responsibilities</h3>${units.map((u,i) => `<button class="wide" data-module-group="${i}">${esc(u.name)} · ${u.members.length}</button>`).join('')}<button id="module-evidence">Evidence and adjustments</button>`;
  document.querySelectorAll('[data-module-group]').forEach(b => b.onclick = () => { previewGroup = 'preview-' + b.dataset.moduleGroup; render(); });
  document.querySelectorAll('[data-module-source]').forEach(b => b.onclick = () => { showSource(+b.dataset.moduleSource); $('source').showModal(); });
  $('module-evidence').onclick = () => { preview=null; view='responsibilities'; render(); };
}
