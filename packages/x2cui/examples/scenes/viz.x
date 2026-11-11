#pragma once

/*  viz.x -- scenes for visualizations, meters, and figure strips

    These components read C arrays of numbers or of CUI's records. Each
    method takes the array and its count, and `$cui.count` supplies the
    count. The generated series are filled once, in `prepare`.
*/

#include <math.h>

#include "scene.x"

// Platform shares of installs, in percent.
static ArrayFloat shares;

// Requests by weekday and hour.
static float traffic[7 * 24];

// Commits on each day of the first half of 2026.
static float commits[182];

// One price candle a trading day.
static cui_candle candles[60];

// Frame time against node count, sized by draw calls.
static cui_vec2 software_points[24], opengl_points[24];
static float software_sizes[24], opengl_sizes[24];

// Audio peaks of a track, 0 to 1.
static float peaks[80];

// The fraction of each day a service was up; negative means no data.
static float api_days[60], web_days[60], cdn_days[60];

// Log lines in each 15 minute bucket of one day.
static float info_lines[96], warning_lines[96], error_lines[96];

static void prepare_traffic(void) {
  for (int d = 0; d < 7; d++)
    for (int h = 0; h < 24; h++) {
      float work = d < 5 ? 1.0f : 0.45f;
      float load = expf(-powf((h - 13.5f) / 4.2f, 2)) * 90 * work +
                   expf(-powf((h - 20.5f) / 2.0f, 2)) * 35;
      traffic[d * 24 + h] = load + (float) ((d * 31 + h * 17) % 11);
    }
}

static void prepare_commits(void) {
  unsigned seed = 7;
  for (int k = 0; k < $cui.count(commits); k++) {
    seed = seed * 1103515245u + 12345u;
    // 2026-01-01 is a Thursday, so weekday 5 and 6 are the weekend.
    int weekday = (k + 3) % 7;
    float base = weekday >= 5 ? 0.6f : 3.2f;
    float r = (float) ((seed >> 16) % 1000) / 1000.0f;
    commits[k] = r < 0.18f ? 0 : floorf(base * r * 4);
  }
}

static void prepare_candles(void) {
  float price = 64;
  for (int k = 0; k < $cui.count(candles); k++) {
    float open = price;
    float close = open * (1 + sinf(k * 0.37f) * 0.018f +
                          cosf(k * 0.11f) * 0.01f);
    candles[k] = (cui_candle){ open, fmaxf(open, close) * 1.006f,
                               fminf(open, close) * 0.994f, close,
                               2000 + (float) ((k * 7919) % 900) * 10 };
    price = close;
  }
}

static void prepare_scatter(void) {
  for (int k = 0; k < $cui.count(software_points); k++) {
    float nodes = 200 + k * 160.0f;
    software_points[k] = (cui_vec2){
      nodes, 0.08f + nodes * 0.00006f + (float) ((k * 37) % 13) * 0.004f };
    opengl_points[k] = (cui_vec2){
      nodes * 0.9f + 150,
      0.15f + nodes * 0.00011f + (float) ((k * 53) % 17) * 0.006f };
    software_sizes[k] = (float) (10 + (k * 7) % 40);
    opengl_sizes[k] = (float) (20 + (k * 11) % 50);
  }
}

static void prepare_signals(void) {
  for (int k = 0; k < $cui.count(peaks); k++)
    peaks[k] = 0.18f + 0.8f * fabsf(sinf(k * 0.37f) * sinf(k * 0.11f + 1.3f));
  for (int d = 0; d < $cui.count(api_days); d++) {
    api_days[d] = d == 41 ? 0.962f : d % 17 == 5 ? 0.9985f : 1;
    web_days[d] = d == 28 ? 0.93f : 1;
    cdn_days[d] = d < 12 ? -1 : 1;
  }
  for (int i = 0; i < $cui.count(info_lines); i++) {
    info_lines[i] = 120 + 80 * sinf(i / 96.0f * 6.28f * 2) + (i * 37 % 23);
    warning_lines[i] = 12 + (i * 13 % 9) + (i > 60 && i < 70 ? 40 : 0);
    error_lines[i] = (i * 7 % 5) + (i > 62 && i < 67 ? 30 : 0);
  }
}

static void prepare(void) {
  shares = [46, 27, 17, 10];
  prepare_traffic();
  prepare_commits();
  prepare_candles();
  prepare_scatter();
  prepare_signals();
}

static void scene_donut_chart(Ui ui) {
  $cui.card(ui, { .align = CUI_ALIGN_CENTER })
    ui.donut_chart("platforms", shares,
                   %("Windows" "macOS" "Linux" "Other"),
                   height: 200, format: "%.0f%%");
}

static void scene_activity_rings(Ui ui) {
  static const cui_viz_item rings[] = {
    { "Move", 0.82f }, { "Exercise", 1.24f }, { "Stand", 0.58f } };
  $cui.card(ui, { .pad = 18 })
    ui.activity_rings("rings", rings, $cui.count(rings),
      size: 170, center: "82%", caption: "of goal", legend: true);
}

