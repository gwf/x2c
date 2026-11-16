/*  test-instruments.x -- CUI 1.4 instruments through the x2c surface. */

import "x2cui" with ChartAnnotations, DotSeries, Offscreen, Ui;

#include "test-support.x"
#include "../../../unittest/test-macros.x"

static cui_event_track_result track_frame(
  Offscreen screen, ArrayDbl times, int &selected) {
  screen.begin();
  cui_event_track_result result = screen.ui().event_track(
    "times", times, 6, 30, step: 0.25, units: hours, selected: &selected);
  screen.end();
  return result;
}

static cui_event_track_result track_key(
  Offscreen screen, ArrayDbl times, int &selected, cui_key key) {
  screen.ui().input_key(key, true, 0);
  cui_event_track_result result = track_frame(screen, times, selected);
  screen.ui().input_key(key, false, 0);
  track_frame(screen, times, selected);
  return result;
}

static void event_track_edits_the_owned_times(void) {
  Offscreen screen = auto Offscreen.open(480, 160);
  ArrayDbl times = [8, 11];
  int selected = 0;
  track_frame(screen, times, selected);
  track_frame(screen, times, selected);
  track_key(screen, times, selected, CUI_KEY_TAB);
  cui_event_track_result moved = track_key(screen, times, selected, CUI_KEY_RIGHT);
  EXPECT_TRUE(moved.changed);
  EXPECT_TRUE(times[0] == 8.25);
  cui_event_track_result added = track_key(screen, times, selected, CUI_KEY_ENTER);
  EXPECT_TRUE(added.changed);
  EXPECT_INT_EQ(added.added, 1);
  EXPECT_INT_EQ(times.len(), 3);
  EXPECT_TRUE(times[1] == 8.5);
  EXPECT_TRUE(times[2] == 11);
  cui_event_track_result removed = track_key(screen, times, selected, CUI_KEY_DELETE);
  EXPECT_TRUE(removed.changed);
  EXPECT_INT_EQ(removed.removed, 1);
  EXPECT_INT_EQ(times.len(), 2);
  EXPECT_TRUE(times[1] == 11);
}

static void instruments_draw_with_annotations(void) {
  Offscreen screen = auto Offscreen.open(480, 480);
  ArrayFloat samples = [10, 20, 40, 30];
  DotSeries series = DotSeries.of([]);
  series.push(cui_dot_series.of(values: samples, name: "Load", accent: true));
  ChartAnnotations marks = ChartAnnotations.of([
    {kind: y, y: 35, label: "Limit"},
    {kind: point, x: 2, y: 40, label: "Peak", accent: true}]);
  EXPECT_INT_EQ(marks.len(), 2);
  EXPECT_INT_EQ(marks[0].kind, CUI_ANNOTATION_Y);
  for (int frame = 0; frame < 3; frame++) {
    screen.begin();
    Ui ui = screen.ui();
    ui.column (pad: 12, gap: 12, width: fill) {
      ui.readout("PEAK", "40", unit: "REQ/S", detail: "Last hour", size: lg);
      ui.dot_chart("load", series, samples.len(), height: 160, annotations: marks);
      ui.dot_display("READY", accent: true);
    }
    screen.end();
  }
  EXPECT_TRUE(screen.commands() > 0);
  EXPECT_TRUE(samples[2] == 40);
}

int main(void) {
  TestHarness_begin();
  $test.run(event_track_edits_the_owned_times);
  $test.run(instruments_draw_with_annotations);
  return TestHarness_finish();
}
