/* A function body written in an arm of a group that defines or undefines
   a macro stays in that arm, because the group reopened after that
   directive could choose another arm. */

#ifndef GENERATE_INCLUDE_GUARD
#define GENERATE_INCLUDE_GUARD 1
static int guarded(void) { return 1; }
#endif

#ifndef PICKED
#define PICKED 1
static int pick(void) { return 2; }
#else
static int pick(void) { return 3; }
#endif

#define TEMPORARY 1
#ifdef TEMPORARY
#undef TEMPORARY
static int cleared(void) { return 4; }
#endif

int main(void) {
  printf("%d %d %d\n", guarded(), pick(), cleared());
  return 0;
}
