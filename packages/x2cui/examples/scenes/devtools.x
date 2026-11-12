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
static FlameSpans flame_spans = FlameSpans.of([
  {name: "Frame 4812", start: 0.0000, end: 0.0164, depth: 0},
  {name: "Update", start: 0.0002, end: 0.0072, depth: 1},
  {name: "Render", start: 0.0074, end: 0.0150, depth: 1},
  {name: "Present", start: 0.0152, end: 0.0163, depth: 1},
  {name: "Input", start: 0.0003, end: 0.0007, depth: 2},
  {name: "Animation", start: 0.0008, end: 0.0023, depth: 2},
  {name: "Physics", start: 0.0024, end: 0.0056, depth: 2},
  {name: "Scripts", start: 0.0057, end: 0.0071, depth: 2},
  {name: "Cull", start: 0.0075, end: 0.0083, depth: 2},
  {name: "Shadow pass", start: 0.0084, end: 0.0103, depth: 2},
  {name: "GBuffer", start: 0.0104, end: 0.0130, depth: 2},
  {name: "Lighting", start: 0.0131, end: 0.0149, depth: 2},
  {name: "Swap buffers", start: 0.0153, end: 0.0162, depth: 2},
  {name: "Skinning", start: 0.0010, end: 0.0022, depth: 3},
  {name: "Broadphase", start: 0.0025, end: 0.0032, depth: 3},
  {name: "Narrowphase", start: 0.0033, end: 0.0042, depth: 3},
  {name: "Solver", start: 0.0043, end: 0.0055, depth: 3},
  {name: "Cascade 0", start: 0.0085, end: 0.0094, depth: 3},
  {name: "Cascade 1", start: 0.0095, end: 0.0102, depth: 3},
  {name: "Opaque", start: 0.0105, end: 0.0125, depth: 3},
  {name: "Wait for GPU", start: 0.0154, end: 0.0161, depth: 3}]);

// Two frames on the main thread and the render thread, sorted by prepare.
static TraceSpans trace_spans = TraceSpans.of([
  {name: "Frame", start: 0.0004, end: 0.0151, track: 0, depth: 0},
  {name: "Update", start: 0.0021, end: 0.0092, track: 0, depth: 1},
  {name: "Physics", start: 0.0023, end: 0.0051, track: 0, depth: 2},
  {name: "Scripts", start: 0.0070, end: 0.0090, track: 0, depth: 2},
  {name: "Layout", start: 0.0094, end: 0.0121, track: 0, depth: 1},
  {name: "Paint", start: 0.0123, end: 0.0149, track: 0, depth: 1},
  {name: "Submit", start: 0.0152, end: 0.0163, track: 1, depth: 0},
  {name: "Frame", start: 0.0170, end: 0.0317, track: 0, depth: 0},
  {name: "Update", start: 0.0187, end: 0.0258, track: 0, depth: 1},
  {name: "Physics", start: 0.0189, end: 0.0217, track: 0, depth: 2},
  {name: "Scripts", start: 0.0236, end: 0.0256, track: 0, depth: 2},
  {name: "Layout", start: 0.0260, end: 0.0287, track: 0, depth: 1},
  {name: "Paint", start: 0.0289, end: 0.0315, track: 0, depth: 1},
  {name: "Submit", start: 0.0318, end: 0.0329, track: 1, depth: 0}]);

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
  cui_flame_sort(flame_spans.data(), flame_spans.len());
  cui_trace_sort(trace_spans.data(), trace_spans.len());
}

