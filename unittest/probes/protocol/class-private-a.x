Var private_number(void);

#pragma private
class Hidden { int number; };

Var private_number(void) { return Hidden.new(7); }
