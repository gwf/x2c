#pragma once

/*  devtools.x -- the gallery's Developer tools page */

#include "state.x"

// The cron expression that the schedule picker edits, created by prepare.
static TextField sc_cron;

// The headers the key-value editor edits, an Array of KeyValue.
static Array headers;

static void prepare(void) {
  sc_cron = TextField.new(64);
  sc_cron.set("30 9 * * 1-5");
  headers = [
    KeyValue.new("Authorization", "Bearer 4f9c2e81d0b7a6", true, true),
    KeyValue.new("Accept", "application/json", true, false),
    KeyValue.new("X-Request-Id", "7d1c0a", false, false),
    KeyValue.new("Accept", "text/html", true, false)];
}

static void devtools_kv(Ui ui) {
  ui.column (gap: 10, width: fill, max_width: 680) {
    ui.text("Headers", font: medium);
    ui.kv_editor("headers", headers);
  }
}

static void devtools_problems(Ui ui) {
  ui.column (gap: 10, width: fill, max_width: 760)
    ui.problems("problems", [
      {severity: error, message: "use of undeclared identifier 'frame_time'",
       file: "src/render/timing.c", line: 42, column: 17, source: "clang",
       code: "undeclared-var"},
      {severity: warning, message: "unused variable 'scale'",
       file: "src/render/timing.c", line: 88, column: 11, source: "clang",
       code: "-Wunused-variable"},
      {severity: error,
       message: "incompatible pointer types passing 'float *' to 'double *'",
       file: "src/core/layout.c", line: 210, column: 33, source: "clang",
       code: "-Wincompatible-pointer-types"},
      {severity: warning,
       message: "implicit conversion loses floating-point precision",
       file: "src/core/layout.c", line: 318, column: 22, source: "clang",
       code: "-Wfloat-conversion"},
      {severity: info, message: "function 'measure' could be declared static",
       file: "src/core/layout.c", line: 402, column: 6, source: "clang-tidy",
       code: "misc-use-internal-linkage"},
      {severity: hint,
       message: "loop variable copied on each iteration; consider a pointer",
       file: "src/app/main.c", line: 51, column: 9, source: "clang-tidy",
       code: "performance-for-range-copy"},
      {severity: warning, message: "comparison of integers of different signs",
       file: "src/app/main.c", line: 77, column: 18, source: "gcc",
       code: "-Wsign-compare"}],
                height: 300);
}

static int pl_sel = 3;

static void devtools_pipeline(Ui ui) {
  ui.column (gap: 10, width: fill, max_width: 920)
    ui.pipeline("run", %("Build" "Test" "Package" "Deploy"), [
      {name: "linux-x64", stage: 0, status: passed, duration: 142},
      {name: "macos-arm64", stage: 0, status: passed, duration: 201},
      {name: "windows-x64", stage: 0, status: passed, duration: 236},
      {name: "unit", stage: 1, status: passed, duration: 64},
      {name: "integration", stage: 1, status: running, duration: 95},
      {name: "lint", stage: 1, status: failed, duration: 12,
       allow_failure: true},
      {name: "docker image", stage: 2, status: pending, duration: -1},
      {name: "release notes", stage: 2, status: skipped, duration: -1},
      {name: "staging", stage: 3, status: pending, duration: -1},
      {name: "production", stage: 3, status: pending, duration: -1}],
      selected: &pl_sel);
}

static const char *const qb_status[] = { "Open", "In progress", "Closed" };
static cui_query_field qb_fields[] = {
  { "Status", CUI_QUERY_CHOICE, qb_status, 3 },
  { "Assignee", CUI_QUERY_TEXT },
  { "Priority", CUI_QUERY_NUMBER },
  { "Has PR", CUI_QUERY_BOOL },
};
static cui_query_node qb_nodes[16] = {
  { 0, true, false }, { 1, false, false, 0, 0, "Open" }, { 1, true, true },
  { 2, false, false, 1, 0, "me" }, { 2, false, false, 2, 2, "2" },
};
static int qb_n = 5;

static void devtools_query(Ui ui) {
  ui.column (gap: 10, width: fill, max_width: 720) {
    ui.query_builder("filter", qb_fields, qb_nodes, qb_n);
    // CUI writes the query as a sentence into a buffer; it has no method.
    char text[256];
    cui_query_text(qb_fields,
                   (int) (sizeof qb_fields / sizeof *qb_fields), qb_nodes,
                   qb_n, text, sizeof text);
    ui.text(text, size: 12, color: text_muted);
  }
}

