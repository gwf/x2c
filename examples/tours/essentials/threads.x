#include "system-macros.x"

/* Threads share references; joining does not transfer their ownership. The
   parent owns counts. Only the consumer writes it, and main reads after
   both workers finish. Immutable text crosses the channel without copying. */
int main(void) {
  Channel lines = auto Channel.new(<string>, 2);
  Map counts = {};
  Thread.run([
    %!() => {
      defer lines.close();
      foreach (String line in %("tea and cake" "more cake")) lines.send(line);
    },
    %!() => {
      foreach (String line in lines)
        foreach (String word in line.words()) counts[word] += 1;
    }
  ]);
  puts($dedent(%"
    Cake: $(counts["cake"])
    Tea: $(counts["tea"])"));
  return 0;
}
