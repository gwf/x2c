#pragma once

/*  canvas.x -- scenes for canvas overlays and toolbars */

#include "scene.x"

static void scene_toolbar_group(Ui ui) {
  ui.toolbar ("grouped", style: grouped) {
    ui.toolbar_group () {
      ui.toolbar_button(undo_2, tooltip: "Undo");
      ui.toolbar_button(redo_2, tooltip: "Redo");
    }
    ui.toolbar_group () {
      ui.toolbar_button(bold, tooltip: "Bold");
      ui.toolbar_button(italic, tooltip: "Italic");
    }
  }
}

static void scene_toolbar_radio(Ui ui) {
  static int mode;
  String move = String.new(CUI_ICON_MOVE), draw = String.new(CUI_ICON_SQUARE_PEN);
  String text = String.new(CUI_ICON_TYPE);
  ui.toolbar ("modes", style: grouped) {
    ui.toolbar_radio("mode", %($move $draw $text),
      mode, labels: ["Move", "Draw", "Text"]);
  }
}

static void scene_toolbar_primary(Ui ui) {
  ui.toolbar ("generate", style: grouped) {
    ui.toolbar_button(settings, tooltip: "Settings");
    ui.toolbar_primary(sparkles, tooltip: "Generate");
  }
}

static void scene_toolbar_cycle(Ui ui) {
  static int scale = 1, format;
  ui.toolbar ("export", style: floating) {
    ui.toolbar_cycle("scale", %("1x" "2x" "4x"), scale, tooltip: "Scale");
    ui.toolbar_cycle("format", %("PNG" "JPG" "WEBP"), format,
      tooltip: "Format");
    ui.toolbar_button(download, tooltip: "Download");
  }
}

static void scene_format_bar(Ui ui) {
  static cui_text_format format = { .size = 44, .bold = true };
  ui.format_bar("format", format);
  ui.heading("The selected text", 1);
}

static void scene_live_cursors(Ui ui) {
  ui.card (width: fill, height: 260, pad: 24) {
    ui.heading("Shared canvas", 2);
    ui.text("Pointers are positions in this card.");
  }
  ui.live_cursors("people", [
    {name: "Kate", tone: info, x: 160, y: 120, says: "Ready to review"},
    {name: "Paul", tone: warning, x: 380, y: 190}], no_glide: true);
}

static void scene_presence_pill(Ui ui) {
  ui.presence_pill("people", [
    {name: "Kate", tone: info, speaking: true},
    {name: "Paul", tone: warning},
    {name: "Mario", tone: rose}]);
}

static void scene_selection_ring(Ui ui) {
  ui.card (width: 320, height: 180, pad: 24) {
    ui.heading("Selected card", 2);
    ui.text("Kate is working here.");
  }
  ui.selection_ring(ui.color_of(CUI_COLOR_INFO), name: "Kate");
}

static void scene_canvas_controls(Ui ui) {
  static cui_node_view view = { 0, 0, 1 };
  ui.node_editor ( "graph", view, height: 300) {
    static float x = 40, y = 60;
    ui.node (1, x, y, "Source", width: 180) {
      ui.node_output(1, "Image", type: 1);
    }
  }
  ui.canvas_controls("view", view, content: { 40, 60, 180, 120 });
}

static cui_texture result_picture(Ui ui) {
  cui_texture *texture = ui.state(ui.make_id("result-picture"), sizeof *texture);
  if (!*texture) {
    static unsigned char pixels[] = {
      100, 160, 230, 255, 160, 200, 240, 255,
      240, 180, 130, 255, 180, 90, 100, 255
    };
    *texture = ui.image_create(2, 2, pixels);
  }
  return *texture;
}

static void scene_result_card(Ui ui) {
  ui.result_card("result", result_picture(ui), "Evening palette",
    caption: "A preview ready to export", badge: "Ready",
    image_w: 2, image_h: 2, width: 260, aspect: 1.1);
}

static void scene_selection_bar(Ui ui) {
  ui.card (width: fill, height: 220, pad: 24) {
    ui.heading("Selected files", 2);
    ui.text("hero.png\nthumbnail.png\nsocial.png");
  }
  ui.selection_bar("files", 3, [
    {icon: copy, label: "Copy"},
    {icon: download, label: "Download"},
    {icon: trash_2, label: "Delete", tone: danger}]);
}

static Scene canvas_scenes[] = {
  { "toolbar_group", scene_toolbar_group },
  { "toolbar_radio", scene_toolbar_radio },
  { "toolbar_primary", scene_toolbar_primary },
  { "toolbar_cycle", scene_toolbar_cycle },
  { "format_bar", scene_format_bar },
  { "live_cursors", scene_live_cursors },
  { "presence_pill", scene_presence_pill },
  { "selection_ring", scene_selection_ring },
  { "canvas_controls", scene_canvas_controls },
  { "result_card", scene_result_card },
  { "selection_bar", scene_selection_bar },
};

Family canvas_family(void) {
  return (Family){ "Canvas", canvas_scenes,
                   sizeof canvas_scenes / sizeof *canvas_scenes };
}