static void devtools_schedule(Ui ui) {
  ui.column (gap: 10, width: fill, max_width: 560)
    ui.schedule_picker("backup", sc_cron, now: 1794211200, utc: true,
                                          next_count: 3);
}

static int km_mods = CUI_MOD_PRIMARY;

static void devtools_keymap(Ui ui) {
  ui.column (gap: 10, width: fill, max_width: 900)
    ui.keymap("keys", [
      {combo: {mods: CUI_MOD_PRIMARY, key: s}, action: "Save", category: 0},
      {combo: {mods: CUI_MOD_PRIMARY, key: o}, action: "Open", category: 0},
      {combo: {mods: CUI_MOD_PRIMARY, key: n}, action: "New file",
       category: 0},
      {combo: {mods: CUI_MOD_PRIMARY, key: w}, action: "Close tab",
       category: 0},
      {combo: {mods: CUI_MOD_PRIMARY, key: p}, action: "Go to file",
       category: 1},
      {combo: {mods: CUI_MOD_PRIMARY, key: g}, action: "Go to line",
       category: 1},
      {combo: {mods: CUI_MOD_PRIMARY, key: f}, action: "Find", category: 2},
      {combo: {mods: CUI_MOD_PRIMARY, key: h}, action: "Replace", category: 2},
      {combo: {mods: CUI_MOD_PRIMARY, key: z}, action: "Undo", category: 2},
      {combo: {mods: CUI_MOD_PRIMARY, key: y}, action: "Redo", category: 2},
      {combo: {mods: CUI_MOD_PRIMARY, key: b}, action: "Build", category: 3},
      {combo: {mods: CUI_MOD_PRIMARY, key: r}, action: "Run", category: 3},
      {combo: {mods: CUI_MOD_PRIMARY, key: d}, action: "Debug", category: 3},
      {combo: {mods: CUI_MOD_PRIMARY, key: slash}, action: "Comment",
       category: 2},
      {combo: {mods: CUI_MOD_PRIMARY, key: e}, action: "Recent files",
       category: 1},
      {combo: {mods: CUI_MOD_PRIMARY, key: r}, action: "Rename symbol",
       category: 2},
      {combo: {mods: 0, key: f5}, action: "Continue", category: 3},
      {combo: {mods: 0, key: f9}, action: "Breakpoint", category: 3},
      {combo: {mods: 0, key: f10}, action: "Step over", category: 3},
      {combo: {mods: 0, key: f11}, action: "Step into", category: 3},
      {combo: {mods: 0, key: f2}, action: "Rename", category: 2},
      {combo: {mods: 0, key: f12}, action: "Definition", category: 1},
      {combo: {mods: CUI_MOD_PRIMARY | CUI_MOD_SHIFT, key: p},
       action: "Commands", category: 1},
      {combo: {mods: CUI_MOD_PRIMARY | CUI_MOD_SHIFT, key: f},
       action: "Find in files", category: 2}],
      categories: ["File", "Navigate", "Edit", "Run and debug"],
      mods: &km_mods);
}

static int cg_sel = 1;

static void devtools_commits(Ui ui) {
  ui.column (gap: 10, width: fill, max_width: 920)
    ui.commit_graph("history", [
      {hash: "a91f3c2e", message: "Merge branch 'feature/trace-viewer'",
       author: "Maya Okafor", date: "2 hours ago", refs: "main, origin/main",
       parent: [1, 4]},
      {hash: "7be04d19", message: "Docs: the trace viewer and the waterfall",
       author: "Maya Okafor", date: "3 hours ago", parent: [2, -1]},
      {hash: "c3d8a7f0", message: "Fix the ruler's last tick on narrow panels",
       author: "Jonas Berg", date: "5 hours ago", parent: [3, -1]},
      {hash: "1f22b9e4", message: "Release 1.2", author: "Jonas Berg",
       date: "yesterday", refs: "tag: v1.2.0", parent: [6, -1]},
      {hash: "e8a0c55b",
       message: "Trace viewer: measure a range with Shift+drag",
       author: "Priya Nair", date: "yesterday", refs: "feature/trace-viewer",
       parent: [5, -1]},
      {hash: "4d9e1a77", message: "Trace viewer: lanes, spans and markers",
       author: "Priya Nair", date: "2 days ago", parent: [6, -1]},
      {hash: "90b7f3c1", message: "Merge pull request #21 from fix/atlas",
       author: "Maya Okafor", date: "3 days ago", parent: [7, 8]},
      {hash: "52ce8d0a", message: "Faster soft shadows in software",
       author: "Lena Fischer", date: "3 days ago", parent: [9, -1]},
      {hash: "b6f1e2d3", message: "Glyph atlas: compact after a zoom",
       author: "Aiko Tanaka", date: "4 days ago", refs: "fix/atlas",
       parent: [9, -1]},
      {hash: "0aa4c9e8", message: "Right to left layout",
       author: "Omid Saadat", date: "5 days ago", parent: [-1, -1]}],
                    selected: &cg_sel, height: 320);
}

