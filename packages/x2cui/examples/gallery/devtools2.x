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
  $cui.column(ui, { .gap = 10, .width = CUI_FILL, .max_width = 760 })
    ui.regex_tester("rx", rx_pat, rx_text, { .height = 110 });
}

static const cui_test_item tx_items[] = {
  { "layout", 0 },
  { "row distributes extra space", 1, CUI_JOB_PASSED, 0.004f },
  { "wraps to the next line", 1, CUI_JOB_PASSED, 0.006f },
  { "mirrors under right to left", 1, CUI_JOB_FAILED, 0.012f,
    "expected x = 412, got 388 (padding not mirrored)" },
  { "text", 0 },
  { "shapes Persian", 1, CUI_JOB_PASSED, 0.210f },
  { "ellipsis keeps whole characters", 1, CUI_JOB_PASSED, 0.003f },
  { "bidi brackets", 1, CUI_JOB_SKIPPED, -1 },
  { "renderer", 0 },
  { "software", 1 },
  { "rounded corners", 2, CUI_JOB_PASSED, 0.031f },
  { "soft shadows", 2, CUI_JOB_RUNNING, -1 },
  { "OpenGL", 1 },
  { "atlas growth", 2, CUI_JOB_PENDING, -1 },
  { "slow gradient path", 2, CUI_JOB_PASSED, 1.42f },
};

static void devtools2_tests(Ui ui) {
  $cui.column(ui, { .gap = 10, .width = CUI_FILL, .max_width = 760 })
    ui.test_explorer("tests", tx_items, $cui.count(tx_items),
                     { .height = 500 });
}

static const char *const st_src1[] = {
  "function total(cart) {", "  let sum = 0;",
  "  for (const item of cart.items) {", "    sum += item.price * item.qty;",
  "  }", "  return sum;" };
static const char *const st_src2[] = {
  "export function checkout(user) {", "  const cart = carts.get(user.id);",
  "  const amount = total(cart);", "  return charge(user, amount);" };
static const cui_stack_frame st_frames[] = {
  { "total", "src/cart.js", 3, 29, false, st_src1, 6, 1 },
  { "checkout", "src/checkout.js", 3, 18, false, st_src2, 4, 1 },
  { "handle", "node_modules/express/lib/router/layer.js", 95, 5, true },
  { "next", "node_modules/express/lib/router/route.js", 149, 13, true },
  { "dispatch", "node_modules/express/lib/router/index.js", 284, 15, true },
  { "onRequest", "src/server.js", 41, 9, false },
};

static void devtools2_stack(Ui ui) {
  $cui.column(ui, { .gap = 10, .width = CUI_FILL, .max_width = 760 })
    ui.stack_trace("trace", st_frames, $cui.count(st_frames), {
      .title = "TypeError",
      .message = "Cannot read properties of undefined (reading 'items')",
      .lang = "js" });
}

static int rq_method = 1;
static cui_kv_pair rq_params[8];
static int rq_n = -1;

// cui_url_params and cui_url_set_params take no cui_ctx, so they are raw C
// calls on the field's buffer.
static void devtools2_request(Ui ui) {
  if (rq_n < 0) rq_n = cui_url_params(rq_url.buffer, rq_params, 8);
  $cui.column(ui, { .gap = 12, .width = CUI_FILL, .max_width = 760 }) {
    cui_request_bar_result r = ui.request_bar("req", rq_method, rq_url, {});
    if (r.changed) rq_n = cui_url_params(rq_url.buffer, rq_params, 8);
    if (ui.kv_editor("params", rq_params, rq_n, $cui.count(rq_params), {}))
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
  $cui.column(ui, { .gap = 10, .width = CUI_FILL, .max_width = 860 })
    ui.uptime("status", sv, $cui.count(sv), {
      .last_day = (cui_date){ 2026, 11, 9 } });
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
  $cui.column(ui, { .gap = 10, .width = CUI_FILL, .max_width = 900 })
    ui.time_histogram("logs", 1794240000, 900, 96, se, $cui.count(se),
                      th_s0, th_s1, { .utc = true, .height = 150 });
}

static const cui_coverage_file cv_files[] = {
  { "src/core/layout.c", 1840, 1702, 620, 541, 88, 86 },
  { "src/core/state.c", 420, 401, 96, 90, 31, 31 },
  { "src/core/draw.c", 960, 610, 300, 160, 54, 40 },
  { "src/text/shape.c", 2210, 1490, 802, 411, 120, 88 },
  { "src/text/atlas.c", 640, 598, 140, 131, 30, 30 },
  { "src/render/gl.c", 1300, 410, 260, 60, 70, 22 },
  { "src/render/software.c", 2400, 2210, 900, 799, 140, 136 },
  { "src/main.c", 120, 120, 10, 10, 4, 4 },
};

static void devtools2_coverage(Ui ui) {
  $cui.column(ui, { .gap = 10, .width = CUI_FILL, .max_width = 820 })
    ui.coverage("cov", cv_files, $cui.count(cv_files), { .height = 372 });
}

static const int bl_commit[] = { 0, 0, 1, 1, 2, 2, 2, 1, 1, 0, 3, 3, 4, 3, 3 };
static const cui_blame_commit bl_commits[] = {
  { "a1b2c3d4e5", "Maya Okafor", "First layout pass", 1730000000 },
  { "b2c3d4e5f6", "Jonas Berg", "Measure: count padding once", 1760000000 },
  { "c3d4e5f6a7", "Priya Nair", "Gaps between children", 1790000000 },
  { "d4e5f6a7b8", "Omid Saadat", "Layout entry point", 1793000000 },
  { "e5f6a7b8c9", "Aiko Tanaka", "Measure every node", 1794100000 },
};

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
  $cui.column(ui, { .gap = 10, .width = CUI_FILL, .max_width = 900 })
    ui.blame("blame", lines, bl_commit, 15, bl_commits,
             $cui.count(bl_commits), {
               .lang = "c", .now = 1794211200, .height = 320,
               .first_line = 120 });
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
  $cui.column(ui, { .gap = 10, .width = CUI_FILL, .max_width = 860 })
    ui.feature_flags("flags", ff_flags, $cui.count(ff_flags),
                     %("Development" "Staging" "Production"), {});
}

static const cui_api_param ax_p1[] = {
  { "id", "path", "string", true, "The user's id" },
  { "fields", "query", "string", false, "Comma separated fields to return" },
};
static const cui_api_param ax_p2[] = {
  { "limit", "query", "integer", false, "At most this many, default 20" },
  { "cursor", "query", "string", false, "From a previous page" },
};
static const cui_api_endpoint ax_eps[] = {
  { "GET", "/users", "List users", "Users", false, ax_p2, 2 },
  { "POST", "/users", "Create a user", "Users" },
  { "GET", "/users/{id}", "Get a user", "Users", false, ax_p1, 2 },
  { "PATCH", "/users/{id}", "Update a user", "Users", false, ax_p1, 1 },
  { "DELETE", "/users/{id}", "Delete a user", "Users", false, ax_p1, 1 },
  { "GET", "/orders", "List orders", "Orders", false, ax_p2, 2 },
  { "PUT", "/orders/{id}/status", "Set an order's status", "Orders" },
  { "GET", "/v1/orders", "List orders (old)", "Orders", true },
};
static int ax_sel = 2;

static void devtools2_api(Ui ui) {
  $cui.column(ui, { .gap = 10, .width = CUI_FILL, .max_width = 820 })
    ui.api_explorer("api", ax_eps, $cui.count(ax_eps),
                    { .selected = &ax_sel });
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
