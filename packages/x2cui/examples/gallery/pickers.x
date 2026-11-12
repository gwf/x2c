#pragma once

/*  pickers.x -- the gallery's Pickers page */

#include "state.x"

static List days, years;

static void prepare(void) {
  Array numbers = [];
  for (int k = 0; k < 31; k++) numbers.push(%"$(k + 1)");
  days = numbers.list_free();
  numbers = [];
  for (int k = 0; k < 12; k++) numbers.push(%"$(2020 + k)");
  years = numbers.list_free();
}

void page_pickers(Ui ui, Gallery g) {
  static bool ready = false;
  if (!ready) {
    prepare();
    ready = true;
  }
  static bool langs[8] = { true, false, true, false, false, true, false,
                           false };
  static cui_date_range range = { { 2026, 11, 3 }, { 2026, 11, 14 } };
  static cui_date_range stay = { { 2026, 12, 18 }, { 2026, 12, 27 } };
  static int hour = 9, minute = 30, h2 = 18, m2 = 45;
  static int day = 13, month = 10, year = 6;
  static int dh = 7, dm = 25;
  static float height = 172, temp = 21.5f;
  static float lo = 40, hi = 160;
  static const float bins[] = { 2, 4, 7, 12, 18, 26, 31, 29, 34, 40, 37, 30,
                                24, 22, 18, 15, 11, 9, 7, 5, 4, 3, 2, 1 };

  section(ui, "Multi-select",
          "Chips for the chosen items, checkboxes in the list.");
  List items = %("C" "C++" "Rust" "Zig" "Go" "Swift" "Kotlin" "Odin");
  ui.row (gap: 12, align: start)
  ui.box (width: 320)
    ui.multi_select("langs", items, langs, label: "Languages",
                                           searchable: true);

  section(ui, "Date range",
          "Presets on the left, two months to pick a start and an end.");
  ui.row (gap: 12, wrap: true) {
    ui.date_range_picker("range", range, width: 300);
    ui.date_range_picker("stay", stay, width: 300,
                                       no_presets: true);
  }
  // As wide as its months.
  ui.row () ui.card (pad: 16)
    ui.range_calendar("inline-range", stay, 2);

  section(ui, "Time",
          "A field with hour and minute columns, 24 hour or 12 hour.");
  ui.row (gap: 12, wrap: true) {
    ui.time_picker("start", hour, minute);
    ui.time_picker("end", h2, m2, twelve_hour: true,
                                  minute_step: 15);
  }

  section(ui, "Wheels and dial",
          "Drag, scroll or use the arrow keys. Several wheels make a date "
          "reel.");
  ui.row (gap: 32, align: center) {
    List months = %("January" "February" "March" "April" "May" "June"
                    "July" "August" "September" "October" "November"
                    "December");
    ui.card (dir: row, gap: 0, pad: 8) {
      ui.wheel_picker("day", days, day, width: 64, loop: true,
                                        join_right: true);
      ui.wheel_picker("month", months, month,
        width: 128, loop: true, join_left: true,
        join_right: true);
      ui.wheel_picker("year", years, year, width: 80,
                                           join_left: true);
    }
    ui.time_dial("dial", dh, dm, 232);
  }

  section(ui, "Ruler and histogram",
          "A tape that slides under a fixed marker, and a range over its "
          "data.");
  ui.row (gap: 24, align: start) {
    ui.column (width: fill, gap: 20) {
      ui.ruler_slider("Height", height, 120, 220, unit: "cm");
      ui.ruler_slider("Temperature", temp, 10, 30,
        step: 0.5f, major_every: 4, spacing: 14, format: "%.1f",
        unit: "\xc2\xb0" "C");
    }
    ui.card (width: fill, gap: 6) {
      // The page ignores the result, so the method stands in for the macro.
      ui.histogram_slider("Price", bins, lo, hi, 0, 240,
                          format: "$%.0f");
      ui.muted("1,204 listings in range");
    }
  }
}
