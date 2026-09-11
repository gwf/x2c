/*  bench.x -- Shared measurement helpers for the x2c side of the suite.

    The applications own the models; this unit owns only the three things
    all of them repeat: a monotonic clock, one printed record line per
    number, and a memory sample that reads Scope, the canonical pool, and
    the process together.

    Samples land in a fixed array allocated once and print after the timed
    work, so measurement never adds an interned String or a List to the
    thing it is measuring. Labels are C strings for the same reason.
*/

#include <stdint.h>
#include <stdio.h>

#include "membytes.h"
#include "handles.h"

typedef enum Bench {
  BENCH_NAMESPACE
} Bench;

/** One memory observation: the four process counters, the Scope counters,
    and the canonical pool's storage, all read back to back. */
typedef struct BenchSample {
  const char *label;
  long index;
  double seconds;
  uint64_t footprint;
  uint64_t footprint_peak;
  uint64_t resident;
  uint64_t resident_peak;
  size_t live_allocations;
  size_t live_scopes;
  size_t allocation_calls;
  size_t free_calls;
  size_t requested_bytes;
  size_t pool_interned;
  size_t pool_active_bytes;
  size_t pool_backing_bytes;
  size_t pool_depot_bytes;
  /* Native handles by XtHandleKind, live and highest ever live. A build
     without the counters leaves these zero and `Bench.flush` says so. */
  uint64_t handles_live[XT_HANDLE_KINDS];
  uint64_t handles_peak[XT_HANDLE_KINDS];
} BenchSample;

#pragma private

static BenchSample *bench_samples = NULL;
static int bench_capacity = 0;
static int bench_count = 0;
static double bench_origin = 0.0;

#pragma public

/** Monotonic seconds excluding system sleep. */
double Bench.now(void) => xb_now();

/** Reserves room for `capacity` samples and starts the sample clock.
    Sampling beyond the reservation is dropped rather than allocating
    inside measured work; `Bench.dropped` reports how many. */
void Bench.begin(int capacity) {
  bench_samples = Scope.calloc(capacity ? capacity : 1, sizeof(BenchSample));
  bench_capacity = capacity;
  bench_count = 0;
  bench_origin = Bench.now();
}

/** Records one observation under `label`, with `index` naming the step,
    request, or cycle it follows. */
void Bench.sample(const char *label, long index) {
  if (bench_count >= bench_capacity) {
    bench_count++;
    return;
  }
  BenchSample *sample = &bench_samples[bench_count++];
  ScopeStats scope = Scope.stats();
  PoolStats pool = Pool.stats(List.pool_current());
  sample.label = label;
  sample.index = index;
  sample.seconds = Bench.now() - bench_origin;
  sample.footprint = xb_footprint();
  sample.footprint_peak = xb_footprint_peak();
  sample.resident = xb_resident();
  sample.resident_peak = xb_resident_peak();
  sample.live_allocations = scope.live_allocations;
  sample.live_scopes = scope.live_scopes;
  sample.allocation_calls = scope.allocation_calls;
  sample.free_calls = scope.free_calls;
  sample.requested_bytes = scope.requested_bytes;
  sample.pool_interned = pool.interned;
  sample.pool_active_bytes = pool.active_bytes;
  sample.pool_backing_bytes = pool.backing_bytes;
  sample.pool_depot_bytes = pool.depot_bytes;
  for (int kind = 0; kind < XT_HANDLE_KINDS; kind++) {
    sample.handles_live[kind] = xb_handles_live(kind);
    sample.handles_peak[kind] = xb_handles_peak(kind);
  }
}

/** Samples that did not fit the reservation. A non-zero count invalidates
    the tail of a memory series and is reported, not hidden. */
int Bench.dropped(void) =>
  bench_count > bench_capacity ? bench_count - bench_capacity : 0;

/** Prints every stored sample as one `sample` line. */
void Bench.flush(void) {
  int stored = bench_count < bench_capacity ? bench_count : bench_capacity;
  for (int i = 0; i < stored; i++) {
    BenchSample *s = &bench_samples[i];
    printf("sample %s %ld %.6f %llu %llu %llu %llu %zu %zu %zu %zu %zu "
           "%zu %zu %zu %zu\n",
           s.label, s.index, s.seconds,
           (unsigned long long) s.footprint,
           (unsigned long long) s.footprint_peak,
           (unsigned long long) s.resident,
           (unsigned long long) s.resident_peak,
           s.live_allocations, s.live_scopes, s.allocation_calls,
           s.free_calls, s.requested_bytes, s.pool_interned,
           s.pool_active_bytes, s.pool_backing_bytes, s.pool_depot_bytes);
    printf("handles %s %ld", s.label, s.index);
    for (int kind = 0; kind < XT_HANDLE_KINDS; kind++)
      printf(" %llu %llu", (unsigned long long) s.handles_live[kind],
             (unsigned long long) s.handles_peak[kind]);
    printf("\n");
  }
  for (int kind = 0; kind < XT_HANDLE_KINDS; kind++)
    printf("handlesum %d %llu %llu %llu %llu\n", kind,
           (unsigned long long) xb_handles_created(kind),
           (unsigned long long) xb_handles_destroyed(kind),
           (unsigned long long) xb_handles_live(kind),
           (unsigned long long) xb_handles_peak(kind));
  printf("counters %d\n", xb_handles_enabled());
  printf("dropped %d\n", Bench.dropped());
}

/** One named number the runner collects. */
void Bench.record(const char *name, double value) {
  printf("record %s %.12g\n", name, value);
}

void Bench.record_int(const char *name, long value) {
  printf("record %s %ld\n", name, value);
}

/** One point of a learning curve: the update and the loss there.
    Printed as it happens, in a check run only, never inside timed work. */
void Bench.curve(long index, double value) {
  printf("curve %ld %.10g\n", index, value);
}

/** One named text field, such as a variant or a library path. */
void Bench.record_text(const char *name, const char *value) {
  printf("text %s %s\n", name, value);
}
