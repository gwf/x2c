#include "x2c.x"
#include "encoding.x"
#include "typed-array.x"

Buffer string_written(String value) {
  auto { Buffer output = Buffer.new(0); return value.write_str(output); }
  return NULL;
}
Buffer string_repr(String value) {
  auto { Buffer output = Buffer.new(0); return value.write_repr(output); }
  return NULL;
}
Buffer list_written(List value) {
  auto { Buffer output = Buffer.new(0); return value.write_str(output); }
  return NULL;
}
Buffer list_repr(List value) {
  auto { Buffer output = Buffer.new(0); return value.write_repr(output); }
  return NULL;
}
Buffer var_written(Var value) {
  auto { Buffer output = Buffer.new(0); return value.write_str(output); }
  return NULL;
}
Buffer var_repr(Var value) {
  auto { Buffer output = Buffer.new(0); return value.write_repr(output); }
  return NULL;
}
Buffer symbol_written(Symbol value) {
  auto { Buffer output = Buffer.new(0); return value.write_str(output); }
  return NULL;
}
Buffer atom_written(Atom value) {
  auto { Buffer output = Buffer.new(0); return value.write_repr(output); }
  return NULL;
}
Buffer code_point(void) {
  auto { Buffer output = Buffer.new(0); return output.write_code_point(65); }
  return NULL;
}
Block explicit_view(void) {
  auto { ArrayInt values = []; return values.block(); }
  return NULL;
}
Array block_view(void) {
  auto { Block values = Block.new(sizeof(Var)); return values.array(); }
  return NULL;
}
