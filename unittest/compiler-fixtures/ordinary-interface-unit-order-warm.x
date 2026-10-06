#include "x2c.x"
$(defun ordinary.unit.name (type) "before")
#include "ordinary-interface-meta/unit-provider.x"
$ordinary.unit.declare(int);
$(defun ordinary.unit.name (type) "later")
$ordinary.unit.declare(int);
int first(void) => produced;
int second(void) => later;

$ordinary.unit.identity(captured_parameter, int value);
enum { retained_enum_value = 17 };
$ordinary.unit.check(retained_enum_value);
