/*  test-sqlite.x -- Imported database values, ownership, and transactions. */

import "sqlite" with Database, Statement;

#include "sqlite-3.h"
#include "test-support.x"
#include <limits.h>
#include <float.h>
#include <math.h>
#include <string.h>
#include <stdio.h>

$(import "../../../unittest/test-macros.xmacro")

static long count_rows(Database db) {
  Statement query = db.prepare("SELECT count(*) FROM item");
  defer query.free();
  List row = query.next();
  return row[0].long_long_value();
}

static void positional_parameters_reset_and_reuse(void) {
  Database db = Database.open(":memory:");
  defer db.close();
  db.execute("CREATE TABLE item(id INTEGER PRIMARY KEY, name TEXT)");
  Statement insert = db.prepare("INSERT INTO item(name) VALUES (?)");
  defer insert.free();
  insert.bind(%("first")).execute();
  EXPECT_INT_EQ(db.changes(), 1);
  EXPECT_INT_EQ(db.last_insert_rowid(), 1);
  insert.bind(%("second")).execute();
  EXPECT_INT_EQ(db.last_insert_rowid(), 2);
  EXPECT_INT_EQ(count_rows(db), 2);

  Statement query = db.prepare("SELECT name FROM item WHERE id = ?");
  defer query.free();
  query.bind(%(1));
  EXPECT_STR_EQ(query.next()[0].string(), %"first");
  EXPECT_TRUE(query.next() == NULL);
  query.reset();
  EXPECT_STR_EQ(query.next()[0].string(), %"first");
  query.bind(%(2));
  EXPECT_STR_EQ(query.next()[0].string(), %"second");
  int caught = 0;
  try { query.bind(%()); }
  catch %(bad-arg *_): { caught = 1; }
  EXPECT_TRUE(caught);
  caught = 0;
  try { query.bind(%(1 2)); }
  catch %(bad-arg *_): { caught = 1; }
  EXPECT_TRUE(caught);
}

static void named_parameters_replace_all_values(void) {
  Database db = Database.open(":memory:");
  defer db.close();
  Statement query = db.prepare("SELECT :left + :right, :left");
  defer query.free();
  query.bind_named(%{":left": 4, ":right": 7});
  List row = query.next();
  EXPECT_INT_EQ(row[0].long_long_value(), 11);
  EXPECT_INT_EQ(row[1].long_long_value(), 4);
  query.bind_named(%{":left": 20, ":right": 2});
  EXPECT_INT_EQ(query.next()[0].long_long_value(), 22);
  int caught = 0;
  try { query.bind_named(%{":left": 1}); }
  catch %(bad-arg *_): { caught = 1; }
  EXPECT_TRUE(caught);
  caught = 0;
  try { query.bind_named(%{":left": 1, ":right": 2, ":extra": 3}); }
  catch %(bad-arg *_): { caught = 1; }
  EXPECT_TRUE(caught);
}

static void null_empty_rows_and_duplicate_columns_are_distinct(void) {
  Database db = Database.open(":memory:");
  defer db.close();
  Statement query = db.prepare("SELECT NULL AS value, 7 AS value");
  defer query.free();
  List names = query.columns();
  EXPECT_INT_EQ(names.len(), 2);
  EXPECT_STR_EQ(names[0].string(), %"value");
  EXPECT_STR_EQ(names[1].string(), %"value");
  List row = query.next();
  EXPECT_INT_EQ(row.len(), 2);
  EXPECT_TRUE(row[0].is_null());
  EXPECT_INT_EQ(row[1].long_long_value(), 7);
  EXPECT_TRUE(query.next() == NULL);
  EXPECT_TRUE(query.next() == NULL);
  Statement empty = db.prepare("SELECT NULL WHERE 0");
  defer empty.free();
  EXPECT_TRUE(empty.next() == NULL);
}

static void rows_copy_text_blobs_and_nul_text(void) {
  Database db = Database.open(":memory:");
  defer db.close();
  Statement query = db.prepare(
    "SELECT 'first', x'410042', CAST(x'610062' AS TEXT), x'' "
    "UNION ALL SELECT 'second', x'ff', 'plain', x'12'"
  );
  List first = query.next();
  EXPECT_STR_EQ(query.next()[0].string(), %"second");
  query.free();
  db.close();
  EXPECT_STR_EQ(first[0].string(), %"first");
  EXPECT_TRUE(first[1] is Bytes);
  Bytes blob = first[1];
  EXPECT_INT_EQ(blob.block().length, 3);
  EXPECT_TRUE(memcmp(blob, "A\0B", 3) == 0);
  EXPECT_TRUE(first[2] is Bytes);
  Bytes text = first[2];
  EXPECT_INT_EQ(text.block().length, 3);
  EXPECT_TRUE(memcmp(text, "a\0b", 3) == 0);
  EXPECT_TRUE(first[3] is Bytes);
  Bytes empty = first[3];
  EXPECT_INT_EQ(empty.block().length, 0);
}

