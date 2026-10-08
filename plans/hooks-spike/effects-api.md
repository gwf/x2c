# Effects and node diagnostics as x2c calls (W1-B)

> Status: reference
> Spike on private branch `gwf/hooks-spike`, worker W1-B, 2026-10-07.

## Spellings

All are declared in `lib/meta.x` as bodyless `meta` prototypes. The
compiler (`src/meta-sdk.x`) and the project helper (`etc/meta-helper.x`)
each define them, so they work in linked and project meta code alike.

| Call | Result |
| --- | --- |
| `x2c_code(code, effects)` | `(code-value "source" CODE EFFECTS)`; return it from a meta call a template slot makes |
| `x2c_fresh_name(role)` | the binder `?__ROLE`, held in an `Atom` local and used as a `$name` hole in any number of quotations |
| `x2c_effect_name(name)` | `(new-name NAME ROLE)`: one fresh, expansion-private binding for the binder |
| `x2c_effect_support(key, name, declaration)` | `(early KEY NAME DECLARATION)`: the declaration once per unit under `key`; later keys reuse its binding |
| `x2c_effect_initialize(area, statement)` | `(initialize AREA STATEMENT)`: append to `<protocol>`, `<prepare>`, `<statics>`, or `<finish>` |
| `x2c_diagnostic_fail_at(node, message, notes)` | error at the first `(at N ...)` in or around `node`, else at the invocation; does not return |

One-layer string switch, from `string-switch.x`:

```x2c
Atom selected = x2c_fresh_name("selected");
List dispatch = _sswitch_dispatch(selected, labels, 0);
return x2c_code(
  $!{ { String $selected = $subject; switch ($dispatch) $rewritten } },
  %(${x2c_effect_name(selected)}));
```

## Choices

- A fresh name is a carrier binder rather than a quotation fresh row, so the
  existing `new-name` effect gives it its binding. An `Atom` local fills a
  declarator or an expression hole; the carrier replaces the binder inside
  every nested quotation's hole values before landing.
- Effect rows stay the compiler's existing carrier vocabulary. `early` keeps
  its spelling and now binds its declaration at unit position, so a
  quotation can build it; the raw form in `macro-early` emits the same C.
- `initialize` binds its statement at the expansion site and lowers it with
  `Compiler.normalize` before `Compiler.add_init`. An unknown effect row is
  now an error instead of being ignored.
- A carrier that reaches `_bind_form` outside a macro value application
  (any direct macro or decorator) binds through `Compiler.bind_code_value`,
  which opens the application context and a transaction that covers
  pending areas and adapters, as `land_quotation` does. Ordinary binding
  pays one more match arm.
- Node diagnostics: the in-process call reports through
  `Compiler.report_meta_error`; the helper raises `meta-fail` with
  `(at NODE)`, replies `(error MESSAGE NOTES (at NODE))`, and the client
  reports at the node's origin. Origin search is one function, in the
  client.
- Bodyless prototypes, not bodied builders: a bodied `lib/meta.x` function
  changes the linked-meta definition hashes, so the seed `bin/x2c` builds
  a project helper while translating `lib/`; with a changed
  `etc/meta-helper.x` that build deadlocks on the project meta lock
  (`Helper.support` translates the loop under the lock its child needs).

## Limits

- A Unit macro at file scope loses `initialize` effects: the expansion runs
  during collection and the full parse reuses its declaration bundle
  without the pending areas. Effects from statement and expression macros
  apply.
- `<statics>` runs before file statics' own initializers, so a statement
  that reads an initialized static belongs in `<finish>`.
- Binders from `x2c_fresh_name` must be distinct within one result; the
  role is the binder's spelling.

## Cost per use

Converged stage-2 compiler, `bench/measure.sh` (one warm-up, minimum of
five), units from `bench/gen-effects.py` with the old `string-switch.x`
from `04a6fbeb` as `string-switch-old.x`. Slope from N=50 to N=400 functions,
one three-label switch each.

| Form | N=50 | N=400 | Per use |
| --- | ---: | ---: | ---: |
| Hand-written | 2,337,727,110 | 5,050,464,341 | 7.75 M |
| Old `$strings.string_switch` (template + meta) | 2,993,576,160 | 8,013,721,595 | 14.34 M |
| Old `$strings.switch` (two metas + template) | 3,230,169,175 | 9,844,870,165 | 18.90 M |
| Old hooked `switch` | 3,228,192,158 | 9,845,909,925 | 18.91 M |
| New `$strings.switch` (one meta) | 3,047,606,406 | 8,413,992,425 | 15.33 M |
| New hooked `switch` | 3,043,669,891 | 8,424,778,092 | 15.37 M |
| New, without the carrier (unhygienic name) | 3,003,863,308 | 8,058,407,783 | 14.44 M |

The one-layer switch saves 3.57 M per use over the old two-layer
`$strings.switch`. The carrier (fresh name, transaction, replacement)
costs 0.89 M per use. The hand-written and old figures match
`findings.md` within 0.04 M, so the unused path costs nothing measurable.
