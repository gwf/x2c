Var private_label(void);

static class Hidden { String label; };

Var private_label(void) { return Hidden.new(%"two"); }
