/*  File-scope conditional groups around static declarations. A group whose
    items divide between the generated header and source keeps its
    directives in both files, and each static initializer runs under the
    directives that enclose its definition. */

#define VERBOSE 1

#if VERBOSE
int shared = 1;
static const char *mode = "verbose";
#  ifdef MISSING
static const char *detail = "missing";
#  else
static const char *detail = "present";
#  endif
#else
int shared = 0;
static const char *mode = "quiet";
static const char *detail = "none";
#endif

#if 0
static int limit = 3;
#elif VERBOSE
static int limit = 4;
#else
static int limit = 5;
#endif

#ifdef MISSING
static int hidden = 6;
#endif

int main(void) {
  printf("%s %s %d %d\n", mode, detail, shared, limit);
  return 0;
}
