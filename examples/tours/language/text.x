#include "system-macros.x"

/* Symbols encode short names. Atoms also represent longer exact names.
   Strings are immutable, canonical text; + and slices produce values. */
int main(void) {
  Symbol phase = <ready>;
  Atom name = %(a-name-too-long-for-a-symbol).car();
  SymbolSet phases = %<ready running done>;
  String greeting = "hello" + " world", expected = "hello world";
  puts($dedent(%"
    Greeting: $greeting
    Slice: $(greeting[0:5])
    Phase: $phase"));
  puts($dedent(%"
    Long atom: $name
    Phase index: $(phases.index(phase))"));
  printf("Equal strings: %d\nIdentical strings: %d\n",
         greeting == expected, greeting === expected);
  return 0;
}
