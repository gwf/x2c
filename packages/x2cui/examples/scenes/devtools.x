#pragma once

/*  devtools.x -- scenes for developer tools: API references, blame,
    commit and dependency graphs, coverage, feature flags, profilers, a hex
    viewer, a keymap, key-value and query editors, pipelines, problems,
    stack traces, tests, a network waterfall, and a tree table

    These components read arrays of CUI's records. The arrays are C arrays
    written with designated initializers, and each method form takes the
    array alone and supplies its count; an editor that grows its array
    takes the array and its live count, and supplies the capacity.
*/

#include "scene.x"

// The source lines that the blame scene annotates.
static List blame_lines;

// One row for each tree table node: name, size, and kind.
static List tree_files;

// Spans of one game frame in seconds, sorted by prepare.
static cui_flame_span flame_spans[] = {
  { "Frame 4812", 0.0000, 0.0164, 0 },
  { "Update", 0.0002, 0.0072, 1 },
  { "Render", 0.0074, 0.0150, 1 },
  { "Present", 0.0152, 0.0163, 1 },
  { "Input", 0.0003, 0.0007, 2 },
  { "Animation", 0.0008, 0.0023, 2 },
  { "Physics", 0.0024, 0.0056, 2 },
  { "Scripts", 0.0057, 0.0071, 2 },
  { "Cull", 0.0075, 0.0083, 2 },
  { "Shadow pass", 0.0084, 0.0103, 2 },
  { "GBuffer", 0.0104, 0.0130, 2 },
  { "Lighting", 0.0131, 0.0149, 2 },
  { "Swap buffers", 0.0153, 0.0162, 2 },
  { "Skinning", 0.0010, 0.0022, 3 },
  { "Broadphase", 0.0025, 0.0032, 3 },
  { "Narrowphase", 0.0033, 0.0042, 3 },
  { "Solver", 0.0043, 0.0055, 3 },
  { "Cascade 0", 0.0085, 0.0094, 3 },
  { "Cascade 1", 0.0095, 0.0102, 3 },
  { "Opaque", 0.0105, 0.0125, 3 },
  { "Wait for GPU", 0.0154, 0.0161, 3 },
};

// Two frames on the main thread and the render thread, sorted by prepare.
static cui_trace_span trace_spans[] = {
  { "Frame", 0.0004, 0.0151, 0, 0 },
  { "Update", 0.0021, 0.0092, 0, 1 },
  { "Physics", 0.0023, 0.0051, 0, 2 },
  { "Scripts", 0.0070, 0.0090, 0, 2 },
  { "Layout", 0.0094, 0.0121, 0, 1 },
  { "Paint", 0.0123, 0.0149, 0, 1 },
  { "Submit", 0.0152, 0.0163, 1, 0 },
  { "Frame", 0.0170, 0.0317, 0, 0 },
  { "Update", 0.0187, 0.0258, 0, 1 },
  { "Physics", 0.0189, 0.0217, 0, 2 },
  { "Scripts", 0.0236, 0.0256, 0, 2 },
  { "Layout", 0.0260, 0.0287, 0, 1 },
  { "Paint", 0.0289, 0.0315, 0, 1 },
  { "Submit", 0.0318, 0.0329, 1, 0 },
};

static void prepare(void) {
  blame_lines = %(
    "static float measure(cui_node *n) {"
    "    float w = n->pad[1] + n->pad[3];"
    "    for (int c = n->first; c >= 0; c = next(c))"
    "        w += width_of(c) + n->gap;"
    "    return w - n->gap;" "}" ""
    "void cui__layout(cui_ctx *ui) {"
    "    for (int i = 0; i < ui->node_count; i++)"
    "        measure(&ui->nodes[i]);" "}");
  tree_files = %(("x2cui" "" "Folder") ("examples" "" "Folder")
                 ("gallery" "" "Folder") ("scenes" "" "Folder")
                 ("gallery.x" "6 KB" "x2c source") ("src" "" "Folder")
                 ("x2cui.x" "38 KB" "x2c source")
                 ("x2cui-arrays.x" "4 KB" "x2c source")
                 ("README.md" "21 KB" "Markdown"));
  // CUI's sorts take no context, so they are raw C calls.
  cui_flame_sort(flame_spans,
                 (int) (sizeof flame_spans / sizeof *flame_spans));
  cui_trace_sort(trace_spans,
                 (int) (sizeof trace_spans / sizeof *trace_spans));
}

