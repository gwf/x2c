# Create a project

`x2c new [-q|--quiet] <directory>` invokes the shipped `x2c-new` command.
The driver retains CLI parsing, response-file expansion, and help. It passes
literal operands to the command, which writes the starter manifest, source,
and ignore file. Project-name validation is shared with the manifest parser.

Build with `make commands`. Normal installations include the command.
The command smoke test owns the existing starter-project behavior checks.
