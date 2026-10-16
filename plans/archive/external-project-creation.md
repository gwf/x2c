> Status: done
> Implemented 2026-10-16. Focused compatibility checks passed.
> Shared-integrator submission selected after dev advanced during validation;
> final integration and publication belong to the integrator.

# External project creation

Move starter templates and filesystem writes into shipped `commands/new`.
Keep `x2c new` parsing, response expansion, help, quiet behavior, diagnostics,
exit status, and generated files compatible. The driver passes only the quiet
flag and a literal directory after `--`; the command does not expand response
files again. Existing command packaging and identity initialization apply.

Reuse the manifest parser's name predicate as `ProjectBuild.valid_name` so
project creation and manifest parsing keep one definition of valid names.
The compiler retains manifest parsing and build planning. Move the existing
starter tests from the CLI probe to the command smoke rather than running
both. Test direct command invocation and an installed prefix as focused checks.

Review the authored diff, regenerate derived documentation and bootstrap with
normal targets. Submit the reviewed change and focused evidence to the shared
integrator, which owns final publication validation.
No new recurring gate or compiler behavior is introduced.

## Plan review

CLI parsing establishes the operand count and options; command parsing serves
the direct executable too. The command alone checks destination occupancy and
writes files. Existing name validation is shared, not duplicated. The small
forwarder reuses the package-command interface. No new representation, cache,
validator, or dedicated diagnostic is needed. Existing negative fixtures protect
empty operands and refusal to overwrite a nonempty directory.

## Evidence

The relocated starter smoke passed, including executable output, nonempty
directory refusal, empty operands, and symlink naming. Driver, direct command,
and staged-prefix creation produced identical files. Literal `@` forwarding,
response-file expansion, and unchanged top-level and `new` help passed.
