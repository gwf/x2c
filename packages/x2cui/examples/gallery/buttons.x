#pragma once

/*  buttons.x -- the gallery's Buttons page */

#include "state.x"

void page_buttons(Ui ui, Gallery g) {
  section(ui, "Variants",
          "One primary action per view. Secondary for everything else.");
  ui.card ()
  ui.row (gap: 8, wrap: true) {
    ui.button("Primary", variant: primary);
    ui.button("Secondary");
    ui.button("Outline", variant: outline);
    ui.button("Ghost", variant: ghost);
    ui.button("Danger", variant: danger);
    ui.button("Link", variant: link);
  }
  section(ui, "Sizes and icons", NULL);
  ui.card (gap: 16) {
    ui.row (gap: 8, wrap: true) {
      ui.button("Small", size: sm);
      ui.button("Medium");
      ui.button("Large", size: lg);
    }
    ui.row (gap: 8, wrap: true) {
      ui.button("New project", variant: primary,
                               icon: plus);
      ui.button("Download", icon: download);
      ui.button("Continue", variant: outline,
                            icon_right: arrow_right);
      ui.icon_button(copy, tooltip: "Copy",
                                    shortcut: "Ctrl C");
      ui.icon_button(share_2, tooltip: "Share");
      ui.icon_button(heart, tooltip: "Like",
                                     variant: outline);
      ui.icon_button(trash_2, tooltip: "Delete",
                                       variant: secondary);
    }
  }
  section(ui, "States",
          "Loading keeps the label so the layout does not jump.");
  ui.card ()
  ui.row (gap: 8, wrap: true) {
    if (ui.button(g.loading ? "Saving" : "Save changes",
          variant: primary, loading: g.loading))
      g.loading = true;
    if (ui.button("Reset##loading")) g.loading = false;
    ui.button("Disabled", disabled: true);
    ui.button("Selected", variant: ghost, selected: true,
                          icon: check);
  }
  section(ui, "Groups, copy and hold to confirm",
          "Hold the button until it fills to confirm a destructive action.");
  ui.card ()
  ui.row (gap: 12, wrap: true) {
    ui.button_group () {
      ui.button("Bold##group", icon: bold);
      ui.button("Italic##group", icon: italic);
      ui.button("Underline##group", icon: underline);
    }
    ui.row (gap: 6, bg: surface_muted, radius: 18,
            pad_left: 14, pad_right: 4, pad_y: 2) {
      ui.text("npm i cui", font: mono, nowrap: true);
      ui.copy_button("install", "npm i cui");
    }
    if (ui.hold_button("Hold to delete", icon: trash_2))
      ui.toast("Deleted", tone: danger);
  }
  section(ui, "Segmented control",
          "A highlight glides to the selected option.");
  ui.card (gap: 16) {
    static const char *view_icons[] = { CUI_ICON_LIST,
                                        CUI_ICON_LAYOUT_DASHBOARD,
                                        CUI_ICON_HISTORY };
    ui.segmented("view", %("List" "Board" "Timeline"), g.seg_view,
                 icons: view_icons);
    ui.segmented("range", %("Day" "Week" "Month" "Year"), g.seg_size,
                 size: sm);
  }
  section(ui, "Dropdown menu", NULL);
  ui.card ()
  ui.row (gap: 8, wrap: true) {
    ui.menu ("Options", icon: settings) {
      ui.menu_label("Project");
      ui.menu_item("Rename", icon: pencil, shortcut: "F2");
      ui.menu_item("Duplicate", icon: copy,
                                shortcut: "Ctrl D");
      ui.menu_item("Share", icon: share_2);
      ui.menu_separator();
      if (ui.menu_item("Delete", icon: trash_2,
                                 danger: true))
        g.confirm_open = true;
    }
    ui.menu ("More actions", icon_only: true,
                             icon: ellipsis) {
      ui.menu_item("Archive", icon: archive);
      ui.menu_item("Export", icon: download);
    }
  }
}
