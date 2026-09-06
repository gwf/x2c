/*  match-cache-benchmark.x -- Match cache-boundary acceptance benchmark

    Measures the production cached-adapter boundary against the
    recursive oracle: the frozen six-family corpus, the prepared / hit /
    cold / negative lanes, and the sublis-document-migration product
    workload. `--check` proves oracle parity and the zero-losing-span contract
    in the current build; `--time N` emits one sample's raw lane timings for
    the paired 21-process runner. Every timed iteration folds status and
    canonical result identity into a volatile receipt that is verified
    against a precomputed expectation, so no arm can drop observable work. */


#include "../test-support.x"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static volatile uint64_t benchmark_sink;

static void _fail(const char *what) {
  fprintf(stderr, "MATCH-CACHE-BENCHMARK-FAIL,%s\n", what);
  exit(1);
}

static void _check(int ok, const char *what) {
  if (!ok) _fail(what);
}

static uint64_t _now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t) ts.tv_sec * 1000000000ULL + ts.tv_nsec;
}

static uint64_t _mix(uint64_t hash, uint64_t value) {
  hash ^= value + 0x9e3779b97f4a7c15ULL + (hash << 6) + (hash >> 2);
  return hash;
}

// frozen fixtures - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#define FAMILY_COUNT 6

static void _families(List *inputs, Var *patterns, const char **names) {
  names[0] = "literal";
  inputs[0] = %(alpha beta gamma);
  patterns[0] = %(alpha beta gamma);
  names[1] = "binders";
  inputs[1] = %(alpha beta gamma);
  patterns[1] = %(?a ?b ?c);
  names[2] = "guard";
  inputs[2] = %(alpha beta gamma);
  patterns[2] = %(!and ?whole (!not missing) (!set ?whole ?));
  names[3] = "star-hit";
  inputs[3] = %(alpha beta gamma delta epsilon);
  patterns[3] = %(*left delta ?last);
  names[4] = "star-miss";
  inputs[4] = %(alpha beta gamma delta epsilon);
  patterns[4] = %(*left missing ?last);
  names[5] = "nested";
  inputs[5] = %(tree ((node 3 4)) leaf);
  patterns[5] = %(tree ((node ?a ?b)) ?rest);
}

/* One document template instantiated through List.sublis. */
static List _product_document(void) {
  List template = %(
    (document
      (header
        (title doc-title)
        (version doc-ver)
        (signature (authors auth-list) (audit audit-log))
      )
      (metadata
        (tags tag-list)
        (attributes attr-list)
        (release (status status-val) (published pub-date) (limits limit-set))
      )
      (body
        (intro intro-blk)
        (chapters chapter-ls)
        (closing (cta cta-text) (notes note-list) (recap doc-title cta-text))
      )
    )
    (appendix
      (summary sum-info)
      (notes note-list)
      (links cross-ref)
      (crumbs crumb-list)
    )
    (mirrors
      (primary doc-title doc-ver status-val)
      (secondary doc-title status-val)
      (relations (title doc-title) (call cta-text) (notes note-list))
    )
    (payload
      (snapshot snap-info)
      (bundle
        (title doc-title)
        (authors auth-list)
        (metadata (tags tag-list) (status status-val) (summary sum-info))
        (timeline (published pub-date) (limits limit-set))
        (calls (once cta-text) (again cta-text))
      )
    )
  );

  List alist = %(
    (doc-title "X2C Guide For Sublis")
    (doc-ver "2025.03")
    (auth-list ("Gary" "Avery" "Mika"))
    (tag-list ("lists" "sublis" "demo"))
    (attr-list ((owner "compiler") (focus "lists") (support ("alpha" "beta"))))
    (status-val draft)
    (pub-date "2025-02-10T16:00Z")
    (limit-set ((memory 2048 4096) (threads 8 16) (burst allowed)))
    (intro-blk
      ((headline "Handling nested substitutions")
       (summary "Step through complex templates")
       (bullets ("lists" "lists.sublis" "demo-run")))
    )
    (chapter-ls
      ((step1 "prepare data") (step2 "call sublis") (step3 "inspect output"))
    )
    (cta-text "Run make stage-3 after updates")
    (note-list ("Validate nested nodes" "Keep scalars interned"))
    (cross-ref
      ((anchor intro)
       (anchor usage)
       (anchor appendix)
       (paths
         ("docs/x2c-language-reference.md" "docs/x2c-development-guide.md")))
    )
    (crumb-list
      ((section "Guides") (chapter "Compiler") (topic "Assoc Lists"))
    )
    (audit-log
      ((actor "codex") (action "bootstrap") (actor "dev") (action "review"))
    )
    (snap-info
      ((name "post-substitution")
       (notes ("mirrors title" "preserves order"))
       (metrics ((replaced 9) (reused 3))))
    )
    (sum-info
      ((headline "Complex sublis scenario")
       (counts ((entries 3) (authors 3)))
       (reviewers ("Gary" "Avery")))
    )
  );

  return List.sublis(alist, template);
}

