/* Match arms try in order without fallthrough. Typed captures test tags,
   not convertibility. A rest capture is a List; $ inserts and @ splices. */
static List simplify(List expression) {
  match (expression) {
    case %(add ?value 0): return %(value $value);
    case %(add ?(int a) ?(int b)): return %(value $(a + b));
    default: return expression;
  }
}

int main(void) {
  List command = %(move (3 4) fast quiet);
  match (command) {
    case %(move (?(int x) ?(int y)) *flags) if (x > 0):
      printf("Matched command: %s\n", %(at $x $y @flags).repr());
    default: puts("No move matched");
  }
  List result = simplify(%(add 2 3));
  if (result ~= %(value ?(int n))) printf("Simplified value: %d\n", n);
  return 0;
}
