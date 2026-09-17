/*  observations.x -- Find slow or failed endpoint observations. */

import "sqlite" with Database, Statement;

int main(void) {
  Database db = $auto(Database.open(":memory:"));
  db.execute("CREATE TABLE observation(url TEXT, status INTEGER, us INTEGER)");

  Statement insert =
    $auto(db.prepare("INSERT INTO observation VALUES (?, ?, ?)"));
  foreach(List reading, %(
    ("/guide" 200 12000)
    ("/reference" 503 40000)
    ("/source" 200 3100000)
  )) insert.bind(reading).execute();

  Statement report = $auto(db.prepare(
    "SELECT url, status, us FROM observation "
    "WHERE status >= 400 OR us > ? ORDER BY us DESC"
  ));
  report.bind(%(3000000));
  foreach(List row, report)
    printf("%s", %"${row[0]}: HTTP ${row[1]}, ${row[2]} us\n");
  return 0;
}
