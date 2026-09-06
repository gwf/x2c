int main(void) {
  List values = %(-0x1e .5 1.e2 0x1.p1 0x.2p1 0b101 0o7);
  return values.len();
}