static int gv_sel = 1;

static void devtools_graph(Ui ui) {
  ui.column (gap: 10, width: fill, max_width: 1000)
    ui.graph_view("deps", [
      {label: "app", detail: "executable", tone: violet},
      {label: "ui", detail: "libcui.a", tone: info},
      {label: "net", detail: "http client", tone: info},
      {label: "storage", detail: "sqlite", tone: teal},
      {label: "render", detail: "software, OpenGL", tone: info},
      {label: "text", detail: "fonts, shaping", tone: info},
      {label: "tls", detail: "mbedtls", tone: warning},
      {label: "zlib", tone: neutral},
      {label: "platform", detail: "X11, Win32, Cocoa", tone: info}],
      [
        {from: 0, to: 1}, {from: 0, to: 2}, {from: 0, to: 3}, {from: 1, to: 4},
        {from: 1, to: 5}, {from: 1, to: 8}, {from: 2, to: 6}, {from: 2, to: 7},
        {from: 3, to: 7}, {from: 5, to: 7}, {from: 4, to: 8}],
        selected: &gv_sel,
                                        height: 340);
}

static int wf_sel = 2;

static void devtools_waterfall(Ui ui) {
  ui.column (gap: 10, width: fill, max_width: 1000)
    ui.waterfall("net", [
      {name: "https://shop.example.com/", method: "GET", status: 200,
       type: "document", size: 18400, start: 0.000,
       timing: [0.002, 0.018, 0.024, 0.031, 0.142, 0.012]},
      {name: "https://shop.example.com/assets/app.css", method: "GET",
       status: 200, type: "stylesheet", size: 42100, start: 0.232,
       timing: [0.004, 0, 0, 0, 0.061, 0.022]},
      {name: "https://shop.example.com/assets/app.js", method: "GET",
       status: 200, type: "script", size: 186000, start: 0.233,
       timing: [0.005, 0, 0, 0, 0.068, 0.094]},
      {name: "https://cdn.example.net/fonts/inter.woff2", method: "GET",
       status: 200, type: "font", size: 48200, start: 0.241,
       timing: [0.003, 0.021, 0.019, 0.028, 0.044, 0.018]},
      {name: "https://shop.example.com/api/session", method: "POST",
       status: 401, type: "fetch", size: 312, start: 0.402,
       timing: [0.002, 0, 0, 0, 0.083, 0.001]},
      {name: "https://shop.example.com/api/products?page=1", method: "GET",
       status: 200, type: "fetch", size: 9600, start: 0.404,
       timing: [0.002, 0, 0, 0, 0.121, 0.006]},
      {name: "https://shop.example.com/img/hero.avif", method: "GET",
       status: 200, type: "image", size: 212000, start: 0.410,
       timing: [0.012, 0, 0, 0, 0.052, 0.188]},
      {name: "https://shop.example.com/img/p/1042.webp", method: "GET",
       status: 304, type: "image", size: 0, start: 0.538,
       timing: [0.006, 0, 0, 0, 0.038, 0]},
      {name: "https://shop.example.com/img/p/1043.webp", method: "GET",
       status: 200, type: "image", size: 31200, start: 0.540,
       timing: [0.008, 0, 0, 0, 0.041, 0.024]},
      {name: "https://analytics.example.org/collect", method: "POST",
       status: 0, type: "ping", size: 0, start: 0.702,
       timing: [0.004, 0.026, 0.031, 0.036, 0.12, 0]}],
      selected: &wf_sel, height: 340, dom_loaded: 0.395,
      loaded: 0.68);
}

static cui_trace_track tr_tracks[] = {
  { "Main thread" }, { "Render" }, { "Worker 1" }, { "Worker 2" }, { "GPU" },
};
enum { TR_CAPACITY = 400 };
static cui_trace_span tr_spans[TR_CAPACITY];
static int tr_n = 0;
static cui_trace_view tr_view = { 0.0042, 0.0418, 0, 0.0161, 0.0236 };
static int tr_sel = -1;

