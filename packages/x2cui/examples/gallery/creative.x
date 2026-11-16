#pragma once

/*  creative.x -- controls for palettes, proportions, and export choices */

#include "state.x"
import "x2cui" with Colors;

static float coffee = 0.37f, training = 0.8f;
static float hue = 190, temperature = 5600, opacity = 0.72f;
static int variations = 3, generated, aspect = 1, format;
static uint32_t seed = 1234567890u, palette_seed = 7;
static bool fixed_seed, picking, locked[5], removed[7];
static Colors palette;

void page_creative(Ui ui, Gallery g) {
  if (!palette) palette = Colors.of([
    {r: 238, g: 240, b: 245, a: 255}, {r: 92, g: 99, b: 112, a: 255},
    {r: 55, g: 198, b: 208, a: 255}, {r: 31, g: 58, b: 95, a: 255},
    {r: 242, g: 189, b: 104, a: 255}]);
  section(ui, "Status tags", "Click a small tag to remove it. Reset restores the set.");
  List states = %("Pending" "In progress" "Submitted" "In review" "Success" "Failed" "Expired");
  ui.row (gap: 8, wrap: true) {
    for (int k = 0; k < states.len(); k++)
      ui.status_tag((String) states[k], (cui_tag_status) k);
  }
  ui.row (gap: 8, wrap: true) {
    for (int k = 0; k < states.len(); k++)
      if (!removed[k] && ui.status_tag((String) states[k], (cui_tag_status) k,
          size: sm, removable: true)) removed[k] = true;
    if (ui.button("Reset tags", size: sm))
      for (int k = 0; k < 7; k++) removed[k] = false;
  }
  section(ui, "Ratios", "Drag the split or use arrow keys. Shift moves in larger steps.");
  ui.ratio_slider("COFFEE", "MILK", coffee, tone: warning);
  ui.ratio_slider("TRAIN", "TEST", training, tone: info);
  section(ui, "Gradient and step sliders", "Change color, temperature and opacity, then generate a variation.");
  ui.gradient_slider("Hue", hue, 0, 360, swatch: true);
  if (ui.gradient_slider("White balance", temperature, 2500, 10000,
      track: CUI_GRADIENT_TEMPERATURE, step: 100, tool: target,
      tool_tooltip: "Pick from image", tool_on: picking) & CUI_WELL_ACTION)
    picking = !picking;
  ui.gradient_slider("Opacity", opacity, 0, 1, track: CUI_GRADIENT_OPACITY,
    color: CUI_RGB(0x2bb8a6));
  if (ui.step_slider("Variations", variations, 1, 4, tool: refresh_cw,
      tool_tooltip: "Generate", value: %"Generated $generated times") & CUI_WELL_ACTION)
    generated++;
  section(ui, "Palette", "Lock swatches before shuffling the remaining colors.");
  ui.palette_strip("Color palette", palette, locked, seed: &palette_seed);
  section(ui, "Output", "Choose an aspect ratio, export format, and repeatable seed.");
  ui.aspect_picker("Aspect ratio", aspect, custom: true);
  if (ui.option_action("Save as", %("PNG" "JPG" "WEBP"), format,
      download, tooltip: "Export") & CUI_WELL_ACTION)
    ui.toast("Export requested", description: "This gallery does not write a file.");
  ui.seed_field("Seed", seed, fixed_seed,
    value: fixed_seed ? "Same image each run" : "Random each run");
}
