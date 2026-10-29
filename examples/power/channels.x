#include <assert.h>

int main(void) {
  // A bounded channel carries values between native threads.
  Channel lines = auto Channel.new(<string>, 4);
  Map counts = {};

  // Thread.run starts every worker and joins them all before returning.
  Thread.run([
    %!(void) => {
      foreach (String line in %("tea and cake" "cake and more cake"))
        lines.send(line);
      lines.close();
    },
    %!(void) => {
      foreach (String line in lines)
        foreach (String word in line.words()) counts[word] += 1;
    }
  ]);

  assert(counts["cake"] == 3 && counts["and"] == 2);
  printf("cake: %s, tea: %s\n", counts["cake"], counts["tea"]);
  return 0;
}
