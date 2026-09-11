class Opaque { int values[2]; };
void Opaque.init(Opaque *value) {
  value->values[0] = 1;
  value->values[1] = 2;
}
int main(void) { return 0; }
