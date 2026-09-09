/*  test-all.x -- harness for x2c library unit tests */

#include "test-support.x"

void scope_suite(void);
void context_suite(void);
void mutex_suite(void);
void thread_suite(void);
void pool_suite(void);
void block_suite(void);
void defer_suite(void);
void map_suite(void);
void string_suite(void);
void split_suite(void);
void string_number_suite(void);
void string_classify_suite(void);
void scan_suite(void);
void tokenizer_suite(void);
void list_suite(void);
void symbol_suite(void);
void symbolset_suite(void);
void atom_suite(void);
void buffer_suite(void);
void match_suite(void);
void match_stmt_suite(void);
void match_logic_suite(void);
void match_binder_contract_suite(void);
void file_suite(void);
void exception_suite(void);
void error_suite(void);
void array_suite(void);
void typed_array_suite(void);
void typed_list_suite(void);
void typed_map_suite(void);
void autodiff_suite(void);
void protocols_suite(void);
void atomic_container_suite(void);
void var_suite(void);
void varops_suite(void);
void iter_suite(void);
void diagnostics_suite(void);
void logger_suite(void);
void interpolation_suite(void);
void lambda_suite(void);
void index_slice_suite(void);
void destructuring_suite(void);
void ast_suite(void);
void func_suite(void);
void lisp_suite(void);
void machine_suite(void);
void lisp_auto_suite(void);
void match_plan_suite(void);
void match_cache_suite(void);

$(import "test-macros.xmacro")

int main(int argc, char **argv) {
  TestHarness_begin();
  TestHarness_select(argc - 1, argv + 1);
  $test.suite(scope_suite);
  $test.suite(context_suite);
  $test.suite(pool_suite);
  $test.suite(block_suite);
  $test.suite(defer_suite);
  $test.suite(map_suite);
  $test.suite(string_suite);
  $test.suite(split_suite);
  $test.suite(string_number_suite);
  $test.suite(string_classify_suite);
  $test.suite(scan_suite);
  $test.suite(tokenizer_suite);
  $test.suite(list_suite);
  $test.suite(symbol_suite);
  $test.suite(symbolset_suite);
  $test.suite(atom_suite);
  $test.suite(exception_suite);
  $test.suite(error_suite);
  $test.suite(buffer_suite);
  $test.suite(machine_suite);
  $test.suite(match_suite);
  $test.suite(match_plan_suite);
  $test.suite(match_cache_suite);
  $test.suite(match_stmt_suite);
  $test.suite(match_logic_suite);
  $test.suite(match_binder_contract_suite);
  $test.suite(file_suite);
  $test.suite(array_suite);
  $test.suite(typed_array_suite);
  $test.suite(typed_list_suite);
  $test.suite(typed_map_suite);
  $test.suite(autodiff_suite);
  $test.suite(protocols_suite);
  $test.suite(atomic_container_suite);
  // The core Atom descriptor registers before suites begin. Keep the runtime
  // consumers ahead of var's dispatch-capacity saturation test.
  $test.suite(func_suite);
  $test.suite(lisp_suite);
  $test.suite(lisp_auto_suite);
  $test.suite(var_suite);
  $test.suite(varops_suite);
  $test.suite(iter_suite);
  $test.suite(diagnostics_suite);
  $test.suite(logger_suite);
  $test.suite(interpolation_suite);
  $test.suite(lambda_suite);
  $test.suite(index_slice_suite);
  $test.suite(destructuring_suite);
  $test.suite(ast_suite);
  $test.suite(mutex_suite);
  $test.suite(thread_suite);
  return TestHarness_finish();
}
