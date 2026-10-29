---
title: Errors that unwind
group: Memory and errors
---

```x2c
#include <assert.h>

String read_text(String path) {
  File f = path.open("r");                  // raises <not-found> on failure
  defer f.close();                          // runs on return and on unwind
  return f.string();
}

String preview(String path) {
  try return read_text(path);
  catch %(not-found *): return "missing";
  catch %(?cause *detail): return %"$cause: $detail";   // bind the rest
}

int main(void) {
  assert(preview("/no/such/file") == "missing");
  try raise %(bad-arg (reason "demo") (value 3));
  catch %(bad-arg * (value ?v) *): assert(v == 3);
  finally puts("always");
  return 0;
}
```

- An Error is a List: `%(cause (key value) ...)`. `catch` selects it with
  the same patterns `match` uses; `catch:` takes anything.
- Runtime failures raise too: a bad conversion, a missing file, an index
  out of range. An uncaught one names your file and line.
- `finally` runs after the handlers; `defer` runs when its block exits.
