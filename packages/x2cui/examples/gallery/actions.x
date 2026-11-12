#pragma once

/*  actions.x -- the gallery's Actions page */

#include "state.x"

void page_actions(Ui ui, Gallery g) {
  static bool fmt[4] = { true, false, false, false };
  static bool align[3] = { true, false, false };
  static cui_status save_status = CUI_STATUS_IDLE;
  static double status_at;
  static cui_reaction reactions[4] = {
    { CUI_ICON_THUMBS_UP, 12, true }, { CUI_ICON_HEART, 4, false },
    { CUI_ICON_ROCKET, 7, false }, { CUI_ICON_SMILE, 2, false },
  };
  static int dial_choice = -1;
  static int theme_mode = -1;
  static int deleted;
  static int split_choice = -1;

  section(ui, "Split button",
          "A main action with related actions one click away.");
  ui.row (gap: 12, wrap: true) {
    List items = %("Save as draft" "Save and publish" "Schedule\xe2\x80\xa6");
    static const char *icons[] = { CUI_ICON_FILE_TEXT, CUI_ICON_SEND,
                                   CUI_ICON_CLOCK };
    int r = ui.split_button("Save", items, item_icons: icons,
                                           icon: CUI_ICON_SAVE);
    if (r >= 0) split_choice = r;
    ui.split_button("Export", items, variant: CUI_BUTTON_OUTLINE,
                                     icon: CUI_ICON_DOWNLOAD);
    if (split_choice >= 0) {
      String choice = split_choice == 0 ? "Saved" : items[split_choice - 1];
      ui.muted(choice);
    }
  }

  section(ui, "Toggle group",
          "Independent toggles for toolbars, or exclusive like radio "
          "buttons.");
  ui.row (gap: 12, wrap: true) {
    static const char *icons[] = { CUI_ICON_BOLD, CUI_ICON_ITALIC,
                                   CUI_ICON_UNDERLINE, CUI_ICON_CODE };
    ui.toggle_group("format", %("Bold" "Italic" "Underline" "Code"), fmt,
                    icons: icons, icon_only: true);
    static const char *aicons[] = { CUI_ICON_ALIGN_LEFT, CUI_ICON_LIST,
                                    CUI_ICON_MENU };
    ui.toggle_group("align", %("Left" "Center" "Right"), align,
                    icons: aicons, exclusive: true);
  }

  section(ui, "Morphing buttons",
          "Confirm before destroying, and show the result of work in "
          "place.");
  ui.row (gap: 12, wrap: true) {
    if (ui.confirm_button("Delete project", icon: CUI_ICON_TRASH_2))
      deleted++;
    if (ui.status_button("Save changes", save_status,
          icon: CUI_ICON_SAVE, success_label: "Saved")) {
      save_status = CUI_STATUS_BUSY;
      status_at = ui.time();
    }
    double age = ui.time() - status_at;
    if (save_status == CUI_STATUS_BUSY && age > 1.4) {
      save_status = CUI_STATUS_SUCCESS;
      status_at = ui.time();
    }
    else if (save_status == CUI_STATUS_SUCCESS && age > 1.6)
      save_status = CUI_STATUS_IDLE;
    if (save_status != CUI_STATUS_IDLE) ui.request_redraw();
    if (deleted) ui.muted("Project deleted");
  }

  section(ui, "Reactions", "Counts roll when they change.");
  // The page ignores the result, so the method stands in for the macro.
  ui.reactions("reactions", reactions);

  section(ui, "Theme",
          "A compact switcher and a single toggle that morphs between sun "
          "and moon.");
  ui.row (gap: 16, wrap: true) {
    ui.theme_switcher(theme_mode, true);
    ui.theme_toggle();
  }

  section(ui, "User menu", "Account trigger for sidebars and headers.");
  ui.box (width: CUI_PX(260))
  ui.user_menu ("Maya Okafor",
      detail: "maya@fieldwork.studio", status: "online",
      placement: CUI_PLACE_BOTTOM_START) {
    ui.menu_item("Profile", icon: CUI_ICON_USER, shortcut: "Ctrl P");
    ui.menu_item("Billing", icon: CUI_ICON_CREDIT_CARD);
    ui.menu_item("Settings", icon: CUI_ICON_SETTINGS,
                             shortcut: "Ctrl ,");
    ui.menu_separator();
    ui.menu_item("Log out", icon: CUI_ICON_LOG_OUT);
  }

  section(ui, "Swipe actions",
          "Drag a row sideways or swipe with two fingers.");
  ui.card (pad: 6, gap: 6) {
    static const cui_swipe_action left[] = {
      { CUI_ICON_CHECK, "Done", CUI_TONE_SUCCESS } };
    static const cui_swipe_action right[] = {
      { CUI_ICON_ARCHIVE, "Archive", CUI_TONE_INFO },
      { CUI_ICON_TRASH_2, "Delete", CUI_TONE_DANGER } };
    List titles = %("Review the design tokens"
                    "Reply to Jonas about the release"
                    "Book the offsite venue");
    ui.each (String title in titles) {
      int action;
      ui.swipe_item (action, "row", left, right) {
        ui.icon(CUI_ICON_CIRCLE, 16, CUI_COLOR_TEXT_MUTED);
        ui.text(title, width: CUI_FILL, nowrap: true);
        ui.text("Today", size: 12, color: CUI_COLOR_TEXT_MUTED);
      }
      if (action >= 0)
        ui.toast(action == 0 ? "Marked as done"
                 : action == 100 ? "Archived" : "Deleted",
                 tone: action == 101 ? CUI_TONE_DANGER : CUI_TONE_SUCCESS);
    }
  }

  section(ui, "Speed dial",
          "A floating action button that fans out related actions.");
  ui.row (gap: 16, align: CUI_ALIGN_CENTER,
          height: CUI_PX(80)) {
    static const cui_speed_action acts[] = {
      { CUI_ICON_FILE_TEXT, "New note" }, { CUI_ICON_IMAGE, "Upload image" },
      { CUI_ICON_MIC, "Record memo" } };
    int c = ui.speed_dial("dial", acts,
                          tooltip: "Create");
    if (c >= 0) dial_choice = c;
    if (dial_choice >= 0) ui.muted(acts[dial_choice].label);
  }
}
