#pragma once

/*  devtools.x -- the gallery's Developer tools page */

#include "state.x"

// The cron expression that the schedule picker edits, created by prepare.
static TextField sc_cron;

static void prepare(void) {
  sc_cron = TextField.new(64);
  sc_cron.set("30 9 * * 1-5");
}

static cui_kv_pair kv_pairs[12] = {
  { "Authorization", "Bearer 4f9c2e81d0b7a6", true, true },
  { "Accept", "application/json", true },
  { "X-Request-Id", "7d1c0a", false },
  { "Accept", "text/html", true },
};
static int kv_n = 4;

static void devtools_kv(Ui ui) {
  ui.column (gap: 10, width: CUI_FILL, max_width: 680) {
    ui.text("Headers", font: CUI_FONT_MEDIUM);
    ui.kv_editor("headers", kv_pairs, kv_n);
  }
}

static const cui_diagnostic pbm_diags[] = {
  { CUI_SEVERITY_ERROR, "use of undeclared identifier 'frame_time'",
    "src/render/timing.c", 42, 17, "clang", "undeclared-var" },
  { CUI_SEVERITY_WARNING, "unused variable 'scale'", "src/render/timing.c",
    88, 11, "clang", "-Wunused-variable" },
  { CUI_SEVERITY_ERROR,
    "incompatible pointer types passing 'float *' to 'double *'",
    "src/core/layout.c", 210, 33, "clang", "-Wincompatible-pointer-types" },
  { CUI_SEVERITY_WARNING,
    "implicit conversion loses floating-point precision",
    "src/core/layout.c", 318, 22, "clang", "-Wfloat-conversion" },
  { CUI_SEVERITY_INFO, "function 'measure' could be declared static",
    "src/core/layout.c", 402, 6, "clang-tidy", "misc-use-internal-linkage" },
  { CUI_SEVERITY_HINT,
    "loop variable copied on each iteration; consider a pointer",
    "src/app/main.c", 51, 9, "clang-tidy", "performance-for-range-copy" },
  { CUI_SEVERITY_WARNING, "comparison of integers of different signs",
    "src/app/main.c", 77, 18, "gcc", "-Wsign-compare" },
};

static void devtools_problems(Ui ui) {
  ui.column (gap: 10, width: CUI_FILL, max_width: 760)
    ui.problems("problems", pbm_diags,
                height: 300);
}

static int pl_sel = 3;

static void devtools_pipeline(Ui ui) {
  static const cui_pipeline_job jobs[] = {
    { "linux-x64", 0, CUI_JOB_PASSED, 142 },
    { "macos-arm64", 0, CUI_JOB_PASSED, 201 },
    { "windows-x64", 0, CUI_JOB_PASSED, 236 },
    { "unit", 1, CUI_JOB_PASSED, 64 },
    { "integration", 1, CUI_JOB_RUNNING, 95 },
    { "lint", 1, CUI_JOB_FAILED, 12, true },
    { "docker image", 2, CUI_JOB_PENDING, -1 },
    { "release notes", 2, CUI_JOB_SKIPPED, -1 },
    { "staging", 3, CUI_JOB_PENDING, -1 },
    { "production", 3, CUI_JOB_PENDING, -1 },
  };
  ui.column (gap: 10, width: CUI_FILL, max_width: 920)
    ui.pipeline("run", %("Build" "Test" "Package" "Deploy"), jobs, selected: &pl_sel);
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
  ui.column (gap: 10, width: CUI_FILL, max_width: 720) {
    ui.query_builder("filter", qb_fields, qb_nodes, qb_n);
    // CUI writes the query as a sentence into a buffer; it has no method.
    char text[256];
    cui_query_text(qb_fields,
                   (int) (sizeof qb_fields / sizeof *qb_fields), qb_nodes,
                   qb_n, text, sizeof text);
    ui.text(text, size: 12, color: CUI_COLOR_TEXT_MUTED);
  }
}

static void devtools_schedule(Ui ui) {
  ui.column (gap: 10, width: CUI_FILL, max_width: 560)
    ui.schedule_picker("backup", sc_cron, now: 1794211200, utc: true,
                                          next_count: 3);
}

static int km_mods = CUI_MOD_PRIMARY;

