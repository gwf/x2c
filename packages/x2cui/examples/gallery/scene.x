#pragma once

/*  scene.x -- what a gallery scene file provides

    A scene file defines its scenes as static functions, lists them in one
    static table, and exports one function that returns its Family.
*/

import "x2cui" with App, Offscreen, TextField, Ui;

/* One component shown in use. `draw` describes the scene's content; the
   gallery supplies the page around it. */
typedef struct Scene {
  String name;
  void (*draw)(Ui ui);
} Scene;

// The scenes of one file, under the title the browser shows.
typedef struct Family {
  String title;
  Scene *scenes;
  int count;
} Family;