typedef struct ProductFixture {
  List document, document_node;
  Var direct_pattern, status_pattern, notes_pattern, actor_pattern;
  Var status_template, actor_template, draft_pattern;
} ProductFixture;

typedef struct ProductReceipt {
  List direct_bindings;
  Var first_match;
  List first_bindings, full_search;
  Var match_replacement;
  List search_replacement, draft_search;
} ProductReceipt;

static ProductFixture _product_fixture(void) {
  ProductFixture fixture;
  fixture.document = _product_document();
  fixture.document_node = car(fixture.document);
  fixture.direct_pattern = %(
    document
    (header (title ?title) *header)
    *sections
  );
  fixture.status_pattern = %(status ?state);
  fixture.notes_pattern = %(notes *items);
  fixture.actor_pattern = %(actor ?who);
  fixture.status_template = %(status reviewed (was ?state));
  fixture.actor_template = %(reviewer ?who);
  fixture.draft_pattern = <draft>;
  return fixture;
}

static void _product_oracle(ProductFixture *fixture, ProductReceipt *receipt) {
  _check(test_match_oracle_try_match(fixture.document_node,
                                    fixture.direct_pattern,
                                    &receipt.direct_bindings),
         "product-oracle-direct");
  _check(test_match_oracle_try_search(fixture.document,
                                     fixture.status_pattern,
                                     &receipt.first_match,
                                     &receipt.first_bindings),
         "product-oracle-first");
  receipt.full_search = test_match_oracle_search(fixture.document,
                                                fixture.notes_pattern);
  _check(test_match_oracle_try_match_replace(
           receipt.first_match, fixture.status_pattern,
           fixture.status_template, &receipt.match_replacement),
         "product-oracle-match-replace");
  receipt.search_replacement = test_match_oracle_search_replace(
    fixture.document, fixture.actor_pattern, fixture.actor_template);
  receipt.draft_search = test_match_oracle_search(fixture.document,
                                                 fixture.draft_pattern);
}

static void _product_candidate(
  MatchCache cache, ProductFixture *fixture, ProductReceipt *receipt) {
  _check(MatchCache.try_match(
           cache, fixture.document_node, fixture.direct_pattern,
           &receipt.direct_bindings),
         "product-candidate-direct");
  _check(MatchCache.try_search(
           cache, fixture.document, fixture.status_pattern,
           &receipt.first_match, &receipt.first_bindings),
         "product-candidate-first");
  _check(MatchCache.search(
           cache, fixture.document, fixture.notes_pattern,
           &receipt.full_search),
         "product-candidate-full");
  _check(MatchCache.try_match_replace(
           cache, receipt.first_match, fixture.status_pattern,
           fixture.status_template, &receipt.match_replacement),
         "product-candidate-match-replace");
  _check(MatchCache.search_replace(
           cache, fixture.document, fixture.actor_pattern,
           fixture.actor_template, &receipt.search_replacement),
         "product-candidate-search-replace");
  _check(MatchCache.search(
           cache, fixture.document, fixture.draft_pattern,
           &receipt.draft_search),
         "product-candidate-draft-fallback");
}

static void _check_product_receipts(
  ProductReceipt *candidate, ProductReceipt *oracle) {
  _check(candidate.direct_bindings == oracle.direct_bindings,
         "product-receipt-direct");
  _check(candidate.first_match == oracle.first_match,
         "product-receipt-first-match");
  _check(candidate.first_bindings == oracle.first_bindings,
         "product-receipt-first-bindings");
  _check(candidate.full_search == oracle.full_search,
         "product-receipt-full-search");
  _check(candidate.match_replacement == oracle.match_replacement,
         "product-receipt-match-replacement");
  _check(candidate.search_replacement == oracle.search_replacement,
         "product-receipt-search-replacement");
  _check(candidate.draft_search == oracle.draft_search,
         "product-receipt-draft-search");
}

