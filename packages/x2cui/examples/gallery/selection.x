#pragma once

/*  selection.x -- the gallery's Selection page */

#include "state.x"

void page_selection(Ui ui, Gallery g) {
  ui.box (dir: CUI_GRID, columns: 2, min_column_width: 260,
          gap: 16) {
    ui.column (gap: 12) {
      section(ui, "Checkbox", NULL);
      ui.card (gap: 14) {
        ui.checkbox("Email notifications", g.newsletter,
          description: "Product news, at most once a month.");
        ui.checkbox("Marketing", g.marketing,
          description: "Offers from our partners.");
        ui.checkbox("Disabled option", g.terms, disabled: true);
      }
    }
    ui.column (gap: 12) {
      section(ui, "Switch", NULL);
      ui.card (gap: 14) {
        ui.switch("Wi-Fi", g.wifi);
        ui.switch("Bluetooth", g.bluetooth);
        ui.switch("Airplane mode", g.airplane,
          description: "Turns off all radios.");
      }
    }
  }
  section(ui, "Radio group", NULL);
  ui.card (gap: 12) {
    ui.radio("Every change", g.plan, 0,
      description: "Save as you type. Uses the most disk.");
    ui.radio("Every 5 minutes", g.plan, 1,
      description: "A good balance for most projects.");
    ui.radio("Only when I save", g.plan, 2,
      description: "Nothing is written until you press Ctrl S.");
  }
  section(ui, "Radio cards",
          "For choices that need a sentence of explanation.");
  {
    static const cui_choice places[] = {
      { "This computer",
        "Saved next to the project. Nothing leaves the machine.",
        CUI_ICON_MONITOR, NULL },
      { "Team server", "Synced to your company server every few minutes.",
        CUI_ICON_SERVER, "Default" },
      { "Both", "A local copy, uploaded to the server every night.",
        CUI_ICON_LAYERS, NULL },
    };
    // The page ignores the result, so the method stands in for the macro.
    ui.radio_cards("places", places, $cui.count(places), g.plan_card);
  }
  section(ui, "Sliders",
          "Drag past either end: the track stretches like rubber.");
  ui.card (gap: 20) {
    ui.slider("Volume", g.volume, 0, 100, show_value: true);
    ui.slider("Brightness", g.brightness, 0, 100,
      step: 10, show_value: true, format: "%.0f%%");
    ui.range_slider("Price range", g.lo, g.hi, 0, 100);
  }
  section(ui, "Chips and rating", NULL);
  ui.card (gap: 16) {
    ui.row (gap: 8, wrap: true) {
      List chips = %("Design" "Engineering" "Marketing" "Sales" "Support"
                     "Finance");
      int i = 0;
      foreach (String chip in chips) {
        ui.chip(chip, g.chips[i]);
        i++;
      }
    }
    ui.rating("rating", g.rating, 5);
  }
}
