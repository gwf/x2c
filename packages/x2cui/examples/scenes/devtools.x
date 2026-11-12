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
  static const cui_api_param by_id[] = {
    { "id", "path", "string", true, "The user's id" },
    { "fields", "query", "string", false, "Comma separated fields" } };
  static const cui_api_param paging[] = {
    { "limit", "query", "integer", false, "At most this many, default 20" },
    { "cursor", "query", "string", false, "From a previous page" } };
  static const cui_api_endpoint endpoints[] = {
    { "GET", "/users", "List users", "Users", false, paging, 2 },
    { "POST", "/users", "Create a user", "Users" },
    { "GET", "/users/{id}", "Get a user", "Users", false, by_id, 2 },
    { "DELETE", "/users/{id}", "Delete a user", "Users", false, by_id, 1 },
    { "GET", "/orders", "List orders", "Orders", false, paging, 2 },
    { "GET", "/v1/orders", "List orders (old)", "Orders", true } };
  static int selected = 2;
  ui.api_explorer("api", endpoints,
    width: CUI_FILL, height: 320, selected: &selected);
}

static void scene_blame(Ui ui) {
  static const int line_commit[] = { 0, 1, 2, 2, 1, 0, 0, 3, 3, 4, 3 };
  static const cui_blame_commit commits[] = {
    { "a1b2c3d4e5", "Maya Okafor", "First layout pass", 1730000000 },
    { "b2c3d4e5f6", "Jonas Berg", "Measure: count padding once",
      1760000000 },
    { "c3d4e5f6a7", "Priya Nair", "Gaps between children", 1790000000 },
    { "d4e5f6a7b8", "Leo Park", "Layout entry point", 1793000000 },
    { "e5f6a7b8c9", "Aiko Tanaka", "Measure every node", 1794100000 } };
  ui.blame("blame", blame_lines, line_commit, blame_lines.len(), commits,
             width: CUI_FILL, height: 220, lang: "c",
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
    width: CUI_FILL, height: 220, selected: &selected);
}

static void scene_coverage(Ui ui) {
  static const cui_coverage_file files[] = {
    { "src/core/layout.c", 1840, 1702, 620, 541, 88, 86 },
    { "src/core/draw.c", 960, 610, 300, 160, 54, 40 },
    { "src/text/shape.c", 2210, 1490, 802, 411, 120, 88 },
    { "src/render/gl.c", 1300, 410, 260, 60, 70, 22 },
    { "src/main.c", 120, 120, 10, 10, 4, 4 } };
  ui.coverage("cov", files,
    width: CUI_PX(640), height: 340);
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
                   width: CUI_PX(640));
}

