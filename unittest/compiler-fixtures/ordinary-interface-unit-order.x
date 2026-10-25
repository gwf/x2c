#include "x2c.x"
#include "ordinary-interface-meta/unit-provider.x"
$ordinary.unit.declare(int);
int first(void) => produced;

$ordinary.unit.identity(captured_parameter, int value);
enum { retained_enum_value = 17 };
$ordinary.unit.check(retained_enum_value);
