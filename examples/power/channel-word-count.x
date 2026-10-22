/*  channel-word-count.x -- bounded word counting with one supervised batch */

#include "path.x"
#include "channel.x"
#include <ctype.h>
#include <stdio.h>

static Map word_count(Path filename) {
  String text = filename.open("r").string_close()
    .filter(%!(unsigned char c) => !ispunct(c)).lower();
  Map counts = {};
  foreach (String word in text.words()) counts[word] += 1;
  return counts;
}

static Map directory_count(Path root) {
  Map counts = {};
  Channel files = $auto(Channel.new(4));
  Channel results = $auto(Channel.new(4));
  Array jobs = $auto([]);
  int remaining_workers = 4;

  jobs.push(%!(void) => {
    foreach (Path filename in root.walk().filter(Path.is_file))
      files.send(filename);
    files.close();
    return <producer>;
  });

  for (int i = 0; i < remaining_workers; ++i)
    jobs.push(%!(void) => {
      foreach (Path filename in files) {
        Map part = word_count(filename);
        part.scope().transfer(results.scope());
        results.send(part);
      }
      return <worker>;
    });

  jobs.push(%!(void) => {
    foreach (Map part in results) {
      counts.merge_with(part, %!(int a, int b) => a + b);
      part.free();
    }
    return <consumer>;
  });

  Thread.run(jobs, %!(Var completed) using &remaining_workers => {
    if (completed == <worker> && --remaining_workers == 0)
      results.close();
  });
  return counts;
}

int main(int argc, char **argv) {
  Path root = argc > 1 ? argv[1]
    : "examples/data/power-channel-word-count/words";
  Map counts = $auto(directory_count(root));
  Array words = $auto(counts.keys().array().sort());
  foreach (String word in words) puts(%"$word ${counts[word]}");
  return 0;
}
