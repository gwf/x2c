/* Notes client. Note content is rendered as text, including titles and tags. */
"use strict";

const element = (id) => document.getElementById(id);
let notes = [];
let selected = null;
let dirty = false;
let busy = false;
let refreshVersion = 0;

async function api(path, method = "GET", body) {
  const options = { method, headers: {} };
  if (body !== undefined) {
    options.headers["Content-Type"] = "application/json";
    options.body = JSON.stringify(body);
  }
  const response = await fetch(path, options);
  const value = await response.json();
  if (!response.ok) throw new Error(value.error || `Request failed (${response.status}).`);
  return value;
}

function status(message, error = false) {
  element("status").textContent = message;
  element("status").dataset.error = String(error);
}

function allowDiscard() {
  return !dirty || window.confirm("Discard unsaved changes?");
}

function edit(note = null) {
  selected = note;
  dirty = false;
  element("editor-title").textContent = note ? "Edit note" : "New note";
  element("title").value = note ? note.title : "";
  element("body").value = note ? note.body || "" : "";
  element("tags").value = note ? (note.tags || []).join(", ") : "";
  element("save").textContent = note ? "Save changes" : "Create note";
  element("delete").hidden = !note;
  const timestamp = note && note.updated;
  element("updated").textContent = timestamp
    ? `Updated ${new Date(timestamp * 1000).toLocaleString()}` : "";
  renderNotes();
}

function renderNotes() {
  const list = element("note-list");
  list.replaceChildren();
  element("empty").hidden = notes.length > 0;
  element("empty").textContent = element("search").value || element("filter-tag").value
    ? "No notes match these filters." : "No notes yet. Create your first note.";
  for (const note of notes) {
    const item = document.createElement("li");
    const button = document.createElement("button");
    button.type = "button";
    button.className = "note";
    button.setAttribute("aria-pressed", String(Boolean(selected && selected.id === note.id)));
    const title = document.createElement("span");
    title.className = "note-title";
    title.textContent = note.title;
    const preview = document.createElement("span");
    preview.className = "note-preview";
    preview.textContent = (note.body || "").replace(/\s+/g, " ").slice(0, 110);
    const tags = document.createElement("span");
    tags.className = "note-tags";
    tags.textContent = (note.tags || []).map((tag) => `#${tag}`).join("  ");
    button.append(title, preview, tags);
    button.addEventListener("click", () => {
      if (busy || !allowDiscard()) return;
      edit(note);
      status("");
      element("title").focus();
    });
    item.append(button);
    list.append(item);
  }
}

function renderStats(stats) {
  element("stats").textContent = `${stats.notes} ${stats.notes === 1 ? "note" : "notes"} / ${stats.bytes} bytes`;
  const summary = element("tag-summary");
  summary.replaceChildren();
  for (const [tag, count] of Object.entries(stats.tags || {}).sort()) {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = `${tag} (${count})`;
    button.setAttribute("aria-label", `Filter by ${tag}, ${count} notes`);
    button.addEventListener("click", () => {
      element("filter-tag").value = tag;
      refresh().catch((error) => status(error.message, true));
    });
    summary.append(button);
  }
}

async function refresh() {
  const version = ++refreshVersion;
  const query = new URLSearchParams();
  if (element("search").value) query.set("q", element("search").value);
  if (element("filter-tag").value) query.set("tag", element("filter-tag").value);
  const [found, stats] = await Promise.all([
    api(`/api/notes?${query}`), api("/api/stats")
  ]);
  if (version !== refreshVersion) return;
  notes = found;
  renderNotes();
  renderStats(stats);
}

function setBusy(value) {
  busy = value;
  for (const control of element("editor").elements) control.disabled = value;
  element("new").disabled = value;
}

element("editor").addEventListener("input", () => { dirty = true; });
element("editor").addEventListener("submit", async (event) => {
  event.preventDefault();
  if (busy) return;
  const body = {
    title: element("title").value.trim(),
    body: element("body").value,
    tags: [...new Set(element("tags").value.split(",")
      .map((tag) => tag.trim()).filter(Boolean))]
  };
  if (!body.title) {
    status("Enter a title.", true);
    element("title").focus();
    return;
  }
  const updating = Boolean(selected);
  const path = selected ? `/api/notes/${encodeURIComponent(selected.id)}` : "/api/notes";
  setBusy(true);
  status("Saving...");
  try {
    const saved = await api(path, updating ? "PUT" : "POST", body);
    edit(saved);
    await refresh();
    status(updating ? "Changes saved." : "Note created.");
  } catch (error) {
    status(error.message, true);
  } finally {
    setBusy(false);
  }
});

element("delete").addEventListener("click", async () => {
  if (busy || !selected || !window.confirm(`Delete "${selected.title}"?`)) return;
  setBusy(true);
  try {
    await api(`/api/notes/${encodeURIComponent(selected.id)}`, "DELETE");
    edit();
    await refresh();
    status("Note deleted.");
  } catch (error) {
    status(error.message, true);
  } finally {
    setBusy(false);
  }
});

element("new").addEventListener("click", () => {
  if (busy || !allowDiscard()) return;
  edit();
  status("");
  element("title").focus();
});

element("filters").addEventListener("submit", (event) => {
  event.preventDefault();
  status("Searching...");
  refresh().then(() => status("")).catch((error) => status(error.message, true));
});

element("clear").addEventListener("click", () => {
  element("search").value = "";
  element("filter-tag").value = "";
  refresh().then(() => status("")).catch((error) => status(error.message, true));
});

window.addEventListener("beforeunload", (event) => {
  if (!dirty) return;
  event.preventDefault();
  event.returnValue = "";
});

refresh().catch((error) => status(error.message, true));