static void scene_api_explorer(Ui ui) {
  static int selected = 2;
  ui.api_explorer("api", [
    {method: "GET", path: "/users", summary: "List users", tag: "Users",
     params: [{name: "limit", in: "query", type: "integer", description: "At most this many, default 20"}, {name: "cursor", in: "query", type: "string", description: "From a previous page"}]},
    {method: "POST", path: "/users", summary: "Create a user", tag: "Users"},
    {method: "GET", path: "/users/{id}", summary: "Get a user", tag: "Users",
     params: [{name: "id", in: "path", type: "string", required: true, description: "The user's id"}, {name: "fields", in: "query", type: "string", description: "Comma separated fields"}]},
    {method: "DELETE", path: "/users/{id}", summary: "Delete a user",
     tag: "Users",
     params: [{name: "id", in: "path", type: "string", required: true, description: "The user's id"}, {name: "fields", in: "query", type: "string", description: "Comma separated fields"}]},
    {method: "GET", path: "/orders", summary: "List orders", tag: "Orders",
     params: [{name: "limit", in: "query", type: "integer", description: "At most this many, default 20"}, {name: "cursor", in: "query", type: "string", description: "From a previous page"}]},
    {method: "GET", path: "/v1/orders", summary: "List orders (old)",
     tag: "Orders", deprecated: true}],
    width: fill, height: 320, selected: &selected);
}

static void scene_blame(Ui ui) {
  static const cui_blame_commit commits[] = {
    { "a1b2c3d4e5", "Maya Okafor", "First layout pass", 1730000000 },
    { "b2c3d4e5f6", "Jonas Berg", "Measure: count padding once",
      1760000000 },
    { "c3d4e5f6a7", "Priya Nair", "Gaps between children", 1790000000 },
    { "d4e5f6a7b8", "Leo Park", "Layout entry point", 1793000000 },
    { "e5f6a7b8c9", "Aiko Tanaka", "Measure every node", 1794100000 } };
  ui.blame("blame", blame_lines, [0, 1, 2, 2, 1, 0, 0, 3, 3, 4, 3], blame_lines.len(), commits,
             width: fill, height: 220, lang: "c",
             now: 1794211200, first_line: 120);
}

static void scene_commit_graph(Ui ui) {
  static const cui_commit commits[] = {
    { "a91f3c2e", "Merge branch 'feature/trace-viewer'", "Maya Okafor",
      "2 hours ago", "main, origin/main", { 1, 3 } },
    { "c3d8a7f0", "Fix the ruler's last tick on narrow panels",
      "Jonas Berg", "5 hours ago", NULL, { 2, -1 } },
    { "1f22b9e4", "Release 1.2", "Jonas Berg", "yesterday", "tag: v1.2.0",
      { 5, -1 } },
    { "e8a0c55b", "Trace viewer: measure a range with Shift+drag",
      "Priya Nair", "yesterday", "feature/trace-viewer", { 4, -1 } },
    { "4d9e1a77", "Trace viewer: lanes, spans and markers", "Priya Nair",
      "2 days ago", NULL, { 5, -1 } },
    { "52ce8d0a", "Faster soft shadows in software", "Lena Fischer",
      "3 days ago", NULL, { 6, -1 } },
    { "0aa4c9e8", "Right to left layout", "Omid Saadat", "5 days ago",
      NULL, { -1, -1 } } };
  static int selected = 1;
  ui.commit_graph("history", commits,
    width: fill, height: 220, selected: &selected);
}

static void scene_coverage(Ui ui) {
  ui.coverage("cov", [
    {path: "src/core/layout.c", lines: 1840, lines_hit: 1702, branches: 620,
     branches_hit: 541, functions: 88, functions_hit: 86},
    {path: "src/core/draw.c", lines: 960, lines_hit: 610, branches: 300,
     branches_hit: 160, functions: 54, functions_hit: 40},
    {path: "src/text/shape.c", lines: 2210, lines_hit: 1490, branches: 802,
     branches_hit: 411, functions: 120, functions_hit: 88},
    {path: "src/render/gl.c", lines: 1300, lines_hit: 410, branches: 260,
     branches_hit: 60, functions: 70, functions_hit: 22},
    {path: "src/main.c", lines: 120, lines_hit: 120, branches: 10,
     branches_hit: 10, functions: 4, functions_hit: 4}],
    width: 640, height: 340);
}