static void scene_bar_list(Ui ui) {
  static const cui_viz_item pages[] = {
    { "/docs", 4820 }, { "/", 3920 }, { "/gallery", 2410 },
    { "/blog/fast-ui-in-c", 1830 }, { "/download", 1210 },
    { "/pricing", 640 } };
  $cui.card(ui, { .width = CUI_FILL, .max_width = 480, .gap = 10 }) {
    ui.label("Top pages this week");
    ui.bar_list("pages", pages, $cui.count(pages));
  }
}

static void scene_calendar_heatmap(Ui ui) {
  $cui.card(ui, { .pad = 18 })
    ui.calendar_heatmap("activity", (cui_date){ 2026, 1, 1 }, commits,
                        $cui.count(commits), unit: "commits");
}

static void scene_candlestick(Ui ui) {
  $cui.card(ui, { .width = CUI_FILL, .max_width = 660, .gap = 10 }) {
    ui.label("Price, 60 trading days");
    ui.candlestick("price", candles, $cui.count(candles), height: 260);
  }
}

static void scene_funnel(Ui ui) {
  static const cui_viz_item stages[] = {
    { "Visited", 12840 }, { "Signed up", 4210 }, { "Activated", 2380 },
    { "Subscribed", 860 } };
  $cui.card(ui, { .width = CUI_FILL, .max_width = 520 })
    ui.funnel("signups", stages, $cui.count(stages));
}

static void scene_heatmap(Ui ui) {
  static const char *weekdays[] = { "Mon", "Tue", "Wed", "Thu", "Fri",
                                    "Sat", "Sun" };
  static const char *hours[24] = {
    "0h", NULL, NULL, "3h", NULL, NULL, "6h", NULL, NULL, "9h", NULL, NULL,
    "12h", NULL, NULL, "15h", NULL, NULL, "18h", NULL, NULL, "21h", NULL,
    NULL };
  $cui.card(ui, { .pad = 18, .width = CUI_FILL, .max_width = 660 })
    ui.heatmap("traffic", traffic, 7, 24,
      row_labels: weekdays, col_labels: hours, format: "%.0f req");
}

static void scene_radar_chart(Ui ui) {
  static const float stable[] = { 82, 64, 90, 58, 75, 88 };
  static const float next[] = { 70, 85, 72, 80, 60, 79 };
  static const cui_series releases[] = {
    { "1.0", stable, $cui.count(stable) },
    { "1.1", next, $cui.count(next) } };
  $cui.card(ui, { .pad = 18 })
    ui.radar_chart("qualities", releases, $cui.count(releases),
                   %("Speed" "Size" "Polish" "Docs" "Platforms" "Tests"),
                   size: 240, max: 100);
}

static void scene_sankey(Ui ui) {
  static const cui_sankey_link links[] = {
    { 0, 3, 420 }, { 1, 3, 260 }, { 2, 3, 180 }, { 0, 4, 300 },
    { 1, 4, 220 }, { 3, 5, 860 }, { 5, 6, 580 }, { 5, 7, 280 } };
  $cui.card(ui, { .pad = 18, .width = CUI_FILL, .max_width = 660 })
    ui.sankey("signups", %("Search" "Social" "Referral" "Sign up" "Bounced"
                           "Trial" "Paid" "Churned"),
              links, $cui.count(links), height: 260);
}

static void scene_scatter_chart(Ui ui) {
  static const cui_scatter_series series[] = {
    { "Software", software_points, software_sizes,
      $cui.count(software_points) },
    { "OpenGL", opengl_points, opengl_sizes, $cui.count(opengl_points) } };
  $cui.card(ui, { .pad = 18, .width = CUI_FILL, .max_width = 660 })
    ui.scatter_chart("frames", series, $cui.count(series),
      height: 280, x_label: "Nodes", y_label: "Frame time (ms)",
      y_format: "%.2f");
}

static void scene_split_bar(Ui ui) {
  static const cui_viz_item parts[] = {
    { "Layout", 38 }, { "Text", 24 }, { "Paint", 21 }, { "Input", 9 },
    { "Other", 8 } };
  $cui.card(ui, { .width = CUI_FILL, .max_width = 520, .gap = 10 }) {
    ui.label("Frame time by stage");
    ui.split_bar("frame", parts, $cui.count(parts), format: "%.0f ms");
  }
}

static void scene_treemap(Ui ui) {
  static const cui_viz_item modules[] = {
    { "Layout", 55 }, { "Text", 42 }, { "Draw", 35 }, { "Controls", 31 },
    { "Charts", 23 }, { "Overlays", 19 }, { "Platform", 16 },
    { "Theme", 9 }, { "Icons", 7 }, { "Grid", 6 } };
  $cui.box(ui, { .width = CUI_FILL, .max_width = 620 })
    ui.treemap("bundle", modules, $cui.count(modules),
               height: 280, format: "%.0f KB");
}

