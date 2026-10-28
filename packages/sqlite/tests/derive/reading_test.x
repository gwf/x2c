/*  reading_test.x -- derived records through SQLite rows */

#include "derive.x"
#include "test.x"
import "sqlite" with Database, Prepared;

typedef struct Reading {
  long id;
  String station;
  double value;
} Reading;

$derive(Reading, <row>, <equal>);

$test()
static void records_round_trip_through_sqlite(void) {
  Database db = auto Database.open(":memory:");
  db.execute("CREATE TABLE reading(id INTEGER, station TEXT, value REAL)");
  Prepared insert = auto db.prepare("INSERT INTO reading VALUES (?, ?, ?)");
  Reading first = { 17, "north", 1.5 };
  Reading second = { 4000000001L, "south", -2.25 };
  insert.bind(@(second.row())).execute();
  insert.bind(@(first.row())).execute();

  Prepared select = auto db.prepare(
    "SELECT id, station, value FROM reading ORDER BY id");
  $expect_eq(select.columns(), Reading.columns());
  Reading copy = Reading.from_row(select.next());
  $expect(first.equal(copy));
  $expect(!second.equal(copy));
  copy = Reading.from_row(select.next());
  $expect(second.equal(copy));
  $expect(select.next() == NULL);
}

$test.main();
