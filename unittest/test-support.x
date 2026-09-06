/*  test-support.x -- unit test harness (declarations + implementation) */

#include <stdarg.h>
#include <stdlib.h>
#include "match-recursive.x"

#define EXPECT_TRUE(expr) \
  Test_expect(#expr, (expr), __FILE__, __LINE__)

#define EXPECT_FALSE(expr) \
  Test_expect("!(" #expr ")", !(expr), __FILE__, __LINE__)

#define EXPECT_INT_EQ(actual, expected) \
  Test_expect_int(#actual " == " #expected, (actual), (expected), \
                  __FILE__, __LINE__)

#define EXPECT_STR_EQ(actual, expected) \
  Test_expect_str(#actual, (actual), (expected), __FILE__, __LINE__)

#define EXPECT_PTR_EQ(actual, expected) \
  Test_expect(#actual " == " #expected, (actual) == (expected), \
              __FILE__, __LINE__)

#define EXPECT_NULL(expr) \
  Test_expect(#expr " == NULL", (expr) == NULL, __FILE__, __LINE__)

#define EXPECT_NOT_NULL(expr) \
  Test_expect(#expr " != NULL", (expr) != NULL, __FILE__, __LINE__)

#define EXPECT_VAR_EQ(actual, expected) \
  Test_expect(#actual " == " #expected, \
              Var_equal((actual), (expected)), __FILE__, __LINE__)

#define EXPECT_LIST_EQ(actual, expected) \
  Test_expect_list(#actual " == " #expected, (actual), (expected), \
                   __FILE__, __LINE__)

#define TEST_FAIL(msg) \
  Test_expect(msg, 0, __FILE__, __LINE__)

typedef void (*TestFn)(void);

typedef struct ContextProbe {
  Var value;
  int exports;
  int fail_at;
} *ContextProbe;

typedef struct {
  int run;
  int passed;
  int failed;
  int skipped;
  int assertions;
  int failures;
} TestStats;

// The oracle is the optional recursive matcher in lib/match-recursive.x.
int test_match_oracle_try_match(List input, Var pattern, List *out_bindings) {
  return match_recursive_try_match(input, pattern, out_bindings);
}

int test_match_oracle_try_match_replace(
  List input, Var pattern, Var template, Var *out) {
  return match_recursive_try_match_replace(input, pattern, template, out);
}

List test_match_oracle_search(List input, Var pattern) {
  return match_recursive_search(input, pattern);
}

int test_match_oracle_try_search(
  List input, Var pattern, Var *out_match, List *out_bindings) {
  return match_recursive_try_search(input, pattern, out_match, out_bindings);
}

List test_match_oracle_search_replace(List input, Var pattern, Var template) {
  return match_recursive_search_replace(input, pattern, template);
}

static TestStats stats;
static const char *current_test = NULL;

static inline const char *current_test_name(void) {
  return current_test ? current_test : "(unknown)";
}

static void report_failure(
  const char *expr, const char *file, int line, const char *fmt, ...) {
  Stderr.printf("[FAIL] %s: %s", current_test_name(), expr);
  if (fmt) {
    Stderr.printf(": ");
    va_list ap;
    va_start(ap, fmt);
    Stderr.va_printf(fmt, ap);
    va_end(ap);
  }
  Stderr.printf(" (%s:%d)\n", file, line);
}

void TestHarness_begin(void) {
  stats.run = 0;
  stats.passed = 0;
  stats.failed = 0;
  stats.skipped = 0;
  stats.assertions = 0;
  stats.failures = 0;
  current_test = NULL;
}

void TestSuite_begin(const char *name) {
  Stdout.printf("\nSuite %s\n", name);
}


void TestHarness_skip(const char *name, const char *reason) {
  stats.skipped++;
  Stdout.printf("[SKIP] %s: %s\n", name, reason);
}


static int scope_chain_contains(Scope scope, Scope target) {
  while (scope) {
    if (scope == target) return 1;
    scope = scope.down;
  }
  return target == NULL;
}


// Scope.push changes the active slot. Restore it before any operation that may
// allocate through Scope, because a test's pushed slot may point into a dead
// stack frame after the test returns or transfers.
static int restore_scope_slots(Scope *saved_slot) {
  int changed = 0;
  while (Scope.top() != saved_slot) {
    changed = 1;
    Scope.pop();
  }
  return changed;
}


// Scope.retain changes the value stored in the active slot.
static int restore_retained_scopes(Scope *saved_slot, Scope saved_scope) {
  int changed = 0;
  if (!scope_chain_contains(*saved_slot, saved_scope)) return -1;
  while (*saved_slot != saved_scope) {
    changed = 1;
    Scope.release();
  }
  return changed;
}

// A test fails on a failed assertion, no assertions, or unbalanced scope
// state. An uncaught Error remains with its configured policy owner.
void TestHarness_run(const char *name, TestFn fn) {
  current_test = name;
  stats.run++;
  Stdout.printf("[RUN] %s\n", name);
  int before = stats.failures, assertions_before = stats.assertions;
  Scope *saved_slot = Scope.top(), saved_scope = *saved_slot;
  fn();
  int slot_change = restore_scope_slots(saved_slot);
  int retained_change = restore_retained_scopes(saved_slot, saved_scope);
  if (retained_change < 0) {
    stats.failures++;
    report_failure("scope underflow", "(harness)", 0, NULL);
    abort();
  }
  if (slot_change || retained_change) {
    stats.failures++;
    report_failure("extra pushed or retained scope", "(harness)", 0, NULL);
  }
  if (stats.assertions == assertions_before) {
    stats.failures++;
    report_failure("test made no assertions", "(harness)", 0, NULL);
  }
  if (stats.failures > before) stats.failed++;
  else stats.passed++;
  current_test = NULL;
}

int Test_expect(const char *expr, int cond, const char *file, int line) {
  stats.assertions++;
  if (cond) return 1;
  stats.failures++;
  report_failure(expr, file, line, NULL);
  return 0;
}

int Test_expect_int(
  const char *expr, long long actual, long long expected, const char *file,
  int line) {
  stats.assertions++;
  if (actual == expected) return 1;
  stats.failures++;
  report_failure(expr, file, line,
                 "(expected %lld, got %lld)", expected, actual);
  return 0;
}

static inline const char *string_or_null(const char *text) {
  return text ? text : "(null)";
}

int Test_expect_str(
  const char *expr, const char *actual, const char *expected, const char *file,
  int line) {
  stats.assertions++;
  String actual_str = (String) actual, expected_str = (String) expected;
  int ok = (actual_str == expected_str);
  if (actual_str && expected_str) ok = actual_str.equal(expected_str);
  if (ok) return 1;
  stats.failures++;
  report_failure(expr, file, line,
                 "(expected \"%s\", got \"%s\")",
                 string_or_null(expected), string_or_null(actual));
  return 0;
}

int Test_expect_list(
  const char *expr, List actual, List expected, const char *file, int line) {
  stats.assertions++;
  if (actual == expected) return 1;
  stats.failures++;
  report_failure(expr, file, line,
                 "(expected %s, got %s)",
                 expected ? expected.repr() : "(null)",
                 actual ? actual.repr() : "(null)");
  return 0;
}

int TestHarness_finish(void) {
  Stdout.printf("\nSummary: %d passed, %d failed, %d skipped, ",
                stats.passed, stats.failed, stats.skipped);
  Stdout.printf("%d total (%d assertions)\n",
                stats.run + stats.skipped, stats.assertions);
  return stats.failed ? 1 : 0;
}
