"use strict";
const $ = (id) => document.getElementById(id);
const demo = {
  title: "Demo snippets", demo: true,
  versions: [
    { label: "Demo 0 - initial", filename: "sum.c", source: "#include <stdio.h>\n\nint main(void)\n{\n    int values[] = {2, 4, 6};\n    int total = 0;\n\n    for (int i = 0; i < 3; i++) {\n        total += values[i];\n    }\n\n    printf(\"%d\\n\", total);\n    return 0;\n}\n" },
    { label: "Demo 1 - count", filename: "sum.c", source: "#include <stdio.h>\n\nint main(void)\n{\n    int values[] = {2, 4, 6, 8};\n    int count = sizeof(values) / sizeof(values[0]);\n    int total = 0;\n\n    for (int i = 0; i < count; i++) {\n        total += values[i];\n    }\n\n    printf(\"sum: %d\\n\", total);\n    return 0;\n}\n" },
    { label: "Demo 2 - output", filename: "sum.c", source: "#include <stdio.h>\n\nint main(void)\n{\n    int values[] = {2, 4, 6, 8};\n    int count = sizeof(values) / sizeof(values[0]);\n    int total = 0;\n\n    for (int i = 0; i < count; i++) {\n        total += values[i];\n    }\n\n    printf(\"%d values, sum: %d\\n\", count, total);\n    return 0;\n}\n" }
  ]
};
let dataset = demo, selected = 1, layout = "split", operations = [], changeRows = [], changeIndex = -1;
let comparisons = [], visualSources = [];
const escapeHTML = (value) => String(value).replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]);
const lineCount = (source) => SourceDiff.lines(source).length;
const signed = (number) => number >= 0 ? `+${number}` : String(number);

function loadDataset(data) {
  if (!data || !Array.isArray(data.versions) || !data.versions.length) throw new Error('Expected an object with a nonempty "versions" array.');
  const versions = data.versions.map((version, index) => {
    if (!version || typeof version.label !== "string" || !version.label.trim() || typeof version.filename !== "string" || !version.filename.trim() || typeof version.source !== "string") {
      throw new Error(`Version ${index + 1} needs a nonempty label, a filename, and a source string.`);
    }
    return { label: version.label, filename: version.filename, source: version.source };
  });
  dataset = { title: typeof data.title === "string" ? data.title : "Source snapshots", status: typeof data.status === "string" ? data.status : "", note: typeof data.note === "string" ? data.note : "", versions, demo: data.demo === true };
  selected = versions.length - 1;
  comparisons = [];
  visualSources = versions.map((version) => SourceDiff.stripComments(version.source));
  render();
}

function comparison(index) {
  if (!comparisons[index]) {
    const ops = SourceDiff.compare(visualSources[Math.max(0, index - 1)], visualSources[index]);
    for (let i = 0; i < ops.length;) {
      if (ops[i].type === "equal") { i++; continue; }
      const removed = [], added = [];
      while (i < ops.length && ops[i].type !== "equal") {
        const op = ops[i++];
        (op.type === "remove" ? removed : added).push(op);
      }
      for (let j = 0; j < Math.min(removed.length, added.length); j++) {
        const parts = SourceDiff.intraline(removed[j].text, added[j].text);
        removed[j].parts = parts.before; added[j].parts = parts.after;
        // Punctuation and indentation alone do not identify corresponding source.
        if (parts.before.some((part) => !part.changed && /[\w$]/.test(part.text))) {
          removed[j].unified = parts.unified;
        }
      }
    }
    comparisons[index] = ops;
  }
  return comparisons[index];
}

function counts(ops) {
  const add = ops.filter((op) => op.type === "add").length;
  const remove = ops.filter((op) => op.type === "remove").length;
  return { add, remove, equal: ops.filter((op) => op.type === "equal").length, net: add - remove };
}