static void scene_api_explorer(Ui ui) {
  static int selected = 2;
  ui.api_explorer("api", [
    {method: "GET", path: "/users", summary: "List users", tag: "Users",
     params: [{name: "limit", in: "query", type: "integer",
               description: "At most this many, default 20"},
              {name: "cursor", in: "query", type: "string",
               description: "From a previous page"}]},
    {method: "POST", path: "/users", summary: "Create a user", tag: "Users"},
    {method: "GET", path: "/users/{id}", summary: "Get a user", tag: "Users",
     params: [{name: "id", in: "path", type: "string", required: true,
               description: "The user's id"},
              {name: "fields", in: "query", type: "string",
               description: "Comma separated fields"}]},
    {method: "DELETE", path: "/users/{id}", summary: "Delete a user",
     tag: "Users",
     params: [{name: "id", in: "path", type: "string", required: true,
               description: "The user's id"},
              {name: "fields", in: "query", type: "string",
               description: "Comma separated fields"}]},
    {method: "GET", path: "/orders", summary: "List orders", tag: "Orders",
     params: [{name: "limit", in: "query", type: "integer",
               description: "At most this many, default 20"},
              {name: "cursor", in: "query", type: "string",
               description: "From a previous page"}]},
    {method: "GET", path: "/v1/orders", summary: "List orders (old)",
     tag: "Orders", deprecated: true}],
    width: fill, height: 320, selected: &selected);
}

static void scene_blame(Ui ui) {
  ui.blame("blame", blame_lines, [0, 1, 2, 2, 1, 0, 0, 3, 3, 4, 3],
           blame_lines.len(), [
             {hash: "a1b2c3d4e5", author: "Maya Okafor",
              summary: "First layout pass", time: 1730000000},
             {hash: "b2c3d4e5f6", author: "Jonas Berg",
              summary: "Measure: count padding once", time: 1760000000},
             {hash: "c3d4e5f6a7", author: "Priya Nair",
              summary: "Gaps between children", time: 1790000000},
             {hash: "d4e5f6a7b8", author: "Leo Park",
              summary: "Layout entry point", time: 1793000000},
             {hash: "e5f6a7b8c9", author: "Aiko Tanaka",
              summary: "Measure every node", time: 1794100000}],
             width: fill, height: 220, lang: "c",
             now: 1794211200, first_line: 120);
}

