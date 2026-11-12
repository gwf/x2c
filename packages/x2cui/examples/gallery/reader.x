#pragma once

/*  reader.x -- the gallery's Reader page */

#include "state.x"

void page_reader(Ui ui, Gallery g) {
  static const cui_toc_item toc[] = {
    { "Introduction", "intro", 0 }, { "Install", "install", 0 },
    { "With CMake", "cmake", 1 }, { "Without CMake", "nocmake", 1 },
    { "First window", "window", 0 }, { "Immediate mode", "imm", 0 },
    { "Layout", "layout", 0 }, { "Next steps", "next", 0 },
  };
  String para = "Components are functions. They draw themselves, handle "
                "input and return what happened. Your variables are the "
                "source of truth, so there is nothing to keep in sync, and "
                "conditional interface is just an if statement. ";
  ui.row (gap: 28, align: start, width: fill) {
    ui.scroll (id: "reader", height: 560,
               width: fill, gap: 14, fade_edges: true) {
      for (int k = 0; k < (int) (sizeof toc / sizeof *toc); k++) {
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
