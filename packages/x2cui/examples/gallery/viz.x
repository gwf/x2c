#pragma once

/*  viz.x -- the gallery's More charts page */

#include <math.h>

#include "state.x"

enum { NC = 2000 };

static float traffic[7 * 24];
static float days[364];
static cui_vec2 points_a[40], points_b[40];
static float sizes_a[40], sizes_b[40];
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
  for (int k = 0; k < 40; k++) {
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
  static const char *wd[] = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat",
                              "Sun" };
  static const char *hours[24] = {
    "0h", NULL, NULL, "3h", NULL, NULL, "6h", NULL, NULL, "9h", NULL, NULL,
    "12h", NULL, NULL, "15h", NULL, NULL, "18h", NULL, NULL, "21h", NULL,
    NULL };
  ui.row (gap: 24, align: CUI_ALIGN_START, width: CUI_FILL)
  ui.column (width: CUI_GROW(1), gap: 10) {
    section(ui, "Heatmap", "Requests by weekday and hour.");
    ui.card (pad: 18, width: CUI_FILL)
      ui.heatmap("traffic", traffic, 7, 24,
        row_labels: wd, col_labels: hours, format: "%.0f req");
  }
  section(ui, "Calendar heatmap", "A year of activity, one square a day.");
  ui.card (pad: 18) {
    cui_date start =
      cui_date_from_days(cui_date_to_days(cui_date_today()) - 363);
    ui.calendar_heatmap("activity", start, days, $cui.count(days),
                        unit: "contributions");
  }
  ui.row (gap: 24, align: CUI_ALIGN_START, width: CUI_FILL) {
    ui.column (width: CUI_GROW(1.3f), gap: 10) {
      section(ui, "Treemap", "Bundle size by module.");
      static const cui_viz_item mods[] = {
        { "Layout", 55 }, { "Text", 42 }, { "Draw", 35 },
        { "Controls", 31 }, { "Charts", 23 }, { "Overlays", 19 },
        { "Platform", 16 }, { "Theme", 9 }, { "Icons", 7 }, { "Grid", 6 },
      };
      ui.treemap("bundle", mods, $cui.count(mods),
                 height: 280, format: "%.0f KB");
    }
    ui.column (width: CUI_GROW(1), gap: 10,
               align: CUI_ALIGN_CENTER) {
      section(ui, "Radar", "Two releases across six qualities.");
      static const float a[] = { 82, 64, 90, 58, 75, 88 };
      static const float b[] = { 70, 85, 72, 80, 60, 79 };
      cui_series rs[] = { { "1.0", a, $cui.count(a) },
                          { "1.1", b, $cui.count(b) } };
      ui.radar_chart("radar", rs, $cui.count(rs),
                     %("Speed" "Size" "Polish" "Docs" "Platforms" "Tests"),
                     size: 220, max: 100);
    }
  }
  ui.row (gap: 24, align: CUI_ALIGN_START, width: CUI_FILL) {
    ui.column (width: CUI_GROW(1), gap: 10) {
      section(ui, "Funnel", "Sign up conversion.");
      static const cui_viz_item stages[] = {
        { "Visited", 12840 }, { "Signed up", 4210 }, { "Activated", 2380 },
        { "Subscribed", 860 } };
      ui.funnel("funnel", stages, $cui.count(stages));
    }
    ui.column (width: CUI_GROW(1), gap: 10) {
      section(ui, "Split bar", "Where the time goes.");
      static const cui_viz_item parts[] = {
        { "Layout", 38 }, { "Text", 24 }, { "Paint", 21 }, { "Input", 9 },
        { "Other", 8 } };
      ui.split_bar("split", parts, $cui.count(parts), format: "%.0f ms");
      ui.gap(18);
      section(ui, "Waffle", "Platforms of the last 100 installs.");
      static const cui_viz_item plats[] = {
        { "Windows", 46 }, { "macOS", 31 }, { "Linux", 23 } };
      ui.waffle("waffle", plats, $cui.count(plats), cell: 14);
    }
  }
  section(ui, "Sankey", "Where sign ups come from and where they end up.");
  static const cui_sankey_link links[] = {
    { 0, 3, 420 }, { 1, 3, 260 }, { 2, 3, 180 }, { 0, 4, 300 },
    { 1, 4, 220 }, { 3, 5, 860 }, { 5, 6, 580 }, { 5, 7, 280 },
  };
  ui.card (pad: 18, width: CUI_FILL)
    ui.sankey("flow", %("Search" "Social" "Referral" "Sign up" "Bounced"
                        "Trial" "Paid" "Churned"),
              links, $cui.count(links), height: 280);
  ui.row (gap: 24, align: CUI_ALIGN_START, width: CUI_FILL) {
    ui.column (width: CUI_GROW(1.4f), gap: 10) {
      section(ui, "Bar list", "Ranked, keyed by label: press Shuffle and "
                              "the rows slide to their new rank.");
      static cui_viz_item pages[] = {
        { "/docs", 4820 }, { "/", 3920 }, { "/gallery", 2410 },
        { "/blog/fast-ui-in-c", 1830 }, { "/download", 1210 },
        { "/pricing", 640 } };
      ui.bar_list("pages", pages, $cui.count(pages));
      if (ui.button("Shuffle", size: CUI_SIZE_SM,
                               icon: CUI_ICON_SHUFFLE,
                               variant: CUI_BUTTON_OUTLINE))
        for (int k = 0; k < 6; k++)
          pages[k].value = (float) (500 + rand() % 5000);
    }
    ui.column (width: CUI_GROW(1), gap: 10,
               align: CUI_ALIGN_CENTER) {
      section(ui, "Activity rings", "Past one, a ring keeps winding.");
      static const cui_viz_item rings[] = {
        { "Move", 0.82f }, { "Exercise", 1.24f }, { "Stand", 0.58f } };
      ui.activity_rings("rings", rings, $cui.count(rings),
        size: 170, center: "82%", caption: "of goal");
    }
  }
  section(ui, "Scatter",
          "Frame time against node count, sized by draw calls.");
  cui_scatter_series ss[] = {
    { "Software", points_a, sizes_a, $cui.count(points_a) },
    { "OpenGL", points_b, sizes_b, $cui.count(points_b) } };
  ui.card (pad: 18, width: CUI_FILL)
    ui.scatter_chart("scatter", ss, $cui.count(ss),
      height: 300, x_label: "Nodes", y_label: "Frame time (ms)",
      y_format: "%.2f");
  static const cui_gauge_band bands[] = {
    { 60, CUI_TONE_SUCCESS }, { 85, CUI_TONE_WARNING },
    { 100, CUI_TONE_DANGER } };
  ui.card (pad: 18, width: CUI_FILL, dir: CUI_ROW,
           wrap: true, gap: 24, align: CUI_ALIGN_CENTER) {
    ui.radial_gauge("cpu", 64, 0, 100,
      unit: "%", label: "CPU", bands: bands,
      band_count: $cui.count(bands), size: 180);
    ui.radial_gauge("temp", 71, 20, 100,
      unit: "C", label: "GPU temperature", show_target: true,
      target: 85, size: 180);
    ui.radial_gauge("mem", 0.62f * 32, 0, 32,
      format: "%.1f", unit: "GB", label: "Memory", no_needle: true,
      ticks: -1, size: 150);
  }
  ui.card (pad: 18, width: CUI_FILL, gap: 10) {
    ui.label("Price, 2,000 periods");
    ui.candlestick("price", candles, $cui.count(candles), height: 280);
  }
}
