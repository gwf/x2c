/*  cstar.x -- the proof-session surface a generated proof program uses.

    A Cstar value owns one C* verification session: the symbolic engine, the
    prover connection, the per-function completion inventory, and the final
    report. Everything else the generated program needs is the pinned raw
    builder API in cstar-0.5.7.h, which consumers also receive.

    Terms, theorems, and report text belong to the running session and its
    bundled collector; none of them may outlive Cstar.finish.
 */

#include "cstar-0.5.7.h"

typedef struct Cstar *Cstar;

#pragma private


struct Cstar {
  int expected, done;
  String file;
  String conditions;
};

static cst_range _cstar_range(Cstar cstar, int line, int column) {
  cst_range where;
  where.start.line = line;
  where.start.column = column;
  where.end = where.start;
  where.filename = cstar.file;
  return where;
}

static term _cstar_conjunct(term conjunct) {
  return bool_calls_for_qcp(Hconj(term_list_n(1, conjunct)));
}

/** Opens the session that verifies `expected` functions of `file`.
    The proof libraries initialize in their upstream order. The session ends
    at `Cstar.finish`, which every path must reach.
*/
Cstar Cstar.open(int expected, String file) {
  Cstar cstar = Scope.calloc(1, sizeof(struct Cstar));
  cstar.expected = expected;
  cstar.file = file;
  cst_set_debug(0);
  cst_main_entry(1);
  _cst_proof_proof_user_init();
  _cst_proof_proof_sl_init();
  _cst_proof_proof_backward_init();
  _cst_proof_proof_backward_sl_init();
  _cst_proof_proof_symexec_init();
  _cst_userlib_qcp_veriftime_init();
  _cst_tutorial_common_init();
  _cst_userlib_operational_operational_init();
  return cstar;
}

/** Loads the array theory and installs its concrete int-list and array
    vocabulary, which the array-fill steps below need. Building that theory
    costs about 0.7 s, so a session asks for it only when it uses one of
    those steps. It must precede the first fed segment. */
void Cstar.load_arrays(Cstar cstar) {
  _cst_array_lib_list_init();
  _cst_array_lib_array_core_init();
  _cst_array_lib_index_init();
  _cst_array_lib_array_init();
  _cst_x2c_array_helpers_init();
  install_array_qcp_interface();
  cst_exit_on_error();
}

/** Submits one program segment at a source position of the verified file. */
void Cstar.feed(Cstar cstar, partial_program segment, int line, int column) {
  cst_range where = _cstar_range(cstar, line, column);
  cst_feed_program_segment_with_loc(segment, where);
}

/** Records that one requested function was fed completely. */
void Cstar.complete(Cstar cstar) {
  cstar.done++;
}

/** Parses one logical term in the backend's syntax. */
term Cstar.term(Cstar cstar, String text) {
  term parsed = parse_term((const_cstr) text);
  cst_exit_on_error();
  return parsed;
}

/** Builds a contract or intermediate assertion from one logical term. */
term Cstar.assertion(Cstar cstar, String text) {
  return _cstar_conjunct(cstar.term(text));
}

/** Builds an assertion over program variables at one program point, adding
    the ownership frame each named variable implies. Loop invariants and
    intermediate assertions both cut the state this way. */
term Cstar.program_assertion(Cstar cstar, String text) {
  return _cstar_conjunct(mk_simple_invariant(cstar.term(text)));
}

/** Adds one proved pure fact to the symbolic state. */
void Cstar.add_fact(Cstar cstar, thm fact) {
  add_fact_st(fact);
  cst_exit_on_error();
}

/** Proves one linear integer arithmetic fact. */
thm Cstar.int_arith(Cstar cstar, String text) {
  thm proved = int_arith_rule(cstar.term(text));
  cst_exit_on_error();
  return proved;
}

/*  The array-fill proof steps of `proof/x2c_array_helpers.c`, reached by
    name from `$cstar.proof`. Each argument is a logical term: the array
    predicate at its base address, the length parameter's address and value,
    the ghost contents list, the loop index existential, and the value
    written into every cell. `elem` selects `Tint` or `Tchar`. */

/** Loop entry: the length is nonnegative, and the whole array is the cursor
    form at index 0. */
