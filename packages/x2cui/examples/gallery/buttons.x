#pragma once

/*  buttons.x -- the gallery's Buttons page */

#include "state.x"

void page_buttons(Ui ui, Gallery g) {
  section(ui, "Variants",
          "One primary action per view. Secondary for everything else.");
  ui.card ()
  ui.row (gap: 8, wrap: true) {
    ui.button("Primary", variant: CUI_BUTTON_PRIMARY);
    ui.button("Secondary");
    ui.button("Outline", variant: CUI_BUTTON_OUTLINE);
    ui.button("Ghost", variant: CUI_BUTTON_GHOST);
    ui.button("Danger", variant: CUI_BUTTON_DANGER);
    ui.button("Link", variant: CUI_BUTTON_LINK);
  }
  section(ui, "Sizes and icons", NULL);
  ui.card (gap: 16) {
    ui.row (gap: 8, wrap: true) {
      ui.button("Small", size: CUI_SIZE_SM);
      ui.button("Medium");
      ui.button("Large", size: CUI_SIZE_LG);
    }
    ui.row (gap: 8, wrap: true) {
      ui.button("New project", variant: CUI_BUTTON_PRIMARY,
                               icon: CUI_ICON_PLUS);
      ui.button("Download", icon: CUI_ICON_DOWNLOAD);
      ui.button("Continue", variant: CUI_BUTTON_OUTLINE,
                            icon_right: CUI_ICON_ARROW_RIGHT);
      ui.icon_button(CUI_ICON_COPY, tooltip: "Copy",
                                    shortcut: "Ctrl C");
      ui.icon_button(CUI_ICON_SHARE_2, tooltip: "Share");
      ui.icon_button(CUI_ICON_HEART, tooltip: "Like",
                                     variant: CUI_BUTTON_OUTLINE);
      ui.icon_button(CUI_ICON_TRASH_2, tooltip: "Delete",
                                       variant: CUI_BUTTON_SECONDARY);
    }
  }
  section(ui, "States",
          "Loading keeps the label so the layout does not jump.");
  ui.card ()
  ui.row (gap: 8, wrap: true) {
    if (ui.button(g.loading ? "Saving" : "Save changes",
          variant: CUI_BUTTON_PRIMARY, loading: g.loading))
      g.loading = true;
    if (ui.button("Reset##loading")) g.loading = false;
    ui.button("Disabled", disabled: true);
    ui.button("Selected", variant: CUI_BUTTON_GHOST, selected: true,
                          icon: CUI_ICON_CHECK);
  }
  section(ui, "Groups, copy and hold to confirm",
          "Hold the button until it fills to confirm a destructive action.");
  ui.card ()
  ui.row (gap: 12, wrap: true) {
    ui.button_group () {
      ui.button("Bold##group", icon: CUI_ICON_BOLD);
      ui.button("Italic##group", icon: CUI_ICON_ITALIC);
      ui.button("Underline##group", icon: CUI_ICON_UNDERLINE);
    }
    ui.row (gap: 6, bg: CUI_COLOR_SURFACE_MUTED, radius: 18,
            pad_left: 14, pad_right: 4, pad_y: 2) {
      ui.text("npm i cui", font: CUI_FONT_MONO, nowrap: true);
      ui.copy_button("install", "npm i cui");
    }
    if (ui.hold_button("Hold to delete", icon: CUI_ICON_TRASH_2))
      ui.toast("Deleted", tone: CUI_TONE_DANGER);
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
                 size: CUI_SIZE_SM);
  }
  section(ui, "Dropdown menu", NULL);
  ui.card ()
  ui.row (gap: 8, wrap: true) {
    ui.menu ("Options", icon: CUI_ICON_SETTINGS) {
      ui.menu_label("Project");
      ui.menu_item("Rename", icon: CUI_ICON_PENCIL, shortcut: "F2");
      ui.menu_item("Duplicate", icon: CUI_ICON_COPY,
                                shortcut: "Ctrl D");
      ui.menu_item("Share", icon: CUI_ICON_SHARE_2);
      ui.menu_separator();
      if (ui.menu_item("Delete", icon: CUI_ICON_TRASH_2,
                                 danger: true))
        g.confirm_open = true;
    }
    ui.menu ("More actions", icon_only: true,
                             icon: CUI_ICON_ELLIPSIS) {
      ui.menu_item("Archive", icon: CUI_ICON_ARCHIVE);
      ui.menu_item("Export", icon: CUI_ICON_DOWNLOAD);
    }
  }
}
