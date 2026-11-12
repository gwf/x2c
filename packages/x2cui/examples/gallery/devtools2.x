#pragma once

/*  devtools2.x -- the gallery's More developer tools page */

#include <math.h>
#include "state.x"

static TextField rx_pat, rx_text, rq_url;

static void prepare(void) {
  rx_pat = TextField.new(128);
  rx_pat.set("(?<user>[\\w.]+)@(?<host>[\\w-]+)\\.(com|org)");
  rx_text = TextField.new(1024);
  rx_text.set("Contact maya.okafor@example.com or jonas@cui-lib.org for "
              "access.\nOld address: priya@legacy.net (no longer read).\n"
              "Support: help@example.com");
  rq_url = TextField.new(256);
  rq_url.set("https://api.example.com/v1/orders?status=open&limit=20");
}

static void devtools2_regex(Ui ui) {
  ui.column (gap: 10, width: fill, max_width: 760)
    ui.regex_tester("rx", rx_pat, rx_text, height: 110);
}


static void devtools2_tests(Ui ui) {
  ui.column (gap: 10, width: fill, max_width: 760)
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
      {name: "ellipsis keeps whole characters", depth: 1, status: passed,
       duration: 0.003f},
      {name: "bidi brackets", depth: 1, status: skipped, duration: -1},
      {name: "renderer", depth: 0}, {name: "software", depth: 1},
      {name: "rounded corners", depth: 2, status: passed, duration: 0.031f},
      {name: "soft shadows", depth: 2, status: running, duration: -1},
      {name: "OpenGL", depth: 1},
      {name: "atlas growth", depth: 2, status: pending, duration: -1},
      {name: "slow gradient path", depth: 2, status: passed, duration: 1.42f}],
                     height: 500);
}


static void devtools2_stack(Ui ui) {
  ui.column (gap: 10, width: fill, max_width: 760)
    ui.stack_trace("trace", [
      {function: "total", file: "src/cart.js", line: 3, column: 29,
       source: [
         "function total(cart) {", "  let sum = 0;",
         "  for (const item of cart.items) {",
         "    sum += item.price * item.qty;", "  }", "  return sum;"],
       source_first: 1},
      {function: "checkout", file: "src/checkout.js", line: 3, column: 18,
       source: [
         "export function checkout(user) {",
         "  const cart = carts.get(user.id);", "  const amount = total(cart);",
         "  return charge(user, amount);"], source_first: 1},
      {function: "handle", file: "node_modules/express/lib/router/layer.js",
       line: 95, column: 5, external: true},
      {function: "next", file: "node_modules/express/lib/router/route.js",
       line: 149, column: 13, external: true},
      {function: "dispatch", file: "node_modules/express/lib/router/index.js",
       line: 284, column: 15, external: true},
      {function: "onRequest", file: "src/server.js", line: 41, column: 9}],
      title: "TypeError",
      message: "Cannot read properties of undefined (reading 'items')",
      lang: "js");
}

static int rq_method = 1;
static cui_kv_pair rq_params[8];
static int rq_n = -1;

// cui_url_params and cui_url_set_params take no cui_ctx, so they are raw C
// calls on the field's buffer.
static void devtools2_request(Ui ui) {
  if (rq_n < 0) rq_n = cui_url_params(rq_url.buffer, rq_params, 8);
  ui.column (gap: 12, width: fill, max_width: 760) {
    cui_request_bar_result r = ui.request_bar("req", rq_method, rq_url);
    if (r.changed) rq_n = cui_url_params(rq_url.buffer, rq_params, 8);
    if (ui.kv_editor("params", rq_params, rq_n))
      cui_url_set_params(rq_url.buffer, rq_url.capacity, rq_params, rq_n);
    ui.response_status(201, 0.142, 18400);
  }
}

static float up_api[90], up_web[90], up_db[90], up_cdn[90];