function render() {
  $("dataset-assumption").textContent = dataset.note;
  $("dataset-assumption").hidden = !dataset.note;
  $("version-count").textContent = String(dataset.versions.length).padStart(2, "0");
  $("dataset-label").textContent = dataset.demo ? "DEMO DATA" : "YOUR SNAPSHOTS";
  $("dataset-note").textContent = dataset.demo ? "Small test snippets. Not the tutorial source." : `${dataset.title}${dataset.status ? ". " + dataset.status : ""}`;
  $("versions").innerHTML = dataset.versions.map((version, index) => {
    const count = counts(comparison(index));
    return `<button class="version" data-version="${index}" aria-current="${index === selected}"><span class="version-number">${index}</span><span><span class="version-label">${escapeHTML(version.label)}</span><span class="version-filename">${escapeHTML(version.filename)}</span><span class="version-detail">${index ? `<span class="added">+${count.add}</span><span class="deleted">-${count.remove}</span> lines<span class="net">${signed(count.net)} net</span>` : "Baseline"}</span></span></button>`;
  }).join("");
  $("versions").querySelectorAll("button").forEach((button) => button.addEventListener("click", () => { selected = Number(button.dataset.version); render(); }));
  revealSelectedVersion();
  const current = dataset.versions[selected], previous = dataset.versions[Math.max(0, selected - 1)];
  $("comparison-title").textContent = selected ? `${previous.label} \u2192 ${current.label}` : `${current.label} \u00b7 Baseline`;
  $("comparison-description").textContent = (dataset.status ? `${dataset.status}. ` : "") + (selected ? "Changes from the previous version." : "The starting source. Select a later version to compare changes.");
  operations = comparison(selected);
  const count = counts(operations);
  $("counts").innerHTML = `<span class="added-count"><strong>+${count.add}</strong> added</span><span class="deleted-count"><strong>-${count.remove}</strong> deleted</span><span class="unchanged-count">${count.equal} unchanged</span><span class="net-count"><strong>${signed(count.net)}</strong> net</span>`;
  $("file-headings").style.gridTemplateColumns = selected ? "1fr 1fr" : "1fr";
  $("file-headings").innerHTML = (selected ? `<div class="file-heading"><p>BEFORE / ${escapeHTML(previous.label)}</p><strong>${escapeHTML(previous.filename)}</strong></div>` : "") + `<div class="file-heading"><p>${selected ? "AFTER" : "BASELINE"} / ${escapeHTML(current.label)}</p><strong>${escapeHTML(current.filename)}</strong></div>`;
  $("line-summary").textContent = selected ? `${lineCount(visualSources[selected - 1])} \u2192 ${lineCount(visualSources[selected])} visual lines` : `${lineCount(visualSources[selected])} visual lines`;
  $("split").disabled = $("unified").disabled = !selected;
  renderCode();
  $("code-scroll").scrollTo(0, 0);
}

function cell(op, side, source, border = false) {
  const number = op && (side === "old" ? op.old : op.new);
  const kind = !op ? "empty" : op.type === "equal" ? "" : op.type;
  const mark = !op || op.type === "equal" ? "" : op.type === "add" ? "+" : "-";
  return `<td class="line-number ${kind} ${border ? "right-start" : ""}">${number || ""}</td><td class="marker ${kind}" aria-hidden="true">${mark}</td><td class="source ${kind}">${op ? sourceText(op, source, op.type === "remove" ? op.old : number) : ""}</td>`;
}

function sourceText(op, source, number = op.type === "remove" ? op.old : op.new) {
  const endNote = number === lineCount(source) && !source.endsWith("\n") ? '<span class="end-of-file"> [no final newline]</span>' : "";
  const text = op.parts ? op.parts.map((part) => part.changed ? `<mark class="token-change">${escapeHTML(part.text)}</mark>` : escapeHTML(part.text)).join("") : escapeHTML(op.text);
  return text + endNote;
}

function splitRows() {
  const rows = [];
  for (let index = 0; index < operations.length;) {
    if (operations[index].type === "equal") { rows.push({ left: operations[index], right: operations[index++], changed: false }); continue; }
    const removed = [], added = [];
    while (index < operations.length && operations[index].type !== "equal") {
      const op = operations[index++];
      (op.type === "remove" ? removed : added).push(op);
    }
    for (let i = 0; i < Math.max(removed.length, added.length); i++) rows.push({ left: removed[i], right: added[i], changed: true });
  }
  return rows;
}

function unifiedRows() {
  return splitRows().flatMap((row) => {
    if (!row.changed) return [{ op: row.left, changed: false }];
    if (row.left && row.right && row.left.unified) return [row];
    return [row.left, row.right].filter(Boolean).map((op) => ({ op, changed: true }));
  });
}