static void bound_values_copy_binary_and_preserve_numeric_edges(void) {
  Database db = Database.open(":memory:");
  defer db.close();
  Statement query = db.prepare("SELECT ?, ?, ?, ?, ?, ?");
  defer query.free();
  Block block = Block.new(1);
  defer block.free();
  block.append("A\0B", 3);
  Bytes bytes = block.bytes;
  Var absent = NULL;
  long long minimum = LLONG_MIN;
  unsigned long long maximum = LLONG_MAX;
  query.bind(%($absent $minimum $maximum 1.25 "text" $bytes));
  memset(block.bytes, 'x', 3);
  List row = query.next();
  EXPECT_TRUE(row[0].is_null());
  EXPECT_TRUE(row[1].long_long_value() == LLONG_MIN);
  EXPECT_TRUE(row[2].long_long_value() == LLONG_MAX);
  EXPECT_TRUE(row[3].floating() == 1.25);
  EXPECT_STR_EQ(row[4].string(), %"text");
  Bytes copy = row[5];
  EXPECT_TRUE(memcmp(copy, "A\0B", 3) == 0);

  Statement empty = db.prepare(
    "SELECT typeof(?), length(?), typeof(?), length(?)"
  );
  defer empty.free();
  Bytes empty_blob = Bytes.new(1);
  empty.bind(%($empty_blob $empty_blob "" ""));
  List kinds = empty.next();
  EXPECT_STR_EQ(kinds[0].string(), %"blob");
  EXPECT_INT_EQ(kinds[1].integer(), 0);
  EXPECT_STR_EQ(kinds[2].string(), %"text");
  EXPECT_INT_EQ(kinds[3].integer(), 0);

  Statement integer = db.prepare("SELECT ?");
  defer integer.free();
  unsigned long long outside = (unsigned long long) LLONG_MAX + 1;
  int caught = 0;
  try { integer.bind(%($outside)); }
  catch %(conv-range *_): { caught = 1; }
  EXPECT_TRUE(caught);
  outside = ULLONG_MAX;
  caught = 0;
  try { integer.bind(%($outside)); }
  catch %(conv-range *_): { caught = 1; }
  EXPECT_TRUE(caught);
  double nan = NAN;
  caught = 0;
  try { integer.bind(%($nan)); }
  catch %(conv-range *_): { caught = 1; }
  EXPECT_TRUE(caught);
#if LDBL_MAX_EXP > DBL_MAX_EXP
  long double wide = LDBL_MAX;
  caught = 0;
  try { integer.bind(%($wide)); }
  catch %(conv-range *_): { caught = 1; }
  EXPECT_TRUE(caught);
#endif
  double infinity = INFINITY;
  integer.bind(%($infinity));
  EXPECT_TRUE(isinf(integer.next()[0].floating()));
}

static void native_failures_preserve_operation_code_and_message(void) {
  Database db = Database.open(":memory:");
  defer db.close();
  db.execute("CREATE TABLE item(value INTEGER UNIQUE); "
             "INSERT INTO item VALUES(1)");
  Statement insert = db.prepare("INSERT INTO item VALUES(?)");
  defer insert.free();
  int caught = 0;
  try { insert.bind(%(1)).execute(); }
  catch %(?code *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<library>).string(), %"SQLite");
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"sqlite3_step");
    EXPECT_INT_EQ(detail.assoc(<code>).integer(),
                  SQLITE_CONSTRAINT_UNIQUE);
    EXPECT_TRUE(detail.assoc(<message>).string().len() > 0);
  }
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(count_rows(db), 1);
  caught = 0;
  try { db.prepare("SELECT FROM"); }
  catch %(?code *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"sqlite3_prepare_v2");
    EXPECT_INT_EQ(detail.assoc(<offset>).integer(), 7);
    EXPECT_TRUE(detail.assoc(<message>).string().len() > 0);
  }
  EXPECT_TRUE(caught);
}

