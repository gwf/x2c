#pragma once

/*  charts.x -- the gallery's Charts page */

#include "state.x"

static ArrayFloat revenue, costs, desktop, mobile, shares;
// Test runs per week.
static ArrayFloat passed, retried, failed;

static void prepare(void) {
  revenue = [18, 22, 21, 27, 31, 29, 36, 41, 39, 46, 52, 58];
  costs = [12, 13, 15, 14, 18, 19, 21, 22, 24, 25, 27, 29];
  desktop = [42, 51, 38, 64, 58, 71];
  mobile = [28, 33, 30, 41, 46, 49];
  shares = [46, 27, 17, 10];
  passed = [112, 124, 131, 128, 140, 152, 149, 161];
  retried = [9, 11, 8, 12, 10, 9, 13, 8];
  failed = [4, 6, 3, 5, 7, 4, 6, 3];
}

void page_charts(Ui ui, Gallery g) {
  static bool ready = false;
  if (!ready) {
    prepare();
    ready = true;
  }
  List months = %("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep"
                  "Oct" "Nov" "Dec");
  section(ui, "Line chart", "Hover to inspect values. The crosshair glides "
                            "between points.");
  $cui.card(ui, {}) {
    cui_series s[] = { cui_series.of("Revenue", revenue),
                       cui_series.of("Costs", costs) };
    ui.line_chart("revenue", s, $cui.count(s), months, {
      .area = true, .smooth = true, .height = 240, .format = "$%.0fk" });
  }
  $cui.box(ui, { .dir = CUI_GRID, .columns = 2, .min_column_width = 260,
                 .gap = 16 }) {
    $cui.column(ui, { .gap = 12 }) {
      section(ui, "Bar chart", NULL);
      $cui.card(ui, {}) {
        cui_series s[] = { cui_series.of("Desktop", desktop),
                           cui_series.of("Mobile", mobile) };
        ui.bar_chart("visits", s, $cui.count(s),
                     %("Jan" "Feb" "Mar" "Apr" "May" "Jun"),
                     { .height = 200 });
      }
    }
    $cui.column(ui, { .gap = 12 }) {
      section(ui, "Donut chart", NULL);
      $cui.card(ui, { .align = CUI_ALIGN_CENTER })
        ui.donut_chart("platforms", shares,
                       %("Windows" "macOS" "Linux" "Other"),
                       { .height = 180, .format = "%.0f%%" });
    }
  }
  section(ui, "Stacked bars and gauges", NULL);
  $cui.box(ui, { .dir = CUI_GRID, .columns = 2, .min_column_width = 260,
                 .gap = 16 }) {
    $cui.card(ui, {}) {
      cui_series s[] = { cui_series.of("Passed", passed),
                         cui_series.of("Retried", retried),
                         cui_series.of("Failed", failed) };
      ui.bar_chart("runs", s, $cui.count(s),
                   %("W1" "W2" "W3" "W4" "W5" "W6" "W7" "W8"),
                   { .stacked = true, .height = 200 });
    }
    $cui.card(ui, { .dir = CUI_ROW, .gap = 24, .align = CUI_ALIGN_CENTER }) {
      ui.gauge("CPU", 0.42f, 130);
      ui.gauge("Memory", 0.81f, 130);
    }
  }
}
