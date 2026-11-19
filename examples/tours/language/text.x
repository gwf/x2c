/* Symbols encode short names. Atoms also represent longer exact names.
   Strings are immutable, canonical text; + and slices produce values. */
int main(void) {
  Symbol phase = <ready>;
  Atom name = %(a-name-too-long-for-a-symbol).car();
  SymbolSet phases = %<ready running done>;
  String greeting = "hello" + " world", expected = "hello world";
  puts(%"Greeting: $greeting\nSlice: $(greeting[0:5])\nPhase: $phase");
  printf("Long atom: %s\nPhase index: %d\n", name, phases.index(phase));
  printf("Equal strings: %d\nIdentical strings: %d\n",
         greeting == expected, greeting === expected);
  return 0;
}
