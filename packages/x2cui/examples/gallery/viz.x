#pragma once

/*  viz.x -- the gallery's More charts page */

#include <math.h>

#include "state.x"

enum { NC = 2000 };

static float traffic[7 * 24];
static float days[364];
enum { RUNS = 40 };
static cui_vec2 points_a[RUNS], points_b[RUNS];
static float sizes_a[RUNS], sizes_b[RUNS];
static cui_candle candles[NC];

static void prepare(void) {
  for (int d = 0; d < 7; d++)
    for (int h = 0; h < 24; h++) {
      float work = (d < 5) ? 1.0f : 0.45f;
      float day = expf(-powf((h - 13.5f) / 4.2f, 2)) * 90 * work +
                  expf(-powf((h - 20.5f) / 2.0f, 2)) * 35;
      traffic[d * 24 + h] = day + (float) ((d * 31 + h * 17) % 11);
    }
  unsigned s = 7;
  for (int k = 0; k < 364; k++) {
    s = s * 1103515245u + 12345u;
    int wd = (k + ((cui_date_to_days(cui_date_today()) - 363) % 7 + 10) % 7)
             % 7;
    float base = (wd >= 5 ? 0.6f : 3.2f) *
                 (0.6f + 0.4f * sinf(k / 40.0f) * sinf(k / 40.0f));
    float r = (float) ((s >> 16) % 1000) / 1000.0f;
    days[k] = r < 0.18f ? 0 : floorf(base * r * 4);
  }
  for (int k = 0; k < RUNS; k++) {
    float n = 200 + k * 95.0f;
    points_a[k] = (cui_vec2){
      n, 0.08f + n * 0.00006f + (float) ((k * 37) % 13) * 0.004f };
    points_b[k] = (cui_vec2){
      n * 0.9f + 150,
      0.15f + n * 0.00011f + (float) ((k * 53) % 17) * 0.006f };
    sizes_a[k] = (float) (10 + (k * 7) % 40);
    sizes_b[k] = (float) (20 + (k * 11) % 50);
  }
  float price = 64;
  for (int k = 0; k < NC; k++) {
    float o = price;
    float c = o * (1 + sinf(k * 0.37f) * 0.012f + cosf(k * 0.043f) * 0.008f);
    candles[k] = (cui_candle){ o, fmaxf(o, c) * 1.006f, fminf(o, c) * 0.994f,
                               c, 2000 + (float) ((k * 7919) % 900) * 10 };
    price = c;
  }
}

