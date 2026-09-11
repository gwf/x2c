---
slug: pcre2
section: packages
tab: PCRE2
title: Make sense of a log file.
links:
  - label: Full source
    href: https://github.com/gwf/x2c/blob/main/packages/pcre2/examples/parse-log.x
  - label: Package guide
    href: https://github.com/gwf/x2c/blob/main/packages/pcre2/README.md
---

<!-- ignore: source excerpt; the complete example requires its optional package and setup. -->
```x2c,ignore
import "pcre2" with Regexp, RegexpMatch;

Regexp entry = Regexp.compile(
  %"^(?<time>\\d\\d:\\d\\d:\\d\\d) "
    + %"(?<program>\\w+)\\[\\d+\\]: (?<text>.*)$$",
  0
);
defer entry.free();
Regexp fields = Regexp.compile(%"\\s*\\|\\s*", 0);
defer fields.free();
Map counts = %{};

foreach(String line, lines) {
  RegexpMatch found = entry.match(line);
  if (!found) continue;
  Var seen = 0;
  counts.try_get(found[<program>], &seen);
  counts[found[<program>]] = seen + 1;
  printf("%s %s\n", found[<time>], found[<program>]);
  foreach(String field, fields.split(found[<text>]))
    printf("    %s\n", field);
}
```

Named captures pick out the time, program, and message from each log
entry. Access captures by name, then split the message on vertical bars,
consuming the surrounding whitespace. Lines that do not match, such as
the log's rotation marker, are skipped.

The first parsed entry appears below. The complete example also counts
entries in a Map and prints a summary: two from `sshd` and one from
`cron`.

First entry's output:

```text
09:14:02 sshd
    accepted key
    user=ada
    port=22
```
