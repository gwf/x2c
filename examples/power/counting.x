#include "path.x"
int main(int argc, char **argv) {
// words.txt: "Tea coffee tea" then "Milk coffee tea".
String path = argc > 1 ? argv[1]
                      : example_data("power-counting/words.txt");
Map counts = word_count(path);

// Rank by count, breaking ties by word in the same descending order.
Array ranked = counts.enumerate().array().sort_with(
  %!(List left, List right) => {
    int order = right[1].compare(left[1]);
    return order ? order : right[0].compare(left[0]);
  });
foreach ((String word, int n) in ranked)
  puts(%"$n $word");
return 0;
}

// Files supply lines; each line supplies words.
Map word_count(String path) {
  Map counts = {};
  auto File input = path.open("r");
  foreach (String line in input)
    foreach (String word in line.lower().words())
      counts[word] += 1;
  return counts;
}

// The checked-in data sits beside the examples wherever they live.
String example_data(String name) {
  Path source = String.new(__FILE__);
  return source.dirname().join("../data").join(name);
}
