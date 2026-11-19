/* Copying a reference does not keep its owner alive. auto regions free
   allocations; initializer auto cleans an acquired value. Neither is
   garbage collection. A closure also copies handles, not objects. */
int main(void) {
  auto {
    Scope saved = auto Scope.new();
    Array kept;
    auto {
      Array temporary = [1, 2];
      temporary.move_to(&saved);
      kept = temporary;
    }
    int count = 3;
    Func snapshot = %!() => count;
    Func shared = %!(int n) using &count => count += n;
    count = 10;
    Var before = snapshot(), after = shared(2);
    printf("lifetime: retained %s; snapshot %s; shared %s\n",
           kept.repr(), before, after);
    // alias substitutes an expression each time; with saves and restores storage.
    alias kept[0] as first;
    first += 4;
    with (count = 99) { printf("   temporary %d; alias %s\n", count, first); }
    try {
      defer puts("   cleanup before catch");
      raise %(bad-arg (operation "tour"));
    }
    catch %(bad-arg *): printf("   caught; restored %d\n", count);
  }
  return 0;
}
