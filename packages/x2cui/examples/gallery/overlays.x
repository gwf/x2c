#pragma once

/*  overlays.x -- the gallery's Overlays page */

#include "state.x"

void page_overlays(Ui ui, Gallery g) {
  section(ui, "Dialogs and sheets",
          "Esc or a click outside closes them. Focus stays inside.");
  $cui.card(ui, {})
  $cui.row(ui, { .gap = 8, .wrap = true }) {
    if (ui.button("Edit profile", { .icon = CUI_ICON_PENCIL }))
      g.dialog_open = true;
    if (ui.button("Open sheet", { .icon = CUI_ICON_PANEL_LEFT }))
      g.sheet_open = true;
    if (ui.button("Delete project", { .variant = CUI_BUTTON_DANGER,
                                      .icon = CUI_ICON_TRASH_2 }))
      g.confirm_open = true;
    if (ui.button("Command palette", {
          .variant = CUI_BUTTON_OUTLINE, .icon = CUI_ICON_COMMAND,
          .tooltip = "Search everything", .shortcut = "Ctrl K" }))
      g.palette_open = true;
  }
  section(ui, "Popover and context menu", NULL);
  $cui.card(ui, { .gap = 16 }) {
    $cui.row(ui, { .gap = 8, .wrap = true }) {
      if (ui.button("Filters", { .icon = CUI_ICON_FILTER }))
        ui.popover_toggle("filters");
      $cui.popover(ui, "filters", { .width = 280 }) {
        ui.label("Filter results");
        ui.checkbox("Only active", g.newsletter, {});
        ui.checkbox("Include archived", g.marketing, {});
        ui.slider("Minimum score", g.brightness, 0, 100,
                  { .show_value = true });
        $cui.row(ui, { .gap = 8, .justify = CUI_JUSTIFY_END }) {
          if (ui.button("Apply", { .variant = CUI_BUTTON_PRIMARY,
                                   .size = CUI_SIZE_SM }))
            ui.popover_close("filters");
        }
      }
    }
    $cui.card(ui, { .muted = true, .id = "ctx-area", .pad = 28,
                    .align = CUI_ALIGN_CENTER, .hoverable = true }) {
      ui.icon(CUI_ICON_ELLIPSIS, 18, CUI_COLOR_TEXT_MUTED);
      ui.text("Right click this area", {
        .color = CUI_COLOR_TEXT_SECONDARY, .align = CUI_TEXT_CENTER });
    }
    $cui.context_menu(ui, "ctx") {
      ui.menu_item("Cut", { .icon = CUI_ICON_SCISSORS,
                            .shortcut = "Ctrl X" });
      ui.menu_item("Copy", { .icon = CUI_ICON_COPY, .shortcut = "Ctrl C" });
      ui.menu_item("Paste", { .icon = CUI_ICON_CLIPBOARD,
                              .shortcut = "Ctrl V" });
      ui.menu_separator();
      ui.menu_item("Delete", { .icon = CUI_ICON_TRASH_2, .danger = true });
    }
  }
  section(ui, "Toasts", "They stack, expand on hover and pause while you "
                        "read.");
  $cui.card(ui, {})
  $cui.row(ui, { .gap = 8, .wrap = true }) {
    if (ui.button("Save profile", {}))
      ui.toast("Changes saved", {
        .description = "Your profile is up to date.",
        .tone = CUI_TONE_SUCCESS });
    if (ui.button("Upload a 30 MB file", {}))
      ui.toast("Upload failed", {
        .description = "The file is larger than 25 MB.",
        .tone = CUI_TONE_DANGER });
    if (ui.button("Archive a message", {}))
      ui.toast("Message archived", { .action = "Undo" });
    if (ui.button("Check for updates", {}))
      ui.toast("Update available", {
        .description = "Version 1.1 is ready to install.",
        .tone = CUI_TONE_INFO });
  }
  section(ui, "Tooltips", NULL);
  $cui.card(ui, {})
  $cui.row(ui, { .gap = 4, .wrap = true }) {
    ui.icon_button(CUI_ICON_BOLD, { .tooltip = "Bold",
                                    .shortcut = "Ctrl B" });
    ui.icon_button(CUI_ICON_ITALIC, { .tooltip = "Italic",
                                      .shortcut = "Ctrl I" });
    ui.icon_button(CUI_ICON_UNDERLINE, { .tooltip = "Underline",
                                         .shortcut = "Ctrl U" });
    ui.separator();
    ui.icon_button(CUI_ICON_ALIGN_LEFT, { .tooltip = "Align left" });
    ui.icon_button(CUI_ICON_LIST, { .tooltip = "Bulleted list" });
    ui.icon_button(CUI_ICON_LINK, { .tooltip = "Insert link" });
  }
}
