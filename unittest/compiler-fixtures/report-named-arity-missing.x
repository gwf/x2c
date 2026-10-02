#include "x2c.x"
$(import "../../src/parse-report-macros.xmacro")

void misuse(void) { $report.parse_package_member(NULL, NULL, "probe"); }
