#pragma once

/*  loading_voice.x -- scenes for loading treatments and voice controls */

#include "scene.x"

static ArrayFloat levels = [0.12, 0.3, 0.55, 0.8, 0.6, 0.25, 0.1,
  0.4, 0.75, 0.9, 0.65, 0.35, 0.15, 0.45, 0.7, 0.5];

static void scene_spinner(Ui ui) {
  ui.row (gap: 32, align: center) {
    ui.spinner(32);
    ui.spinner(48, style: radar);
    ui.spinner(48, style: plasma);
    ui.spinner(32, style: upload);
  }
}

static void scene_status_spinner(Ui ui) {
  ui.row (gap: 32, align: center) {
    ui.status_spinner("saving", busy);
    ui.status_spinner("saved", success);
    ui.status_spinner("failed", error);
  }
}

static void scene_skeleton_group(Ui ui) {
  ui.skeleton_group (dither: true, gap: 16) {
    ui.row (gap: 12) {
      ui.skeleton(48, 48);
      ui.column (width: fill, gap: 10) {
        ui.skeleton(240, 12);
        ui.skeleton(160, 8);
      }
    }
    ui.skeleton(fill, 8);
  }
}

static void scene_pattern_meter(Ui ui) {
  ui.pattern_meter("storage", [
    {name: "Images", value: 42},
    {name: "Audio", value: 24},
    {name: "Documents", value: 12}],
    total: 100, label: "Storage", unit: "GB");
}

static void scene_voice_wave(Ui ui) {
  static float progress = 0.4;
  ui.voice_wave("clip", levels, progress: &progress);
}

static void scene_voice_note(Ui ui) {
  static cui_voice_note note;
  note.levels = (float *) levels.bytes;
  note.count = levels.len();
  note.position = 4;
  note.duration = 12;
  ui.voice_note("message", note, mine: true);
}

static void scene_voice_session(Ui ui) {
  static bool muted;
  ui.voice_session("call", listening, levels,
    transcript: "Can you summarize the meeting?", muted: &muted);
}

static void scene_veil(Ui ui) {
  static bool revealed;
  ui.veil ("private", revealed, label: "Private preview",
           hint: "Click to reveal", toggle: true, radius: 10) {
    ui.card (width: fill, height: 180, pad: 24) {
      ui.heading("Early design", 2);
      ui.text("The contents stay behind the veil until revealed.");
    }
  }
}

static Scene loading_voice_scenes[] = {
  { "spinner", scene_spinner },
  { "status_spinner", scene_status_spinner },
  { "skeleton_group", scene_skeleton_group },
  { "pattern_meter", scene_pattern_meter },
  { "voice_wave", scene_voice_wave },
  { "voice_note", scene_voice_note },
  { "voice_session", scene_voice_session },
  { "veil", scene_veil },
};

Family loading_voice_family(void) {
  return (Family){ "Loading and voice", loading_voice_scenes,
                   sizeof loading_voice_scenes / sizeof *loading_voice_scenes };
}