function replacementCell(row, previousSource, currentSource) {
  const combined = row.left.unified.map((part) => {
    const text = escapeHTML(part.text), tag = part.type === "remove" ? "del" : "ins";
    return part.type === "equal" ? text : `<${tag}>${text}</${tag}>`;
  }).join("");
  const notes = [];
  if (row.left.old === lineCount(previousSource) && !previousSource.endsWith("\n")) notes.push("before: no final newline");
  if (row.right.new === lineCount(currentSource) && !currentSource.endsWith("\n")) notes.push("after: no final newline");
  const endNote = notes.length ? `<span class="end-of-file"> [${notes.join("; ")}]</span>` : "";
  return `<td class="line-number remove" tabindex="0" role="button" aria-label="Show before block">${row.left.old}</td><td class="line-number add" tabindex="0" role="button" aria-label="Show after block">${row.right.new}</td><td class="marker" aria-hidden="true">~</td><td class="source replacement"><span class="version-combined">${combined}${endNote}</span><span class="version-before">${sourceText(row.left, previousSource)}</span><span class="version-after">${sourceText(row.right, currentSource)}</span></td>`;
}

function renderCode() {
  const currentSource = visualSources[selected], previousSource = visualSources[Math.max(0, selected - 1)];
  const split = selected && layout === "split";
  $("file-headings").classList.toggle("single-flow", !split);
  const rows = split ? splitRows() : unifiedRows();
  const changed = rows.map((row, index) => row.changed ? index : -1).filter((index) => index >= 0);
  const visible = new Set();
  if ($("changes-only").checked && selected) changed.forEach((index) => { for (let i = Math.max(0, index - 3); i <= Math.min(rows.length - 1, index + 3); i++) visible.add(i); });
  else rows.forEach((_, index) => visible.add(index));
  let html = "", hidden = 0, wasChanged = false, group = 0;
  const gap = () => { if (hidden) html += `<tr class="gap"><td colspan="${split ? 6 : selected ? 4 : 3}">${hidden} unchanged ${hidden === 1 ? "line" : "lines"} hidden</td></tr>`; hidden = 0; };
  rows.forEach((row, index) => {
    if (!visible.has(index)) { hidden++; wasChanged = false; return; }
    gap();
    const start = row.changed && !wasChanged;
    if (start) group++;
    html += `<tr${start ? ` data-change="${group - 1}"` : ""}${row.changed ? ` data-block="${group - 1}"` : ""}>`;
    if (split) html += cell(row.left, "old", previousSource) + cell(row.right, "new", currentSource, true);
    else if (!selected) html += cell(row.op, "new", currentSource);
    else if (row.left && row.right) html += replacementCell(row, previousSource, currentSource);
    else {
      const op = row.op, kind = op.type === "equal" ? "" : op.type;
      html += `<td class="line-number ${kind}">${op.old || ""}</td>` + cell(op, "new", op.type === "remove" ? previousSource : currentSource);
    }
    html += "</tr>";
    wasChanged = row.changed;
  });
  gap();
  const columns = split ? '<col class="number-col"><col class="marker-col"><col><col class="number-col"><col class="marker-col"><col>' : selected ? '<col class="number-col"><col class="number-col"><col class="marker-col"><col>' : '<col class="number-col"><col class="marker-col"><col>';
  $("code").innerHTML = !rows.length ? '<p class="empty-message">This source file is empty.</p>' : !visible.size ? '<p class="empty-message">No changes between these versions.</p>' : `<table class="code-table" aria-label="${split ? "Before and after source" : "Source lines"}"><colgroup>${columns}</colgroup><tbody>${html}</tbody></table>`;
  // Size by actual text, so long source lines scroll instead of overlapping panes.
  const longest = (source) => SourceDiff.lines(source).reduce((max, line) => Math.max(max, line.replace(/\t/g, "    ").length), 0);
  const table = $("code").querySelector("table");
  if (table) {
    const charWidth = parseFloat(getComputedStyle(table).fontSize) * .63;
    const displayed = rows.map((row) => row.op ? row.op.text : row.left?.unified?.map((part) => part.text).join("") || "").join("\n");
    const width = split ? Math.max(360, longest(previousSource) * charWidth + 100, longest(currentSource) * charWidth + 100) * 2 : Math.max(300, longest(displayed) * charWidth + 150);
    table.style.minWidth = `${width}px`;
    $("file-headings").style.minWidth = split ? table.style.minWidth : "";
  } else $("file-headings").style.minWidth = "";
  changeRows = Array.from($("code").querySelectorAll("[data-change]"));
  changeIndex = -1;
  $("next-change").disabled = $("previous-change").disabled = !changeRows.length;
  $("change-position").textContent = `${changeRows.length} ${changeRows.length === 1 ? "change" : "changes"}`;
}

