/*  refused-literal.x -- Array literals a form refuses.

    `cui_reactions` takes `cui_reaction *`, which CUI edits, so the form
    refuses the literal: a literal never keeps state between frames. A
    variable in an element is refused too, since the static array would
    keep its first value. `make refused-literal` checks both refusals.
*/

import "x2cui" with Ui;

void reactions(Ui ui) {
  ui.reactions("reactions", [{icon: heart, count: 4}]);
}

void funnel(Ui ui, float visits) {
  ui.funnel("funnel", [{label: "Visited", value: visits}]);
}
