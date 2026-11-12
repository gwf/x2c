---
slug: scopes
section: love
home: true
order: 8
tab: memory
title: Working memory has a home.
---

```x2c
~/* Allocation counts are zero unless X2C_SCOPE_ACCOUNTING=1 is set, so the
~   assertions that expect live allocations check only with accounting. */
~#include <assert.h>
~int main(void) {
~// Prepare the catch before measuring reclaimable working storage.
~fail_in_scope();
~size_t before = Scope.stats().live_allocations;
// Reclaim working storage regularly in a long-running survey.
size_t total = 0;
// Each day's file list lives until that survey finishes.
while (wait_for_day()) auto {
~  assert(Scope.stats().live_allocations == before);
  Array files = survey_files();
~  size_t daily = Scope.stats().live_allocations;

  // Working data is reclaimed after every file.
  foreach (String path in files) auto {
~    assert(Scope.stats().live_allocations == daily);
    Map findings = inspect_file(path);
    save_findings(path, findings);
~    assert(!Scope.accounting_enabled() ||
~           Scope.stats().live_allocations > daily);
    total++;
  }
~  assert(Scope.stats().live_allocations == daily);
}
printf("processed: %zu files\n", total);
~assert(total == 4 && Scope.stats().live_allocations == before);
~assert(return_early() == 2);
~assert(Scope.stats().live_allocations == before);
~fail_in_scope();
~assert(Scope.stats().live_allocations == before);
~return 0;
~}

~int wait_for_day(void) { static int days = 0; return days++ < 2; }

~void save_findings(String path, Map findings) {
~  Array sizes = findings[<sizes>];
~  assert(sizes[0] == 12 && findings[<errors>] == 0);
~}

~auto int return_early(void) {
~  Array files = survey_files();
~  return files.length;
~}

~Array survey_files(void) => ["first.dat", "second.dat"];

~void fail_in_scope(void) {
~  size_t before = Scope.stats().live_allocations;
~  try auto {
~    Map findings = inspect_file("failure.dat");
~    assert(!Scope.accounting_enabled() ||
~           Scope.stats().live_allocations > before);
~    raise %(oops);
~  }
~  catch %(oops): {}
~}

~Map inspect_file(String path) => {sizes: [12, 24], errors: 0};
```

An auto scope reclaims temporary storage together when its block ends. Nested scopes let a program finish one file before moving to the next, while keeping results in their intended destination.
