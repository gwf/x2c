---
title: Packages and imports
group: Toolbox
---

<!-- ignore: imports need the packages installed or a registered package directory. -->
```x2c,ignore
import "pcre2" as rx;               // alias: rx.Regexp, rx.Regexp.compile
import "sqlite" with Database;      // or pull selected names in bare

int main(void) {
  rx.Regexp re = rx.Regexp.compile("^(?<word>[a-z]+)", 0);
  defer re.free();
  rx.RegexpMatch found = re.match("hello world");
  puts(found[<word>]);
  Database db = Database.open(":memory:");
  defer db.close();
  return 0;
}
```

```sh
x2c install pcre2                    # from the package index into ~/.local/x2c
x2c run --package-dir packages main.x
x2c bind --package foo --header foo.h -l foo   # a package skeleton from a C header
```

- A package is a directory with `src/`; its public names get a `pkg__`
  prefix in C, so two packages can export the same name.
- Shipped: pcre2, sqlite, yyjson, raylib, termbox2, libcurl, libuv, blis,
  torch, autodiff.
