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

int main(int argc, char **argv) {
// words.txt: "Tea coffee tea" then "Milk coffee tea".
String path = argc > 1 ? argv[1]
                      : "examples/data/power-counting/words.txt";
Map counts = word_count(path);

// Rank by count, breaking ties by word in the same descending order.
Array ranked = counts.enumerate().array().sort_with(
  %!(List left, List right) => {
    int order = right[1].compare(left[1]);
    return order ? order : right[0].compare(left[0]);
  });
foreach (Var (word, n), ranked)
  puts(%"$n $word");
return 0;
}