void page_viz(Ui ui, Gallery g) {
  static bool ready = false;
  if (!ready) {
    prepare();
    ready = true;
  }
  ui.row (gap: 24, align: start, width: fill)
  ui.column (width: grow(1), gap: 10) {
    section(ui, "Heatmap", "Requests by weekday and hour.");
    ui.card (pad: 18, width: fill)
      ui.heatmap("traffic", traffic, 7, 24,
        row_labels: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
        col_labels: ["0h", NULL, NULL, "3h", NULL, NULL, "6h", NULL, NULL,
                     "9h", NULL, NULL, "12h", NULL, NULL, "15h", NULL, NULL,
                     "18h", NULL, NULL, "21h", NULL, NULL],
        format: "%.0f req");
  }
  section(ui, "Calendar heatmap", "A year of activity, one square a day.");
  ui.card (pad: 18) {
    cui_date start =
      cui_date_from_days(cui_date_to_days(cui_date_today()) - 363);
    ui.calendar_heatmap("activity", start, days,
                        unit: "contributions");
  }
  ui.row (gap: 24, align: start, width: fill) {
    ui.column (width: grow(1.3f), gap: 10) {
      section(ui, "Treemap", "Bundle size by module.");
      ui.treemap("bundle", [
          {label: "Layout", value: 55}, {label: "Text", value: 42},
          {label: "Draw", value: 35}, {label: "Controls", value: 31},
          {label: "Charts", value: 23}, {label: "Overlays", value: 19},
          {label: "Platform", value: 16}, {label: "Theme", value: 9},
          {label: "Icons", value: 7}, {label: "Grid", value: 6}],
        height: 280, format: "%.0f KB");
    }
    ui.column (width: grow(1), gap: 10,
               align: center) {
      section(ui, "Radar", "Two releases across six qualities.");
      ui.radar_chart("radar", [
          {name: "1.0", values: [82, 64, 90, 58, 75, 88]},
          {name: "1.1", values: [70, 85, 72, 80, 60, 79]}],
        %("Speed" "Size" "Polish" "Docs" "Platforms" "Tests"),
        size: 220, max: 100);
    }
  }
  ui.row (gap: 24, align: start, width: fill) {
    ui.column (width: grow(1), gap: 10) {
      section(ui, "Funnel", "Sign up conversion.");
      ui.funnel("funnel", [
        {label: "Visited", value: 12840}, {label: "Signed up", value: 4210},
        {label: "Activated", value: 2380}, {label: "Subscribed", value: 860}]);
    }
    ui.column (width: grow(1), gap: 10) {
      section(ui, "Split bar", "Where the time goes.");
      ui.split_bar("split", [
          {label: "Layout", value: 38}, {label: "Text", value: 24},
          {label: "Paint", value: 21}, {label: "Input", value: 9},
          {label: "Other", value: 8}],
        format: "%.0f ms");
      ui.gap(18);
      section(ui, "Waffle", "Platforms of the last 100 installs.");
      ui.waffle("waffle", [
          {label: "Windows", value: 46}, {label: "macOS", value: 31},
          {label: "Linux", value: 23}],
        cell: 14);
    }
  }
  section(ui, "Sankey", "Where sign ups come from and where they end up.");
  ui.card (pad: 18, width: fill)
    ui.sankey("flow", %("Search" "Social" "Referral" "Sign up" "Bounced"
                        "Trial" "Paid" "Churned"), [
        {from: 0, to: 3, value: 420}, {from: 1, to: 3, value: 260},
        {from: 2, to: 3, value: 180}, {from: 0, to: 4, value: 300},
        {from: 1, to: 4, value: 220}, {from: 3, to: 5, value: 860},
        {from: 5, to: 6, value: 580}, {from: 5, to: 7, value: 280}],
      height: 280);
  ui.row (gap: 24, align: start, width: fill) {
    ui.column (width: grow(1.4f), gap: 10) {
      section(ui, "Bar list", "Ranked, keyed by label: press Shuffle and "
                              "the rows slide to their new rank.");
      static cui_viz_item pages[] = {
        { "/docs", 4820 }, { "/", 3920 }, { "/gallery", 2410 },
        { "/blog/fast-ui-in-c", 1830 }, { "/download", 1210 },
        { "/pricing", 640 } };
      ui.bar_list("pages", pages);
      if (ui.button("Shuffle", size: sm,
                               icon: shuffle,
                               variant: outline))
        for (int k = 0; k < 6; k++)
          pages[k].value = (float) (500 + rand() % 5000);
    }
    ui.column (width: grow(1), gap: 10,
               align: center) {
      section(ui, "Activity rings", "Past one, a ring keeps winding.");
      ui.activity_rings("rings", [
          {label: "Move", value: 0.82f}, {label: "Exercise", value: 1.24f},
          {label: "Stand", value: 0.58f}],
        size: 170, center: "82%", caption: "of goal");
    }
  }
  section(ui, "Scatter",
          "Frame time against node count, sized by draw calls.");
  ui.card (pad: 18, width: fill)
    ui.scatter_chart("scatter", [
        {name: "Software", points: points_a, sizes: sizes_a},
        {name: "OpenGL", points: points_b, sizes: sizes_b}],
      height: 300, x_label: "Nodes", y_label: "Frame time (ms)",
      y_format: "%.2f");
  ui.card (pad: 18, width: fill, dir: row,
           wrap: true, gap: 24, align: center) {
    ui.radial_gauge("cpu", 64, 0, 100,
      unit: "%", label: "CPU", size: 180, bands: [
        {to: 60, tone: success}, {to: 85, tone: warning},
        {to: 100, tone: danger}]);
    ui.radial_gauge("temp", 71, 20, 100,
      unit: "C", label: "GPU temperature", show_target: true,
      target: 85, size: 180);
    ui.radial_gauge("mem", 0.62f * 32, 0, 32,
      format: "%.1f", unit: "GB", label: "Memory", no_needle: true,
      ticks: -1, size: 150);
  }
  ui.card (pad: 18, width: fill, gap: 10) {
    ui.label("Price, 2,000 periods");
    ui.candlestick("price", candles, height: 280);
  }
}
