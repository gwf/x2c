# Create a project

```sh
x2c new hello
cd hello
x2c run
```

`x2c new [-q|--quiet] <directory>` invokes the shipped `x2c-new` command.
The driver expands response files once and forwards the argument vector.
Both entry paths use `CliRequest.parse_arguments` for options and help.
Direct invocation keeps response-file words literal. The command writes the
starter manifest, source, and ignore file. Project-name validation is shared
with the manifest parser.

Build with `make commands`. Normal installations include the command.
The command smoke test owns the starter-project behavior checks.
