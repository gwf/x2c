Var private_number(void);

static class Hidden { int number; };

Var private_number(void) { return Hidden.new(7); }
