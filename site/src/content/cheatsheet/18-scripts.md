---
title: Scripts, commands, and paths
group: Toolbox
---

```x2c
#!/usr/bin/env -S x2c script
// File-scope statements are the program; process.x, path.x, and args are in.
String branch = %(git rev-parse --abbrev-ref HEAD).job().output().strip(NULL);
foreach (String file in %(git diff --name-only).job().lines())
  printf("%s: %s\n", branch, file);
Path here = ".";
foreach (Path source in here.join("*.x").glob())
  printf("%s has %d bytes\n", source, source.read_text().len());
if (args.len()) printf("first argument: %s\n", args[0]);
```

- A command is a List; `$value` stays one argument whatever it contains.
  `.job()` makes it a `Job`; `.run()`, `.output()`, `.lines()`, `.start()`,
  `Job.wait_any()`.
- `x2c script tool.x args` builds once and reuses the executable until the
  source changes. A failure exits nonzero with the cause.
- `Path.join`, `.glob()`, `.read_text()`, `.write_text()`, `.make_dirs()`,
  `.is_file()`.
