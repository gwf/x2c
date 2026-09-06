---
section: power
tab: counting
---

```x2c
// Files supply lines; each line supplies words.
Map word_count(String path) {
  Map counts = %{};
  File input = path.open("r");
  defer input.close();
  foreach (String line, input)
    foreach (String word, line.lower().words())
      counts[word] += 1;
  return counts;
}

~int main(void) {
// words.txt: "Tea coffee tea" then "Milk coffee tea".
Map counts = word_count("words.txt");

// Put counts first, then sort the pairs from most to least.
Array ranked = counts.enumerate()
  .map(%!(List pair) => pair.reverse())
  .array().sort().reverse();
foreach (Var (n, word), ranked)
  puts(%"$n $word");
~return 0;
~}
```

`File` iteration, `String.lower`, and `Map` updates count words without
manual buffers or table management. Reversing each pair to `(count word)`
lets `Array.sort` and `Array.reverse` rank the results: 3 tea, 2 coffee,
1 milk. Ties sort by word in reverse order.
