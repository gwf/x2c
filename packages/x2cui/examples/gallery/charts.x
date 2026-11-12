#pragma once

/*  charts.x -- the gallery's Charts page */

#include "state.x"

static ArrayFloat revenue, costs, desktop, mobile, shares;
// Test runs per week.
static ArrayFloat passed, retried, failed;
// The series each chart draws, over the values above.
static Series trends, visits, runs;

static void prepare(void) {
  revenue = [18, 22, 21, 27, 31, 29, 36, 41, 39, 46, 52, 58];
  costs = [12, 13, 15, 14, 18, 19, 21, 22, 24, 25, 27, 29];
  desktop = [42, 51, 38, 64, 58, 71];
  mobile = [28, 33, 30, 41, 46, 49];
  shares = [46, 27, 17, 10];
  passed = [112, 124, 131, 128, 140, 152, 149, 161];
  retried = [9, 11, 8, 12, 10, 9, 13, 8];
  failed = [4, 6, 3, 5, 7, 4, 6, 3];
  trends = Series.of([]);
  trends.push(cui_series.of("Revenue", revenue));
  trends.push(cui_series.of("Costs", costs));
  visits = Series.of([]);
  visits.push(cui_series.of("Desktop", desktop));
  visits.push(cui_series.of("Mobile", mobile));
  runs = Series.of([]);
  runs.push(cui_series.of("Passed", passed));
  runs.push(cui_series.of("Retried", retried));
  runs.push(cui_series.of("Failed", failed));
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
  ui.card () {
    ui.line_chart("revenue", trends, months,
      area: true, smooth: true, height: 240, format: "$%.0fk");
  }
  ui.box (dir: grid, columns: 2, min_column_width: 260,
          gap: 16) {
    ui.column (gap: 12) {
      section(ui, "Bar chart", NULL);
      ui.card () {
        ui.bar_chart("visits", visits,
                     %("Jan" "Feb" "Mar" "Apr" "May" "Jun"),
                     height: 200);
      }
    }
    ui.column (gap: 12) {
      section(ui, "Donut chart", NULL);
      ui.card (align: center)
        ui.donut_chart("platforms", shares,
                       %("Windows" "macOS" "Linux" "Other"),
                       height: 180, format: "%.0f%%");
    }
  }
  section(ui, "Stacked bars and gauges", NULL);
  ui.box (dir: grid, columns: 2, min_column_width: 260,
          gap: 16) {
    ui.card () {
      ui.bar_chart("runs", runs,
                   %("W1" "W2" "W3" "W4" "W5" "W6" "W7" "W8"),
                   stacked: true, height: 200);
    }
    ui.card (dir: row, gap: 24, align: center) {
      ui.gauge("CPU", 0.42f, 130);
      ui.gauge("Memory", 0.81f, 130);
    }
  }
}