static void devtools_keymap(Ui ui) {
  static const cui_keymap_binding binds[] = {
    { { CUI_MOD_PRIMARY, CUI_KEY_S }, "Save", 0 },
    { { CUI_MOD_PRIMARY, CUI_KEY_O }, "Open", 0 },
    { { CUI_MOD_PRIMARY, CUI_KEY_N }, "New file", 0 },
    { { CUI_MOD_PRIMARY, CUI_KEY_W }, "Close tab", 0 },
    { { CUI_MOD_PRIMARY, CUI_KEY_P }, "Go to file", 1 },
    { { CUI_MOD_PRIMARY, CUI_KEY_G }, "Go to line", 1 },
    { { CUI_MOD_PRIMARY, CUI_KEY_F }, "Find", 2 },
    { { CUI_MOD_PRIMARY, CUI_KEY_H }, "Replace", 2 },
    { { CUI_MOD_PRIMARY, CUI_KEY_Z }, "Undo", 2 },
    { { CUI_MOD_PRIMARY, CUI_KEY_Y }, "Redo", 2 },
    { { CUI_MOD_PRIMARY, CUI_KEY_B }, "Build", 3 },
    { { CUI_MOD_PRIMARY, CUI_KEY_R }, "Run", 3 },
    { { CUI_MOD_PRIMARY, CUI_KEY_D }, "Debug", 3 },
    { { CUI_MOD_PRIMARY, CUI_KEY_SLASH }, "Comment", 2 },
    { { CUI_MOD_PRIMARY, CUI_KEY_E }, "Recent files", 1 },
    { { CUI_MOD_PRIMARY, CUI_KEY_R }, "Rename symbol", 2 },
    { { 0, CUI_KEY_F5 }, "Continue", 3 },
    { { 0, CUI_KEY_F9 }, "Breakpoint", 3 },
    { { 0, CUI_KEY_F10 }, "Step over", 3 },
    { { 0, CUI_KEY_F11 }, "Step into", 3 },
    { { 0, CUI_KEY_F2 }, "Rename", 2 },
    { { 0, CUI_KEY_F12 }, "Definition", 1 },
    { { CUI_MOD_PRIMARY | CUI_MOD_SHIFT, CUI_KEY_P }, "Commands", 1 },
    { { CUI_MOD_PRIMARY | CUI_MOD_SHIFT, CUI_KEY_F }, "Find in files", 2 },
  };
  static const char *cats_en[] = { "File", "Navigate", "Edit",
                                   "Run and debug" };
  ui.column (gap: 10, width: CUI_FILL, max_width: 900)
    ui.keymap("keys", binds,
      categories: cats_en,
      mods: &km_mods);
}

static const cui_commit cg_commits[] = {
  { "a91f3c2e", "Merge branch 'feature/trace-viewer'", "Maya Okafor",
    "2 hours ago", "main, origin/main", { 1, 4 } },
  { "7be04d19", "Docs: the trace viewer and the waterfall", "Maya Okafor",
    "3 hours ago", NULL, { 2, -1 } },
  { "c3d8a7f0", "Fix the ruler's last tick on narrow panels", "Jonas Berg",
    "5 hours ago", NULL, { 3, -1 } },
  { "1f22b9e4", "Release 1.2", "Jonas Berg", "yesterday", "tag: v1.2.0",
    { 6, -1 } },
  { "e8a0c55b", "Trace viewer: measure a range with Shift+drag",
    "Priya Nair", "yesterday", "feature/trace-viewer", { 5, -1 } },
  { "4d9e1a77", "Trace viewer: lanes, spans and markers", "Priya Nair",
    "2 days ago", NULL, { 6, -1 } },
  { "90b7f3c1", "Merge pull request #21 from fix/atlas", "Maya Okafor",
    "3 days ago", NULL, { 7, 8 } },
  { "52ce8d0a", "Faster soft shadows in software", "Lena Fischer",
    "3 days ago", NULL, { 9, -1 } },
  { "b6f1e2d3", "Glyph atlas: compact after a zoom", "Aiko Tanaka",
    "4 days ago", "fix/atlas", { 9, -1 } },
  { "0aa4c9e8", "Right to left layout", "Omid Saadat", "5 days ago", NULL,
    { -1, -1 } },
};
static int cg_sel = 1;

static void devtools_commits(Ui ui) {
  ui.column (gap: 10, width: CUI_FILL, max_width: 920)
    ui.commit_graph("history", cg_commits,
                    selected: &cg_sel, height: 320);
}

