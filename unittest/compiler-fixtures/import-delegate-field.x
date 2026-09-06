import "delegatebox" as d;

int imported_delegate(d.Box value) {
  return value.read();
}
