#pragma once

/*  data.x -- scenes for charts, tables, and the data grid

    These components read arrays of CUI's records. The arrays are C arrays
    written with designated initializers, and each `$cui.` macro takes the
    array itself and supplies its count. The numbers and rows come from x2c
    collections.
*/

#include "scene.x"

// Monthly figures in thousands of dollars.
static ArrayFloat subscriptions, cloud_spend, desktop, mobile;

// One row for each person: name, team, commits, and review score.
static List people;

static void prepare(void) {
  subscriptions = [18, 22, 21, 27, 31, 29, 36, 41, 39, 46, 52, 58];
  cloud_spend = [12, 13, 15, 14, 18, 19, 21, 22, 24, 25, 27, 29];
  desktop = [42, 51, 38, 64, 58, 71];
  mobile = [28, 33, 30, 41, 46, 49];
  people = %(("Jonas Berg" "Engine" 884 97.2)
             ("Lena Fischer" "Platform" 640 88.1)
             ("Sam Whitfield" "Engine" 597 84.0)
             ("Daniel Mensah" "Platform" 431 71.9)
             ("Aiko Tanaka" "Design" 388 90.4)
             ("Priya Nair" "Docs" 212 79.5));
}

static void scene_line_chart(Ui ui) {
  cui_series series[] = { cui_series.of("Subscriptions", subscriptions),
                          cui_series.of("Cloud spend", cloud_spend) };
  List months = %("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep"
                  "Oct" "Nov" "Dec");
  $cui.card(ui, { .width = CUI_FILL, .max_width = 660 })
    ui.line_chart("revenue", series, $cui.count(series), months,
      area: true, smooth: true, height: 200, format: "$%.0fk");
}

static void scene_bar_chart(Ui ui) {
  cui_series series[] = { cui_series.of("Desktop", desktop),
                          cui_series.of("Mobile", mobile) };
  $cui.card(ui, { .width = CUI_FILL, .max_width = 520 })
    ui.bar_chart("visits", series, $cui.count(series),
                 %("Jan" "Feb" "Mar" "Apr" "May" "Jun"), height: 200);
}

static void scene_table(Ui ui) {
  static cui_table_column columns[] = {
    { "Name", .sortable = true },
    { "Team", .width = CUI_PX(110) },
    { "Commits", .width = CUI_PX(100), .align = CUI_TEXT_RIGHT },
    { "Score", .width = CUI_PX(90), .align = CUI_TEXT_RIGHT } };
  static cui_table_sort sort = { 0, false };
  static int chosen = 1;
  $cui.box(ui, { .width = CUI_FILL, .max_width = 620 })
  $cui.table(ui, "people", columns, { .sort = &sort, .selectable = true }) {
    int index = 0;
    foreach (List person in people) {
      (String name, String team, int commits, double score) = person;
      if (ui.table_row(index == chosen)) chosen = index;
      index++;
      ui.table_cell();
      ui.avatar(name, size: 24);
      ui.text(name, font: CUI_FONT_MEDIUM, nowrap: true);
      ui.table_cell();
      ui.badge(team);
      ui.table_cell_text(%"$commits");
      ui.table_cell_text(String.format("%.1f", score));
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
      ui.data_grid_cell();
      ui.avatar(name, size: 24);
      ui.text(name, size: 13.5f);
      ui.data_grid_cell();
      ui.badge(team);
      ui.data_grid_cell_text(%"$commits");
      ui.data_grid_cell_text(String.format("%.1f", score));
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
