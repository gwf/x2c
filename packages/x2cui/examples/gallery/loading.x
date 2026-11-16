#pragma once

/*  loading.x -- dithered progress, placeholders, and revealable content */

#include "state.x"

static bool grayscale, revealed;
static float progress = 0.62f;
static int job = 1;

void page_loading(Ui ui, Gallery g) {
  section(ui, "Spinner styles", "Each animation has a different shape and pacing.");
  List names = %("Arc" "Comet" "Dot matrix" "Fill and drain" "Radar" "Ripple"
    "Upload" "Download" "Transfer" "Orbit" "Bounce" "Scan" "Pulse" "Spiral" "Plasma");
  ui.row (gap: 24, wrap: true, align: end) {
    for (int k = 0; k < names.len(); k++) ui.column (gap: 8, align: center) {
      ui.spinner(40, style: (cui_spinner_style) k);
      ui.muted((String) names[k]);
    }
  }
  section(ui, "Job status", "Switch from Busy to Success or Error to see the transition.");
  ui.segmented("job-state", %("Idle" "Busy" "Success" "Error"), job);
  ui.status_spinner("job", (cui_status) job, size: 36, keep: true);
  section(ui, "Progress and placeholders", "Dots also show progress and a shared loading shimmer.");
  ui.slider("Progress", progress, 0, 1);
  ui.progress(progress, label: "Import", show_value: true, dither: true);
  ui.skeleton_group (dither: true, gap: 12) {
    ui.row (gap: 12) { ui.skeleton(40, 40); ui.skeleton(240, 12); }
    ui.skeleton(fill, 10);
    ui.skeleton(320, 10);
  }
  section(ui, "Pattern meter", "Hover a segment or focus the meter and use arrow keys.");
  ui.switch("Grayscale", grayscale);
  ui.pattern_meter("storage", [
    {name: "Images", value: 42}, {name: "Video", value: 28},
    {name: "Documents", value: 12}], total: 100, unit: "GB",
    label: "Storage", grayscale: grayscale);
  section(ui, "Veil", "Click to reveal the content. Click again to cover it.");
  ui.veil ("preview", revealed, label: "Unreleased preview", hint: "Click to reveal",
      toggle: true, radius: 12) {
    ui.card (width: fill, pad: 24) {
      ui.heading("A preview worth sharing", 2);
      ui.secondary("The veil covers ordinary content and handles pointer and keyboard input.");
    }
  }
}
