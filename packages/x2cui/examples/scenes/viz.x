#pragma once

/*  viz.x -- scenes for visualizations, meters, and figure strips

    These components read C arrays of numbers or of CUI's records. A
    method form takes the array alone and supplies its count. The
    generated series are filled once, in `prepare`; their lengths are the
    constants below.
*/

#include <math.h>

#include "scene.x"

// Platform shares of installs, in percent.
static ArrayFloat shares;

// Requests by weekday and hour.
static float traffic[7 * 24];

enum { HALF_YEAR = 182, TRADING_DAYS = 60, RUNS = 24, PEAKS = 80,
       UPTIME_DAYS = 60, BUCKETS = 96 };

// Commits on each day of the first half of 2026.
static float commits[HALF_YEAR];

// One price candle a trading day.
static cui_candle candles[TRADING_DAYS];

// Frame time against node count, sized by draw calls.
static cui_vec2 software_points[RUNS], opengl_points[RUNS];
static float software_sizes[RUNS], opengl_sizes[RUNS];

// Audio peaks of a track, 0 to 1.
static float peaks[PEAKS];

// The fraction of each day a service was up; negative means no data.
static float api_days[UPTIME_DAYS], web_days[UPTIME_DAYS],
             cdn_days[UPTIME_DAYS];