static const cui_graph_node gv_nodes[] = {
  { "app", "executable", CUI_TONE_VIOLET },
  { "ui", "libcui.a", CUI_TONE_INFO },
  { "net", "http client", CUI_TONE_INFO },
  { "storage", "sqlite", CUI_TONE_TEAL },
  { "render", "software, OpenGL", CUI_TONE_INFO },
  { "text", "fonts, shaping", CUI_TONE_INFO },
  { "tls", "mbedtls", CUI_TONE_WARNING },
  { "zlib", NULL, CUI_TONE_NEUTRAL },
  { "platform", "X11, Win32, Cocoa", CUI_TONE_INFO },
};
static const cui_graph_edge gv_edges[] = {
  { 0, 1 }, { 0, 2 }, { 0, 3 }, { 1, 4 }, { 1, 5 }, { 1, 8 },
  { 2, 6 }, { 2, 7 }, { 3, 7 }, { 5, 7 }, { 4, 8 },
};
static int gv_sel = 1;

static void devtools_graph(Ui ui) {
  ui.column (gap: 10, width: CUI_FILL, max_width: 1000)
    ui.graph_view("deps", gv_nodes, gv_edges, selected: &gv_sel,
                                        height: 340);
}

static const cui_net_request wf_reqs[] = {
  { "https://shop.example.com/", "GET", 200, "document", 18400, 0.000,
    { 0.002, 0.018, 0.024, 0.031, 0.142, 0.012 } },
  { "https://shop.example.com/assets/app.css", "GET", 200, "stylesheet",
    42100, 0.232, { 0.004, 0, 0, 0, 0.061, 0.022 } },
  { "https://shop.example.com/assets/app.js", "GET", 200, "script", 186000,
    0.233, { 0.005, 0, 0, 0, 0.068, 0.094 } },
  { "https://cdn.example.net/fonts/inter.woff2", "GET", 200, "font", 48200,
    0.241, { 0.003, 0.021, 0.019, 0.028, 0.044, 0.018 } },
  { "https://shop.example.com/api/session", "POST", 401, "fetch", 312,
    0.402, { 0.002, 0, 0, 0, 0.083, 0.001 } },
  { "https://shop.example.com/api/products?page=1", "GET", 200, "fetch",
    9600, 0.404, { 0.002, 0, 0, 0, 0.121, 0.006 } },
  { "https://shop.example.com/img/hero.avif", "GET", 200, "image", 212000,
    0.410, { 0.012, 0, 0, 0, 0.052, 0.188 } },
  { "https://shop.example.com/img/p/1042.webp", "GET", 304, "image", 0,
    0.538, { 0.006, 0, 0, 0, 0.038, 0 } },
  { "https://shop.example.com/img/p/1043.webp", "GET", 200, "image", 31200,
    0.540, { 0.008, 0, 0, 0, 0.041, 0.024 } },
  { "https://analytics.example.org/collect", "POST", 0, "ping", 0, 0.702,
    { 0.004, 0.026, 0.031, 0.036, 0.12, 0 } },
};
static int wf_sel = 2;

static void devtools_waterfall(Ui ui) {
  ui.column (gap: 10, width: CUI_FILL, max_width: 1000)
    ui.waterfall("net", wf_reqs,
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

static const cui_trace_marker tr_marks[] = {
  { "vsync", 0.0, CUI_TONE_NEUTRAL }, { "vsync", 0.0166, CUI_TONE_NEUTRAL },
  { "GC pause", 0.0273, CUI_TONE_WARNING },
  { "vsync", 0.0332, CUI_TONE_NEUTRAL },
};

static void devtools_trace(Ui ui) {
  if (!tr_n) tr_build();
  if (tr_sel < 0)
    for (int i = 0; i < tr_n; i++)
      if (!strcmp(tr_spans[i].name, "Update") && tr_spans[i].start > 0.016
          && tr_spans[i].start < 0.03)
        tr_sel = i;
  ui.column (gap: 10, width: CUI_FILL, max_width: 1000)
    // The spans in use are fewer than the array holds, so both counts
    // are written.
    ui.trace_view("trace", tr_tracks,
                  (int) (sizeof tr_tracks / sizeof *tr_tracks), tr_spans,
                  tr_n, tr_view, tr_sel, markers: tr_marks, height: 320);
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