static void devtools2_uptime(Ui ui) {
  static bool init;
  if (!init) {
    init = true;
    for (int i = 0; i < 90; i++) {
      up_api[i] = 1;
      up_web[i] = 1;
      up_db[i] = 1;
      up_cdn[i] = i < 20 ? -1 : 1;
      if (i % 17 == 5) up_api[i] = 0.9985f;
      if (i == 61) up_api[i] = 0.962f;
      if (i == 44) up_web[i] = 0.93f;
      if (i % 23 == 9) up_db[i] = 0.995f;
      if (i == 88) up_db[i] = 0.97f;
    }
  }
  static const char *names_en[] = { "API", "Website", "Database", "CDN" };
  const cui_uptime_service sv[] = {
    { names_en[0], up_api, 90 }, { names_en[1], up_web, 90 },
    { names_en[2], up_db, 90 }, { names_en[3], up_cdn, 90 } };
  ui.column (gap: 10, width: fill, max_width: 860)
    ui.uptime("status", sv,
      last_day: (cui_date){ 2026, 11, 9 });
}

static float th_info[96], th_warn[96], th_err[96];
static double th_s0 = 1794240000 + 3600 * 5;
static double th_s1 = 1794240000 + 3600 * 7.5;

static void devtools2_histogram(Ui ui) {
  static bool init;
  if (!init) {
    init = true;
    for (int i = 0; i < 96; i++) {
      double x = i / 96.0;
      th_info[i] = (float) (120 + 80 * sin(x * 6.28 * 2) + (i * 37 % 23));
      th_warn[i] = (float) (12 + (i * 13 % 9) + (i > 60 && i < 70 ? 40 : 0));
      th_err[i] = (float) ((i * 7 % 5) + (i > 62 && i < 67 ? 30 : 0));
    }
  }
  const cui_histogram_series se[] = {
    { "Info", th_info, CUI_TONE_INFO },
    { "Warning", th_warn, CUI_TONE_WARNING },
    { "Error", th_err, CUI_TONE_DANGER } };
  ui.column (gap: 10, width: fill, max_width: 900)
    ui.time_histogram("logs", 1794240000, 900, 96, se,
                      th_s0, th_s1, utc: true, height: 150);
}


static void devtools2_coverage(Ui ui) {
  ui.column (gap: 10, width: fill, max_width: 820)
    ui.coverage("cov", [
      {path: "src/core/layout.c", lines: 1840, lines_hit: 1702, branches: 620,
       branches_hit: 541, functions: 88, functions_hit: 86},
      {path: "src/core/state.c", lines: 420, lines_hit: 401, branches: 96,
       branches_hit: 90, functions: 31, functions_hit: 31},
      {path: "src/core/draw.c", lines: 960, lines_hit: 610, branches: 300,
       branches_hit: 160, functions: 54, functions_hit: 40},
      {path: "src/text/shape.c", lines: 2210, lines_hit: 1490, branches: 802,
       branches_hit: 411, functions: 120, functions_hit: 88},
      {path: "src/text/atlas.c", lines: 640, lines_hit: 598, branches: 140,
       branches_hit: 131, functions: 30, functions_hit: 30},
      {path: "src/render/gl.c", lines: 1300, lines_hit: 410, branches: 260,
       branches_hit: 60, functions: 70, functions_hit: 22},
      {path: "src/render/software.c", lines: 2400, lines_hit: 2210,
       branches: 900, branches_hit: 799, functions: 140, functions_hit: 136},
      {path: "src/main.c", lines: 120, lines_hit: 120, branches: 10,
       branches_hit: 10, functions: 4, functions_hit: 4}], height: 372);
}


static void devtools2_blame(Ui ui) {
  List lines = %(
    "#include \"cui_internal.h\"" ""
    "/* the width a component asks for */"
    "static float measure(cui_node *n) {"
    "    float w = n->pad[1] + n->pad[3];"
    "    for (int c = n->first; c >= 0; c = next(c))"
    "        w += width_of(c) + n->gap;"
    "    return w - n->gap;" "}" ""
    "void cui__layout(cui_ctx *ui) {"
    "    for (int i = 0; i < ui->node_count; i++)"
    "        measure(&ui->nodes[i]);"
    "    place(ui, 0);  /* the root */" "}");
  ui.column (gap: 10, width: fill, max_width: 900)
    ui.blame("blame", lines,
      [0, 0, 1, 1, 2, 2, 2, 1, 1, 0, 3, 3, 4, 3, 3], 15, [
      {hash: "a1b2c3d4e5", author: "Maya Okafor", summary: "First layout pass",
       time: 1730000000},
      {hash: "b2c3d4e5f6", author: "Jonas Berg",
       summary: "Measure: count padding once", time: 1760000000},
      {hash: "c3d4e5f6a7", author: "Priya Nair",
       summary: "Gaps between children", time: 1790000000},
      {hash: "d4e5f6a7b8", author: "Omid Saadat",
       summary: "Layout entry point", time: 1793000000},
      {hash: "e5f6a7b8c9", author: "Aiko Tanaka",
       summary: "Measure every node", time: 1794100000}],
               lang: "c", now: 1794211200, height: 320,
               first_line: 120);
}