static void transactions_commit_and_preserve_rollback_error(void) {
  Database db = Database.open(":memory:");
  defer db.close();
  db.execute("CREATE TABLE item(value INTEGER)");
  Var result = db.transaction(%!() => {
    db.execute("INSERT INTO item VALUES(1); INSERT INTO item VALUES(2)");
    return 17;
  });
  EXPECT_INT_EQ(result.integer(), 17);
  EXPECT_INT_EQ(count_rows(db), 2);
  int caught = 0;
  try {
    db.transaction(%!() => {
      db.execute("INSERT INTO item VALUES(3)");
      raise %(bad-arg (marker "original"));
    });
  }
  catch %(bad-arg *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<marker>).string(), %"original");
  }
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(count_rows(db), 2);
  EXPECT_TRUE(sqlite3_get_autocommit(db.native()));
}

static void nested_transactions_reject_without_partial_commit(void) {
  Database db = Database.open(":memory:");
  defer db.close();
  db.execute("CREATE TABLE item(value INTEGER)");
  int caught = 0;
  try {
    db.transaction(%!() => {
      db.execute("INSERT INTO item VALUES(1)");
      return db.transaction(%!() => 9);
    });
  }
  catch %(bad-state *_): { caught = 1; }
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(count_rows(db), 0);
  db.transaction(%!() => {
    db.execute("INSERT INTO item VALUES(2)");
    return 0;
  });
  EXPECT_INT_EQ(count_rows(db), 1);
}

static void file_reopen_readonly_and_busy_are_observable(void) {
  String filename = %"builds/test-sqlite.db";
  remove(filename);
  defer remove(filename);
  Database db = Database.open(filename);
  defer db.close();
  db.execute("CREATE TABLE item(value INTEGER); INSERT INTO item VALUES(9)");
  db.close();
  Database readonly = Database.open_with(filename, SQLITE_OPEN_READONLY);
  defer readonly.close();
  EXPECT_INT_EQ(count_rows(readonly), 1);
  int caught = 0;
  try { readonly.execute("INSERT INTO item VALUES(10)"); }
  catch %(?code *detail): {
    caught = 1;
    EXPECT_INT_EQ(detail.assoc(<code>).integer() & 255,
                  SQLITE_READONLY);
  }
  EXPECT_TRUE(caught);
  readonly.close();

  Database first = Database.open(filename);
  defer first.close();
  Database second = Database.open(filename);
  defer second.close();
  second.busy_timeout(1);
  first.execute("BEGIN IMMEDIATE");
  caught = 0;
  try { second.execute("INSERT INTO item VALUES(11)"); }
  catch %(?code *detail): {
    caught = 1;
    EXPECT_INT_EQ(detail.assoc(<code>).integer() & 255, SQLITE_BUSY);
  }
  EXPECT_TRUE(caught);
  first.execute("ROLLBACK");
  second.execute("INSERT INTO item VALUES(12)");
  EXPECT_INT_EQ(count_rows(second), 2);
}

static void explicit_close_invalidates_operations_but_cleanup_is_safe(void) {
  Database db = Database.open(":memory:");
  Statement query = db.prepare("SELECT 1");
  db.close();
  db.close();
  int caught = 0;
  try { query.next(); }
  catch %(bad-state *_): { caught = 1; }
  EXPECT_TRUE(caught);
  query.free();
  query.free();
  caught = 0;
  try { db.prepare("SELECT 2"); }
  catch %(bad-state *_): { caught = 1; }
  EXPECT_TRUE(caught);
}

void sqlite_suite(void) {
  $test.run(positional_parameters_reset_and_reuse);
  $test.run(named_parameters_replace_all_values);
  $test.run(null_empty_rows_and_duplicate_columns_are_distinct);
  $test.run(rows_copy_text_blobs_and_nul_text);
  $test.run(bound_values_copy_binary_and_preserve_numeric_edges);
  $test.run(native_failures_preserve_operation_code_and_message);
  $test.run(transactions_commit_and_preserve_rollback_error);
  $test.run(nested_transactions_reject_without_partial_commit);
  $test.run(file_reopen_readonly_and_busy_are_observable);
  $test.run(explicit_close_invalidates_operations_but_cleanup_is_safe);
}

int main(void) {
  TestHarness_begin();
  $test.suite(sqlite_suite);
  return TestHarness_finish();
}
