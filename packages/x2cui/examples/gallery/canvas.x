#pragma once

/*  canvas.x -- grouped tools, shared canvas controls, and selection actions */

#include "state.x"
import "x2cui" with LiveUsers;

static bool numbers = true, bold, italic, grid = true, saved;
static int mode, scale = 1, format, deleted;
static bool selected[3] = { true, true, false };
static cui_node_view view = { 0, 0, 1 };
static cui_text_format text_format = {
  CUI_TONE_ROSE, true, false, false, 0, 44,
  CUI_FORMAT_ALIGN_LEFT, CUI_FORMAT_LIST_NONE
};

typedef struct CanvasPaint { cui_node_view view; bool grid; cui_id wheel; } CanvasPaint;

static void paint_board(Ui ui, cui_rect area, void *data) {
  CanvasPaint *p = data;
  ui.draw_rect(area, CUI_CORNERS(12), ui.color_of(surface_muted));
  if (p.grid) for (int y = 0; y < 12; y++)
    for (int x = 0; x < 30; x++)
      ui.draw_circle((cui_vec2){area.x + x * 24, area.y + y * 24},
        1, ui.color_of(border));
  cui_rect card = {area.x + 30 + p.view.x,
    area.y + 80 + p.view.y, 220 * p.view.zoom, 110 * p.view.zoom};
  ui.draw_rect(card, CUI_CORNERS(12), ui.color_of(accent_subtle));
  ui.wheel_region(p.wheel, area);
}

typedef struct CanvasImage { cui_texture texture; } CanvasImage;

static void free_picture(Ui ui, void *data) {
  CanvasImage *held = data;
  ui.image_destroy(held.texture);
}

static cui_texture picture(Ui ui) {
  cui_id id = ui.make_id("gallery-result-image");
  CanvasImage *held = ui.state(id, sizeof *held);
  if (held.texture) return held.texture;
  unsigned char pixels[96 * 64 * 4];
  for (int y = 0; y < 64; y++) for (int x = 0; x < 96; x++) {
    int i = (y * 96 + x) * 4;
    pixels[i] = 65 + x;
    pixels[i + 1] = 110 + y;
    pixels[i + 2] = 200;
    pixels[i + 3] = 255;
  }
  held.texture = ui.image_create(96, 64, pixels);
  cui_state_on_free(ui, id, free_picture);
  return held.texture;
}

void page_canvas(Ui ui, Gallery g) {
  section(ui, "Grouped toolbar", "Choose a tool, toggle formatting, and try the primary action.");
  String move_icon = String.new(CUI_ICON_MOVE);
  String draw_icon = String.new(CUI_ICON_SQUARE_PEN);
  String text_icon = String.new(CUI_ICON_TYPE);
  ui.toolbar ("drawing-tools", style: grouped) {
    ui.toolbar_group () {
      if (ui.toolbar_button(undo_2, tooltip: "Undo")) ui.toast("Undo requested");
      if (ui.toolbar_button(redo_2, tooltip: "Redo")) ui.toast("Redo requested");
    }
    ui.toolbar_group () {
      ui.toolbar_button(NULL, label: "123", tooltip: "Numbers", toggle: &numbers);
      ui.toolbar_button(CUI_ICON_BOLD, tooltip: "Bold", toggle: &bold);
      ui.toolbar_button(CUI_ICON_ITALIC, tooltip: "Italic", toggle: &italic);
      ui.toolbar_radio("mode", %($move_icon $draw_icon $text_icon), mode, labels: ["Move", "Draw", "Text"]);
    }
    if (ui.toolbar_primary(sparkles, tooltip: "Generate")) ui.toast("Generation requested");
  }
  section(ui, "Format bar", "Change the text style and alignment. Delete asks for confirmation.");
  int action = ui.format_bar("format", text_format);
  if (action & CUI_FORMAT_DELETE) deleted++;
  if (action & CUI_FORMAT_LINK) text_format.link = !text_format.link;
  ui.muted(%"Delete confirmed $deleted times");
  section(ui, "Canvas controls", "Scroll over the canvas to pan. Use the rail to zoom or fit.");
  cui_canvas_toggle toggles[] = {{CUI_ICON_GRID_3X3, "Grid", &grid}};
  static LiveUsers people;
  if (!people) people = LiveUsers.of([
    {name: "Paul", x: 80, y: 110, tone: warning, speaking: true},
    {name: "Kate", x: 250, y: 150, tone: info, says: "Looks good"}]);
  ui.box (dir: stack, width: fill, height: 300, clip: true, radius: 12) {
    cui_id wheel = ui.make_id("board-wheel");
    cui_vec2 delta;
    if (ui.wheel_take(wheel, delta)) {
      view.x += delta.x * 24;
      view.y += delta.y * 24;
    }
    CanvasPaint paint = {view, grid, wheel};
    ui.canvas("board", fill, 300, paint_board, &paint, sizeof paint);
    ui.selection_ring(ui.color_of(warning), name: "Paul");
    ui.canvas_controls("zoom", view, content: {0, 0, 340, 230}, toggles: toggles);
    ui.live_cursors("people", people, view: &view);
    ui.box (pad: 12) ui.presence_pill("here", people);
  }
  section(ui, "Result and selection", "The card and floating tools report actions. Select files for bulk actions.");
  if (ui.result_card("result", picture(ui), "Gradient study", caption: "A generated texture with export controls",
      badge: "Ready", image_w: 96, image_h: 64, width: 280, aspect: 0.6f)) ui.toast("Result opened");
  ui.toolbar ("result-tools", style: floating) {
    ui.toolbar_button(bookmark, tooltip: "Save", toggle: &saved);
    ui.toolbar_cycle("scale", %("1x" "2x" "4x"), scale, tooltip: "Scale");
    ui.toolbar_cycle("format", %("PNG" "JPG" "WEBP"), format, tooltip: "Format");
  }
  ui.column (id: "files", width: fill, gap: 8) {
    ui.checkbox("hero.png", selected[0]);
    ui.checkbox("social.png", selected[1]);
    ui.checkbox("icon.png", selected[2]);
  }
  int bulk = ui.selection_bar("bulk", 0, [
    {icon: copy, label: "Copy"}, {icon: trash_2, label: "Delete", tone: danger}],
    selected: selected, item_count: 3, anchor: ui.make_id("files"));
  if (bulk >= 0) ui.toast(bulk == 0 ? "Copy requested" : "Delete requested");
}
