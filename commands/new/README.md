# Create a project

`x2c new [-q|--quiet] <directory>` invokes the shipped `x2c-new` command.
The driver expands response files once and passes the argument vector to the
command for legacy CLI parsing and help. Direct `x2c-new` invocation keeps
literal arguments and its own argument parser. The command writes the starter
manifest, source, and ignore file. Project-name validation is shared with the manifest parser.

Build with `make commands`. Normal installations include the command.
The command smoke test owns the existing starter-project behavior checks.
