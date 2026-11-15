/*  main.x -- update an installed release compiler

    Copyright (c) 2026 Gary William Flake.
*/
#include "utils.x"
#include <errno.h>
#include <string.h>
#include <unistd.h>

String x2c_embedded_identity(void);

int main(int argc, char **argv) {
  x2c_initialize_command_environment(argv[0], x2c_embedded_identity());
  Path directory = Path.dirname(x2c_get_executable());
  Path home = directory.dirname().dirname();
  if (directory.basename() != "x2c") home = home.dirname();
  Path installer = home.join("etc/install.sh");
  Path checkout = home.join("site/public/install.sh");
  if (!installer.is_file() && checkout.is_file()) {
    installer = checkout;
    int help = argc == 2 &&
      (!strcmp(argv[1], "--help") || !strcmp(argv[1], "-h"));
    if (!help)
      Diagnostics.driver_error(
        %"this is a development checkout; run 'make install' in $home " +
        "to install its current compiler");
  }
  char **args = xcalloc(argc + 5, sizeof(char *));
  args[0] = "sh";
  args[1] = installer;
  args[2] = "--update";
  args[3] = "--prefix";
  args[4] = home;
  for (int i = 1; i < argc; i++) args[i + 4] = argv[i];
  execvp("sh", args);
  Diagnostics.driver_error(
    %"cannot run the compiler installer: $(String.new(strerror(errno)))");
}
