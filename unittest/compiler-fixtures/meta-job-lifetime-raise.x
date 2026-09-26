#include "x2c.x"
#include "meta.x"
#include "process.x"

$(import "meta-job-lifetime-raise.xmacro")

void first(void) { $starts(); }
void second(void) { $after(); }
