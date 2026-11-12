#pragma once

/*  layout.x -- scenes for boxes, rows, columns, cards, scrolling,
    splits, id and disabled scopes, text, and buttons
*/

#include "scene.x"

// A labelled tile, so a layout scene shows where each child lands.
static void tile(Ui ui, String label) {
  ui.box (pad: 12, bg: CUI_COLOR_SURFACE_MUTED, radius: 8)
    ui.label(label);
}

static void scene_box(Ui ui) {
  ui.box (width: CUI_PX(280), pad: 20, gap: 8, radius: 12,
          bg: CUI_COLOR_SURFACE_MUTED) {
    ui.label("A box");
    ui.text("A box holds children and has padding, a gap between "
            "children, a background, and a corner radius.");
  }
}

static void scene_row(Ui ui) {
  ui.row (gap: 8, align: CUI_ALIGN_CENTER) {
    tile(ui, "First");
    tile(ui, "Second");
    ui.spacer();
    tile(ui, "Pushed to the end");
  }
}

static void scene_column(Ui ui) {
  ui.column (gap: 8, width: CUI_PX(240)) {
    tile(ui, "Top");
    tile(ui, "Middle");
    tile(ui, "Bottom");
  }
}

static void scene_card(Ui ui) {
  ui.card (width: CUI_PX(320), pad: 20, gap: 8) {
    ui.heading("Quarterly report", 4);
    ui.text("A card is a surface with a border. This one holds a heading, "
            "a paragraph, and an action.", color: CUI_COLOR_TEXT_MUTED);
    ui.button("Open", variant: CUI_BUTTON_OUTLINE);
  }
}

static void scene_scroll(Ui ui) {
  ui.scroll (id: "rows", width: CUI_PX(280), height: CUI_PX(220),
             gap: 6) {
    for (int i = 1; i <= 24; i++) tile(ui, %"Row $i");
  }
}

static void scene_split(Ui ui) {
  static float ratio = 0.35f;
  ui.split ("panes", ratio, width: CUI_FILL,
                            height: CUI_PX(240)) {
    tile(ui, "Navigation");
    ui.split_next();
    tile(ui, "Content. Drag the divider.");
  }
}

static void scene_id_scope(Ui ui) {
  static bool first = true, second = false;
  // Both rows hold a switch labelled "Enabled"; the scope keeps them apart.
  $cui.id_scope(ui, "wifi") ui.row (gap: 12) {
    ui.label("Wi-Fi");
    ui.switch("Enabled", first);
  }
  $cui.id_scope(ui, "bluetooth") ui.row (gap: 12) {
    ui.label("Bluetooth");
    ui.switch("Enabled", second);
  }
}

static void scene_disabled_scope(Ui ui) {
  static bool locked = true, notify = true;
  ui.switch("Lock the form", locked);
  $cui.disabled_scope(ui, locked) ui.column (gap: 8) {
    ui.checkbox("Send notifications", notify);
    ui.button("Save", variant: CUI_BUTTON_PRIMARY);
  }
}

static void scene_text(Ui ui) {
  ui.heading("Heading", 2);
  ui.label("A label has medium weight.");
  ui.text("Body text wraps to the width it is given and follows the theme.",
          width: CUI_PX(320));
  ui.text("Muted, smaller text.", color: CUI_COLOR_TEXT_MUTED,
                                  size: 12);
}

static void scene_button(Ui ui) {
  static int clicks = 0;
  ui.row (gap: 8, wrap: true) {
    if (ui.button("Primary", variant: CUI_BUTTON_PRIMARY,
                             icon: CUI_ICON_PLUS))
      clicks++;
    ui.button("Secondary");
    ui.button("Outline", variant: CUI_BUTTON_OUTLINE);
    ui.button("Ghost", variant: CUI_BUTTON_GHOST);
    ui.button("Danger", variant: CUI_BUTTON_DANGER);
    ui.button("Saving", variant: CUI_BUTTON_PRIMARY, loading: true);
  }
  ui.text(%"Primary was clicked $clicks times.");
}

static void scene_icon_button(Ui ui) {
  ui.row (gap: 8) {
    ui.icon_button(CUI_ICON_SETTINGS, tooltip: "Settings");
    ui.icon_button(CUI_ICON_SEARCH, variant: CUI_BUTTON_OUTLINE);
    ui.icon_button(CUI_ICON_X, variant: CUI_BUTTON_GHOST,
                               size: CUI_SIZE_SM);
  }
}

static Scene layout_scenes[] = {
  { "box", scene_box },
  { "row", scene_row },
  { "column", scene_column },
  { "card", scene_card },
  { "scroll", scene_scroll },
  { "split", scene_split },
  { "id_scope", scene_id_scope },
  { "disabled_scope", scene_disabled_scope },
  { "text", scene_text },
  { "button", scene_button },
  { "icon_button", scene_icon_button },
};

Family layout_family(void) => (Family){
  "Layout and text", layout_scenes,
  sizeof layout_scenes / sizeof *layout_scenes };