static uint64_t _product_token(ProductReceipt *receipt) {
  uint64_t hash = 0x50524f44ULL;
  hash = _mix(hash, receipt.direct_bindings.var().u64);
  hash = _mix(hash, receipt.first_match.u64);
  hash = _mix(hash, receipt.first_bindings.var().u64);
  hash = _mix(hash, receipt.full_search.var().u64);
  hash = _mix(hash, receipt.match_replacement.u64);
  hash = _mix(hash, receipt.search_replacement.var().u64);
  hash = _mix(hash, receipt.draft_search.var().u64);
  return hash;
}

// correctness gate - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

static void _check_mode(void) {
  List inputs[FAMILY_COUNT];
  Var patterns[FAMILY_COUNT];
  const char *names[FAMILY_COUNT];
  _families(inputs, patterns, names);

  MatchCache cache = MatchCache.new(64);
  for (int round = 0; round < 2; round++)
    for (int i = 0; i < FAMILY_COUNT; i++) {
      List oracle = %(sentinel), candidate = %(sentinel);
      int oracle_status = inputs[i].try_match(patterns[i], &oracle);
      int matched = MatchCache.try_match(
        cache, inputs[i], patterns[i], &candidate
      );
      _check(matched == oracle_status, "family-status");
      if (oracle_status) _check(candidate == oracle, "family-result");
    }

  // Losing star candidates construct nothing at the plan boundary.
  MatchPlan miss_plan = MatchPlan.prepare(patterns[4]);
  _check(miss_plan.status == MACHINE_PREPARED, "star-miss-prepare");
  MachineStats miss_stats;
  memset(&miss_stats, 0, sizeof(miss_stats));
  List miss_bindings;
  _check(MatchPlan.execute(miss_plan, inputs[4], &miss_bindings,
                           &miss_stats) == 0, "star-miss-status");
  _check(miss_stats.span_descriptors == 0 &&
         miss_stats.materialization_requests == 0 &&
         miss_stats.cons_requests == 0, "star-miss-zero-spans");
  MatchPlan.free(miss_plan);

  // The approved malformed probe never matches and never falls back.
  List malformed_bindings = %(sentinel);
  _check(!MatchCache.try_match(
           cache, %(foo), %(!or *whole missing), &malformed_bindings),
         "malformed-probe-status");
  _check(malformed_bindings == %(sentinel), "malformed-probe-output");
  MatchCache.dispose(cache);

  // Product pipeline: cold and warm exact receipts.
  ProductFixture fixture = _product_fixture();
  ProductReceipt oracle_receipt, cold_receipt, warm_receipt;
  _product_oracle(&fixture, &oracle_receipt);
  MatchCache product = MatchCache.new(64);
  _product_candidate(product, &fixture, &cold_receipt);
  _check_product_receipts(&cold_receipt, &oracle_receipt);
  _product_candidate(product, &fixture, &warm_receipt);
  _check_product_receipts(&warm_receipt, &oracle_receipt);
  MatchCache.dispose(product);
  printf("check,ok\n");
}

// timed lanes - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

static uint64_t _time_oracle_match(
  List input, Var pattern, int iterations, uint64_t *receipt) {
  uint64_t hash = 0x4f4d41ULL, start = _now_ns();
  for (int i = 0; i < iterations; i++) {
    List bindings = NULL;
    int matched = test_match_oracle_try_match(input, pattern, &bindings);
    hash = _mix(hash, matched ? bindings.var().u64 + 1 : 0);
  }
  uint64_t elapsed = _now_ns() - start;
  *receipt = hash;
  return elapsed;
}

static uint64_t _time_adapter_match(
  MatchCache cache, List input, Var pattern, int iterations,
  uint64_t *receipt) {
  uint64_t hash = 0x43414eULL, start = _now_ns();
  for (int i = 0; i < iterations; i++) {
    List bindings = NULL;
    int matched = MatchCache.try_match(cache, input, pattern, &bindings);
    hash = _mix(hash, (uint64_t) matched);
    hash = _mix(hash, bindings.var().u64);
  }
  uint64_t elapsed = _now_ns() - start;
  *receipt = hash;
  return elapsed;
}

static uint64_t _expected_oracle_match(
  List input, Var pattern, int iterations) {
  List bindings = NULL;
  int matched = test_match_oracle_try_match(input, pattern, &bindings);
  uint64_t hash = 0x4f4d41ULL;
  for (int i = 0; i < iterations; i++)
    hash = _mix(hash, matched ? bindings.var().u64 + 1 : 0);
  return hash;
}

