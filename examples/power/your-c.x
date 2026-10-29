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
