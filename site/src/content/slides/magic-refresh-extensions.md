---
slug: extensions
section: magic
home: true
order: 5
tab: extensions
title: UI had me at hello.
run: |
  make -C packages/x2cui build
  ./x2c build --package-dir packages \
    --c-include-dir packages/x2cui/deps/include \
    -I packages/x2cui/deps/include \
    --output /tmp/x2cui-counter packages/x2cui/examples/counter.x
  /tmp/x2cui-counter
links:
  - label: Full source
    href: https://github.com/gwf/x2c/blob/main/packages/x2cui/examples/counter.x
  - label: Build the example
    href: /docs/guide/x2cui.html
---

<!-- ignore: requires the optional x2cui package and a window. -->
```x2c,ignore
import "x2cui" with App, Ui;

~int main(void) {
  App app = auto App.open(title: "Counter", width: 360, height: 240);
  int clicks = 0;
  while (app.frame()) {
    Ui ui = app.ui();
    ui.column (pad: 24, gap: 12) {
      ui.heading("A tiny counter", 2);
      if (ui.button("Add one", variant: primary))
        clicks++;
      ui.text(%"Clicked $clicks times.");
    }
  }
~  return 0;
~}
```

One import brings in a UI notation: block containers, named options, and short option values. The package generates these forms at compile time from CUI's declarations. Your program uses the extension alongside ordinary C control flow; the compiler needs no UI-specific feature.