static uint64_t _expected_adapter_match(
  List input, Var pattern, int iterations) {
  List oracle_bindings = %(sentinel);
  int matched = test_match_oracle_try_match(input, pattern, &oracle_bindings);
  List bindings = matched ? oracle_bindings : NULL;
  uint64_t hash = 0x43414eULL;
  for (int i = 0; i < iterations; i++) {
    hash = _mix(hash, (uint64_t) matched);
    hash = _mix(hash, bindings.var().u64);
  }
  return hash;
}

static void _time_family(
  MatchCache cache, const char *name, List input, Var pattern, int iterations,
  int candidate_first) {
  uint64_t reference_receipt, candidate_receipt, reference_ns, candidate_ns;
  if (candidate_first) {
    candidate_ns = _time_adapter_match(cache, input, pattern,
                                       iterations,
                                       &candidate_receipt);
    reference_ns = _time_oracle_match(input, pattern, iterations,
                                      &reference_receipt);
  }
  else {
    reference_ns = _time_oracle_match(input, pattern, iterations,
                                      &reference_receipt);
    candidate_ns = _time_adapter_match(cache, input, pattern,
                                       iterations,
                                       &candidate_receipt);
  }
  _check(reference_receipt ==
         _expected_oracle_match(input, pattern, iterations),
         "reference-receipt");
  _check(candidate_receipt ==
         _expected_adapter_match(input, pattern, iterations),
         "candidate-receipt");
  benchmark_sink ^= reference_receipt ^ candidate_receipt;
  printf("family,%s,%d,%llu,%llu\n", name, iterations,
         (unsigned long long) reference_ns,
         (unsigned long long) candidate_ns);
}

static uint64_t _time_product_oracle(
  ProductFixture *fixture, int iterations, uint64_t expected) {
  uint64_t start = _now_ns();
  for (int i = 0; i < iterations; i++) {
    ProductReceipt receipt;
    _product_oracle(fixture, &receipt);
    benchmark_sink ^= _product_token(&receipt) ^ expected;
  }
  return _now_ns() - start;
}

static uint64_t _time_product_candidate(
  ProductFixture *fixture, int iterations, int cold, MatchCache warm_cache,
  uint64_t expected) {
  uint64_t start = _now_ns();
  for (int i = 0; i < iterations; i++) {
    MatchCache cache = cold ? MatchCache.new(64) : warm_cache;
    ProductReceipt receipt;
    _product_candidate(cache, fixture, &receipt);
    benchmark_sink ^= _product_token(&receipt) ^ expected;
    if (cold) MatchCache.dispose(cache);
  }
  return _now_ns() - start;
}