static void scene_waffle(Ui ui) {
  static const cui_viz_item platforms[] = {
    { "Windows", 46 }, { "macOS", 31 }, { "Linux", 23 } };
  $cui.card(ui, { .pad = 18, .gap = 10 }) {
    ui.label("Platforms of the last 100 installs");
    ui.waffle("installs", platforms, $cui.count(platforms), cell: 16);
  }
}

static void scene_waveform(Ui ui) {
  static float progress = 0.36f;
  $cui.card(ui, { .pad = 14, .width = CUI_PX(380) })
  $cui.row(ui, { .gap = 12, .align = CUI_ALIGN_CENTER, .width = CUI_FILL }) {
    ui.icon_button(CUI_ICON_PLAY, size: CUI_SIZE_SM,
                                  variant: CUI_BUTTON_SECONDARY);
    $cui.box(ui, { .width = CUI_FILL })
      ui.waveform("track", peaks, $cui.count(peaks), progress,
                  height: 34);
    ui.text("0:42", size: 12, tabular: true,
                    color: CUI_COLOR_TEXT_MUTED);
  }
}

static void scene_level_meter(Ui ui) {
  // Linear sample peaks of the left and right channels; 1.0 is 0 dBFS.
  static float levels[] = { 0.42f, 0.61f };
  $cui.card(ui, { .gap = 10 }) {
    ui.label("Master");
    ui.level_meter("master", levels, $cui.count(levels),
      horizontal: true, length: 280, scale: true, segmented: true);
  }
}

static void scene_histogram_slider(Ui ui) {
  static const float bins[] = { 2, 4, 7, 12, 18, 26, 31, 29, 34, 40, 37,
                                30, 24, 19, 15, 11, 8, 6, 4, 3 };
  static float lo = 40, hi = 160;
  $cui.card(ui, { .width = CUI_PX(380), .gap = 6 }) {
    ui.histogram_slider("Price", bins, $cui.count(bins), lo, hi, 0, 240,
                        format: "$%.0f");
    ui.muted("1,204 listings in range");
  }
}

static void scene_time_histogram(Ui ui) {
  static const cui_histogram_series levels[] = {
    { "Info", info_lines, CUI_TONE_INFO },
    { "Warning", warning_lines, CUI_TONE_WARNING },
    { "Error", error_lines, CUI_TONE_DANGER } };
  // Seconds since 1970: the day starts at 2026-11-09 00:00 UTC.
  static double day = 1794182400;
  static double from = 1794182400 + 3600 * 15, to = 1794182400 + 3600 * 17.5;
  $cui.box(ui, { .width = CUI_FILL, .max_width = 660 })
    ui.time_histogram("logs", day, 900, $cui.count(info_lines), levels,
                      $cui.count(levels), from, to,
                      utc: true, height: 150);
}

static void scene_uptime(Ui ui) {
  static const cui_uptime_service services[] = {
    { "API", api_days, $cui.count(api_days) },
    { "Website", web_days, $cui.count(web_days) },
    { "CDN", cdn_days, $cui.count(cdn_days) } };
  $cui.box(ui, { .width = CUI_FILL, .max_width = 660 })
    ui.uptime("status", services, $cui.count(services),
      last_day: (cui_date){ 2026, 11, 9 });
}

static void scene_ticker(Ui ui) {
  static const cui_ticker_item figures[] = {
    { "Revenue", "$48.2k", 6.9f }, { "Active users", "12,408", 3.1f },
    { "Churn", "1.7%", -0.6f, true }, { "Latency", "182 ms", -8.4f, true },
    { "Builds", "1,204", 12.0f }, { "Uptime", "99.98%", 0 } };
  $cui.box(ui, { .width = CUI_FILL })
    ui.ticker("figures", figures, $cui.count(figures));
}

static Scene viz_scenes[] = {
  { "donut_chart", scene_donut_chart },
  { "activity_rings", scene_activity_rings },
  { "bar_list", scene_bar_list },
  { "calendar_heatmap", scene_calendar_heatmap },
  { "candlestick", scene_candlestick },
  { "funnel", scene_funnel },
  { "heatmap", scene_heatmap },
  { "radar_chart", scene_radar_chart },
  { "sankey", scene_sankey },
  { "scatter_chart", scene_scatter_chart },
  { "split_bar", scene_split_bar },
  { "treemap", scene_treemap },
  { "waffle", scene_waffle },
  { "waveform", scene_waveform },
  { "level_meter", scene_level_meter },
  { "histogram_slider", scene_histogram_slider },
  { "time_histogram", scene_time_histogram },
  { "uptime", scene_uptime },
  { "ticker", scene_ticker },
};

Family viz_family(void) {
  prepare();
  return (Family){ "Visualizations", viz_scenes,
                   sizeof viz_scenes / sizeof *viz_scenes };
}
