/* Symbols encode short names. Atoms also represent longer exact names.
   Strings are immutable, canonical text; + and slices produce values. */
int main(void) {
  auto {
    Symbol phase = <ready>;
    Atom name = %(a-name-too-long-for-a-symbol).car();
    SymbolSet phases = %<ready running done>;
    String greeting = "hello" + " world", expected = "hello world";
    puts(%"text: $greeting; $(greeting[0:5]); $phase");
    printf("   %s; phase index %d\n", name, phases.index(phase));
    printf("   equal %d, identical %d\n",
           greeting == expected, greeting === expected);
  }
  return 0;
}
