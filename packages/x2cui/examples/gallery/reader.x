#pragma once

/*  reader.x -- the gallery's Reader page */

#include "state.x"

void page_reader(Ui ui, Gallery g) {
  static TocItems toc = TocItems.of([
    {title: "Introduction", anchor: "intro", level: 0},
    {title: "Install", anchor: "install", level: 0},
    {title: "With CMake", anchor: "cmake", level: 1},
    {title: "Without CMake", anchor: "nocmake", level: 1},
    {title: "First window", anchor: "window", level: 0},
    {title: "Immediate mode", anchor: "imm", level: 0},
    {title: "Layout", anchor: "layout", level: 0},
    {title: "Next steps", anchor: "next", level: 0}]);
  String para = "Components are functions. They draw themselves, handle "
                "input and return what happened. Your variables are the "
                "source of truth, so there is nothing to keep in sync, and "
                "conditional interface is just an if statement. ";
  ui.row (gap: 28, align: start, width: fill) {
    ui.scroll (id: "reader", height: 560,
               width: fill, gap: 14, fade_edges: true) {
      for (int k = 0; k < toc.len(); k++) {
        ui.toc_anchor(toc[k].anchor);
        ui.heading(toc[k].title, toc[k].level ? 4 : 3);
        for (int p = 0; p < 3; p++) {
          ui.push_id_int(k * 10 + p);
          ui.text(para, color: text_secondary);
          ui.pop_id();
        }
      }
      ui.gap(200);
    }
    ui.column (width: 200, gap: 10) {
      ui.text("On this page", size: 12, font: medium,
                              color: text_muted);
      ui.toc("reader", toc);
    }
  }
}
