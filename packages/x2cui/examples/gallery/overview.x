#pragma once

/*  overview.x -- the gallery's Overview page */

#include "state.x"

void page_overview(Ui ui, Gallery g) {
  ui.column (gap: 14, pad_bottom: 8) {
    ui.heading("Components for C", 1);
    ui.text("Forms, tables, charts, planning boards and chat pieces that "
            "draw themselves the same way on Windows, macOS and Linux. "
            "Every one works from the keyboard.",
            color: text_secondary, size: 15);
    ui.row (gap: 8, pad_top: 6, wrap: true) {
      if (ui.button("Browse components",
            variant: primary,
            icon_right: arrow_right))
        g.page = PAGE_BUTTONS;
      if (ui.button("Open command palette",
            variant: outline, icon: command))
        g.palette_open = true;
    }
  }
  ui.box (dir: grid, columns: 3, min_column_width: 200,
          gap: 16) {
    static const float frame_times[] = { 9, 7, 8, 6, 5, 6, 4, 4, 3 };
    ui.metric("Components", "150", icon: box);
    ui.metric("Frame time", "0.4 ms",
      delta: -18.0f, delta_label: "-18% vs v0.9",
      lower_is_better: true, spark: frame_times, icon: zap);
    ui.metric("Dependencies", "0", icon: package);
  }
  ui.box (dir: grid, columns: 2, min_column_width: 260,
          gap: 16) {
    ui.card (gap: 16) {
      ui.column (gap: 4) {
        ui.heading("Create a workspace", 4);
        ui.secondary("You can invite people once it exists.");
      }
      ui.input("ov-name", g.name, label: "Name",
                                  placeholder: "Your name");
      ui.input("ov-email", g.email, label: "Email",
                                    icon: mail,
                                    placeholder: "you@company.com");
      ui.checkbox("Email me a weekly summary", g.terms);
      if (ui.button("Create workspace", variant: primary,
                                        full_width: true))
        ui.toast("Workspace created",
          description: "It is empty for now. Start with a project.",
          tone: success);
    }
    ui.card (gap: 12) {
      ui.row () {
        ui.column (gap: 4, width: fill) {
          ui.heading("Team", 4);
          ui.secondary("Four people, one owner.");
        }
        ui.button("Invite", icon: user_plus,
                            size: sm);
      }
      List people = %(("Jonas Berg" "jonas@northlight.io" "Owner")
                      ("Priya Nair" "priya@harbor.dev" "Admin")
                      ("Tomas Rivera" "tomas@kiln.app" "Editor")
                      ("Lena Fischer" "lena@fischer.dev" "Viewer"));
      int index = 0;
      foreach (List person in people) {
        (String name, String email, String role) = person;
        String status = index == 0 ? "online" : index == 1 ? "away" : NULL;
        index++;
        ui.row (gap: 12, pad_y: 4) {
          ui.avatar(name, size: 34, status: status);
          ui.column (width: fill, gap: 1) {
            ui.text(name, font: medium, nowrap: true);
            ui.text(email, size: 12, color: text_secondary,
                           nowrap: true);
          }
          ui.badge(role, tone: role == "Owner" ? accent
                                                 : neutral);
        }
      }
    }
  }
}
