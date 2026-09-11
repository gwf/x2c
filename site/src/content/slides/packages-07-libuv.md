---
slug: libuv
section: packages
tab: libuv
title: Put two processes to work.
links:
  - label: Full source
    href: https://github.com/gwf/x2c/blob/main/packages/libuv/examples/process-report.x
  - label: Package guide
    href: https://github.com/gwf/x2c/blob/main/packages/libuv/README.md
---

<!-- ignore: source excerpt; the complete example requires its optional package and setup. -->
```x2c,ignore
import "libuv" with UvLoop, UvProcess;

UvLoop loop = UvLoop.new();
defer loop.free();
UvProcess normalized = loop.spawn(
  %("/usr/bin/tr" "[:lower:]" "[:upper:]")
);
defer normalized.free();
normalized.write(%"alpha\nbeta\ngamma\n")
  .close_stdin();

UvProcess counted = loop.spawn(
  %("/usr/bin/wc" "-l")
);
defer counted.free();
counted.write(%"alpha\nbeta\ngamma\n").close_stdin();
loop.run(UV_RUN_DEFAULT);

printf("normalized:\n");
foreach(String line, normalized.stdout().lines())
  printf("  %s\n", line);
printf("line count: %s", counted.stdout());
```

Start two child processes and send each the same three lines. `tr`
converts them to uppercase while `wc` counts them. Close each input
stream so the commands can finish, then run the event loop to collect
their output and exit statuses.

Both children start before the loop runs. Their captured output remains
available afterward, and both exit successfully. The complete example
also prints their process IDs before collecting the results.

Full example output:

```text
normalized:
  ALPHA
  BETA
  GAMMA
line count:        3
exits: normalized=0 counted=0
```
