#pragma once

/*  grid.x -- the gallery's Data grid page */

#include "state.x"

typedef struct person {
  TextField name;
  String email, team;
  int commits;
  float score;
} person;

enum { PEOPLE = 2000 };
static person people[PEOPLE];
static int order_ix[PEOPLE];
static bool people_sel[PEOPLE];
static cui_table_sort people_sort;
static TextField search;

static int cmp_people(const void *a, const void *b) {
  const person *x = &people[*(const int *) a];
  const person *y = &people[*(const int *) b];
  int r = 0;
  switch (people_sort.column) {
    case 0: r = strcmp(x.name.buffer, y.name.buffer); break;
    case 2: r = String.compare(x.team, y.team); break;
    case 3: r = x.commits - y.commits; break;
    default: r = x.score < y.score ? -1 : x.score > y.score; break;
  }
  return people_sort.descending ? -r : r;
}

static void prepare(void) {
  List first = %("Maya" "Priya" "Jonas" "Lena" "Sam" "Tomas" "Aiko" "Daniel"
                 "Rosa" "Omar" "Elif" "Ben" "Nora" "Kwame" "Hana" "Felix");
  List last = %("Okafor" "Nair" "Berg" "Fischer" "Whitfield" "Rivera"
                "Tanaka" "Mensah" "Delgado" "Haddad" "Kaya" "Carter"
                "Lindqvist" "Asante" "Novak" "Moreau");
  List teams = %("Engine" "Design" "Platform" "Docs" "Growth");
  for (int k = 0; k < PEOPLE; k++) {
    // A cheap hash, so neighbouring rows do not repeat each other.
    uint32_t h = (uint32_t) k * 2654435761u;
    h ^= h >> 15;
    h *= 2246822519u;
    h ^= h >> 13;
    String fn = first[h % 16], ln = last[(h >> 4) % 16];
    people[k].name = TextField.new(48);
    people[k].name.set(%"$fn $ln");
    people[k].email =
      String.format("%s.%c%u@cui.dev", fn, ln[0], (h >> 8) % 90 + 10)
        .lower();
    people[k].team = teams[(h >> 12) % 5];
    people[k].commits = (int) ((h >> 16) % 1400) + 12;
    people[k].score = (float) ((h >> 3) % 1000) / 10.0f;
    order_ix[k] = k;
  }
  people_sort.column = 3;
  people_sort.descending = true;
  search = TextField.new(64);
}

void page_grid(Ui ui, Gallery g) {
  static bool ready;
  if (!ready) {
    prepare();
    ready = true;
  }
  static cui_table_sort last_sort = { -1, false };
  if (people_sort.column != last_sort.column ||
      people_sort.descending != last_sort.descending) {
    qsort(order_ix, PEOPLE, sizeof(int), cmp_people);
    last_sort = people_sort;
  }
  static uint32_t filters[3] = { 1u << 0 | 1u << 2, 0, 0 };
  section(ui, "Filter bar", "Chips for active filters, values in a list, "
                            "and a search.");
  // `filters` holds one mask for each field.
  ui.filter_bar("filters", [
    {name: "Team", icon: users,
     options: ["Engine", "Design", "Platform", "Docs", "Growth"]},
    {name: "Status", icon: circle_dot, options: ["Active", "Away", "Invited"]},
    {name: "Role", icon: key_round, options: ["Owner", "Admin", "Member"]}],
    filters, search);

  section(ui, "Data grid", "2,000 rows, virtualized. Sort, resize columns, "
                           "select with Shift and Ctrl, edit names with a "
                           "double click.");
  int n_sel = 0;
  for (int k = 0; k < PEOPLE; k++) n_sel += people_sel[k];
  ui.data_grid ("people", PEOPLE, f0, l0,
                columns: {"Name": 200, "Email": unsorted(196), "Team": 110,
                          "Commits": right(96), "Score": right(130)},
                height: 420, selected: people_sel, sort: &people_sort) {
    for (int r = f0; r < l0; r++) {
      person *p = &people[order_ix[r]];
      ui.data_grid_row(r);
      ui.grid_cell () {
        ui.avatar(p.name.text(), size: 24);
        ui.data_grid_edit(p.name);
      }
      ui.grid_cell_text(p.email);
      ui.grid_cell () ui.badge(p.team);
      ui.grid_cell_text(%"$(p.commits)");
      ui.grid_cell () {
        ui.progress(p.score / 100, width: 70, height: 5);
        ui.text(String.format("%.1f", (double) p.score),
                tabular: true, size: 13, color: text_secondary);
      }
    }
  }
  ui.muted(n_sel ? "Rows selected. Press Esc to clear."
                 : "Click a row, Shift+click to select a range, Ctrl+A for "
                   "all.");

  section(ui, "Tree table", "Tree cells inside a table: disclosure, "
                            "indentation, totals.");
  {
    static bool open_src = true, open_ui = false;
    // A leaf has no open state, so it passes NULL for the flag.
    ui.table ("tree", columns: {"Name": unsorted(fill),
                                "Files": right(unsorted(80)),
                                "Size": right(unsorted(100))}) {
      ui.table_row (row) {
        ui.cell () ui.tree_cell("src", 0, true, open_src, folder);
        ui.cell_text("42");
        ui.cell_text("1.2 MB");
      }
      if (open_src) {
        ui.table_row (row) {
          ui.cell () ui.tree_cell("ui", 1, true, open_ui, folder);
          ui.cell_text("18");
          ui.cell_text("640 KB");
        }
        if (open_ui) ui.table_row (row) {
          ui.cell () ui.tree_cell("button.c", 2, false, NULL, file);
          ui.cell_text("1");
          ui.cell_text("24 KB");
        }
        ui.table_row (row) {
          ui.cell () ui.tree_cell("main.c", 1, false, NULL, file);
          ui.cell_text("1");
          ui.cell_text("8 KB");
        }
      }
      ui.table_row (row) {
        ui.cell () ui.tree_cell("README.md", 0, false, NULL, file_text);
        ui.cell_text("1");
        ui.cell_text("12 KB");
      }
    }
  }
}
