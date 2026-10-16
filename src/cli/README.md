# Command-line requests

This module turns command-line arguments into typed requests and renders
command help. The rest of the compiler consumes those requests rather than
parsing option strings again.

Start with `cli.x` for the request types, then `requests.x` for defaults and
`parsing.x` for option handling.

## Files

| File | Responsibility |
| --- | --- |
| [cli.x](cli.x) | Declares CliRequest, target descriptions, shared diagnostics, and module members. |
| [parsing.x](parsing.x) | Defines command and option tables, parses operands and options, and fills requests. |
| [responses.x](responses.x) | Expands response files and handles their quoting, escaping, comments, and whitespace. |
| [requests.x](requests.x) | Supplies defaults, target kinds, package search roots, input checks, and version text. |
| [help.x](help.x) | Renders top-level and command help from the shared command and option descriptions. |

## Related code

[main.x](../main.x) dispatches requests. [Project
planning](../project/README.md) produces the same request type from manifests.
The [build command](../../commands/build/build.x) executes build and run
requests.

[Source guide](../README.md)
