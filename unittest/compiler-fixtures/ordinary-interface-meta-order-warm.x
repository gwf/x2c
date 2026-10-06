#include "x2c.x"
$(def ordinary_meta_value (lambda (value) 99))
#include "ordinary-interface-meta/provider.x"

int included(void) => $(ordinary_meta_value 3);
$(def ordinary_meta_value (lambda (value) 99))
int later(void) => $(ordinary_meta_value 3);