static void scene_feature_flags(Ui ui) {
  // CUI changes the switches and shares in place.
  static cui_feature_flag flags[] = {
    { "new-checkout", "Single-page checkout with saved cards",
      { true, true, false }, { 0, 25, 0 } },
    { "dark-mode-default", "Start new accounts in dark mode",
      { true, false, false } },
    { "search-v2", "Ranked search with typo tolerance",
      { true, true, true }, { 0, 100, 5 } },
    { "export-pdf", "Export reports as PDF", { false, false, false } } };
  ui.feature_flags("flags", flags,
                   %("Development" "Staging" "Production"),
                   width: 640);
}

static void scene_flame_graph(Ui ui) {
  static cui_flame_view view;
  static int selected = 6;
  ui.column (width: 640, gap: 10) {
    if (selected >= 0) {
      cui_flame_span span = flame_spans[selected];
      double ms = (span.end - span.start) * 1e3;
      ui.text(String.format("%s, %.2f ms", span.name, ms),
              size: 13, color: text_secondary);
    }
    ui.flame_graph("profile", flame_spans, view,
                   selected);
  }
}

static void scene_graph_view(Ui ui) {
  static const cui_graph_node nodes[] = {
    { "app", "executable", CUI_TONE_VIOLET },
    { "ui", "libcui.a", CUI_TONE_INFO },
    { "net", "http client", CUI_TONE_INFO },
    { "render", "software, OpenGL", CUI_TONE_INFO },
    { "tls", "mbedtls", CUI_TONE_WARNING },
    { "zlib", NULL, CUI_TONE_NEUTRAL } };
  static int selected = 1;
  ui.graph_view("deps", nodes, [
    {from: 0, to: 1}, {from: 0, to: 2}, {from: 1, to: 3}, {from: 2, to: 4},
    {from: 2, to: 5}, {from: 3, to: 5}],
                width: 640, height: 280,
                selected: &selected);
}

static void scene_hex_view(Ui ui) {
  // The start of a PNG file: its signature, IHDR, and a tEXt chunk.
  static const uint8_t png[] = {
    0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A,
    0x00, 0x00, 0x00, 0x0D, 'I', 'H', 'D', 'R',
    0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x02, 0xD0,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x8D, 0x89, 0x6E, 0x4B,
    0x00, 0x00, 0x00, 0x0E, 't', 'E', 'X', 't',
    'S', 'o', 'f', 't', 'w', 'a', 'r', 'e', 0x00, 'x', '2', 'c', 'u', 'i',
    0x5B, 0x1E, 0x9C, 0x07 };
  static cui_hex_selection selection = { 0x10, 8, 0x17 };
  ui.hex_view("hex", png, sizeof png, selection,
    width: 640, ranges: [
      {offset: 0, length: 8, tone: info, label: "PNG signature"},
      {offset: 8, length: 25, tone: violet,
       label: "IHDR chunk, 1280 by 720 RGBA"},
      {offset: 33, length: 26, tone: teal, label: "tEXt chunk, Software"}]);
}

static void scene_keymap(Ui ui) {
  static int mods = CUI_MOD_PRIMARY;
  ui.keymap("keys", [
    {combo: {mods: CUI_MOD_PRIMARY, key: s}, action: "Save", category: 0},
    {combo: {mods: CUI_MOD_PRIMARY, key: o}, action: "Open", category: 0},
    {combo: {mods: CUI_MOD_PRIMARY, key: p}, action: "Go to file",
     category: 1},
    {combo: {mods: CUI_MOD_PRIMARY, key: g}, action: "Go to line",
     category: 1},
    {combo: {mods: CUI_MOD_PRIMARY, key: f}, action: "Find", category: 2},
    {combo: {mods: CUI_MOD_PRIMARY, key: z}, action: "Undo", category: 2},
    {combo: {mods: CUI_MOD_PRIMARY, key: b}, action: "Build", category: 3},
    {combo: {mods: CUI_MOD_PRIMARY, key: r}, action: "Run", category: 3},
    {combo: {mods: CUI_MOD_PRIMARY, key: r}, action: "Rename symbol",
     category: 2},
    {combo: {mods: 0, key: f5}, action: "Continue", category: 3},
    {combo: {mods: 0, key: f12}, action: "Definition", category: 1}],
    width: 664, categories: ["File", "Navigate", "Edit", "Run and debug"], mods: &mods);
}

