#pragma once

/*  data.x -- scenes for charts, tables, and the data grid

    These components read arrays of CUI's records. A table and a data grid
    take their columns as a Map literal, and a chart takes a C array of
    series alone. The numbers and rows come from x2c collections.
*/

#include "scene.x"

// Monthly figures in thousands of dollars.
static ArrayFloat subscriptions, cloud_spend, desktop, mobile;
// The series the two charts draw over them.
static Series revenue, visits;

// One row for each person: name, team, commits, and review score.
static List people;

static void prepare(void) {
  subscriptions = [18, 22, 21, 27, 31, 29, 36, 41, 39, 46, 52, 58];
  cloud_spend = [12, 13, 15, 14, 18, 19, 21, 22, 24, 25, 27, 29];
  desktop = [42, 51, 38, 64, 58, 71];
  mobile = [28, 33, 30, 41, 46, 49];
  revenue = Series.of([]);
  revenue.push(cui_series.of("Subscriptions", subscriptions));
  revenue.push(cui_series.of("Cloud spend", cloud_spend));
  visits = Series.of([]);
  visits.push(cui_series.of("Desktop", desktop));
  visits.push(cui_series.of("Mobile", mobile));
  people = %(("Jonas Berg" "Engine" 884 97.2)
             ("Lena Fischer" "Platform" 640 88.1)
             ("Sam Whitfield" "Engine" 597 84.0)
             ("Daniel Mensah" "Platform" 431 71.9)
             ("Aiko Tanaka" "Design" 388 90.4)
             ("Priya Nair" "Docs" 212 79.5));
}

static void scene_line_chart(Ui ui) {
  List months = %("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep"
                  "Oct" "Nov" "Dec");
  ui.card (width: fill, max_width: 660)
    ui.line_chart("revenue", revenue, months,
      area: true, smooth: true, height: 200, format: "$%.0fk");
}

static void scene_bar_chart(Ui ui) {
  ui.card (width: fill, max_width: 520)
    ui.bar_chart("visits", visits,
                 %("Jan" "Feb" "Mar" "Apr" "May" "Jun"), height: 200);
}

static void scene_table(Ui ui) {
  static cui_table_sort sort = { 0, false };
  static int chosen = 1;
  ui.box (width: fill, max_width: 620)
  ui.table ("people", sort: &sort, selectable: true,
            columns: {"Name": fill, "Team": unsorted(110),
                      "Commits": right(unsorted(100)),
                      "Score": right(unsorted(90))}) {
    int index = 0;
    foreach (List person in people) {
      (String name, String team, int commits, double score) = person;
      ui.table_row (row, selected: index == chosen) {
        if (row.clicked) chosen = index;
        ui.cell () {
          ui.avatar(name, size: 24);
          ui.text(name, font: medium, nowrap: true);
        }
        ui.cell () ui.badge(team);
        ui.cell_text(%"$commits");
        ui.cell_text(String.format("%.1f", score));
      }
      index++;
    }
  }
}

static void scene_data_grid(Ui ui) {
  static bool selected[6] = { false, true, true };
  static cui_table_sort sort = { 2, true };
  // The grid draws only the rows on screen, from `first` up to `last`.
  ui.data_grid ("people", people.len(), first, last,
                columns: {"Name": 240, "Team": 140, "Commits": right(100),
                          "Score": right(120)},
                height: 300, selected: selected, sort: &sort) {
    for (int row = first; row < last; row++) {
      (String name, String team, int commits, double score) = people[row];
      ui.data_grid_row(row);
      ui.grid_cell () {
        ui.avatar(name, size: 24);
        ui.text(name, size: 13.5f);
      }
      ui.grid_cell () ui.badge(team);
      ui.grid_cell_text(%"$commits");
      ui.grid_cell_text(String.format("%.1f", score));
    }
  }
}

static Scene data_scenes[] = {
  { "line_chart", scene_line_chart },
  { "bar_chart", scene_bar_chart },
  { "table", scene_table },
  { "data_grid_begin", scene_data_grid },
};

Family data_family(void) {
  prepare();
  return (Family){ "Charts, tables, and the data grid", data_scenes,
                   sizeof data_scenes / sizeof *data_scenes };
}
