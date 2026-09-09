> Status: done
> Corrected September 8, 2026: wildcard catch was already implemented.
> The commit archiving this plan adds the missing guide example and verifies
> code/detail binding and retained detail through `Error.snapshot`.

# Wildcard catch with access to the raised error

The September 6 proposal requested a catch that exposes an arbitrary error's
code and details, motivated by the Lisp shell's repeated reporting handlers.
Its claim that a filter requires a bare literal code was incorrect. Existing
Match binders already provide the requested behavior:

```x2c
Symbol code = 0;
List detail = nil;
try raise %(bad-arg (operation "load"));
catch %(?caught *fields): {
  code = caught;
  detail = Error.snapshot(fields);
}
printf("%s %s\n", code.str(), detail.repr());
```

The current compiler builds this program, which prints
`bad-arg ((operation "load"))` after the arm exits. The caught code binds as a
`Var`, the remaining fields bind as a borrowed `List`, and `Error.snapshot`
keeps the details valid beyond the arm. Filters retain their existing source
order, and a selected handler is detached before its body executes.

The [exceptions guide](../../docs/src/guide/exceptions.md#catching-by-cause)
now demonstrates the form and its lifetime. No new syntax or compiler/runtime
implementation is needed.