static void scene_kv_editor(Ui ui) {
  static cui_kv_pair headers[8] = {
    { "Authorization", "Bearer 4f9c2e81d0b7a6", true, true },
    { "Accept", "application/json", true },
    { "X-Request-Id", "7d1c0a", false } };
  static int count = 3;
  ui.column (width: 600, gap: 10) {
    ui.text("Headers", font: medium);
    ui.kv_editor("headers", headers, count);
  }
}

static void scene_pipeline(Ui ui) {
  static int selected = 3;
  ui.pipeline("run", %("Build" "Test" "Deploy"), [
    {name: "linux-x64", stage: 0, status: passed, duration: 142},
    {name: "macos-arm64", stage: 0, status: passed, duration: 201},
    {name: "unit", stage: 1, status: passed, duration: 64},
    {name: "integration", stage: 1, status: running, duration: 95},
    {name: "lint", stage: 1, status: failed, duration: 12,
     allow_failure: true},
    {name: "staging", stage: 2, status: pending, duration: -1}],
              width: 640, selected: &selected);
}

static void scene_problems(Ui ui) {
  ui.problems("problems", [
    {severity: error, message: "use of undeclared identifier 'frame_time'",
     file: "src/render/timing.c", line: 42, column: 17, source: "clang",
     code: "undeclared-var"},
    {severity: warning, message: "unused variable 'scale'",
     file: "src/render/timing.c", line: 88, column: 11, source: "clang",
     code: "-Wunused-variable"},
    {severity: warning, message: "comparison of integers of different signs",
     file: "src/app/main.c", line: 77, column: 18, source: "gcc",
     code: "-Wsign-compare"},
    {severity: info, message: "function 'measure' could be declared static",
     file: "src/core/layout.c", line: 402, column: 6, source: "clang-tidy",
     code: "misc-use-internal-linkage"}],
    width: 640, height: 250);
}

static void scene_query_builder(Ui ui) {
  // All of: Status is Open, and any of: Assignee is me, Priority > 2.
  static cui_query_node nodes[12] = {
    { 0, true, false }, { 1, false, false, 0, 0, "Open" },
    { 1, true, true }, { 2, false, false, 1, 0, "me" },
    { 2, false, false, 2, 2, "2" } };
  static int count = 5;
  ui.query_builder("filter", [
    {name: "Status", type: choice, choices: ["Open", "In progress", "Closed"]},
    {name: "Assignee", type: text}, {name: "Priority", type: number}], nodes, count, width: 640);
}

static void scene_stack_trace(Ui ui) {
  ui.stack_trace("trace", [
    {function: "total", file: "src/cart.js", line: 3, column: 29,
     source: ["function total(cart) {", "  let sum = 0;", "  for (const item of cart.items) {", "    sum += item.price * item.qty;", "  }", "  return sum;"],
     source_first: 1},
    {function: "checkout", file: "src/checkout.js", line: 3, column: 18},
    {function: "handle", file: "node_modules/express/lib/router/layer.js",
     line: 95, column: 5, external: true},
    {function: "next", file: "node_modules/express/lib/router/route.js",
     line: 149, column: 13, external: true},
    {function: "onRequest", file: "src/server.js", line: 41, column: 9}],
    width: 640, title: "TypeError",
    message: "Cannot read properties of undefined (reading 'items')",
    lang: "js");
}

static void scene_test_explorer(Ui ui) {
  ui.test_explorer("tests", [
    {name: "layout", depth: 0},
    {name: "row distributes extra space", depth: 1, status: passed,
     duration: 0.004f},
    {name: "wraps to the next line", depth: 1, status: passed,
     duration: 0.006f},
    {name: "mirrors under right to left", depth: 1, status: failed,
     duration: 0.012f,
     message: "expected x = 412, got 388 (padding not mirrored)"},
    {name: "text", depth: 0},
    {name: "shapes Persian", depth: 1, status: passed, duration: 0.210f},
    {name: "bidi brackets", depth: 1, status: skipped, duration: -1},
    {name: "renderer", depth: 0},
    {name: "soft shadows", depth: 1, status: running, duration: -1},
    {name: "atlas growth", depth: 1, status: pending, duration: -1}],
    width: 640, height: 370);
}