void Cstar.fill_entry(Cstar cstar, String array_at, String length_addr,
                      String length_var, String xs, String value) {
  x2c_fill_entry(cstar.term(array_at), cstar.term(length_addr),
                 cstar.term(length_var), cstar.term(xs), cstar.term(value));
  cst_exit_on_error();
}

/** Before the store: the index is in range for the cursor-shaped list the
    state owns, and its cell is a literal `data_at` a plain assignment can
    write. */
void Cstar.fill_before_store(Cstar cstar, String elem, String p_pre,
                             String index_var, String length_var, String xs,
                             String value) {
  x2c_fill_before_store(cstar.term(elem), cstar.term(p_pre),
                        cstar.term(index_var), cstar.term(length_var),
                        cstar.term(xs), cstar.term(value));
  cst_exit_on_error();
}

/** After the store: re-fold the written cell, advance the functional
    cursor, and re-establish the index bounds for `i + 1`. */
void Cstar.fill_after_store(Cstar cstar, String elem, String p_pre,
                            String index_var, String length_var, String xs,
                            String value) {
  x2c_fill_after_store(cstar.term(elem), cstar.term(p_pre),
                       cstar.term(index_var), cstar.term(length_var),
                       cstar.term(xs), cstar.term(value));
  cst_exit_on_error();
}

/** The index half of `fill_before_store`, without opening a cell. */
void Cstar.fill_index_bound(Cstar cstar, String index_var,
                            String length_var, String xs, String value) {
  x2c_fill_index_bound(cstar.term(index_var), cstar.term(length_var),
                       cstar.term(xs), cstar.term(value));
  cst_exit_on_error();
}

/** The cursor half of `fill_after_store`, without closing a cell. */
void Cstar.fill_advance(Cstar cstar, String index_var, String length_var,
                        String xs, String value) {
  x2c_fill_advance(cstar.term(index_var), cstar.term(length_var),
                   cstar.term(xs), cstar.term(value));
  cst_exit_on_error();
}

/** Loop exit: at `i = n` the cursor form collapses to the finished list. */
void Cstar.fill_exit(Cstar cstar, String index_var, String length_var,
                     String xs, String value) {
  x2c_fill_exit(cstar.term(index_var), cstar.term(length_var),
                cstar.term(xs), cstar.term(value));
  cst_exit_on_error();
}

/** Returns the session's rendered verification and trust obligations.
    The pinned printer drains verification conditions. Retain those items
    across queries; its axiom and strategy arrays already span the session. */
String Cstar.report(Cstar cstar) {
  String report = cst_print_vc();
  String prefix = %"{\"verification_conditions\":[";
  int end = report.find(%"],\"axioms\":[");
  if (report.find(prefix) != 0 || end < prefix.len())
    raise %(bad-state (library "cstar") (operation "report")
            (message "unexpected verification report"));
  String conditions = report[prefix.len():end];
  if (conditions.len())
    cstar.conditions = cstar.conditions
      ? cstar.conditions + %"," + conditions : conditions;
  return prefix + (cstar.conditions ? cstar.conditions : %"") + report[end:];
}

static Symbol _cstar_verdict(Cstar cstar, String report) {
  if (cstar.done != cstar.expected) return <incomplete>;
  int clean = report.find("\"verification_conditions\":[]") >= 0 &&
              report.find("\"axioms\":[]") >= 0 &&
              report.find("\"strategies\":[]") >= 0;
  return clean ? <verified> : <obligation>;
}

/** Classifies the run: `<verified>` only when every requested function was
    fed and no obligation remains, `<incomplete>` when the inventory is
    short, otherwise `<obligation>`. */
Symbol Cstar.verdict(Cstar cstar) {
  return _cstar_verdict(cstar, cstar.report());
}

/** Prints the report and the verdict, closes the session, and returns the
    program's exit code: 0 verified, 1 obligations remain, 2 incomplete. */
int Cstar.finish(Cstar cstar) {
  String report = cstar.report();
  Symbol verdict = _cstar_verdict(cstar, report);
  Stdout.printf("\nCSTAR REPORT: %s\n", report);
  Stdout.printf("processed %d of %d functions\n", cstar.done, cstar.expected);
  Stdout.printf("RESULT: %s\n", verdict == <verified> ? "verified"
                              : verdict == <obligation> ? "obligations remain"
                              : "incomplete");
  cst_main_exit();
  return verdict == <verified> ? 0 : verdict == <obligation> ? 1 : 2;
}