static void scene_flame_graph(Ui ui) {
  static cui_flame_view view;
  static int selected = 6;
  ui.column (width: CUI_PX(640), gap: 10) {
    if (selected >= 0) {
      cui_flame_span span = flame_spans[selected];
      double ms = (span.end - span.start) * 1e3;
      ui.text(String.format("%s, %.2f ms", span.name, ms),
              size: 13, color: CUI_COLOR_TEXT_SECONDARY);
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
  static const cui_graph_edge edges[] = {
    { 0, 1 }, { 0, 2 }, { 1, 3 }, { 2, 4 }, { 2, 5 }, { 3, 5 } };
  static int selected = 1;
  ui.graph_view("deps", nodes, edges,
                width: CUI_PX(640), height: 280,
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
  static const cui_hex_range marks[] = {
    { 0, 8, CUI_TONE_INFO, "PNG signature" },
    { 8, 25, CUI_TONE_VIOLET, "IHDR chunk, 1280 by 720 RGBA" },
    { 33, 26, CUI_TONE_TEAL, "tEXt chunk, Software" } };
  static cui_hex_selection selection = { 0x10, 8, 0x17 };
  ui.hex_view("hex", png, sizeof png, selection,
    width: CUI_PX(640), ranges: marks);
}

static void scene_keymap(Ui ui) {
  static const cui_keymap_binding bindings[] = {
    { { CUI_MOD_PRIMARY, CUI_KEY_S }, "Save", 0 },
    { { CUI_MOD_PRIMARY, CUI_KEY_O }, "Open", 0 },
    { { CUI_MOD_PRIMARY, CUI_KEY_P }, "Go to file", 1 },
    { { CUI_MOD_PRIMARY, CUI_KEY_G }, "Go to line", 1 },
    { { CUI_MOD_PRIMARY, CUI_KEY_F }, "Find", 2 },
    { { CUI_MOD_PRIMARY, CUI_KEY_Z }, "Undo", 2 },
    { { CUI_MOD_PRIMARY, CUI_KEY_B }, "Build", 3 },
    { { CUI_MOD_PRIMARY, CUI_KEY_R }, "Run", 3 },
    { { CUI_MOD_PRIMARY, CUI_KEY_R }, "Rename symbol", 2 },
    { { 0, CUI_KEY_F5 }, "Continue", 3 },
    { { 0, CUI_KEY_F12 }, "Definition", 1 } };
  static const char *categories[] = { "File", "Navigate", "Edit",
                                      "Run and debug" };
  static int mods = CUI_MOD_PRIMARY;
  ui.keymap("keys", bindings,
    width: CUI_PX(664), categories: categories, mods: &mods);
}

static void scene_kv_editor(Ui ui) {
  static cui_kv_pair headers[8] = {
    { "Authorization", "Bearer 4f9c2e81d0b7a6", true, true },
    { "Accept", "application/json", true },
    { "X-Request-Id", "7d1c0a", false } };
  static int count = 3;
  ui.column (width: CUI_PX(600), gap: 10) {
    ui.text("Headers", font: CUI_FONT_MEDIUM);
    ui.kv_editor("headers", headers, count);
  }
}

static void scene_pipeline(Ui ui) {
  static const cui_pipeline_job jobs[] = {
    { "linux-x64", 0, CUI_JOB_PASSED, 142 },
    { "macos-arm64", 0, CUI_JOB_PASSED, 201 },
    { "unit", 1, CUI_JOB_PASSED, 64 },
    { "integration", 1, CUI_JOB_RUNNING, 95 },
    { "lint", 1, CUI_JOB_FAILED, 12, true },
    { "staging", 2, CUI_JOB_PENDING, -1 } };
  static int selected = 3;
  ui.pipeline("run", %("Build" "Test" "Deploy"), jobs,
              width: CUI_PX(640), selected: &selected);
}

static void scene_problems(Ui ui) {
  static const cui_diagnostic diagnostics[] = {
    { CUI_SEVERITY_ERROR, "use of undeclared identifier 'frame_time'",
      "src/render/timing.c", 42, 17, "clang", "undeclared-var" },
    { CUI_SEVERITY_WARNING, "unused variable 'scale'",
      "src/render/timing.c", 88, 11, "clang", "-Wunused-variable" },
    { CUI_SEVERITY_WARNING, "comparison of integers of different signs",
      "src/app/main.c", 77, 18, "gcc", "-Wsign-compare" },
    { CUI_SEVERITY_INFO, "function 'measure' could be declared static",
      "src/core/layout.c", 402, 6, "clang-tidy",
      "misc-use-internal-linkage" } };
  ui.problems("problems", diagnostics,
    width: CUI_PX(640), height: 250);
}

static void scene_query_builder(Ui ui) {
  static const char *const statuses[] = { "Open", "In progress", "Closed" };
  static const cui_query_field fields[] = {
    { "Status", CUI_QUERY_CHOICE, statuses, 3 },
    { "Assignee", CUI_QUERY_TEXT },
    { "Priority", CUI_QUERY_NUMBER } };
  // All of: Status is Open, and any of: Assignee is me, Priority > 2.
  static cui_query_node nodes[12] = {
    { 0, true, false }, { 1, false, false, 0, 0, "Open" },
    { 1, true, true }, { 2, false, false, 1, 0, "me" },
    { 2, false, false, 2, 2, "2" } };
  static int count = 5;
  ui.query_builder("filter", fields, nodes, count, width: CUI_PX(640));
}

static void scene_stack_trace(Ui ui) {
  static const char *const cart[] = {
    "function total(cart) {", "  let sum = 0;",
    "  for (const item of cart.items) {",
    "    sum += item.price * item.qty;", "  }", "  return sum;" };
  static const cui_stack_frame frames[] = {
    { "total", "src/cart.js", 3, 29, false, cart, 6, 1 },
    { "checkout", "src/checkout.js", 3, 18 },
    { "handle", "node_modules/express/lib/router/layer.js", 95, 5, true },
    { "next", "node_modules/express/lib/router/route.js", 149, 13, true },
    { "onRequest", "src/server.js", 41, 9 } };
  ui.stack_trace("trace", frames,
    width: CUI_PX(640), title: "TypeError",
    message: "Cannot read properties of undefined (reading 'items')",
    lang: "js");
}

static void scene_test_explorer(Ui ui) {
  static const cui_test_item tests[] = {
    { "layout", 0 },
    { "row distributes extra space", 1, CUI_JOB_PASSED, 0.004f },
    { "wraps to the next line", 1, CUI_JOB_PASSED, 0.006f },
    { "mirrors under right to left", 1, CUI_JOB_FAILED, 0.012f,
      "expected x = 412, got 388 (padding not mirrored)" },
    { "text", 0 },
    { "shapes Persian", 1, CUI_JOB_PASSED, 0.210f },
    { "bidi brackets", 1, CUI_JOB_SKIPPED, -1 },
    { "renderer", 0 },
    { "soft shadows", 1, CUI_JOB_RUNNING, -1 },
    { "atlas growth", 1, CUI_JOB_PENDING, -1 } };
  ui.test_explorer("tests", tests,
    width: CUI_PX(640), height: 370);
}

static void scene_trace_view(Ui ui) {
  static cui_trace_track tracks[] = { { "Main thread" }, { "Render" } };
  static const cui_trace_marker markers[] = {
    { "vsync", 0.0, CUI_TONE_NEUTRAL },
    { "vsync", 0.0166, CUI_TONE_NEUTRAL },
    { "GC pause", 0.0273, CUI_TONE_WARNING } };
  static cui_trace_view view = { 0, 0.0335, 0, 0.0187, 0.0258 };
  static int selected = -1;
  if (selected < 0)
    for (int i = 0; i < (int) (sizeof trace_spans / sizeof *trace_spans); i++)
      if (trace_spans[i].start == 0.0187) selected = i;
  ui.trace_view("trace", tracks, trace_spans, view, selected,
                  width: CUI_PX(640), height: 170, markers: markers);
}

static void scene_waterfall(Ui ui) {
  static const cui_net_request requests[] = {
    { "https://shop.example.com/", "GET", 200, "document", 18400, 0.000,
      { 0.002, 0.018, 0.024, 0.031, 0.142, 0.012 } },
    { "https://shop.example.com/assets/app.css", "GET", 200, "stylesheet",
      42100, 0.232, { 0.004, 0, 0, 0, 0.061, 0.022 } },
    { "https://shop.example.com/assets/app.js", "GET", 200, "script",
      186000, 0.233, { 0.005, 0, 0, 0, 0.068, 0.094 } },
    { "https://shop.example.com/api/session", "POST", 401, "fetch", 312,
      0.402, { 0.002, 0, 0, 0, 0.083, 0.001 } },
    { "https://shop.example.com/img/hero.avif", "GET", 200, "image",
      212000, 0.410, { 0.012, 0, 0, 0, 0.052, 0.188 } },
    { "https://analytics.example.org/collect", "POST", 0, "ping", 0, 0.702,
      { 0.004, 0.026, 0.031, 0.036, 0.12, 0 } } };
  static int selected = 2;
  ui.waterfall("net", requests,
    width: CUI_FILL, height: 250, selected: &selected,
    dom_loaded: 0.395, loaded: 0.68);
}

static void scene_tree_table(Ui ui) {
  static const cui_grid_column columns[] = {
    { "Name", 300, CUI_TEXT_LEFT, true },
    { "Size", 100, CUI_TEXT_RIGHT, true, false, 1 },
    { "Kind", 140, CUI_TEXT_LEFT, true, false, 2 } };
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
  ui.tree_table ("files", columns, nodes, width: 640, height: 340,
                 cursor: &cursor, guides: true)
    while ((node = ui.tree_table_row()) >= 0) {
      (String name, String size, String kind) = tree_files[node];
      ui.tree_table_name(name, kind == "Folder" ? CUI_ICON_FOLDER
                                                : CUI_ICON_FILE);
      ui.data_grid_cell_text(size);
      ui.data_grid_cell_text(kind);
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