static void scene_trace_view(Ui ui) {
  static cui_trace_track tracks[] = { { "Main thread" }, { "Render" } };
  static cui_trace_view view = { 0, 0.0335, 0, 0.0187, 0.0258 };
  static int selected = -1;
  if (selected < 0)
    for (int i = 0; i < (int) (sizeof trace_spans / sizeof *trace_spans); i++)
      if (trace_spans[i].start == 0.0187) selected = i;
  ui.trace_view("trace", tracks, trace_spans, view, selected,
                  width: 640, height: 170, markers: [
                    {name: "vsync", time: 0.0, tone: neutral},
                    {name: "vsync", time: 0.0166, tone: neutral},
                    {name: "GC pause", time: 0.0273, tone: warning}]);
}

static void scene_waterfall(Ui ui) {
  static int selected = 2;
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
    {name: "https://shop.example.com/api/session", method: "POST", status: 401,
     type: "fetch", size: 312, start: 0.402,
     timing: [0.002, 0, 0, 0, 0.083, 0.001]},
    {name: "https://shop.example.com/img/hero.avif", method: "GET",
     status: 200, type: "image", size: 212000, start: 0.410,
     timing: [0.012, 0, 0, 0, 0.052, 0.188]},
    {name: "https://analytics.example.org/collect", method: "POST", status: 0,
     type: "ping", size: 0, start: 0.702,
     timing: [0.004, 0.026, 0.031, 0.036, 0.12, 0]}],
    width: fill, height: 250, selected: &selected,
    dom_loaded: 0.395, loaded: 0.68);
}

static void scene_tree_table(Ui ui) {
  // Each node links to its parent, first child, and next sibling.
  static cui_tree_node nodes[] = {
    { -1, 1, -1, CUI_TREE_HAS_CHILDREN | CUI_TREE_OPEN },
    { 0, 2, 5, CUI_TREE_HAS_CHILDREN | CUI_TREE_OPEN },
    { 1, -1, 3, CUI_TREE_HAS_CHILDREN },
    { 1, -1, 4, CUI_TREE_HAS_CHILDREN },
    { 1, -1, -1, 0 },
    { 0, 6, 8, CUI_TREE_HAS_CHILDREN | CUI_TREE_OPEN },
    { 5, -1, 7, CUI_TREE_SELECTED },
    { 5, -1, -1, 0 },
    { 0, -1, -1, 0 } };
  static int cursor = 6;
  int node;
  ui.tree_table ("files", [
    {title: "Name", width: 300, align: left, sortable: true},
    {title: "Size", width: 100, align: right, sortable: true, priority: 1},
    {title: "Kind", width: 140, align: left, sortable: true, priority: 2}], nodes, width: 640, height: 340,
                 cursor: &cursor, guides: true)
    while ((node = ui.tree_table_row()) >= 0) {
      (String name, String size, String kind) = tree_files[node];
      ui.tree_table_name(name, kind == "Folder" ? folder
                                                : file);
      ui.grid_cell_text(size);
      ui.grid_cell_text(kind);
    }
}

static Scene devtools_scenes[] = {
  { "api_explorer", scene_api_explorer },
  { "blame", scene_blame },
  { "commit_graph", scene_commit_graph },
  { "coverage", scene_coverage },
  { "feature_flags", scene_feature_flags },
  { "flame_graph", scene_flame_graph },
  { "graph_view", scene_graph_view },
  { "hex_view", scene_hex_view },
  { "keymap", scene_keymap },
  { "kv_editor", scene_kv_editor },
  { "pipeline", scene_pipeline },
  { "problems", scene_problems },
  { "query_builder", scene_query_builder },
  { "stack_trace", scene_stack_trace },
  { "test_explorer", scene_test_explorer },
  { "trace_view", scene_trace_view },
  { "waterfall", scene_waterfall },
  { "tree_table_begin", scene_tree_table },
};

Family devtools_family(void) {
  prepare();
  return (Family){ "Developer tools", devtools_scenes,
                   sizeof devtools_scenes / sizeof *devtools_scenes };
}
