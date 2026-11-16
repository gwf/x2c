#pragma once

/*  instruments.x -- scenes for dot charts, event tracks, and readouts */

#include "scene.x"

import "x2cui" with DotSeries;

static ArrayFloat loads = [12, 24, 38, 61, 84, 72, 64, 81, 94, 68, 42, 26];
static DotSeries series;
static ArrayDbl starts = [8, 10.75, 14.25];

static void scene_dot_chart(Ui ui) {
  ui.dot_chart("load", series, loads.len(), height: 280,
    x_min: 6, x_max: 17, x_units: hours, min: 0, max: 120, unit: "REQ/S",
    annotations: [
      {kind: y, y: 100, label: "CAPACITY 100"},
      {kind: x, x: 14, label: "PEAK HOUR"}]);
}

static void scene_event_track(Ui ui) {
  ui.heading("Scheduled jobs", 2);
  ui.event_track("jobs", starts, 6, 30, step: 0.25, units: hours, label_step: 6);
  ui.muted("Drag to move. Click to add. Double-click to remove.");
}

static void scene_readout(Ui ui) {
  ui.row (gap: 36, align: end) {
    ui.readout("MEDIAN LATENCY", "182", unit: "MS", size: lg,
               accent: true, detail: "LAST HOUR");
    ui.readout("REQUESTS", "94", unit: "REQ/S", detail: "PEAK TODAY");
  }
}

static void scene_dot_display(Ui ui) {
  ui.dot_display("12:34:56", pitch: 6, accent: true);
  ui.dot_display("ALL SYSTEMS READY", pitch: 3);
}

static Scene instrument_scenes[] = {
  { "dot_chart", scene_dot_chart },
  { "event_track", scene_event_track },
  { "readout", scene_readout },
  { "dot_display", scene_dot_display },
};

Family instruments_family(void) {
  series = DotSeries.of([]);
  series.push(cui_dot_series.of(values: loads, name: "Requests", accent: true));
  return (Family){ "Instruments", instrument_scenes,
                   sizeof instrument_scenes / sizeof *instrument_scenes };
}
