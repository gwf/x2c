#pragma once

/*  overview.x -- the gallery's Overview page */

#include "state.x"

void page_overview(Ui ui, Gallery g) {
  ui.column (gap: 14, pad_bottom: 8) {
    ui.heading("Components for C", 1);
    ui.text("Forms, tables, charts, planning boards and chat pieces that "
            "draw themselves the same way on Windows, macOS and Linux. "
            "Every one works from the keyboard.",
            color: CUI_COLOR_TEXT_SECONDARY, size: 15);
    ui.row (gap: 8, pad_top: 6, wrap: true) {
      if (ui.button("Browse components",
            variant: CUI_BUTTON_PRIMARY,
            icon_right: CUI_ICON_ARROW_RIGHT))
        g.page = PAGE_BUTTONS;
      if (ui.button("Open command palette",
            variant: CUI_BUTTON_OUTLINE, icon: CUI_ICON_COMMAND))
        g.palette_open = true;
    }
  }
  ui.box (dir: CUI_GRID, columns: 3, min_column_width: 200,
          gap: 16) {
    static const float frame_times[] = { 9, 7, 8, 6, 5, 6, 4, 4, 3 };
    ui.metric("Components", "150", icon: CUI_ICON_BOX);
    ui.metric("Frame time", "0.4 ms",
      delta: -18.0f, delta_label: "-18% vs v0.9",
      lower_is_better: true, spark: frame_times,
      spark_count: $cui.count(frame_times), icon: CUI_ICON_ZAP);
    ui.metric("Dependencies", "0", icon: CUI_ICON_PACKAGE);
  }
  ui.box (dir: CUI_GRID, columns: 2, min_column_width: 260,
          gap: 16) {
    ui.card (gap: 16) {
      ui.column (gap: 4) {
        ui.heading("Create a workspace", 4);
        ui.secondary("You can invite people once it exists.");
      }
      ui.input("ov-name", g.name, label: "Name",
                                  placeholder: "Your name");
      ui.input("ov-email", g.email, label: "Email",
                                    icon: CUI_ICON_MAIL,
                                    placeholder: "you@company.com");
      ui.checkbox("Email me a weekly summary", g.terms);
      if (ui.button("Create workspace", variant: CUI_BUTTON_PRIMARY,
                                        full_width: true))
        ui.toast("Workspace created",
          description: "It is empty for now. Start with a project.",
          tone: CUI_TONE_SUCCESS);
    }
    ui.card (gap: 12) {
      ui.row () {
        ui.column (gap: 4, width: CUI_FILL) {
          ui.heading("Team", 4);
          ui.secondary("Four people, one owner.");
        }
        ui.button("Invite", icon: CUI_ICON_USER_PLUS,
                            size: CUI_SIZE_SM);
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
          ui.column (width: CUI_FILL, gap: 1) {
            ui.text(name, font: CUI_FONT_MEDIUM, nowrap: true);
            ui.text(email, size: 12, color: CUI_COLOR_TEXT_SECONDARY,
                           nowrap: true);
          }
          ui.badge(role, tone: role == "Owner" ? CUI_TONE_ACCENT
                                                 : CUI_TONE_NEUTRAL);
        }
      }
    }
  }
}