// CUI changes the switches and shares in place.
static cui_feature_flag ff_flags[] = {
  { "new-checkout", "Single-page checkout with saved cards",
    { true, true, false }, { 0, 25, 0 } },
  { "dark-mode-default", "Start new accounts in dark mode",
    { true, false, false } },
  { "search-v2", "Ranked search with typo tolerance",
    { true, true, true }, { 0, 100, 5 } },
  { "export-pdf", "Export reports as PDF", { false, false, false } },
};

static void devtools2_flags(Ui ui) {
  ui.column (gap: 10, width: fill, max_width: 860)
    ui.feature_flags("flags", ff_flags,
                     %("Development" "Staging" "Production"));
}

static const cui_api_param ax_p1[] = {
  { "id", "path", "string", true, "The user's id" },
  { "fields", "query", "string", false, "Comma separated fields to return" },
};
static const cui_api_param ax_p2[] = {
  { "limit", "query", "integer", false, "At most this many, default 20" },
  { "cursor", "query", "string", false, "From a previous page" },
};
static int ax_sel = 2;

static void devtools2_api(Ui ui) {
  ui.column (gap: 10, width: fill, max_width: 820)
    ui.api_explorer("api", [
      {method: "GET", path: "/users", summary: "List users", tag: "Users",
       params: ax_p2},
      {method: "POST", path: "/users", summary: "Create a user", tag: "Users"},
      {method: "GET", path: "/users/{id}", summary: "Get a user", tag: "Users",
       params: ax_p1},
      {method: "PATCH", path: "/users/{id}", summary: "Update a user",
       tag: "Users", params: ax_p1},
      {method: "DELETE", path: "/users/{id}", summary: "Delete a user",
       tag: "Users", params: ax_p1},
      {method: "GET", path: "/orders", summary: "List orders", tag: "Orders",
       params: ax_p2},
      {method: "PUT", path: "/orders/{id}/status",
       summary: "Set an order's status", tag: "Orders"},
      {method: "GET", path: "/v1/orders", summary: "List orders (old)",
       tag: "Orders", deprecated: true}],
                    selected: &ax_sel);
}

void page_devtools2(Ui ui, Gallery g) {
  static bool ready = false;
  if (!ready) {
    prepare();
    ready = true;
  }
  section(ui, "Test explorer", "Suites fold; hover a row to run it; filter "
                               "by status or name.");
  devtools2_tests(ui);
  section(ui, "Stack trace", "Library frames fold; a frame with source "
                             "opens; copy the trace.");
  devtools2_stack(ui);
  section(ui, "Blame", "Hover the gutter to mark a commit's lines; click it "
                       "to open the commit.");
  devtools2_blame(ui);
  section(ui, "Coverage", "Folders sum up their files; click a column to "
                          "sort.");
  devtools2_coverage(ui);
  section(ui, "Regex tester", "Matches and groups are marked as you type.");
  devtools2_regex(ui);
  section(ui, "HTTP request bar", "The parameters table and the URL stay in "
                                  "step.");
  devtools2_request(ui);
  section(ui, "API explorer", "Click an endpoint for its parameters.");
  devtools2_api(ui);
  section(ui, "Feature flags", "A switch per environment; click a share to "
                               "change it.");
  devtools2_flags(ui);
  section(ui, "Uptime", "One bar per day; hover for the day.");
  devtools2_uptime(ui);
  section(ui, "Time histogram", "Drag to select a range; click to clear it.");
  devtools2_histogram(ui);
}
