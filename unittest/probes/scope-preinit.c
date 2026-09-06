/*  scope-preinit.c -- Scope use before aggregate runtime initialization */

#include "scope.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

void x2c_initialize_protocols(void) {}

/* Scope shutdown drives the per-thread release order, and this probe links
   scope.o and thread-state.o without the Match half of that order. */
void x2c_match_thread_release(void) {}

void x2c_error_raise_n(
  const X2CErrorSite *site, Symbol code, unsigned pair_count, ...
) {
  (void)site;
  (void)code;
  (void)pair_count;
  abort();
}

int main(int argc, char **argv) {
  if (argc != 2) return 2;

  if (!strcmp(argv[1], "allocate")) {
    void *ptr = Scope_malloc(8);
    if (!ptr) return 1;
    Scope_free(ptr);
    ScopeStats stats = Scope_stats();
    if (stats.allocation_calls != 1 || stats.free_calls != 1)
      return 1;
    Scope_shutdown();
    return 0;
  }

  if (!strcmp(argv[1], "shutdown")) {
    Scope_shutdown();
    Scope_shutdown();
    ScopeStats stats = Scope_stats();
    return stats.live_scopes || stats.live_allocations;
  }

  if (!strcmp(argv[1], "reinitialize")) {
    Scope_initialize();
    Scope_shutdown();
    Scope_initialize();
    Scope_malloc(8);
    return 1;
  }

  if (!strcmp(argv[1], "malloc-overflow")) Scope_malloc(SIZE_MAX);
  if (!strcmp(argv[1], "calloc-overflow")) Scope_calloc(SIZE_MAX, 2);

  return 2;
}
