/*  test-sqlite-lisp.x -- Read SQL values through installed Lisp bindings */

import "sqlite" with SqliteLisp;

#include "test-support.x"
#include "sqlite-3.h"
#include <stdio.h>

$(import "../../../unittest/test-macros.xmacro")

static void lisp_reads_rows_null_and_binary(void) {
  Lisp lisp = Lisp.new();
  defer lisp.destroy();
  SqliteLisp.install(lisp);
  List rows = lisp.eval(%(
    sqlite-query ":memory:" "SELECT ?, ?, ?, ?"
      (list "archive" (sqlite-bytes '(0 127 255)) (sqlite-null)
        (sqlite-bytes '()))
  ));
  lisp.set_global("rows", rows);
  EXPECT_INT_EQ(lisp.eval(%(length rows)).integer(), 1);
  EXPECT_INT_EQ(lisp.eval(%(length (car rows))).integer(), 4);
  EXPECT_STR_EQ(lisp.eval(%(car (car rows))).string(), %"archive");
  List bytes = lisp.eval(%(sqlite-bytes-list (cadr (car rows))));
  EXPECT_TRUE(bytes == %(0 127 255));
  Var null_result = lisp.eval(%(sqlite-null? (car (cdr (cdr (car rows))))));
  EXPECT_TRUE(!null_result.is_nil());
  EXPECT_TRUE(lisp.eval(%(sqlite-null? '())).is_nil());
  Var empty = lisp.eval(%(sqlite-bytes-list
    (car (cdr (cdr (cdr (car rows)))))));
  EXPECT_TRUE(empty.is_nil());
  int caught = 0;
  try { lisp.eval(%(sqlite-bytes '(0 256))); }
  catch %(bad-arg *_): { caught = 1; }
  EXPECT_TRUE(caught);
}

static void lisp_persists_parameters_and_reports_errors(void) {
  String path = "builds/test-sqlite-lisp.db";
  remove(path);
  defer remove(path);
  Lisp lisp = Lisp.new();
  defer lisp.destroy();
  SqliteLisp.install(lisp);
  EXPECT_INT_EQ(lisp.eval(%(sqlite-execute $path
    "CREATE TABLE item(name TEXT, value INTEGER)" '())).integer(), 0);
  EXPECT_INT_EQ(lisp.eval(%(sqlite-execute $path
    "INSERT INTO item VALUES (?, ?)" '("saved" 42))).integer(), 1);
  EXPECT_STR_EQ(lisp.eval(%(car (car (sqlite-query $path
    "SELECT name FROM item WHERE value = ?" '(42))))).string(), %"saved");
  EXPECT_INT_EQ(lisp.eval(%(length (sqlite-query $path
    "SELECT name FROM item WHERE value = ?" '(43)))).integer(), 0);
  long long native_before = sqlite3_memory_used();
  int caught = 0;
  try { lisp.eval(%(sqlite-query $path "SELECT ?" '())); }
  catch %(bad-arg *_): { caught = 1; }
  EXPECT_TRUE(caught);
  long long native_after = sqlite3_memory_used();
  EXPECT_INT_EQ(native_before, native_after);
  caught = 0;
  try { lisp.eval(%(sqlite-execute $path "INSERT INTO missing VALUES (1)"
    '())); }
  catch %(bad-state *detail): {
    caught = 1;
    EXPECT_TRUE(detail.assoc(<message>).string().len() > 0);
  }
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(lisp.eval(%(car (car (sqlite-query $path
    "SELECT count(*) FROM item" '())))).integer(), 1);
}

void sqlite_lisp_suite(void) {
  $test.run(lisp_reads_rows_null_and_binary);
  $test.run(lisp_persists_parameters_and_reports_errors);
}

int main(void) {
  TestHarness_begin();
  $test.suite(sqlite_lisp_suite);
  return TestHarness_finish();
}
