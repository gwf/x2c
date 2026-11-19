/* A pattern states the structure you need and names its parts. Typed
   captures test tags rather than converting; a double does not match ?(int
   n). Templates then build a result without manual List plumbing. */
int main(void) {
  List command = %(move (3 4) fast quiet);
  match (command) {
    case %(move (?(int x) ?(int y)) *flags):
      puts(%"Matched command: $(%(at $x $y @flags).repr())");
  }
  List real = %(move (3.0 4.0));
  printf("Doubles match the int pattern: %d\n",
         real ~= %(move (?(int x) ?(int y))));
  return 0;
}
