#pragma once

/*  overlays.x -- the gallery's Overlays page */

#include "state.x"

void page_overlays(Ui ui, Gallery g) {
  section(ui, "Dialogs and sheets",
          "Esc or a click outside closes them. Focus stays inside.");
  ui.card ()
  ui.row (gap: 8, wrap: true) {
    if (ui.button("Edit profile", icon: pencil))
      g.dialog_open = true;
    if (ui.button("Open sheet", icon: panel_left))
      g.sheet_open = true;
    if (ui.button("Delete project", variant: danger,
                                    icon: trash_2))
      g.confirm_open = true;
    if (ui.button("Command palette",
          variant: outline, icon: command,
          tooltip: "Search everything", shortcut: "Ctrl K"))
      g.palette_open = true;
  }
  section(ui, "Popover and context menu", NULL);
  ui.card (gap: 16) {
    ui.row (gap: 8, wrap: true) {
      if (ui.button("Filters", icon: filter))
        ui.popover_toggle("filters");
      ui.popover ("filters", width: 280) {
        ui.label("Filter results");
        ui.checkbox("Only active", g.newsletter);
        ui.checkbox("Include archived", g.marketing);
        ui.slider("Minimum score", g.brightness, 0, 100,
                  show_value: true);
        ui.row (gap: 8, justify: end) {
          if (ui.button("Apply", variant: primary,
                                 size: sm))
            ui.popover_close("filters");
        }
      }
    }
    ui.card (muted: true, id: "ctx-area", pad: 28,
             align: center, hoverable: true) {
      ui.icon(ellipsis, 18, text_muted);
      ui.text("Right click this area",
        color: text_secondary, align: center);
    }
    ui.context_menu ("ctx") {
      ui.menu_item("Cut", icon: scissors,
                          shortcut: "Ctrl X");
      ui.menu_item("Copy", icon: copy, shortcut: "Ctrl C");
      ui.menu_item("Paste", icon: clipboard,
                            shortcut: "Ctrl V");
      ui.menu_separator();
      ui.menu_item("Delete", icon: trash_2, danger: true);
    }
  }
  section(ui, "Toasts", "They stack, expand on hover and pause while you "
                        "read.");
  ui.card ()
  ui.row (gap: 8, wrap: true) {
    if (ui.button("Save profile"))
      ui.toast("Changes saved",
        description: "Your profile is up to date.",
        tone: success);
    if (ui.button("Upload a 30 MB file"))
      ui.toast("Upload failed",
        description: "The file is larger than 25 MB.",
        tone: danger);
    if (ui.button("Archive a message"))
      ui.toast("Message archived", action: "Undo");
    if (ui.button("Check for updates"))
      ui.toast("Update available",
        description: "Version 1.1 is ready to install.",
        tone: info);
  }
  section(ui, "Tooltips", NULL);
  ui.card ()
  ui.row (gap: 4, wrap: true) {
    ui.icon_button(bold, tooltip: "Bold",
                                  shortcut: "Ctrl B");
    ui.icon_button(italic, tooltip: "Italic",
                                    shortcut: "Ctrl I");
    ui.icon_button(underline, tooltip: "Underline",
                                       shortcut: "Ctrl U");
    ui.separator();
    ui.icon_button(align_left, tooltip: "Align left");
    ui.icon_button(list, tooltip: "Bulleted list");
    ui.icon_button(link, tooltip: "Insert link");
  }
}
