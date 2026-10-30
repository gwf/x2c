---
slug: your-c
section: love
tab: your C
title: Your C still works. All of it.
---

```x2c
#include <assert.h>
#include <string.h>
#include <stdlib.h>

// X-macros, token pasting, and conditional groups all parse.
#define FIELDS(X) X(alpha) X(beta) X(gamma)
#define DECLARE(name) int name;
#define COUNT(name) + 1
typedef struct Config { FIELDS(DECLARE) } Config;

#ifdef __GNUC__
int main(void) {
#else
int main() {
#endif
// Ordinary C code is ordinary x2c code.
Config config = { 1, 2, 3 };
int fields = 0 FIELDS(COUNT);
char *copy = strdup("plain C strings");
assert(fields == 3 && strlen(copy) == 15);

// A struct field reached through a pointer is still a field.
Config *view = &config;
view.beta += 40;

// x2c values accept C values at every typed boundary.
Map named = {alpha: config.alpha, beta: view->beta, text: copy};
printf("%d fields, beta is %s\n", fields, named[<beta>]);
free(copy);
return 0;
}
```

Not "mostly works". X-macros expand, `#ifdef __GNUC__` gets decided, token
pasting pastes, and a `struct` is the same bytes it always was. x2c runs
its own C preprocessor, so a macro that supplies grammar parses like the
grammar it supplies.

`.` reaches through one pointer; `->` is still there if you miss it.
Headers are headers, libraries link. You add x2c to a file. You do not port
a project.