// Log lines in each 15 minute bucket of one day.
static float info_lines[BUCKETS], warning_lines[BUCKETS],
             error_lines[BUCKETS];

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
  for (int k = 0; k < HALF_YEAR; k++) {
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
  for (int k = 0; k < TRADING_DAYS; k++) {
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
  for (int k = 0; k < RUNS; k++) {
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
  for (int k = 0; k < PEAKS; k++)
    peaks[k] = 0.18f + 0.8f * fabsf(sinf(k * 0.37f) * sinf(k * 0.11f + 1.3f));
  for (int d = 0; d < UPTIME_DAYS; d++) {
    api_days[d] = d == 41 ? 0.962f : d % 17 == 5 ? 0.9985f : 1;
    web_days[d] = d == 28 ? 0.93f : 1;
    cdn_days[d] = d < 12 ? -1 : 1;
  }
  for (int i = 0; i < BUCKETS; i++) {
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
  ui.card (align: center)
    ui.donut_chart("platforms", shares,
                   %("Windows" "macOS" "Linux" "Other"),
                   height: 200, format: "%.0f%%");
}

static void scene_activity_rings(Ui ui) {
  static const cui_viz_item rings[] = {
    { "Move", 0.82f }, { "Exercise", 1.24f }, { "Stand", 0.58f } };
  ui.card (pad: 18)
    ui.activity_rings("rings", rings,
      size: 170, center: "82%", caption: "of goal", legend: true);
}

static void scene_bar_list(Ui ui) {
  static const cui_viz_item pages[] = {
    { "/docs", 4820 }, { "/", 3920 }, { "/gallery", 2410 },
    { "/blog/fast-ui-in-c", 1830 }, { "/download", 1210 },
    { "/pricing", 640 } };
  ui.card (width: fill, max_width: 480, gap: 10) {
    ui.label("Top pages this week");
    ui.bar_list("pages", pages);
  }
}

static void scene_calendar_heatmap(Ui ui) {
  ui.card (pad: 18)
    ui.calendar_heatmap("activity", (cui_date){ 2026, 1, 1 }, commits, unit: "commits");
}

static void scene_candlestick(Ui ui) {
  ui.card (width: fill, max_width: 660, gap: 10) {
    ui.label("Price, 60 trading days");
    ui.candlestick("price", candles, height: 260);
  }
}

static void scene_funnel(Ui ui) {
  ui.card (width: fill, max_width: 520)
    ui.funnel("signups", [
      {label: "Visited", value: 12840}, {label: "Signed up", value: 4210},
      {label: "Activated", value: 2380}, {label: "Subscribed", value: 860}]);
}

static void scene_heatmap(Ui ui) {
  ui.card (pad: 18, width: fill, max_width: 660)
    ui.heatmap("traffic", traffic, 7, 24,
      row_labels: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], col_labels: [
        "0h", NULL, NULL, "3h", NULL, NULL, "6h", NULL, NULL, "9h", NULL, NULL,
        "12h", NULL, NULL, "15h", NULL, NULL, "18h", NULL, NULL, "21h", NULL,
        NULL], format: "%.0f req");
}

static void scene_radar_chart(Ui ui) {
  enum { QUALITIES = 6 };
  ui.card (pad: 18)
    ui.radar_chart("qualities", [
      {name: "1.0", values: [82, 64, 90, 58, 75, 88]},
      {name: "1.1", values: [70, 85, 72, 80, 60, 79]}],
                   %("Speed" "Size" "Polish" "Docs" "Platforms" "Tests"),
                   size: 240, max: 100);
}

static void scene_sankey(Ui ui) {
  ui.card (pad: 18, width: fill, max_width: 660)
    ui.sankey("signups", %("Search" "Social" "Referral" "Sign up" "Bounced"
                           "Trial" "Paid" "Churned"),
              [
                {from: 0, to: 3, value: 420}, {from: 1, to: 3, value: 260},
                {from: 2, to: 3, value: 180}, {from: 0, to: 4, value: 300},
                {from: 1, to: 4, value: 220}, {from: 3, to: 5, value: 860},
                {from: 5, to: 6, value: 580}, {from: 5, to: 7, value: 280}], height: 260);
}

static void scene_scatter_chart(Ui ui) {
  static const cui_scatter_series series[] = {
    { "Software", software_points, software_sizes, RUNS },
    { "OpenGL", opengl_points, opengl_sizes, RUNS } };
  ui.card (pad: 18, width: fill, max_width: 660)
    ui.scatter_chart("frames", series,
      height: 280, x_label: "Nodes", y_label: "Frame time (ms)",
      y_format: "%.2f");
}

static void scene_split_bar(Ui ui) {
  ui.card (width: fill, max_width: 520, gap: 10) {
    ui.label("Frame time by stage");
    ui.split_bar("frame", [
      {label: "Layout", value: 38}, {label: "Text", value: 24},
      {label: "Paint", value: 21}, {label: "Input", value: 9},
      {label: "Other", value: 8}], format: "%.0f ms");
  }
}

static void scene_treemap(Ui ui) {
  ui.box (width: fill, max_width: 620)
    ui.treemap("bundle", [
      {label: "Layout", value: 55}, {label: "Text", value: 42},
      {label: "Draw", value: 35}, {label: "Controls", value: 31},
      {label: "Charts", value: 23}, {label: "Overlays", value: 19},
      {label: "Platform", value: 16}, {label: "Theme", value: 9},
      {label: "Icons", value: 7}, {label: "Grid", value: 6}],
               height: 280, format: "%.0f KB");
}

static void scene_waffle(Ui ui) {
  static const cui_viz_item platforms[] = {
    { "Windows", 46 }, { "macOS", 31 }, { "Linux", 23 } };
  ui.card (pad: 18, gap: 10) {
    ui.label("Platforms of the last 100 installs");
    ui.waffle("installs", platforms, cell: 16);
  }
}

static void scene_waveform(Ui ui) {
  static float progress = 0.36f;
  ui.card (pad: 14, width: 380)
  ui.row (gap: 12, align: center, width: fill) {
    ui.icon_button(play, size: sm,
                                  variant: secondary);
    ui.box (width: fill)
      ui.waveform("track", peaks, progress,
                  height: 34);
    ui.text("0:42", size: 12, tabular: true,
                    color: text_muted);
  }
}

static void scene_level_meter(Ui ui) {
  // Linear sample peaks of the left and right channels; 1.0 is 0 dBFS.
  static float levels[] = { 0.42f, 0.61f };
  ui.card (gap: 10) {
    ui.label("Master");
    ui.level_meter("master", levels,
      horizontal: true, length: 280, scale: true, segmented: true);
  }
}

static void scene_histogram_slider(Ui ui) {
  static float lo = 40, hi = 160;
  ui.card (width: 380, gap: 6) {
    ui.histogram_slider("Price", [
      2, 4, 7, 12, 18, 26, 31, 29, 34, 40, 37, 30, 24, 19, 15, 11, 8, 6, 4, 3], lo, hi, 0, 240,
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
  ui.box (width: fill, max_width: 660)
    ui.time_histogram("logs", day, 900, BUCKETS, levels, from, to,
                      utc: true, height: 150);
}

static void scene_uptime(Ui ui) {
  ui.box (width: fill, max_width: 660)
    ui.uptime("status", [
      {name: "API", days: api_days}, {name: "Website", days: web_days},
      {name: "CDN", days: cdn_days}],
      last_day: (cui_date){ 2026, 11, 9 });
}

static void scene_ticker(Ui ui) {
  static const cui_ticker_item figures[] = {
    { "Revenue", "$48.2k", 6.9f }, { "Active users", "12,408", 3.1f },
    { "Churn", "1.7%", -0.6f, true }, { "Latency", "182 ms", -8.4f, true },
    { "Builds", "1,204", 12.0f }, { "Uptime", "99.98%", 0 } };
  ui.box (width: fill)
    ui.ticker("figures", figures);
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
