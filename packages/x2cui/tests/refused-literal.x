/*  refused-literal.x -- Array literals a form refuses.

    `cui_reactions` takes `cui_reaction *`, which CUI edits, so the form
    refuses the literal: a literal never keeps state between frames. A
    variable in an element is refused too, since the static array would
    keep its first value, and so is a C array of CUI's records, which
    belongs in a collection. `make refused-literal` checks the three
    refusals.
*/

import "x2cui" with Ui;

void reactions(Ui ui) {
  ui.reactions("reactions", [{icon: heart, count: 4}]);
}

void funnel(Ui ui, float visits) {
  ui.funnel("funnel", [{label: "Visited", value: visits}]);
}

void reactions_in_c(Ui ui) {
  static cui_reaction kept[] = { { "heart", 4, false } };
  ui.reactions("kept", kept);
}
