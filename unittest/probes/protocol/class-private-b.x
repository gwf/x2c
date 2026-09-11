Var private_label(void);

#pragma private
class Hidden { String label; };

Var private_label(void) { return Hidden.new(%"two"); }
