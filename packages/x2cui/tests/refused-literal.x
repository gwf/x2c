/*  refused-literal.x -- an Array literal where CUI may write through it.

    `cui_reactions` takes `cui_reaction *`, which CUI edits, so the form
    refuses the literal: a literal never keeps state between frames.
    `make refused-literal` checks that the translation fails.
*/

import "x2cui" with Ui;

void reactions(Ui ui) {
  ui.reactions("reactions", [{icon: heart, count: 4}]);
}