static void tr_add(const char *name, double s, double e, int track,
                   int depth) {
  if (tr_n < TR_CAPACITY)
    tr_spans[tr_n++] = (cui_trace_span){ name, s, e, track, depth, 0 };
}

static void tr_build(void) {
  for (int f = 0; f < 3; f++) {
    double t = f * 0.0166;
    tr_add("Frame", t + 0.0004, t + 0.0151, 0, 0);
    tr_add("Input", t + 0.0006, t + 0.0019, 0, 1);
    tr_add("Update", t + 0.0021, t + 0.0092, 0, 1);
    tr_add("Physics", t + 0.0023, t + 0.0051, 0, 2);
    tr_add("Animation", t + 0.0053, t + 0.0068, 0, 2);
    tr_add("Scripts", t + 0.0070, t + 0.0090, 0, 2);
    tr_add("Layout", t + 0.0094, t + 0.0121, 0, 1);
    tr_add("Measure", t + 0.0095, t + 0.0108, 0, 2);
    tr_add("Paint", t + 0.0123, t + 0.0149, 0, 1);
    tr_add("Record", t + 0.0124, t + 0.0139, 0, 2);
    tr_add("Submit", t + 0.0152, t + 0.0163, 1, 0);
    tr_add("Upload", t + 0.0153, t + 0.0157, 1, 1);
    tr_add("Encode", t + 0.0157, t + 0.0162, 1, 1);
    tr_add("Decode image", t + 0.0012, t + 0.0074, 2, 0);
    tr_add("Inflate", t + 0.0013, t + 0.0049, 2, 1);
    tr_add("Parse JSON", t + 0.0081, t + 0.0118, 3, 0);
    tr_add("Draw", t + 0.0164, t + 0.0166 + 0.0105, 4, 0);
  }
  cui_trace_sort(tr_spans, tr_n);
}

static void devtools_trace(Ui ui) {
  if (!tr_n) tr_build();
  if (tr_sel < 0)
    for (int i = 0; i < tr_n; i++)
      if (!strcmp(tr_spans[i].name, "Update") && tr_spans[i].start > 0.016
          && tr_spans[i].start < 0.03)
        tr_sel = i;
  ui.column (gap: 10, width: fill, max_width: 1000)
    // The spans in use are fewer than the array holds, so both counts
    // are written.
    ui.trace_view("trace", tr_tracks,
                  (int) (sizeof tr_tracks / sizeof *tr_tracks), tr_spans,
                  tr_n, tr_view, tr_sel, markers: [
                    {name: "vsync", time: 0.0, tone: neutral},
                    {name: "vsync", time: 0.0166, tone: neutral},
                    {name: "GC pause", time: 0.0273, tone: warning},
                    {name: "vsync", time: 0.0332, tone: neutral}],
                    height: 320);
}

void page_devtools(Ui ui, Gallery g) {
  static bool ready;
  if (!ready) {
    prepare();
    ready = true;
  }
  section(ui, "Trace viewer",
          "Wheel zooms, drag pans, Shift+drag measures, a lane's name "
          "folds it.");
  devtools_trace(ui);
  section(ui, "Network waterfall",
          "Hover a bar for its timing; Up and Down move the selection.");
  devtools_waterfall(ui);
  section(ui, "Dependency graph",
          "Hover a node to light up its neighbours; wheel zooms, F fits.");
  devtools_graph(ui);
  section(ui, "Commit graph",
          "Branch lanes, merges and refs; only the rows in view are built.");
  devtools_commits(ui);
  section(ui, "Pipeline", "Stages of jobs; a stage sums up its jobs.");
  devtools_pipeline(ui);
  section(ui, "Problems",
          "Grouped by file; filter by severity or text, Enter opens.");
  devtools_problems(ui);
  section(ui, "Key-value editor",
          "Type in the empty row to add a pair; the lock hides a value.");
  devtools_kv(ui);
  section(ui, "Query builder", "Nested all and any groups.");
  devtools_query(ui);
  section(ui, "Schedule picker",
          "Writes a cron expression and shows the next runs.");
  devtools_schedule(ui);
  section(ui, "Keymap",
          "Shortcuts on a keyboard; keys bound twice are marked.");
  devtools_keymap(ui);
}
