#pragma once

/*  voice.x -- simulated voice levels and interactive playback controls */

#include "state.x"
#include <math.h>

static float levels[120], clip_position = 0.3f;
static uint8_t owners[120];
static cui_voice_note note;
static bool initialized, muted;
static int state;
static double last;

void page_voice(Ui ui, Gallery g) {
  if (!initialized) {
    for (int i = 0; i < 120; i++) {
      levels[i] = 0.15f + 0.75f * fabsf(sinf(i * 0.37f) * cosf(i * 0.13f));
      owners[i] = i < 60 ? CUI_VOICE_YOU : CUI_VOICE_REPLY;
    }
    note = (cui_voice_note){levels, 120, 0, 12, 1, false};
    initialized = true;
  }
  double now = ui.time();
  if (note.playing) {
    note.position += last ? (now - last) * note.speed : 0;
    if (note.position >= note.duration) { note.position = 0; note.playing = false; }
    ui.request_wakeup(1.0f / 30);
  }
  last = now;
  section(ui, "Voice note", "Play, seek, and change speed. This demo animates levels without playing audio.");
  ui.voice_note("message", note, width: fill);
  section(ui, "Voice session", "Choose a state, mute the microphone, or end the simulated session.");
  ui.segmented("voice-state", %("Listening" "Thinking" "Speaking"), state);
  cui_voice_state current = muted ? CUI_VOICE_MUTED : state == 1 ? CUI_VOICE_THINKING :
    state == 2 ? CUI_VOICE_SPEAKING : CUI_VOICE_LISTENING;
  float session_levels[120];
  for (int i = 0; i < 120; i++)
    session_levels[i] = state == 1 ? CUI_VOICE_SILENT : muted ? 0 : levels[i];
  int event = ui.voice_session("session", current, session_levels,
    transcript: "A preview of a spoken conversation.",
    muted: &muted, you: "You", assistant: "Guide");
  if (event & CUI_VOICE_SESSION_END) {
    state = 0; muted = false; ui.toast("Session ended", description: "The demo is ready to start again.");
  }
  section(ui, "Waveform", "Click or drag to seek. Focus the strip and use arrow keys.");
  ui.voice_wave("clip", levels, progress: &clip_position, owners: owners);
  ui.muted(%"Position: $( (int) (clip_position * 100))%");
}
