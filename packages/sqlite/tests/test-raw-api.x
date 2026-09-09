/* test-raw-api.x -- direct calls through the complete pinned SQLite header. */

import "sqlite";

#include "sqlite-3.h"
#include "test-support.x"
#include <limits.h>
#include <string.h>

$(import "../../../unittest/test-macros.xmacro")

static void sqlite_raw_values_and_profile(void) {
  EXPECT_INT_EQ(sqlite3_libversion_number(), SQLITE_VERSION_NUMBER);
  EXPECT_INT_EQ(sqlite3_threadsafe(), 1);
  EXPECT_TRUE(sqlite3_compileoption_used("THREADSAFE=1"));

  sqlite3 *db = NULL;
  EXPECT_INT_EQ(sqlite3_open_v2(":memory:", &db,
    SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL), SQLITE_OK);
  EXPECT_NOT_NULL(db);
  if (!db) return;
  defer sqlite3_close(db);

  sqlite3_stmt *stmt = NULL;
  EXPECT_INT_EQ(sqlite3_prepare_v3(db,
    "SELECT ?1, ?2, ?3, ?4, ?5, json_valid('{\"x\":1}')", -1,
    SQLITE_PREPARE_PERSISTENT, &stmt, NULL), SQLITE_OK);
  EXPECT_NOT_NULL(stmt);
  if (!stmt) return;
  defer sqlite3_finalize(stmt);

  const unsigned char blob[] = {0, 255, 7};
  EXPECT_INT_EQ(sqlite3_bind_int64(stmt, 1, LLONG_MIN), SQLITE_OK);
  EXPECT_INT_EQ(sqlite3_bind_double(stmt, 2, 1.5), SQLITE_OK);
  EXPECT_INT_EQ(sqlite3_bind_text64(
    stmt, 3, "a\0b", 3, SQLITE_TRANSIENT, SQLITE_UTF8), SQLITE_OK);
  EXPECT_INT_EQ(sqlite3_bind_blob64(
    stmt, 4, blob, sizeof(blob), SQLITE_TRANSIENT), SQLITE_OK);
  EXPECT_INT_EQ(sqlite3_bind_null(stmt, 5), SQLITE_OK);
  EXPECT_INT_EQ(sqlite3_step(stmt), SQLITE_ROW);
  EXPECT_TRUE(sqlite3_column_int64(stmt, 0) == LLONG_MIN);
  EXPECT_TRUE(sqlite3_column_double(stmt, 1) == 1.5);
  EXPECT_INT_EQ(sqlite3_column_bytes(stmt, 2), 3);
  EXPECT_INT_EQ(memcmp(sqlite3_column_text(stmt, 2), "a\0b", 3), 0);
  EXPECT_INT_EQ(sqlite3_column_bytes(stmt, 3), sizeof(blob));
  EXPECT_INT_EQ(memcmp(sqlite3_column_blob(stmt, 3), blob, sizeof(blob)), 0);
  EXPECT_INT_EQ(sqlite3_column_type(stmt, 4), SQLITE_NULL);
  EXPECT_INT_EQ(sqlite3_column_int(stmt, 5), 1);
  EXPECT_INT_EQ(sqlite3_step(stmt), SQLITE_DONE);
}

static void sqlite_raw_backup(void) {
  sqlite3 *source = NULL, *destination = NULL;
  EXPECT_INT_EQ(sqlite3_open(":memory:", &source), SQLITE_OK);
  EXPECT_NOT_NULL(source);
  if (!source) return;
  defer sqlite3_close(source);
  EXPECT_INT_EQ(sqlite3_open(":memory:", &destination), SQLITE_OK);
  EXPECT_NOT_NULL(destination);
  if (!destination) return;
  defer sqlite3_close(destination);

  EXPECT_INT_EQ(sqlite3_exec(source,
    "CREATE TABLE item(value INTEGER); INSERT INTO item VALUES (42)",
    NULL, NULL, NULL), SQLITE_OK);
  sqlite3_backup *backup = sqlite3_backup_init(
    destination, "main", source, "main");
  EXPECT_NOT_NULL(backup);
  if (!backup) return;
  EXPECT_INT_EQ(sqlite3_backup_step(backup, -1), SQLITE_DONE);
  EXPECT_INT_EQ(sqlite3_backup_finish(backup), SQLITE_OK);

  sqlite3_stmt *stmt = NULL;
  EXPECT_INT_EQ(sqlite3_prepare_v2(destination,
    "SELECT value FROM item", -1, &stmt, NULL), SQLITE_OK);
  EXPECT_NOT_NULL(stmt);
  if (!stmt) return;
  defer sqlite3_finalize(stmt);
  EXPECT_INT_EQ(sqlite3_step(stmt), SQLITE_ROW);
  EXPECT_INT_EQ(sqlite3_column_int(stmt, 0), 42);
}

static void sqlite_raw_error_details(void) {
  sqlite3 *db = NULL;
  EXPECT_INT_EQ(sqlite3_open(":memory:", &db), SQLITE_OK);
  EXPECT_NOT_NULL(db);
  if (!db) return;
  defer sqlite3_close(db);
  sqlite3_stmt *stmt = NULL;
  EXPECT_INT_EQ(sqlite3_prepare_v2(
    db, "SELECT FROM", -1, &stmt, NULL), SQLITE_ERROR);
  EXPECT_NULL(stmt);
  EXPECT_INT_EQ(sqlite3_errcode(db), SQLITE_ERROR);
  EXPECT_TRUE(sqlite3_error_offset(db) >= 0);
  EXPECT_TRUE(strlen(sqlite3_errmsg(db)) > 0);
}

void sqlite_raw_suite(void) {
  $test.run(sqlite_raw_values_and_profile);
  $test.run(sqlite_raw_backup);
  $test.run(sqlite_raw_error_details);
}

int main(void) {
  TestHarness_begin();
  $test.suite(sqlite_raw_suite);
  return TestHarness_finish();
}
