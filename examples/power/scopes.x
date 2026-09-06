#include <assert.h>
int wait_for_day(void) { static int days = 0; return days++ < 2; }
Array survey_files(void) => %["first.dat", "second.dat"];
Map inspect_file(String path) => %{sizes: [12, 24], errors: 0};
void save_findings(String path, Map findings) {
  Array sizes = findings[<sizes>];
  assert(sizes[0] == 12 && findings[<errors>] == 0);
}
int return_early(void) { {
  Scope.retain();
  defer Scope.release();
  Array files = survey_files();
  return files.length;
} }
int main(void) {
size_t before = Scope.stats().live_allocations;
// Reclaim working storage regularly in a long-running survey.
size_t total = 0;
// Each day's file list lives until that survey finishes.
while (wait_for_day()) {
  Scope.retain();
  defer Scope.release();
  assert(Scope.stats().live_allocations == before);
  Array files = survey_files();
  size_t daily = Scope.stats().live_allocations;

  // Working data is reclaimed after every file.
  foreach (String path, files) {
    Scope.retain();
    defer Scope.release();
    assert(Scope.stats().live_allocations == daily);
    Map findings = inspect_file(path);
    save_findings(path, findings);
    assert(Scope.stats().live_allocations > daily);
    total++;
  }
  assert(Scope.stats().live_allocations == daily);
}
printf("processed: %zu files\n", total);
assert(total == 4 && Scope.stats().live_allocations == before);
assert(return_early() == 2);
assert(Scope.stats().live_allocations == before);
try {
  Scope.retain();
  defer Scope.release();
  Map findings = inspect_file(%"failure.dat");
  assert(Scope.stats().live_allocations > before);
  raise %(oops);
}
catch %(oops): {}
assert(Scope.stats().live_allocations == before);
return 0;
}
