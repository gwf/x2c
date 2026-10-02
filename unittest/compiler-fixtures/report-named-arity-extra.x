#include "x2c.x"
$(import "../../src/parse-report-macros.xmacro")

void misuse(void) { $report.parse_alias_name(NULL, 1); }
