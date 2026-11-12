#pragma once

/*  navigation.x -- the gallery's Navigation page */

#include "state.x"

void page_navigation(Ui ui, Gallery g) {
  section(ui, "Tabs", "The indicator slides to the active tab.");
  ui.card (gap: 16) {
    List tabs = %("Overview" "Analytics" "Reports" "Settings");
    ui.tabs("tabs", tabs, g.tab);
    ui.column (gap: 6, pad_y: 4) {
      String current = tabs[g.tab];
      ui.label(current);
      ui.secondary("Tabs switch between views of the same thing. Content "
                   "changes in place.");
    }
    ui.tabs("tabs2", %("Account" "Password" "Billing"), g.tab2,
            variant: pill, icons: [user, lock, credit_card]);
  }
  section(ui, "Breadcrumb and pagination", NULL);
  ui.card (gap: 18) {
    List crumbs = %("Home" "Projects" "CUI" "Settings");
    int c = ui.breadcrumb(crumbs);
    if (c >= 0) {
      String crumb = crumbs[c];
      ui.toast(crumb);
    }
    ui.pagination("pages", g.page_index, 12);
  }
  section(ui, "Stepper", NULL);
  ui.card (gap: 18) {
    ui.stepper(%("Account" "Workspace" "Invite team" "Done"), g.step);
    ui.row (gap: 8, wrap: true) {
      if (ui.button("Back", disabled: g.step == 0)) g.step--;
      if (ui.button(g.step >= 3 ? "Finish" : "Next",
            variant: primary,
            icon_right: arrow_right)) {
        if (g.step < 3) g.step++;
        else ui.toast("All set", tone: success);
      }
    }
  }
}
