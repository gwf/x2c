// Milestone 1 probe: an x2c program that verifies `absolute` through the
// C* builder API, with one x2c theorem helper, and refuses success unless
// every requested function completed.
#include <stdio.h>
#include <string.h>
#include <time.h>
#include "cstar-shim.h"

// Proof-library operations reused from the prebuilt library objects.
term Hconj(term *conjuncts);
term bool_calls_for_qcp(term raw_assertion);
term return_int(term value);
void _cst_proof_proof_user_init(void);
void _cst_proof_proof_sl_init(void);
void _cst_proof_proof_backward_init(void);
void _cst_proof_proof_backward_sl_init(void);
void _cst_proof_proof_symexec_init(void);
void _cst_userlib_qcp_veriftime_init(void);

static cst_range _at(int line) {
  cst_range r;
  r.start.line = line;
  r.start.column = 1;
  r.end = r.start;
  r.filename = "abs.x";
  return r;
}

static void _feed(partial_program p, int line) {
  cst_feed_program_segment_with_loc(p, _at(line));
}

static term _assert(const char *text) {
  return bool_calls_for_qcp(Hconj(term_list_n(1, parse_term(text))));
}

// An x2c theorem helper: proves a scalar arithmetic fact and returns it.
static thm helper_int_fact(const char *text) {
  thm th = int_arith_rule(parse_term(text));
  cst_exit_on_error();
  return th;
}

static int _done = 0;

static void absolute(int bounded) {
  ctype i = make_int_type();
  _feed(make_cst_require(_assert(bounded
    ? "fact(x >= --2147483647i)" : "fact(x <= 2147483647i)")), 4);
  _feed(make_cst_ensure(_assert(
    "fact(x >= 0i && __return == x || x < 0i && __return == --x)")), 5);
  ctype params[1] = {i};
  const char *names[1] = {"x"};
  _feed(make_function_start("absolute", i, params, names, 1), 6);
  _feed(make_block_begin(), 6);
  _feed(make_if_condition(make_binary_expr(BINOP_GREATER_EQUAL,
    make_var_expr("x", i), make_const_expr(0, i), i)), 7);
  _feed(make_block_begin(), 7);
  _feed(make_return_expr(make_var_expr("x", i)), 8);
  _feed(make_block_end(), 9);
  _feed(make_else(), 9);
  _feed(make_block_begin(), 9);
  _feed(make_return_expr(make_unary_expr(UNOP_MINUS,
    make_var_expr("x", i), i)), 10);
  _feed(make_block_end(), 11);
  _feed(make_block_end(), 12);
  _feed(make_function_end(), 12);
  _done++;
}

static void twice(int stop_early) {
  ctype i = make_int_type();
  _feed(make_cst_require(_assert("fact(0i <= n && n <= 100i)")), 14);
  _feed(make_cst_ensure(bool_calls_for_qcp(Hconj(term_list_n(1,
    return_int(parse_term("n + n:int")))))), 15);
  ctype params[1] = {i};
  const char *names[1] = {"n"};
  _feed(make_function_start("twice", i, params, names, 1), 16);
  _feed(make_block_begin(), 16);
  _feed(make_var_def_init("r", i, make_binary_expr(BINOP_ADD,
    make_var_expr("n", i), make_var_expr("n", i), i)), 17);
  if (stop_early) return;
  struct timespec t0, t1;
  clock_gettime(CLOCK_MONOTONIC, &t0);
  thm fact = helper_int_fact("n + n == n + n");
  clock_gettime(CLOCK_MONOTONIC, &t1);
  printf("helper theorem: %s (%.1f ms warm call)\n", string_of_thm(fact),
         (t1.tv_sec - t0.tv_sec) * 1e3 + (t1.tv_nsec - t0.tv_nsec) / 1e6);
  _feed(make_return_expr(make_var_expr("r", i)), 18);
  _feed(make_block_end(), 19);
  _feed(make_function_end(), 19);
  _done++;
}

int main(int argc, char **argv) {
  int stop_early = argc > 1 && !strcmp(argv[1], "--stop-early");
  int unbounded = argc > 1 && !strcmp(argv[1], "--unbounded");
  cst_set_debug(0);
  cst_main_entry(1);
  _cst_proof_proof_user_init();
  _cst_proof_proof_sl_init();
  _cst_proof_proof_backward_init();
  _cst_proof_proof_backward_sl_init();
  _cst_proof_proof_symexec_init();
  _cst_userlib_qcp_veriftime_init();
  absolute(!unbounded);
  twice(stop_early);
  const char *report = cst_print_vc();
  puts(report);
  int expected = 2;
  printf("processed %d of %d functions\n", _done, expected);
  cst_main_exit();
  if (_done != expected) {
    puts("RESULT: incomplete (refusing success)");
    return 2;
  }
  int clean = strstr(report, "\"verification_conditions\":[]")
    && strstr(report, "\"axioms\":[]")
    && strstr(report, "\"strategies\":[]");
  puts(clean ? "RESULT: verified" : "RESULT: obligations remain");
  return clean ? 0 : 1;
}
