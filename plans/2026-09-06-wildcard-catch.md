> Status: needs author scoping
> Follow-up requested September 6, 2026; not implemented.

# Wildcard catch with access to the raised error

Add a convenient wildcard catch that binds the raised error so ordinary code
can inspect its code and details, report it, or otherwise handle it manually.
Syntax is not decided yet.

The motivating example is the Lisp shell: one handler could call
`_print_error` with the caught list's head as the code and its tail as the
details, instead of enumerating error codes with identical handler bodies.

Currently, catch syntax requires a bare literal code. A default `catch:`
selects any error but binds nothing. The runtime retains selected records
inside the catch handle and removes them from the public error stack before
the body runs; only pattern captures are exposed to source code.

When designing this change, reuse that retained record and the existing catch
capture lifetime. Decide how wildcard binding interacts with catch ordering
and the existing default arm. Preserve the rule that a handler is detached
before its body runs, so a new error propagates outward. Confirm that callers
can snapshot the bound value when it must outlive the handler.

This is a to-do item, not an approved syntax or implementation plan.
