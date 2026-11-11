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
  $cui.row(ui, { .gap = 28, .align = CUI_ALIGN_START, .width = CUI_FILL }) {
    $cui.scroll(ui, { .id = "reader", .height = CUI_PX(560),
                      .width = CUI_FILL, .gap = 14, .fade_edges = true }) {
      for (int k = 0; k < $cui.count(toc); k++) {
        ui.toc_anchor(toc[k].anchor);
        ui.heading(toc[k].title, toc[k].level ? 4 : 3);
        for (int p = 0; p < 3; p++) {
          ui.push_id_int(k * 10 + p);
          ui.text(para, { .color = CUI_COLOR_TEXT_SECONDARY });
          ui.pop_id();
        }
      }
      ui.gap(200);
    }
    $cui.column(ui, { .width = CUI_PX(200), .gap = 10 }) {
      ui.text("On this page", { .size = 12, .font = CUI_FONT_MEDIUM,
                                .color = CUI_COLOR_TEXT_MUTED });
      ui.toc("reader", toc, $cui.count(toc));
    }
  }
}