static void _time_mode(int sample) {
  List inputs[FAMILY_COUNT];
  Var patterns[FAMILY_COUNT];
  const char *names[FAMILY_COUNT];
  _families(inputs, patterns, names);
  int candidate_first = sample % 2 == 0, iterations = 20000;
  printf("sample,%d\n", sample);

  MatchCache cache = MatchCache.new(64);
  for (int i = 0; i < FAMILY_COUNT; i++) {
    List warm_bindings = NULL;
    MatchCache.try_match(cache, inputs[i], patterns[i], &warm_bindings);
  }
  for (int i = 0; i < FAMILY_COUNT; i++)
    _time_family(cache, names[i], inputs[i], patterns[i], iterations,
                 candidate_first);

  // Status lanes: prepared-only execution versus the full cached hit.
  Var status_pattern = %(status-lane ?value);
  List status_input = %(status-lane ok);
  MatchPlan plan = MatchPlan.prepare(status_pattern);
  _check(plan.status == MACHINE_PREPARED, "status-lane-prepare");
  uint64_t start = _now_ns();
  for (int i = 0; i < iterations; i++) {
    List bindings = NULL;
    plan.try_match(status_input, &bindings);
    benchmark_sink ^= bindings.var().u64;
  }
  uint64_t prepared_ns = _now_ns() - start;
  MatchPlan.free(plan);
  uint64_t hit_receipt;
  uint64_t hit_ns = _time_adapter_match(cache, status_input,
                                        status_pattern, iterations,
                                        &hit_receipt);
  benchmark_sink ^= hit_receipt;
  uint64_t reference_receipt;
  uint64_t reference_ns = _time_oracle_match(status_input,
                                             status_pattern,
                                             iterations,
                                             &reference_receipt);
  benchmark_sink ^= reference_receipt;
  printf("lane,prepared,%d,%llu,%llu\n", iterations,
         (unsigned long long) reference_ns,
         (unsigned long long) prepared_ns);
  printf("lane,hit,%d,%llu,%llu\n", iterations,
         (unsigned long long) reference_ns,
         (unsigned long long) hit_ns);
  MatchCache.dispose(cache);

  // Cold lane: a capacity-one cache with two alternating patterns
  // makes every acquire a miss, preparation, and eviction.
  int cold_iterations = 2000;
  Var cold_patterns[2];
  cold_patterns[0] = %(cold-a ?value);
  cold_patterns[1] = %(cold-b ?value);
  List cold_inputs[2];
  cold_inputs[0] = %(cold-a ok);
  cold_inputs[1] = %(cold-b ok);
  MatchCache cold_cache = MatchCache.new(1);
  start = _now_ns();
  for (int i = 0; i < cold_iterations; i++) {
    List bindings = NULL;
    int matched = MatchCache.try_match(
      cold_cache, cold_inputs[i & 1], cold_patterns[i & 1], &bindings
    );
    benchmark_sink ^= (uint64_t) matched ^ bindings.var().u64;
  }
  uint64_t cold_candidate_ns = _now_ns() - start;
  start = _now_ns();
  for (int i = 0; i < cold_iterations; i++) {
    List bindings = NULL;
    benchmark_sink ^= (uint64_t)
      test_match_oracle_try_match(cold_inputs[i & 1],
                                 cold_patterns[i & 1], &bindings);
  }
  uint64_t cold_reference_ns = _now_ns() - start;
  MatchCache.dispose(cold_cache);
  printf("lane,cold,%d,%llu,%llu\n", cold_iterations,
         (unsigned long long) cold_reference_ns,
         (unsigned long long) cold_candidate_ns);

  // Negative lane: the intentional bare-atom fallback through search.
  ProductFixture fixture = _product_fixture();
  int negative_iterations = 500;
  MatchCache negative_cache = MatchCache.new(8);
  start = _now_ns();
  for (int i = 0; i < negative_iterations; i++) {
    List results = NULL;
    int matched = MatchCache.search(
      negative_cache, fixture.document, fixture.draft_pattern, &results
    );
    benchmark_sink ^= (uint64_t) matched ^ results.var().u64;
  }
  uint64_t negative_candidate_ns = _now_ns() - start;
  start = _now_ns();
  for (int i = 0; i < negative_iterations; i++) {
    List results = test_match_oracle_search(fixture.document,
                                           fixture.draft_pattern);
    benchmark_sink ^= results.var().u64;
  }
  uint64_t negative_reference_ns = _now_ns() - start;
  MatchCache.dispose(negative_cache);
  printf("lane,negative,%d,%llu,%llu\n", negative_iterations,
         (unsigned long long) negative_reference_ns,
         (unsigned long long) negative_candidate_ns);

  // Product workload, warm and cold, reported separately.
  ProductReceipt oracle_receipt;
  _product_oracle(&fixture, &oracle_receipt);
  uint64_t expected = _product_token(&oracle_receipt);
  int product_iterations = 200;
  MatchCache warm_cache = MatchCache.new(64);
  ProductReceipt warm_receipt;
  _product_candidate(warm_cache, &fixture, &warm_receipt);
  _check_product_receipts(&warm_receipt, &oracle_receipt);
  uint64_t product_warm_candidate = _time_product_candidate(
    &fixture, product_iterations, 0, warm_cache, expected);
  uint64_t product_warm_reference = _time_product_oracle(
    &fixture, product_iterations, expected);
  MatchCache.dispose(warm_cache);
  printf("lane,product-warm,%d,%llu,%llu\n", product_iterations,
         (unsigned long long) product_warm_reference,
         (unsigned long long) product_warm_candidate);
  int product_cold_iterations = 100;
  uint64_t product_cold_candidate = _time_product_candidate(
    &fixture, product_cold_iterations, 1, NULL, expected);
  uint64_t product_cold_reference = _time_product_oracle(
    &fixture, product_cold_iterations, expected);
  printf("lane,product-cold,%d,%llu,%llu\n", product_cold_iterations,
         (unsigned long long) product_cold_reference,
         (unsigned long long) product_cold_candidate);
}

int main(int argc, char **argv) {
  if (argc >= 2 && !strcmp(argv[1], "--check")) {
    _check_mode();
    return 0;
  }
  if (argc >= 3 && !strcmp(argv[1], "--time")) {
    _time_mode(atoi(argv[2]));
    return 0;
  }
  fprintf(stderr, "usage: %s --check | --time SAMPLE\n", argv[0]);
  return 2;
}