function showBlockVersion(event) {
  const number = event.target.closest('.line-number[role="button"]');
  if (!number) return;
  const block = number.closest("tr").dataset.block;
  const preview = event.type === "pointerover" || event.type === "focusin";
  $("code").querySelectorAll(`tr[data-block="${block}"]`).forEach((row) => {
    row.classList.toggle("show-before", preview && number.classList.contains("remove"));
    row.classList.toggle("show-after", preview && number.classList.contains("add"));
  });
}
for (const type of ["pointerover", "pointerout", "focusin", "focusout"]) $("code").addEventListener(type, showBlockVersion);

function revealSelectedVersion() {
  if (!matchMedia("(max-width: 700px)").matches) return;
  const nav = $("versions"), button = nav.querySelector('[aria-current="true"]');
  if (!button) return;
  const bounds = nav.getBoundingClientRect(), item = button.getBoundingClientRect();
  if (item.right > bounds.right) nav.scrollLeft += item.right - bounds.right;
  else if (item.left < bounds.left) nav.scrollLeft += item.left - bounds.left;
}
window.addEventListener("resize", revealSelectedVersion);

function navigateChange(direction) {
  if (!changeRows.length) return;
  changeIndex = (changeIndex + direction + changeRows.length) % changeRows.length;
  const row = changeRows[changeIndex], container = $("code-scroll");
  container.scrollTo({ top: row.getBoundingClientRect().top - container.getBoundingClientRect().top + container.scrollTop - 32, behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth" });
  $("change-position").textContent = `${changeIndex + 1} of ${changeRows.length} changes`;
}

$("next-change").addEventListener("click", () => navigateChange(1));
$("previous-change").addEventListener("click", () => navigateChange(changeIndex < 0 ? 0 : -1));
$("changes-only").addEventListener("change", renderCode);
for (const mode of ["split", "unified"]) $(mode).addEventListener("click", () => {
  layout = mode;
  for (const name of ["split", "unified"]) $(name).setAttribute("aria-pressed", String(name === mode));
  renderCode();
});
$("load").addEventListener("click", () => { $("json-error").textContent = ""; $("loader").showModal(); });
$("add").addEventListener("click", () => {
  $("version-form").reset();
  $("source-error").textContent = "";
  $("version-label").value = `Version ${dataset.demo ? 0 : dataset.versions.length}`;
  $("add-description").textContent = dataset.demo ? "The first added version replaces the demo set." : "Paste source code or choose a local source file.";
  $("editor").showModal();
});
document.querySelectorAll("[data-close]").forEach((button) => button.addEventListener("click", () => button.closest("dialog").close()));
$("json-file").addEventListener("change", async (event) => {
  const file = event.target.files[0];
  if (!file) return;
  try { $("json-input").value = await file.text(); $("json-error").textContent = ""; }
  catch { $("json-error").textContent = "This file could not be read. Choose it again or paste the JSON."; }
});
$("source-file").addEventListener("change", async (event) => {
  const file = event.target.files[0];
  if (!file) return;
  try { $("source-input").value = await file.text(); $("version-filename").value = file.name; }
  catch { $("source-error").textContent = "This file could not be read. Choose it again or paste its source."; }
});
$("snapshot-form").addEventListener("submit", (event) => {
  event.preventDefault();
  try { loadDataset(JSON.parse($("json-input").value)); $("loader").close(); }
  catch (error) { $("json-error").textContent = error instanceof SyntaxError ? "Invalid JSON. Check quotes, commas, and escaped newlines in source strings." : error.message; }
});
$("version-form").addEventListener("submit", (event) => {
  event.preventDefault();
  const version = { label: $("version-label").value.trim(), filename: $("version-filename").value.trim(), source: $("source-input").value };
  try {
    loadDataset({ title: dataset.demo ? "Source snapshots" : dataset.title, status: dataset.status, note: dataset.note, versions: [...(dataset.demo ? [] : dataset.versions), version] });
    selected = dataset.versions.length - 1;
    render();
    $("editor").close();
  } catch (error) { $("source-error").textContent = error.message; }
});
$("export").addEventListener("click", () => {
  const url = URL.createObjectURL(new Blob([JSON.stringify(dataset, null, 2) + "\n"], { type: "application/json" }));
  const link = document.createElement("a");
  link.href = url; link.download = dataset.demo ? "demo-snapshots.json" : "snapshots.json"; link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
});
$("changes-only").checked = false;
loadDataset(window.TUTORIAL_SNAPSHOTS || demo);
