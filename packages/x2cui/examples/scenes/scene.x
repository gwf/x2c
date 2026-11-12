#pragma once

/*  scene.x -- what a scene file provides

    A scene file defines its scenes as static functions, lists them in one
    static table, and exports one function that returns its Family.
*/

import "x2cui" with ApiParams, CalEvents, Candles, CheckSteps, CurveKeys,
  DocTabs, FeatureFlags, FlameSpans, GanttTasks, GradientStops, KvPairs,
  Offscreen, PromptSuggestions, QueryNodes, ScatterSeries, Series,
  SpeedActions, TextField, TimelineTracks, TourSteps, TraceSpans, TraceTracks,
  TreeNodes, Ui, Vec2s;

/* One component shown in use. `draw` describes the scene's content;
   scenes.x supplies the page around it. */
typedef struct Scene {
  String name;
  void (*draw)(Ui ui);
} Scene;

// The scenes of one file, under a title.
typedef struct Family {
  String title;
  Scene *scenes;
  int count;
} Family;
