/* Lists are immutable and share tails. Arrays and Maps are mutable; copying
   a handle shares its object. Percent literals quote names as data. */
int main(void) {
  auto {
    int n = 2;
    List quoted = %(n $n $(n + 1));
    List evaluated = $(n, n + 1), extended = %(1 @evaluated);
    Array numbers = [1, n, n + 1], shared = numbers;
    shared[0] = 9;
    String key = "answer";
    Map named = {key: n}, computed = ${key: n};
    printf("lists: %s; %s; %s\n",
           quoted.repr(), evaluated.repr(), extended.repr());
    printf("   array %s; last %s; slice %s\n",
           numbers.repr(), numbers[-1], numbers[1:].repr());
    printf("   map keys: %s / %s; member %d\n",
           named.keys().list().repr(), computed.keys().list().repr(),
           key in computed);
    printf("   shared tail %d; shared object %d\n",
           extended.cdr() === evaluated, numbers === shared);
    // Quoted Array/Map contents follow the same data-reading rule.
    Array tags = %[ready, done];
    Map settings = %{mode: fast};
    printf("   quoted: %s %s\n", tags.repr(), settings[<mode>]);
  }
  return 0;
}
