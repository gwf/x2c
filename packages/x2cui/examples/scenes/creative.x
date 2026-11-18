#pragma once

/*  creative.x -- scenes for creative controls */

#include "scene.x"

import "x2cui" with Colors;

static void scene_status_tag(Ui ui) {
  ui.row (gap: 10, wrap: true) {
    ui.status_tag("Waiting", pending);
    ui.status_tag("Rendering", in_progress);
    ui.status_tag("Ready", success, removable: true);
  }
}

static void scene_ratio_slider(Ui ui) {
  static float ratio = 0.7;
  ui.ratio_slider("TRAIN", "TEST", ratio, tone: info);
}

static void scene_gradient_slider(Ui ui) {
  static float hue = 190, temperature = 5600;
  ui.gradient_slider("Hue", hue, 0, 360, swatch: true);
  ui.gradient_slider("White balance", temperature, 2500, 10000,
    track: temperature, step: 100);
}

static void scene_step_slider(Ui ui) {
  static int variations = 3;
  ui.step_slider("Variations", variations, 1, 4,
    tool: CUI_ICON_REFRESH_CW, tool_tooltip: "Generate");
}

static void scene_palette_strip(Ui ui) {
  static Colors colors;
  if (!colors) colors = Colors.of([
    {r: 238, g: 240, b: 245, a: 255},
    {r: 55, g: 198, b: 208, a: 255},
    {r: 242, g: 189, b: 104, a: 255}]);
  static bool locked[] = { false, true, false };
  static uint32_t seed = 7;
  ui.palette_strip("Palette", colors, locked, seed: &seed,
    value: "The middle swatch is locked");
}

static void scene_aspect_picker(Ui ui) {
  static int aspect = 1;
  ui.aspect_picker("Aspect ratio", aspect, custom: true);
}

static void scene_option_action(Ui ui) {
  static int format = 0;
  ui.option_action("Save as", %("PNG" "JPG" "WEBP"), format,
    download, tooltip: "Download", value: "Ready to export");
}

static void scene_seed_field(Ui ui) {
  static uint32_t seed = 1234567890;
  static bool locked = true;
  ui.seed_field("Seed", seed, locked, value: "Same image every run");
}

static Scene creative_scenes[] = {
  { "status_tag", scene_status_tag },
  { "ratio_slider", scene_ratio_slider },
  { "gradient_slider", scene_gradient_slider },
  { "step_slider", scene_step_slider },
  { "palette_strip", scene_palette_strip },
  { "aspect_picker", scene_aspect_picker },
  { "option_action", scene_option_action },
  { "seed_field", scene_seed_field },
};

Family creative_family(void) {
  return (Family){ "Creative", creative_scenes,
                   sizeof creative_scenes / sizeof *creative_scenes };
}
