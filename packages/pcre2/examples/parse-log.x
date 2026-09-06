/*  parse-log.x -- Summarize one syslog batch by program name. */

import "pcre2" with Regexp, RegexpMatch;

int main(void) {
  Regexp entry = Regexp.compile(
    %"^(?<time>\\d\\d:\\d\\d:\\d\\d) (?<program>\\w+)\\[\\d+\\]: (?<text>.*)$$",
    0
  );
  defer entry.free();
  Regexp fields = Regexp.compile(%"\\s*\\|\\s*", 0);
  defer fields.free();

  Map counts = %{};
  foreach(String line, %(
    "09:14:02 sshd[441]: accepted key | user=ada | port=22"
    "09:14:07 cron[88]: ran backup | status=ok"
    "09:15:31 sshd[512]: refused password | user=root | port=22"
    "-- rotated --"
  )) {
    RegexpMatch found = entry.match(line);
    if (!found) continue;

    Var seen = 0;
    counts.try_get(found[<program>], &seen);
    counts[found[<program>]] = seen + 1;
    printf("%s %s\n", found[<time>], found[<program>]);
    foreach(String field, fields.split(found[<text>]))
      printf("    %s\n", field);
  }

  foreach(Var (program, count), counts)
    printf("%s", %"$program: $count lines\n");
  return 0;
}
