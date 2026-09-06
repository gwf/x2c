#include "x2c.x"

int main(void) {
  x2c_initialize();
  x2c_register_type(%"fixture");
  unsigned long storage[2] = {0};
  Var.new(<fixture>, ((unsigned char *) storage) + 1);
  return 0;
}
