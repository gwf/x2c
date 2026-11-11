#pragma once

/*  audio.x -- the gallery's Audio page */

#include "state.x"
#include <math.h>

void page_audio(Ui ui, Gallery g) {
  static float cutoff = 1800, res = 0.3f, attack = 12, pan = 0.15f;
  static float faders[6] = { -4, -9, 0, -15, -6, -2 };
  static int tick;
  tick++;
  List names = %("Kick" "Snare" "Bass" "Keys" "Vocals" "FX");
  static const float marks[] = { 6, 0, -6, -12, -24, -48 };
  float lv[6][2];
  for (int k = 0; k < 6; k++)
    for (int c = 0; c < 2; c++) {
      float t = (tick + c * 5) / 60.0f;
      float beat = fmodf(t * (1.8f + 0.2f * k) + k * 0.31f, 1.0f);
      lv[k][c] = (0.3f + 0.1f * k) * (0.2f + 0.8f * expf(-beat * (2.5f + k)));
    }
  static int tour = -1;
  static cui_tour_step steps[3] = {
    { 0, "Turn a knob", "Drag up and down. Hold Shift for fine steps, "
                        "double-click to reset.", CUI_PLACE_BOTTOM_START },
    { 0, "Watch the levels", "Bars fall back after each peak; the mark "
                             "above them holds the peak a moment.",
      CUI_PLACE_TOP_START },
    { 0, "Ride the faders", "Click a fader, then use the wheel or the "
                            "arrow keys.", CUI_PLACE_LEFT_START },
  };
  if (ui.button("Take the tour", icon: CUI_ICON_SPARKLES,
                                 variant: CUI_BUTTON_OUTLINE))
    tour = 0;
  $cui.row(ui, { .gap = 16, .wrap = true, .align = CUI_ALIGN_START }) {
    $cui.card(ui, { .gap = 16, .min_width = 280 }) {
      ui.heading("Synth", 4);
      $cui.row(ui, { .gap = 14, .wrap = true }) {
        ui.knob("Cutoff", cutoff, 20, 20000,
          unit: "Hz", log_scale: true, reset: 1000);
        steps[0].target = ui.last_id();
        ui.knob("Resonance", res, 0, 1, format: "%.2f");
        ui.knob("Attack", attack, 1, 2000,
          unit: "ms", log_scale: true, reset: 10);
        ui.knob("Pan", pan, -1, 1, bipolar: true, format: "%+.2f");
      }
      float master[2] = { lv[0][0] * 1.4f, lv[4][1] * 1.3f };
      // The page ignores the result, so the method stands in for the macro.
      ui.level_meter("master", master, $cui.count(master),
        horizontal: true, length: 240, scale: true,
        segmented: true);
      steps[1].target = ui.last_id();
    }
    $cui.card(ui, { .dir = CUI_ROW, .gap = 8, .wrap = true }) {
      for (int k = 0; k < 6; k++) $cui.id_index(ui, k) {
        String name = names[k];
        ui.fader(name, faders[k], -48, 6,
          unit: "dB", length: 180, ticks: k == 0 ? marks : NULL,
          tick_count: k == 0 ? $cui.count(marks) : 0, meter: lv[k],
          meter_channels: 2);
        if (k == 2) steps[2].target = ui.last_id();
      }
    }
  }
  if (tour >= 0) ui.tour("audio-tour", steps, $cui.count(steps), tour);
}
