#pragma once

/*  data.x -- the gallery's Data display page */

#include "state.x"

class Person {
  int index;             // the person's place in `people`
  String name, email, role, status, amount;
  cui_tone tone;
} *;

// A row is: name, email, role, status, revenue, and the status's tone.
void Person.init(Person p, int index, List row) {
  p.index = index;
  p.name = row[0];
  p.email = row[1];
  p.role = row[2];
  p.status = row[3];
  p.amount = row[4];
  p.tone = (int) row[5];
}

// The text the table sorts by in `column`.
String Person.sort_key(Person p, int column) =>
  column == 0 ? p.name : column == 2 ? p.role : p.status;

static List people_rows = %(
  ("Jonas Berg" "jonas@northlight.io" "Owner" "Active" "\$12,384" 2)
  ("Priya Nair" "priya@harbor.dev" "Admin" "Active" "\$9,846" 2)
  ("Tomas Rivera" "tomas@kiln.app" "Editor" "Invited" "\$7,215" 3)
  ("Lena Fischer" "lena@fischer.dev" "Viewer" "Active" "\$3,127" 2)
  ("Aiko Tanaka" "aiko@tanaka.design" "Editor" "Suspended" "\$1,962" 4));

static List people;

/* The people in the table's order: sorted by the clicked column, with
   rows that tie keeping their order in either direction. */
static List sorted_people(cui_table_sort sort) {
  Func key = %!(Person p) => p.sort_key(sort.column);
  return sort.descending ? people.reverse().sort_by(key).reverse()
                         : people.sort_by(key);
}

void page_data(Ui ui, Gallery g) {
  section(ui, "Table", "Sortable columns, row selection and components in "
                       "cells.");
  if (!people) {
    Array all = [];
    foreach (List row in people_rows) all.push(Person.new(all.len(), row));
    people = all;
  }
  ui.table ("people", sort: &g.sort, selectable: true,
            columns: {"Name": fill, "Email": unsorted(grow(1.2)),
                      "Role": 110, "Status": 120,
                      "Revenue": right(unsorted(110))})
  ui.each (Person p in sorted_people(g.sort), key: p.index)
  ui.table_row (row, selected: g.selected_row == p.index) {
    if (row.clicked) g.selected_row = p.index;
    ui.cell () {
      ui.avatar(p.name, size: 26);
      ui.text(p.name, font: medium, nowrap: true);
    }
    ui.cell () ui.text(p.email, color: text_secondary, nowrap: true);
    ui.cell_text(p.role);
    ui.cell () ui.badge(p.status, tone: p.tone, dot: true);
    ui.cell_text(p.amount);
  }
  ui.box (dir: grid, columns: 2, min_column_width: 260,
          gap: 16) {
    ui.column (gap: 12) {
      section(ui, "Tree view", NULL);
      ui.card (pad: 10, gap: 1)
      ui.tree ("src", g.tree_src) {
        // A leaf has no open state, so it passes NULL for the flag, and
        // never opens, so its block is empty.
        ui.tree ("components", g.tree_ui) {
          int i = 0;
          foreach (String file in %("button.c" "dialog.c" "slider.c"
                                    "table.c")) {
            ui.tree (file, NULL, leaf: true,
                     selected: g.selected_file == i) {}
            if (ui.tree_clicked()) g.selected_file = i;
            i++;
          }
        }
        ui.tree ("assets", g.tree_assets) {
          ui.tree ("logo.png", NULL, leaf: true, icon: image) {}
        }
        ui.tree ("main.c", NULL, leaf: true) {}
      }
    }
    ui.column (gap: 12) {
      section(ui, "List", NULL);
      ui.card (pad: 8, gap: 2) {
        ui.list_item("Design review",
          avatar: "Jonas Berg", subtitle: "Tomorrow at 10:00",
          trailing: "45m");
        ui.list_item("Release 1.0",
          avatar: "Priya Nair", subtitle: "Ship it", trailing: "2h",
          selected: true);
        ui.list_item("Planning",
          avatar: "Tomas Rivera", subtitle: "Q1 roadmap",
          trailing: "1h");
      }
    }
  }
  section(ui, "Reorderable list", "Drag a row. The others make room as you "
                                  "go.");
  // The rows carry their own edges: no card around them.
  ui.column (width: fill) {
    List tasks = %("Write the release notes" "Record the demo video"
                   "Update the screenshots" "Tag version 1.0"
                   "Post the announcement");
    // One tone per label, wherever it appears.
    static const cui_tone tones[5] = {
      CUI_TONE_INFO, CUI_TONE_NEUTRAL, CUI_TONE_INFO, CUI_TONE_WARNING,
      CUI_TONE_TEAL };
    List labels = %("Docs" "Video" "Docs" "Release" "Blog");
    ui.reorder_begin("tasks", g.task_order);
    for (int i = 0; i < 5; i++) {
      ui.reorder_item (i) {
        int t = g.task_order[i];
        String task = tasks[t], label = labels[t];
        ui.text(task, nowrap: true, width: fill);
        ui.badge(label, tone: tones[t]);
      }
    }
    if (ui.reorder_end()) ui.toast("Order saved");
  }
  section(ui, "Accordion", NULL);
  ui.card (pad_y: 4, gap: 0) {
    ui.accordion ("Is it really dependency free?", g.acc[0])
      ui.secondary("Yes. The core is plain C99. Windows uses Win32, macOS "
                   "uses Cocoa and Linux uses X11. Fonts and icons are "
                   "embedded.");
    ui.accordion ("Can I use my own renderer?", g.acc[1])
      ui.secondary("CUI outputs vertices and draw commands. Port the 60 "
                   "line shader to Vulkan, Metal or Direct3D and you are "
                   "done.");
    ui.accordion ("Does it respect reduced motion?", g.acc[2])
      ui.secondary("Every animation has a reduced motion path that keeps "
                   "the final state and feedback.");
  }
  section(ui, "Virtual list", "Ten thousand rows. Only the visible ones are "
                              "built.");
  ui.card (pad: 6) {
    int first = 0, last = 0;
    ui.virtual_list ("big", 10000, 36, 220, first, last) {
      for (int i = first; i < last; i++) {
        unsigned h = (unsigned) (i + 1) * 2654435761u;
        String invoice = String.format("Invoice 2026-%05d", 10000 - i);
        String amount = String.format("$%u.%02u", 40 + (h >> 8) % 2400,
                                      (h >> 4) % 100);
        ui.row (height: 36, pad_x: 12, gap: 12) {
          ui.icon(file_text, 16, text_muted);
          ui.text(invoice, nowrap: true, width: fill,
                           tabular: true);
          ui.text(amount, size: 13, tabular: true, nowrap: true);
          ui.text((h >> 20) % 5 == 0 ? "Due" : "Paid",
            size: 12, color: text_muted, nowrap: true,
            width: 32);
        }
      }
    }
  }
}
