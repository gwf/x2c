---
slug: threads
section: power
tab: threads
title: Threads that start together and finish together.
---

```x2c
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
```

Native threads, bounded channels, and one call that starts the workers and
joins them all. `Thread.run` takes an Array of lambdas and returns when
every one has finished. A Channel typed `<string>` carries Strings between
them, and `foreach` drains it until the sender closes.

A `Mutex` is there when you need one, and `$lock(m) { ... }` holds it for
one block, including while an error unwinds.