static void scene_commit_graph(Ui ui) {
  static int selected = 1;
  ui.commit_graph("history", [
    {hash: "a91f3c2e", message: "Merge branch 'feature/trace-viewer'",
     author: "Maya Okafor", date: "2 hours ago", refs: "main, origin/main",
     parent: [1, 3]},
    {hash: "c3d8a7f0", message: "Fix the ruler's last tick on narrow panels",
     author: "Jonas Berg", date: "5 hours ago", parent: [2, -1]},
    {hash: "1f22b9e4", message: "Release 1.2", author: "Jonas Berg",
     date: "yesterday", refs: "tag: v1.2.0", parent: [5, -1]},
    {hash: "e8a0c55b",
     message: "Trace viewer: measure a range with Shift+drag",
     author: "Priya Nair", date: "yesterday", refs: "feature/trace-viewer",
     parent: [4, -1]},
    {hash: "4d9e1a77", message: "Trace viewer: lanes, spans and markers",
     author: "Priya Nair", date: "2 days ago", parent: [5, -1]},
    {hash: "52ce8d0a", message: "Faster soft shadows in software",
     author: "Lena Fischer", date: "3 days ago", parent: [6, -1]},
    {hash: "0aa4c9e8", message: "Right to left layout", author: "Omid Saadat",
     date: "5 days ago", parent: [-1, -1]}],
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
  static FeatureFlags flags = FeatureFlags.of([
    {key: "new-checkout", description: "Single-page checkout with saved cards",
     on: [true, true, false], rollout: [0, 25, 0]},
    {key: "dark-mode-default", description: "Start new accounts in dark mode",
     on: [true, false, false]},
    {key: "search-v2", description: "Ranked search with typo tolerance",
     on: [true, true, true], rollout: [0, 100, 5]},
    {key: "export-pdf", description: "Export reports as PDF",
     on: [false, false, false]}]);
  ui.feature_flags("flags", flags,
                   %("Development" "Staging" "Production"),
                   width: 640);
}

static void scene_flame_graph(Ui ui) {
  static cui_flame_view view;
  static int selected = 6;
  ui.column (width: 640, gap: 10) {
    if (selected >= 0) {
      cui_flame_span span = *flame_spans[selected];
      double ms = (span.end - span.start) * 1e3;
      ui.text(String.format("%s, %.2f ms", span.name, ms),
              size: 13, color: text_secondary);
    }
    ui.flame_graph("profile", flame_spans, view,
                   selected);
  }
}

static void scene_graph_view(Ui ui) {
  static int selected = 1;
  ui.graph_view("deps", [
    {label: "app", detail: "executable", tone: violet},
    {label: "ui", detail: "libcui.a", tone: info},
    {label: "net", detail: "http client", tone: info},
    {label: "render", detail: "software, OpenGL", tone: info},
    {label: "tls", detail: "mbedtls", tone: warning},
    {label: "zlib", tone: neutral}], [
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
    width: 664, categories: ["File", "Navigate", "Edit", "Run and debug"],
    mods: &mods);
}

static void scene_kv_editor(Ui ui) {
  static KvPairs headers = KvPairs.of([
    {key: "Authorization", value: "Bearer 4f9c2e81d0b7a6", enabled: true,
     secret: true},
    {key: "Accept", value: "application/json", enabled: true},
    {key: "X-Request-Id", value: "7d1c0a"}]);
  ui.column (width: 600, gap: 10) {
    ui.text("Headers", font: medium);
    ui.kv_editor("headers", headers);
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
  static QueryNodes nodes = QueryNodes.of([
    {depth: 0, group: true}, {depth: 1, field: 0, op: 0, value: "Open"},
    {depth: 1, group: true, any: true},
    {depth: 2, field: 1, op: 0, value: "me"},
    {depth: 2, field: 2, op: 2, value: "2"}]);
  ui.query_builder("filter", [
    {name: "Status", type: choice, choices: ["Open", "In progress", "Closed"]},
    {name: "Assignee", type: text}, {name: "Priority", type: number}],
    nodes, width: 640);
}

static void scene_stack_trace(Ui ui) {
  ui.stack_trace("trace", [
    {function: "total", file: "src/cart.js", line: 3, column: 29,
     source: [
       "function total(cart) {", "  let sum = 0;",
       "  for (const item of cart.items) {",
       "    sum += item.price * item.qty;", "  }", "  return sum;"],
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
  static TraceTracks tracks = TraceTracks.of([
    {name: "Main thread"}, {name: "Render"}]);
  static cui_trace_view view = { 0, 0.0335, 0, 0.0187, 0.0258 };
  static int selected = -1;
  if (selected < 0)
    for (int i = 0; i < trace_spans.len(); i++)
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
  static TreeNodes nodes = TreeNodes.of([
    {parent: -1, first_child: 1, next_sibling: -1,
     flags: CUI_TREE_HAS_CHILDREN | CUI_TREE_OPEN},
    {parent: 0, first_child: 2, next_sibling: 5,
     flags: CUI_TREE_HAS_CHILDREN | CUI_TREE_OPEN},
    {parent: 1, first_child: -1, next_sibling: 3,
     flags: CUI_TREE_HAS_CHILDREN},
    {parent: 1, first_child: -1, next_sibling: 4,
     flags: CUI_TREE_HAS_CHILDREN},
    {parent: 1, first_child: -1, next_sibling: -1, flags: 0},
    {parent: 0, first_child: 6, next_sibling: 8,
     flags: CUI_TREE_HAS_CHILDREN | CUI_TREE_OPEN},
    {parent: 5, first_child: -1, next_sibling: 7, flags: CUI_TREE_SELECTED},
    {parent: 5, first_child: -1, next_sibling: -1, flags: 0},
    {parent: 0, first_child: -1, next_sibling: -1, flags: 0}]);
  static int cursor = 6;
  int node;
  ui.tree_table ("files", [
    {title: "Name", width: 300, align: left, sortable: true},
    {title: "Size", width: 100, align: right, sortable: true, priority: 1},
    {title: "Kind", width: 140, align: left, sortable: true, priority: 2}],
    nodes, width: 640, height: 340,
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
