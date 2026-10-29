/*  sqlite-consumer.x -- use the package x2c bind generates from sqlite3.h. */

import "sqlite3" with Sqlite3, Sqlite3Stmt;

#include "sqlite3-raw.h"

int main(void) {
  auto Sqlite3 db = NULL;
  if (sqlite3_open(":memory:", &db) != SQLITE_OK) return 1;
  auto Sqlite3Stmt statement = NULL;
  db.prepare_v2("SELECT 6 * 7", -1, &statement, NULL);
  if (statement.step() != SQLITE_ROW) return 1;
  printf("answer %d\n", statement.column_int(0));
  return 0;
}
