#pragma once

/*  data.x -- the gallery's Data display page */

#include "state.x"

typedef struct person_row {
  String name, email, role, status;
  cui_tone status_tone;
  String amount;
} person_row;

// The text of a row that the table sorts by in `column`.
static String sort_key(person_row *row, int column) =>
  column == 0 ? row.name : column == 2 ? row.role : row.status;

void page_data(Ui ui, Gallery g) {
  section(ui, "Table", "Sortable columns, row selection and components in "
                       "cells.");
  static person_row rows[] = {
    { "Jonas Berg", "jonas@northlight.io", "Owner", "Active",
      CUI_TONE_SUCCESS, "$12,384" },
    { "Priya Nair", "priya@harbor.dev", "Admin", "Active",
      CUI_TONE_SUCCESS, "$9,846" },
    { "Tomas Rivera", "tomas@kiln.app", "Editor", "Invited",
      CUI_TONE_WARNING, "$7,215" },
    { "Lena Fischer", "lena@fischer.dev", "Viewer", "Active",
      CUI_TONE_SUCCESS, "$3,127" },
    { "Aiko Tanaka", "aiko@tanaka.design", "Editor", "Suspended",
      CUI_TONE_DANGER, "$1,962" },
  };
  int order[5] = { 0, 1, 2, 3, 4 };
  for (int i = 1; i < 5; i++) {
    int v = order[i], j = i - 1;
    while (j >= 0) {
      int c = String.compare(sort_key(&rows[order[j]], g.sort.column),
                             sort_key(&rows[v], g.sort.column));
      if (g.sort.descending ? c < 0 : c > 0) {
        order[j + 1] = order[j];
        j--;
      }
      else break;
    }
    order[j + 1] = v;
  }
  ui.table ("people", sort: &g.sort, selectable: true,
            columns: {"Name": fill, "Email": unsorted(grow(1.2)),
                      "Role": 110, "Status": 120,
                      "Revenue": right(unsorted(110))}) {
    for (int k = 0; k < 5; k++) {
      person_row *r = &rows[order[k]];
      if (ui.table_row(g.selected_row == order[k])) g.selected_row = order[k];
      ui.table_cell();
      ui.avatar(r.name, size: 26);
      ui.text(r.name, font: CUI_FONT_MEDIUM, nowrap: true);
      ui.table_cell();
      ui.text(r.email, color: CUI_COLOR_TEXT_SECONDARY, nowrap: true);
      ui.table_cell_text(r.role);
      ui.table_cell();
      ui.badge(r.status, tone: r.status_tone, dot: true);
      ui.table_cell_text(r.amount);
    }
  }
  ui.box (dir: CUI_GRID, columns: 2, min_column_width: 260,
          gap: 16) {
    ui.column (gap: 12) {
      section(ui, "Tree view", NULL);
      ui.card (pad: 10, gap: 1)
      ui.tree ("src", g.tree_src) {
        // A leaf has no open state, so it passes NULL for the flag.
        ui.tree ("components", g.tree_ui) {
          int i = 0;
          foreach (String file in %("button.c" "dialog.c" "slider.c"
                                    "table.c")) {
            ui.tree_begin(file, NULL, {
              .leaf = true, .selected = g.selected_file == i });
            if (ui.tree_clicked()) g.selected_file = i;
            i++;
          }
        }
        ui.tree ("assets", g.tree_assets) {
          ui.tree_begin("logo.png", NULL, {
            .leaf = true, .icon = CUI_ICON_IMAGE });
        }
        ui.tree_begin("main.c", NULL, { .leaf = true });
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
  ui.column (width: CUI_FILL) {
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
        ui.text(task, nowrap: true, width: CUI_FILL);
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
    ui.virtual_list ("big", 10000, 36, CUI_PX(220), first, last) {
      for (int i = first; i < last; i++) {
        unsigned h = (unsigned) (i + 1) * 2654435761u;
        String invoice = String.format("Invoice 2026-%05d", 10000 - i);
        String amount = String.format("$%u.%02u", 40 + (h >> 8) % 2400,
                                      (h >> 4) % 100);
        ui.row (height: CUI_PX(36), pad_x: 12, gap: 12) {
          ui.icon(CUI_ICON_FILE_TEXT, 16, CUI_COLOR_TEXT_MUTED);
          ui.text(invoice, nowrap: true, width: CUI_FILL,
                           tabular: true);
          ui.text(amount, size: 13, tabular: true, nowrap: true);
          ui.text((h >> 20) % 5 == 0 ? "Due" : "Paid",
            size: 12, color: CUI_COLOR_TEXT_MUTED, nowrap: true,
            width: CUI_PX(32));
        }
      }
    }
  }
}
