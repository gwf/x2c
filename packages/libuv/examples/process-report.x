/*  process-report.x -- two child processes on one libuv event loop */

import "libuv" with UvLoop, UvProcess;

int main(void) {
  UvLoop loop = $auto(UvLoop.new());

  UvProcess normalized =
    $auto(loop.spawn(%("/usr/bin/tr" "[:lower:]" "[:upper:]")));
  normalized.write("alpha\nbeta\ngamma\n").close_stdin();

  UvProcess counted = $auto(loop.spawn(%("/usr/bin/wc" "-l")));
  counted.write("alpha\nbeta\ngamma\n").close_stdin();

  printf("started %d and %d before running the loop\n",
         normalized.pid(), counted.pid());
  loop.run(UV_RUN_DEFAULT);

  printf("normalized:\n");
  foreach(String line, normalized.stdout().lines()) printf("  %s\n", line);

  printf("line count: %s", counted.stdout());
  printf("exits: normalized=%ld counted=%ld\n",
         normalized.exit_status(), counted.exit_status());
  return normalized.exit_status() || counted.exit_status();
}
