/*  observation-history.x -- Persist a batch and report endpoint history. */

import "sqlite" with Database, Statement;

#include <stdlib.h>

static void ingest(String filename, String database) {
  File input = filename.open("r");
  defer input.close();
  Database db = Database.open(database);
  defer db.close();
  db.execute("CREATE TABLE IF NOT EXISTS observation "
             "(url TEXT, status INTEGER, us INTEGER)");
  Statement insert = db.prepare("INSERT INTO observation VALUES (?, ?, ?)");
  defer insert.free();

  /* The input is a whitespace-separated URL, status, and latency per row. */
  db.transaction(%!() => {
    foreach(String line, input) {
      if (!line.strip(NULL)) continue;
      String (url, status, us) = line.words().iter().list();
      long status_code = atol(status), elapsed = atol(us);
      insert.bind(%($url $status_code $elapsed)).execute();
    }
  });
}

int main(int argc, char **argv) {
  String input = argc > 1 ? argv[1] : "examples/observations.txt";
  String filename = argc > 2 ? argv[2] : "builds/observation-history.db";
  ingest(input, filename);

  Database db = Database.open(filename);
  defer db.close();
  Statement report = db.prepare(
    "SELECT url, count(*), sum(status >= 400), "
    "CAST(avg(us) AS INTEGER), max(us) "
    "FROM observation GROUP BY url ORDER BY url"
  );
  defer report.free();
  foreach(List row, report)
    printf("%s", %"${row[0]}: ${row[1]} readings, ${row[2]} failures, " +
                  %"${row[3]} us average, ${row[4]} us maximum\n");
  return 0;
}
