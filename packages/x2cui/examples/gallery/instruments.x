#pragma once

/*  instruments.x -- the gallery's Instruments page */

#include "state.x"

import "x2cui" with DotSeries;

static ArrayFloat requests = [18, 24, 38, 61, 84, 72, 64, 81, 94, 68, 42, 26];
static DotSeries traffic;
static ArrayDbl starts = [8, 10.75, 14.25];
static int selected = 1;

void page_instruments(Ui ui, Gallery g) {
  static bool ready = false;
  if (!ready) {
    traffic = DotSeries.of([]);
    traffic.push(cui_dot_series.of(values: requests, name: "Requests", accent: true));
    ready = true;
  }
  section(ui, "Readouts", "A label, a value with its unit, and a line of context.");
  ui.row (gap: 40, wrap: true, align: end) {
    ui.readout("PEAK REQUESTS", "94", unit: "REQ/S", size: lg,
               accent: true, detail: "14:00 TODAY");
    ui.readout("MEDIAN LATENCY", "182", unit: "MS", detail: "LAST HOUR");
    ui.readout("JOBS", %"$(starts.len())", size: sm, detail: "SCHEDULED TODAY");
  }
  section(ui, "Dot-matrix chart", "Hover or use arrow keys to inspect the samples.");
  ui.dot_chart("traffic", traffic, requests.len(), height: 220,
    x_min: 6, x_max: 17, x_units: hours, min: 0, max: 120, unit: "REQ/S",
    annotations: [
      {kind: y, y: 100, label: "CAPACITY 100", detail: "REQ/S"},
      {kind: point, x: 14, y: 94, label: "PEAK", accent: true}]);
  section(ui, "Event track", "Drag a job, click to add one, or double-click to remove it.");
  ui.event_track("jobs", starts, 6, 30,
    step: 0.25, units: hours, label_step: 6, selected: &selected);
  section(ui, "Dot-matrix display", "Text in a 5 by 7 dot font.");
  ui.dot_display("ALL SYSTEMS READY", pitch: 3, accent: true);
}
