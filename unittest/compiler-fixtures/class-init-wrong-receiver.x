class WrongValue { Array items; };
void WrongValue.init(WrongValue value) { value.items = %[]; }
int WrongValue.equal(WrongValue a, WrongValue b) {
  return (void *) a.items == (void *) b.items;
}
unsigned WrongValue.hash(WrongValue value) {
  return x2c_hash_word((unsigned long) value.items);
}
int main(void) { return 0; }
