#include "path.x"

String example_data(String name) {
  Path source = String.new(__FILE__);
  return source.dirname().join("../data", name);
}

int main(int argc, char **argv) {
  Path directory = argc > 1 ? argv[1] : example_data("love-files");
  Path path = directory.join("quantities.txt");

  // Walk collection elements and Map values.
  foreach (int score in [3, 4, 5])
    printf("score: %d\n", score);
  foreach (String name in %("Ada" "Grace"))
    puts(name);
  foreach (int count in {"tea": 2})
    printf("stock: %d\n", count);

  // Split text into lines, then words.
  String text = "tea and cake\ncoffee and biscuits";
  foreach (String line in text.lines())
    foreach (String word in line.words())
      puts(word);

  // Read file lines and walk their words.
  auto File input = path.open("r");
  foreach (String line in input)
    foreach (String word in line.words())
      puts(word);
  return 0;
}
