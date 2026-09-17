# Repository review, 2026-09-17

> Status: active - catalog of reproduced defects from a whole-repository
> review at ea10e89, rechecked at a0e5641 on 2026-09-17. Groups 1, 2, 6, 8,
> 10, and 13 are fixed and on main (`ecdcea9..bed22b2` plus the collections
> commits that follow it), as are the scanner, private-interface, and
> library-removal items under "Assigned elsewhere" (`ecdcea9..4a003c1`).
> Groups 3, 4, 5, 7, 9, 11, 12, 14, 15, 16, and 17 are open. `make verify`,
> `verify-fixtures`, `examples`, `check`, and `packages-check` all passed at
> ea10e89, so none of these defects was caught by a current gate.

## Result

Each group below is one fix change: its files do not overlap another group's,
so groups can proceed in separate sessions. A fix reproduces the row first,
repairs the cause, adds or extends a fixture or unit test only where the row
is wrong output, a crash, or a documented behavior, and updates the book where
the row says the book is wrong.

The **R** column says who reproduced the row: `me` means rerun by the review
author at a0e5641 (or at ea10e89 where marked), and `agent` means a review
subagent reproduced it with the recorded probe and it has not been rerun.
Line numbers are from a0e5641. Probe sources were under `/tmp/x2c-review/`,
which does not survive a reboot; each row carries enough to rebuild the probe.

## Group 1: parser and preprocessor

> Fixed 2026-09-17 except the raw 0xFF row, which needs `lib/scan.x`. The
> emitted C now places a leading attribute after the storage class, and a
> storage class written after the type parses.

Files: `src/parse.x`, `src/statements.x`, `src/expressions.x`,
`src/compiler.x` (directive scan), `lib/tokenizer.x`.

| Defect | Reproduction | Cause | R |
| --- | --- | --- | --- |
| A leading attribute drops the return conversion; wrong values, bad reads, exit 0. | `__attribute__((noinline)) String f(void) { return "plain"; }`; `f().len()` prints 177655. Also `static Var boxit(int)`, `__attribute__((unused)) static Array items = [1, 2];`, `$scoped(__attribute__((unused)) Var b = 5)`, and `_Noreturn void die(int);` then a plain definition ("does not match prior prototype"). | `_storage_class` (`parse.x:302`) keeps the attribute in the declared type; 4aa5b58 filtered it only in `_declaration_group`. Still in the function return type, `cache.x:327`, and `parse_declaration_argument`. | me |
| A directive group after a governed statement absorbs the following statements. | `if (flag)` / `#if 1` / `a += 1;` / `defer printf(...)` / `#endif`: the defer runs inside the `if` scope. `foreach` body gives `b=3` where `for` gives `b=1`. `if`/`#if`/`a=1;`/`else a=2;`/`#endif` and a `do` ... `while` split the same way are rejected. | `Compiler.parse_governed` (`statements.x:52-75`) keeps parsing while `depth > 0` instead of returning after the governed statement. From c7d8cf7. | me |
| A prefix macro takes the words of an inactive `#if` arm. | zlib's `z_const`: `#if defined(ZLIB_CONST) ...` `#define z_const const` / `#else` `#define z_const` / `#endif`; `struct s { z_const char *p; }` emits `const`, so valid C fails. | `_prefix_macro_words` (`parse.x:271`) emits recorded words; `_prefix_rank` (`compiler.x:1488`) ranks `(const)` above empty. From 55350d0. | me |
| A storage class written literally before the type but after a qualifier is rejected. | `const static int limit = 6;` gives "type: expected scalar type", though C11 6.11.5 allows it. `int static five(void)` and the macro spellings work. Predates this review. | `_declaration_types` (`src/parse.x`) scans qualifiers, then the type, and takes storage words only around the type. | me |
| A macro-supplied `static` in a later position is dropped, so the symbol is exported. | `#define LOCAL static` / `int LOCAL helper(int x)` appears in the header; `const LOCAL int hidden = 1;` likewise. | `_prefix_macro_words` discards storage-class-only macros in qualifier position. | me |
| `($param)[0]` in a macro with an inferred parameter kind is read as a cast. | `macro Expression $first($items) => (($items)[0])`; `$first(numbers)` emits invalid C. | `case <[>:` in `_cast_operand_follows` (`expressions.x:673`) via `_macro_hole_starts_cast_type`. From 0b7fa48. | me |
| A ternary of Symbol literals becomes raw `ulong` bits. | `Var v = c ? <*x> : <?x>;` prints `1904`, tag `ulong`; `return c ? <*y> : <*>;` likewise. | Ternary typing does not keep the Symbol literal type. | me |
| A lexical error inside `#if 0` truncates the translated file with status 0. | `#if 0` / `this isn't code` / `#endif` then `main`: the `.c` holds only its include; C then reports an unterminated conditional. | `_scan_conditionals` (`compiler.x:546`) turns the tokenizer `<error>` into a comment; `scan_status` is not checked. | me |
| `#define NAME "x"` is a String literal regardless of arm or `#undef`. | `#ifdef USE_TEXT` `#define SEP "/"` `#else` `#define SEP 47` `#endif`; `Var v = SEP;` emits `String_new(47)`. `#undef LABEL` then `int LABEL` does the same. | `parse_variable` (`expressions.x:2273`) trusts `object_macros`; `_macro_prefix` reads one token, first definition wins, `#undef` is not recorded. | agent |
| `sizeof` accepts only a unary expression in parentheses. | `sizeof(x + 1)`, `sizeof((long) x)`, `sizeof(c ? 'a' : 2.0)` are rejected. | `_parse_sizeof` (`expressions.x:542-559`). | agent |
| `#if defined(A) && B \|\| defined(C) && D` hides the arm C takes. | The `__cplusplus` / `__STDC_VERSION__` form leaves `modern()` undeclared. | `compiler.x:525` `startswith("if defined <never> && ")` ignores `\|\|`. | agent |
| A string literal adjacent to a macro is rejected. | `printf("%" PRId64 "\n", x)`, `printf(PREFIX "v")`. | Literal concatenation with an identifier. | agent |
| Leading attributes and prefix macros are rejected at block scope and in struct fields. | `__attribute__((unused)) int x;` inside a function; `from-c.md` does not limit them to file scope. | `_test_declaration_start` (`parse.x:1040`). | agent |
| A raw 0xFF byte in code position ends tokenization. | `undeclared_\xff = 1;` gives "unexpected end of file". | A `char` compared with EOF in the tokenizer. | agent |

## Group 2: macro substitution and autodiff

> Fixed 2026-09-17. Generated C is unchanged across `src/` and `lib/`.
> Group 16 removes the per-producer grouping this added.

Files: `src/macros.x` (hole substitution), `lib/autodiff.xmacro`.

| Defect | Reproduction | Cause | R |
| --- | --- | --- | --- |
| Macro `Expr` holes lose their grouping; the book's own guard is wrong. | `idioms.md:42` and `macros.md:249`: `$guard(value > 0)` emits `if(! value > 0)`, so `positive(-3)` returns -3. `$show(1 + 2)` with `$c * 2, -$c, !$c` prints `5 1 2`. `language.md:703` says a hole binds parsed syntax. | Substitution splices the hole's tokens without grouping. | me |
| Autodiff drops parentheses around operands. | `$ad.both() static double f(double x) => log(x + 1.0);` gives d/dx 2 at 1 (exact 0.5); `s *= x + 1.0` gives forward 4, reverse 3; `acosh`, `log2`, `pow`, `/=` likewise. | `ad._raw` (`autodiff.xmacro:163`) and `ad._typed` (`:322`) build `v OP rhs` without grouping operands. | me |
| Forward mode returns NaN where reverse returns the derivative at 0. | `pow(x, 2)` at 0, `sqrt(x) + y` d/dy at 0. | 0 times inf in the table at `autodiff.xmacro:266-272`. | agent |

## Group 3: declarations and generated C

> Partly fixed 2026-09-17: public file objects now publish `extern` in the
> header, and `static const` file objects with runtime initializers build.
> The `_Generic` row needs `src/expressions.x` and moves to Group 4's files;
> the `volatile` row is reverted and needs a decision (below).

Files: `src/generate.x`, `src/cache.x`, `src/transform.x` (volatile locals).

| Defect | Reproduction | Cause | R |
| --- | --- | --- | --- |
| Public file-scope objects are defined in the generated header. | `int counter = 0;` in `a.x` included by `b.x` and `c.x`: link fails with duplicate `_counter`. `Map registry = {};` in one unit: C rejects `Map_new()` in the header. | `_partition_declaration` and `_header_declaration` (`generate.x`); only the tagged-object path emits `extern`. | me |
| `static const` file objects with runtime initializers produce invalid C. | `static const String g = "hi";`, `static const String names[] = {...}`, `static List const items = %(1 2);`. | `cache.x:327,332` filter on any `const`, broader than the object check at `:285-287`. | me |
| An untyped `_Generic` result assigned to `String` stays a raw literal. | `String name = _Generic(s, char *: "charp", default: "other"); name.len();` prints garbage or crashes; `Var boxed = _Generic(s, char *: 1, default: 2);` emits `Var boxed = 1;`. Still open. | `Compiler.convert_expression` (`src/expressions.x`) returns the expression unchanged when the selection has no type. Either convert each association to the target the way the conditional-operator case just above it does, or extend the "cannot convert an unresolved expression" diagnostic to every named x2c type, which is what `language.md` already promises. | me |
| A `volatile` local's address is passed to a non-volatile `self`. | A struct local modified across `try`, then `counter.step()`: clang warns discards qualifiers; undefined behavior (C11 6.7.3). `examples/programs/literate-lisp` hits it. Twelve fixture `cc.stderr` files hold C warnings that no check reads. | The receiver address is taken without the qualifier. | me |

## Group 4: warnings

> Fixed 2026-09-17, all seven rows.

Files: `src/expressions.x` (conversion warnings), `src/regions.x`,
`src/diagnostics.x`.

| Defect | Reproduction | Cause | R |
| --- | --- | --- | --- |
| The conversion warning names a receiver; following it changes the value. | `int width = items.str().len();` warns "remove .str()"; removing it changes 9 to 3. The book says receivers are not reported. | The note survives when the call becomes a receiver (`expressions.x:175-185`), matched structurally at `:1454-1459`. | me |
| "Remove the cast" on a string literal changes a native comparison into a String comparison. | `int native = (char *) "abc" == t;` result changes from 0 to 1. `language.md:2043` documents the cast. | `_warn_unnecessary_cast` (`expressions.x:719-730`). | me |
| The printf warning fires when the format is not a literal; the suggested edit fails to translate. | `printf(fmt, v.str())` and `printf(FMT, v.str())`. | `expressions.x:241-248` does not check for a literal format. | me |
| Method-form printf warnings use the wrong argument index. | `"%s-%s".printf(v.str(), w.str())` warns only on `w`; `b.printf("%s", v.str())` does not warn. | The table offsets ignore the dropped receiver (`expressions.x:187-196`). | agent |
| Region `after-free` false positive on goto cleanup. | `Array a = [1]; if (err) goto fail; a.free(); return 0; fail: a.free();` | `regions.x:517-520` and `_walk_block` never clear `dead` after `return`/`goto` or at a label. | me |
| Region false positive when a Scope local is destroyed and reused. | push/pop/destroy `s`, then `s = Scope.new()`, push, `Array b = [1, 2]`, pop, `c = b;`. | `_owner` caches `slot.owner`; `_assign` never resets it (`regions.x:195-202, 538-550`). | me |
| Identical warnings print twice; `language.md:2757` says they do not. | `keep2(a, a);` in a `$scope()` prints the region warning twice. | f6ef305 removed the error-path dedupe; warnings never had one. Decide which the book states. | me |

## Group 5: cleanup control flow

> Fixed 2026-09-17. `matchcases` is a break boundary, so an arm's `break`
> leaves the match without leaving a cleanup region.

Files: `src/cleanup.x`, `src/transform.x` (match lowering).

| Defect | Reproduction | Cause | R |
| --- | --- | --- | --- |
| `break` in a `match` arm in a function with `defer` aborts. | `defer n++; match (v) { case %(keep): break; default: n = 1; }`: the second call aborts with "uncaught exception cleanup chain imbalance". `match.md:265` documents `break` in an arm. | Not isolated. | me |

## Group 6: Error, Scope, and Context runtime

> Fixed 2026-09-17. The handler stack holds only live registrations again,
> and a running arm's caught error lives on a separate per-thread chain.

Files: `lib/error.x`, `lib/scope.x`, `lib/context.x`, `lib/logger.x`.

| Defect | Reproduction | Cause | R |
| --- | --- | --- | --- |
| Popping an outer observer inside a catch arm aborts; the book says the selected catch is removed before its body runs. | `h = Error.push(obs, void); try raise %(bad-arg); catch %(bad-arg): Error.pop(h);` gives "Error.pop out of order", status 134. | dd33e20 made `x2c_error_catch_detach` mark the handle instead of unlinking it (`error.x:220`). Regression from 2026-09-17. | me |
| An observer that raises under `defer Error.pop` aborts; without the defer it leaks. | `try { h = Error.push(raising_obs, void); defer Error.pop(h); Error.raise(<usr>, NULL); } catch %(bad-state *d): ...` aborts. `lib/thread.x:137,140` uses this pattern, so a raising Logger sink in a worker aborts the process. | Nested `_dispatch` resets `handler_top` and `dispatch_saved` (`error.x:1080, 1100`). | me |
| `Error.snapshot` of a wide value leaks a Scope when the active slot is empty. | `Scope slot = NULL; Scope.push(&slot); Error.snapshot(b); Scope.pop();` reports a Scope leak at exit. | `_snapshot_value` pushes a local copy of the slot (`error.x:667-669`). | me |
| A shutdown hook registered during shutdown never runs. | A hook calling `Scope.shutdown_hook(late)`; `late` never runs. | `Scope_shutdown` walks from the old count (`scope.x:982`). | me |
| `exit()` inside a Context with a pushed slot aborts; inside `Error.push` callbacks it reports false leaks; inside a sink during `log_fatal` it aborts. | `Context c = Context.open(); Scope s = NULL; Scope.push(&s); Scope.malloc(8); exit(2);` gives 134. | `Context.close` pops the user's slot (`context.x:359-360`); `_region_destroy` only in a defer (`error.x:1090`); `Logger.free` during delivery (`logger.x:670`). | agent |

## Group 7: strings, symbols, and regex

Files: `lib/common.x` (slice count), `lib/string.x` (except escapes),
`lib/string-number.x`, `lib/atom.x`, `lib/regex.x`, `lib/scan.x`
(`scan_atom` only).

| Defect | Reproduction | Cause | R |
| --- | --- | --- | --- |
| Empty stepped slices return one element; some read out of bounds or abort. | `"abcdef"[2:2:2]` is `"c"`; `%(a b c d)[1:1:3]` is `(b)`; `"abc"[3:3:2]` aborts on the `_finish` assertion; `"01234"[-100::-2]` returns the byte before the string. `Array` is correct. | `common.x:865-867` count `(stop - start - 1)/\|step\| + 1` truncates toward zero; `string.x:722` and `list.x:827` trust it. | me |
| `String.map` aborts when the callback returns a value with low byte 0. | `"abc".map(to256)` aborts; the doc promises `<bad-result>`. | `string.x:878` tests the `int` before truncating to `char` at `:881`. | me |
| `String.getindex` sign-extends, so byte 0xFF equals "out of range". | `String.new("\xff\xc3")[0]` is -1, same as `[5]`; `foreach (int b, s)` yields -1, -61. Platform-dependent. | `string.x:581` returns signed `char`. | me |
| `find_all` returns empty for a negative start. | `"abcabc".find_all("c", -3, -1)` is `()`; `find_within` gives 5. | `string.x:546` loops `while (pos >= 0)` before normalizing. | me |
| `try_long` accepts whitespace and a sign after `0b`/`0o`. | `"0b 101"` gives 5; `"0b-0"` gives 0; `"0x 1f"` is rejected. | `string-number.x:54` uses `strtoul`. | me |
| `scan_atom` ignores a backslash in the first byte. | `scan_atom("\\(abc")` is 1; `scan_atom("x\\(abc")` is 6. | `scan.x:645` starts the escape loop at 1. | me |
| `Atom` repr does not read back for spellings that start with `<`. | `Atom.intern("<a")` repr `<a`; `Lisp.read` raises `<incomplete>`. Also `<ab`, `<a b`, `<"`. | `atom.x:131` escapes a leading `<` only when a `>` follows. | me |
| `String.partition` docstring says the first element is empty on a miss; the last two are. | `"abc".partition("x")` is `("abc" "" "")`. | `string.x:980-982` wording. | me |
| Regex group repetition overflows a worker thread's stack below the documented limit. | `Regex.compile("(?:a\|b)*").match("a".repeat(1800))` in `Thread.start` exits 138. | About 8 frames per repetition; macOS threads get 512 KiB (`thread.x:200`); `_DEPTH_LIMIT` (`regex.x:404`) assumes more. | me |

## Group 8: collections and Var

> Fixed 2026-09-17. Row 1 needed no String-side change, and row 7 is
> documentation only, as decided.

Files: `lib/array.x`, `lib/array-generics.xmacro`, `lib/list.x`,
`lib/list-generics.xmacro`, `lib/dispatch.x`, `lib/map.x` (docs).

| Defect | Reproduction | Cause | R |
| --- | --- | --- | --- |
| `Array.join` aborts on an empty String element. | `["", "a", ""].join(",")` raises uncaught `<bad-arg>` from `Buffer_write`. | `array.x:716` passes `elem.string()`, NULL for `""`. | me |
| `setslice` and `remslice` read the end bound differently from `getslice`. | `a[1:-1]` is `[1, 2, 3, 4]`; `setslice(1, -1, [9])` leaves `[0, 9, 4]`; `remslice(1, -1)` removes `[1, 2, 3]`. Applies to typed arrays and `splice`. | `_core_normalize_bound` (`array-generics.xmacro:222-228`). | me |
| Numeric repr prints wrong text and does not read back. | `<u32>` 0xFFFFFFFF prints `-1`; `<i16>` -1 prints `0xFFFFFFFF`; `1e-9` prints `0.000000l`; `<u8>` 0 embeds NUL. `collections.md:89` says the form round-trips. | `dispatch.x:500-509` and the copy at `:624-640` use `%d`, `%04X` on a widened value, and `%lfl`. | me |
| `List` equality and hash compare element bits; the book says content. | `%(${Var.box_long(5l)})` built twice: `==` 0, `compare` 0, Map lookup misses; equal Arrays inside Lists: `<=` and `>=` 1, `==` 0. `map.x:255,280` say Array/Map keys compare structurally. | `list.x:889-908`. Needs a decision (below). | me |
| `List.get` truncates a large integer key. | `%(1 2 3).get(Var.box_long(4294967296l))` returns 1. | `list.x:749` narrows to `int`. | me |
| `ListDbl` holding inf or NaN cannot convert back. | `ListDbl` with `1.0/0.0` cast to `List` and back raises `<no-convert>`. | `Var.box_f64` tags inf/NaN separately; `List.$lower` accepts only `<f64>`. | me |

## Group 9: Match, Lisp, and Func

Files: `lib/match.x`, `lib/machine.x`, `lib/lisp.x`, `etc/init.xlisp`,
`lib/func.x`.

| Defect | Reproduction | Cause | R |
| --- | --- | --- | --- |
| The Match plan cache returns stale plans after `List.pool_release`. | Loop 2000 times: `List.pool_retain()`, build `(foo n ?x)` and `(foo n bar)`, `try_match`, `pool_release()`: 1999 wrong. `memory.md` recommends this bracket. | Cache keyed by `pattern.u64` (`match.x:1946, 2093`); cells are reused. | me |
| Lisp `car`/`cdr` on a non-List reads raw memory; `(cdr "x")` segfaults. | `lisp.eval_string("(cdr \"x\")")` exits 139; `(car "x")` returns `<0x...78>`. | `Var.car`/`Var.cdr` do no tag check (`list.x:287-289`), bound directly in `init.xlisp:9-10`. | me |
| Lisp numeric `=`, `<`, `<=` use the Var total order. | `(= 1 1.0)` is `()`; `(= 5 (- 3000000005 3000000000))` is `()`; `(< 1.0 1)` is `true`. | `lisp_compare` returns `a.compare(b)` (`lisp.x:619`). Needs a decision (below). | agent |
| Func rejects multi-token return types; a direct binding aborts before `main`. | `static unsigned char f(unsigned char a) => a; Func f = f;` gives "raise before initialization", 134. | `func.x:268` pattern allows one return token. | me |
| An anchored star compares a List anchor by bits. | `%(1 ($w1) 2)` against `%(*a ($w2) *b)` with equal wide ints: machine 0, reference 1. | `_bits_unique` treats `<list>` as unique (`match.x:1035-1043`). | me |
| The two replacement paths disagree on unbound `*x`; `List.replace` with nil bindings keeps binders. | `List.replace(%(a *m b), %((?x 1)))` gives `(a b)`; with nil bindings `(a *m b)`. The doc says missing binders are retained. | `_capture_replace` (`match.x:782`) and early return at `:751-755`. | me |
| A leading binder on a multi-argument guard becomes an alternative. | `(q (!set ?w a b))` matches `(q c)`; `(?y (!not ?y))` matches `(a a)`. | `_normalize_pattern` (`match.x:334`). | me |
| Deep inputs crash instead of raising. | `List.search` on 80,000 elements exits 139; `Lisp.read` of 100,000 nested parens exits 139. | Recursion at `match.x:849, 865, 887` and `lisp.x:361-447`. | agent |
| Repeated star binders use two equality rules. | `(*a b *a)` rejects equal wide ints; `(*a b *a c)` accepts them. | `machine.x:310-354`. | agent |

## Group 10: process, path, JSON, diff

> Fixed 2026-09-17. `copy_file` onto the same file is a documented no-op.

Files: `lib/process.x`, `lib/path.x`, `lib/file.x` (error details),
`lib/json.x`, `lib/diff.x`.

| Defect | Reproduction | Cause | R |
| --- | --- | --- | --- |
| An empty `input` gives the child the parent's stdin. | `%(cat).job().options({input: ""}).output()` prints the parent's piped stdin; with a slow producer it hangs. | `process.x:217` tests the NULL empty String. | me |
| A NUL byte in captured output makes `status()` raise, then loses the output. | `%(printf "a\\000b").job().status()` raises `embedded NUL`; the next `status()` is 0 and `output()` NULL. | `_finish` sets `finished` before `string_close` raises (`process.x:271-283`). | me |
| A failed start leaks two descriptors each time. | 50 failed starts with `input` and a bad `stderr` path: fds 3 to 103. | fds opened before the closing defer (`process.x:217-238`). | me |
| Child stdio is wired wrong when the parent has fd 0-2 closed. | `./p <&-` gives NULL output for `%(cat)` with input. | `dup2` order in `_child` (`process.x:154-157`). | agent |
| `$auto` Job cleanup blocks if the child ignores SIGTERM. | `trap '' TERM; sleep 4` holds the block 4 s. | `process.x:483-487`. | agent |
| `Path.copy_file(p, p)` empties the file. | Copy a "hello" file onto itself; it reads back NULL. | `path.x:409` opens the target with `"wb"` first. | me |
| `copy_tree` into its own subtree recurses until ENAMETOOLONG. | `t.join("x").copy_tree(t.join("x/y/copy"))`. | `path.x:433-435` lists after creating the target. | agent |
| Reading a directory raises `io-fail` without `path`. | `Path.read_text(dir)`, `Json.read_file(dir)`, `copy_file(dir, t)` (which also leaves an empty target). | Raised by `_check_read` (`file.x:101-105`), outside the path error owner. | me |
| `Path("..").extension()` is `"."`. | Also `/x/..`; `stem()` is `"."`. | `path.x:75-86`. | me |
| The JSON writer emits duplicate names. | A Map with `"a"` and `<a>` writes `{"a":1,"a":2}`. | `json.x:492-511` sorts names without detecting collisions. | me |
| `Diff.unified` splits hunks that `diff -u` merges. | Lines 1..12 with 2 and 9 changed: two hunks; GNU diff prints one. | `diff.x:151` uses `<` where `<=` is needed. | agent |
| `Path.glob_match` is exponential on repeated stars; `glob` differs from the shell. | `*a*a*a*a*a*a*a*a*a*a*b` on 40 `a`s takes 17 s. `src/*/`, `src//*.x`, and `[]a].x` return `()`. | Recursive backtracking (`path.x:275-280`); `path.x:237, 320`. | agent |

## Group 11: driver, build, and project

Files: `src/build.x`, `src/project.x` (planning and manifest), `src/main.x`,
`src/cli.x`, `src/utils.x`, `src/script.x`, `src/bootstrap.x`, `src/deps.x`.

| Defect | Reproduction | Cause | R |
| --- | --- | --- | --- |
| A build with a build directory can exit 1 and print nothing. | `env -u PATH x2c build --plain --build-dir bd --output o hello.x` prints only the Translate line and exits 1; an execute-only `--cc` wrapper and every manifest build hit it; concurrent builds in one project do too. | `build.x:459` `if (!ok) return 1;` when the fingerprint cannot read the compiler or `.i`. | me |
| `x2c run` with `%` in a path segfaults. | `x2c run -q 'r%s.x'` exits 139. `translate` was fixed by d17c1b5. | Paths pasted into printf formats: `build.x:55`, `script.x:74, 98`, `install.x:219`, `bootstrap.x:115`. | me |
| `x2c new ""` overwrites a project in the current directory and exits 0. | In a directory with `x2c.toml`, `src/main.x`, `.gitignore`: all replaced; prints `created (null)`. `cli.md` says it never overwrites. | Empty operand becomes a NULL Path (`project.x:703-712`). | me |
| `build -###` and invalid manifests install packages and write `x2c.lock`. | `x2c build -###` with `[dependencies]` installs and locks; `--target bogus` errors but installs first. | `_resolve_dependencies` (`project.x:668`) runs before validation and ignores `dry_run`. | agent |
| `build -###` fails on a manifest with a static-library dependency. | "input does not exist: .x2c-build/libcore.a", exit 2. | `build_check_input` (`build.x:203`) during a dry run. | agent |
| `X2C_HOME` through a symlink or a relative path links the wrong stage runtime and loses the prelude; `X2C_HOME=.` means no home. | `X2C_HOME=$PWD/fakehome fakehome/builds/1/x2c env runtime_lib` names `builds/0`; translations are 5x slower; package installs fail at `lib/iter.x:93`. | `utils.x:110, 124` and `collect.x:625` use the unresolved root. | agent |
| A package unit fails to translate when lib `.xi` interfaces are missing. | `translate --package-dir pkgsrc pkgsrc/greet/src/greet.x` in a home without `builds/0/lib/*.xi`: "'as' applies only to a Var adoption". | Not isolated. | agent |
| `--dump-cpp` writes to stderr. | `x2c translate --dump-cpp hello.x 2>/dev/null \| wc -c` is 0. | `main.x:109`. | me |
| `--target` and `--profile` are ignored with explicit inputs; `-c` is ignored for manifests. | `x2c build -q --target nonexistent --output o hello.x` exits 0. | `main.x:416` rejects only `--manifest-path`; `project.x:503` resets `compile_only`. | me |
| `--profile` does not apply to dependency targets. | `x2c run --profile release` prints `core=1`, expected 100. | `project.x:532` applies it only when `chosen`. | agent |
| A warm `x2c script` run preprocesses and links on every run. | `run_script -v args.x` on an unchanged script reports `up-to-date translate` and `up-to-date compile`, then runs `cc -E` for the depfile and links `run.<pid>` again. Found when `unittest/probes/run-cli-boundary.sh:1304` was made able to fail; that assertion expected no rebuild step at all and is now narrowed to translate and compile. | `src/build.x` fingerprints through a fresh `.i` and republishes the run image. | me |
| A script edited during its build keeps running the old code. | Edit a script 0.2 s into `x2c script --rebuild`; later runs print the old text. | `Build.publish_script` (`build.x:905-928`) fingerprints files after the build. | agent |
| `x2c new <symlink>` names the target after the destination. | `x2c new linkempty` writes `[target.realempty]`. | `Path.absolute` resolves links (`project.x:704`). | agent |
| A non-canonical `X2C_HOME` compiles the runtime into every script. | 49 runtime modules translated per script, 3.4 s. | `Build.script_helpers` (`build.x:884-886`) uses `x2c_get_root()`. | agent |
| Manifest arrays across lines and `--jobs=2` / `--out-dir=out` are rejected. | Valid TOML multi-line `sources`; `--color=never` is accepted. | `_string_array` (`project.x:155`); CLI option parsing. | agent |
| `deps.x` pushes the last word before a newline twice. | The doc comment records the bug. | `deps.x:51, 63`. | agent |

## Group 12: install and packages

Files: `src/install.x`, `src/project.x` (lockfile), `packages/package.mk`.

| Defect | Reproduction | Cause | R |
| --- | --- | --- | --- |
| Pinned dependencies ignore the lockfile's url and sha256 and rewrite the lock. | Build against one index; point another index at a different archive with the same version; remove and rebuild: new code runs, `x2c.lock` changes. `cli.md` and `packages.md` promise the same packages. | `_lock_satisfies` and `_resolve_dependencies` compare name and version only (`project.x:596-635`); `install_require` (`install.x:295`) resolves from the index. | agent |
| `x2c run` holds the packages lock while the program runs. | A 15 s program that needed an install blocks `x2c install` 11 s. | `_locked_packages` (`install.x:183-198`). | agent |
| `install` and `list` abort with 134 on bad inputs; one bad marker breaks `list` and builds. | A package directory without `src/`; a `BUNDLE.json` that is not JSON; an installed marker that is a JSON array. `cli.md` says refusals exit 2. | Uncaught errors at `install.x:131, 144, 175-176`. | agent |
| Installing a package directory archives stale `builds/*.c`. | `builds/old.c` defining a symbol appears in `libgreet.a`. | `install.x:151-161`. | agent |
| A failed install leaves `.install.<pid>/` with the download. | After a sha256 mismatch. | `x2c_driver_error` calls `_exit`, skipping the defer (`install.x:265`). | agent |
| Install, remove, and new print receipts on stdout, mixed with `x2c run` output. | `x2c: installed ...` precedes program output. `cli.md` says standard error. | `install.x:251, 324`, `project.x:729`. | agent |
| Reinstalling from a local path loses the version; concurrent removes both succeed. | `greet 1.0 source` becomes `greet - source`. | `install.x:244-248, 316-320`. | agent |
| Remove the `.link` format (decided 2026-09-17). | Switch `package.mk` and `install.x` to `.native.rsp`; note the rebuild for outside packages in the release notes. | Two formats for one link record. | n/a |

## Group 13: tooling, gates, and release

> Fixed 2026-09-17 except the `make debug` and `autocrlf` rows.

Files: `tools/`, `site/public/install.sh`, `.github/workflows/`,
`unittest/benchmarks/`, `unittest/probes/`, `examples/check.sh`, `etc/x2c.mk`,
`Makefile`.

| Defect | Reproduction | Cause | R |
| --- | --- | --- | --- |
| `gate-state.py ensure` records the tree after the gate, so edits during the gate are recorded green. | An edit made while `make agent-pr-check` runs; `check` then prints `valid`. | `cmd_ensure` digests after `run_gate` (`gate-state.py:334-337`); take the digest before and record only if unchanged. | me (read) |
| `install.sh` deletes installed packages when an upgrade fails partway. | `packages` is moved into the temp tree (`install.sh:88-90`); a failing `mv` at `:92` exits and the trap removes it. | Move packages last, or outside the trap's directory. | me (read) |
| Four benchmark scripts cannot compile. | `unittest/benchmarks/run-iter-hot-paths.sh` fails with `'x2c.h' file not found`, so `make bm-iter` and `bm-all` fail; also `run-match-capture-benchmark.sh`, `run-match-cache-benchmark.sh`, `run-func-apply-direct.sh` (orphaned). | `-iquote $ROOT/include` after 9e409aa moved headers to `include/x2c/`. | me |
| `check-doc-examples.py` ignores a sample's exit status. | A sample that prints the expected text and aborts passes. `x2c ignore` (space) skips silently. | `check-doc-examples.py:147, 184-186`. | me (read) |
| `check-conformance-coherence.sh` passes when the compiler crashes or prints nothing. | `X2C=/usr/bin/false` prints "agree (0 units)". | `\|\| true` at lines 32, 36. | agent |
| `make doc-check` needs `builds/0` and misreports its absence as stale docs. | Fresh clone: "module catalog is stale" plus a traceback. | No `build` prerequisite (`Makefile:235`). | agent |
| The release workflow never detects mismatched tarball versions. | `sort -u` separates with newlines; the `case` looks for a space. | `release.yml:129-134`. | me (read) |
| gate-state can be bypassed by an excluded `GNUmakefile`, `MAKEFILES`, `assume-unchanged`, `skip-worktree`, or `autocrlf`. | Each reports `valid` after a change. | Runs `make` without `-f Makefile`; trusts `git diff --name-only`. Low: needs deliberate setup. | agent |
| Negative probe assertions never fail. | A bare `! grep ...` statement is exempt from `set -e`, so the assertion cannot fail the run. Fixed in `run-error-floor.sh` by Group 6 (deaf794); still open at `run-cli-boundary.sh:96, 1304, 1339, 1341` and `run-preprocessor-boundary.sh:112`. The piped forms at `run-cli-boundary.sh:1076`, `run-preprocessor-boundary.sh:127`, and `run-raw-symbol-sweep.sh:52` are inside conditions and are fine. | `set -e` ignores a command whose status is inverted. | me |
| Smaller tooling defects. | `install.sh --help` truncated or empty under `sh -s`; `etc/x2c.mk` includes relative to the includer; `make debug` rewrites tracked `etc/build-mode`; `run-suite-coverage` compares counts only; `examples/check.sh` does not scan `examples/scripts/`. | Individual. | agent |

## Group 14: documentation, plans, examples, fixtures

Files: `docs/`, `agents/`, `plans/`, `site/src/`, `examples/`,
`unittest/compiler-fixtures/`, `lib/*.x` comments.

- Book samples now trigger the unnecessary-conversion warning, and
  `memory.md:371` says its sample compiles without warnings (line 388 warns):
  `collections.md:332, 782`; `iteration.md:237, 348, 349`; `memory.md:276,
  388`; `system-macros.md:41, 171`; `scripting.md:94`;
  `library/modules/process.md:332`; `library/overview.md:64, 186, 195-196`;
  `protocols.md:422`; `symbols.md:121, 289`. (me for `memory.md`, agent for
  the rest)
- `memory.md:364` describes `unbalanced` as release in another block; the
  check reports a region with no release in its opening block.
- `language.md:2389` prints `Var.integer()` (long) with `%d`.
- `from-c.md:185` says the driver has four commands; `--help` lists 11.
- `language.md:2757` dedupe sentence (see Group 4).
- `site/src/pages/index.astro:201` links the 0.12.0 APE, which later releases
  do not publish.
- `agents/adapters-macros-decorators.md:247` names `examples/decorators.x`
  (now `examples/magic/decorators.x`); lines 133-140 and 206 cite stale or
  out-of-range lines. `agents/replacing-manual-ast-walks-with-match.md:257`
  names emit.x helpers now in `src/type.x:78, 95`. `check-docs.py` does not
  audit these files.
- Plans: `region-warnings.md` and `research-agenda.md` are finished and
  should be archived; `emit-cleanup-lowering.md` Phase 1 landed (68eea0a) and
  its tables are stale; `x2c-c-on-ramp.md:3` cites commits not on main
  (landed as 8c6eccf, 6cdd7c2); `x2c-header-collection-gaps.md:63` relies on
  the removed `_skip_empty_macro`, and its "fixed 2026-09-17" leading
  attribute row is the Group 1 miscompile.
- Stale "snapshot" comments at `lib/common.x:483` and `lib/atom.x:34`; probe
  name `run-symbol-snapshot.sh` now compares live symbols.
- `examples/power/shared-threads.x:54` prints `List.len()` with `%zu`;
  `examples/README.md:136` says seven adapters (the table lists eight);
  `examples/packages/README.md` omits SQLite; raylib emits three
  unnecessary-conversion warnings (`examples/texture-sheet.x:119`,
  `tests/test-raylib.x:181, 258`); `packages/torch/Makefile` defaults
  `TORCH_PYTHON` to a path under `/Users/gary`.
- Seven fixtures pin runtime-library line numbers (`var-custom-unaligned`,
  `var-i48-overflow`, `var-invalid-tag`, `var-truthy-void`,
  `atomic-container-missing-source`, `class-repr-signature`,
  `protocol-typedef-inherited-invalid`); b25e4b8 existed only to update three.
  `protocol-adoption-native-parse` duplicates `protocol-native`.
- Tests that assert almost nothing: `test-scope.x:232` ends with
  `EXPECT_TRUE(1)`; `test-index-slice.x:80` is empty; `test-func.x:58`
  checks only non-null.

## Group 15: member access, class registration, and one test

Files: `src/expressions.x`, `src/parse.x`, `lib/error.x`, `lib/dispatch.x`,
`src/compiler.x`, `etc/builtin-macros.xmacro`, `unittest/test-file.x`.

Found by the 2026-09-17 dogfooding survey, which
[x2c-dogfooding-remediation](x2c-dogfooding-remediation.md) carries; these
rows are compiler work and stay here. Reproduced at ecdcea9 with
`builds/0/x2c`.

| Defect | Reproduction | Cause | R |
| --- | --- | --- | --- |
| `.` through a pointer to a pointer typedef calls the wrong pointer and aborts at runtime. | `static int first(List *c) { return c.car().int(); }` emits `Var_int(List_car(c))`; only `cc` warns, and running aborts with `<no-convert>`, status 134. | An unresolvable receiver passes through undiagnosed; `.` reaches one pointer level, so this needs a diagnostic or a second dereference. | me |
| `.` to a member of an anonymous union or struct through a pointer emits uncompilable C. | `unittest/compiler-fixtures/class-layout.x:17,18`; the member is emitted with `.` and the C compiler rejects it. | Same path as the row above: an unresolvable member is emitted verbatim. | me |
| The 32nd record or heap class aborts during startup with an undecoded code. | 32 `class Pn { int x; int y; };`, never boxed: `x2c error floor: code 0x12e4d3e60a58: raise before initialization`. | `lib/error.x` prints the raw code in the floor path while the ordinary report decodes it; the raise in `lib/dispatch.x` carries the class name and the 32-row limit, and all of it is lost. Decode it and name the registry. | me |
| `class C enum { ... };` fails and no enum spelling works. | `class Color enum { RED, GREEN };` gives "enumerator 'RED' is already bound in this scope"; naming a declared enum gives "Var representation has no fixed tag". | The enumerators are bound by the capture and again by the re-emitted declaration. Support it, or reject it with a message that names the limit instead of blaming the enumerator. | me |
| `protocol Var(Compiler);` spends a descriptor row nothing can select. | 31 classes plus this shape aborts as above; the boxed value reports `tag=p48 custom=-1`. | `src/compiler.x:151-156` boxes raw `p64`, so the registered row is unreachable. Use `protocol Var(Compiler) as void *;`, the spelling `lib/iter.x:93` and `lib/logger.x:108` already use, and keep the converters. | me |
| `unittest/test-file.x` releases the caller's region on eight failure branches. | `$test.scoped()` already defers a release; lines 187, 196, 202, 290, 405, 427, 447, 474 call `Scope.release()` again before an early `return`. | Delete the eight explicit releases. Latent: the branches run only after an `EXPECT` already failed. | me |
| `x2c` parses `#include` inside a conditional branch that is false. | A header with `#if defined(X2C_NEVER_DEFINED_MACRO)` / `#include "never.h"` / `#endif` fails on the contents of `never.h`. | This is why a real third-party header cannot be made visible to x2c: pointing the compiler at `uv.h` dies inside `uv/win.h`, which sits behind `#if defined(_WIN32)`. It keeps ~190 package `->` sites that `.` would otherwise replace. Scoped in [x2c-header-collection-gaps](x2c-header-collection-gaps.md). | me |

Two diagnostics in the same area: the "managed initializer requires Cleanup
participation" message points at the token after the declaration, because
`src/parse.x:1257-1265` reports with an already-advanced token; and defining a
method on an imported package type fails with "parse: missing closing
parenthesis" pointing at a parameter name.
## Group 19: gaps found while fixing Groups 3, 5, and 7

Files: `src/transform.x` or `src/expressions.x` (row 1), `src/type.x` (row 2),
`src/cleanup.x` (row 3).

| Defect | Reproduction | Cause | R |
| --- | --- | --- | --- |
| An expression-bodied `void` function emits `return <expr>;`. | `static void Counter.step(Counter *self) => self.value++;` generates `return self -> value ++;`, which clang rejects with `-Wreturn-mismatch` (an error). | The arrow body always emits a return. | agent |
| `const` on a named x2c type loses its methods. | `static const String g = "hi"; g.len();` fails with `type (const "String") has no method text/len`. | The qualifier is part of the looked-up type. | agent |
| `_changed_name` misses indirect writes, so a local written only through a pointer is not preserved across a transfer. | `int *p = &x; try { *p = 5; f(); }` does not qualify `x`; today such locals are `volatile` only when a catch arm happens to write them by name. | `src/cleanup.x` inspects direct assignments to a name. Latent, and the reason the Group 3 `volatile` narrowing was unsafe. | agent |
| A compact Atom does not round-trip through `Var.repr`. | `Atom.intern` returns an immediate `<symbol>` for short spellings, so `Var.repr` dispatches to Symbol's repr: `Atom.intern("va_arg").repr()` gives `<"va_arg">`, which reads back as a Symbol with different bits; `"a b"` raises on read. General to compact atoms, not to the leading `<` that Group 7 fixed in `Atom.write_repr`. | Dispatch picks the repr by representation, not by the value's origin. | agent |
| `String.parse_char` accepts an octal escape above a byte. | `"'\\400'".parse_char()` returns 256. The Simplify session rejected `\400` in the scanner and in `String.unescape`; this entry point still accepts it. | `lib/string.x` decodes the escape without the range check. | me |

## Group 18: merge the two readable-format owners

Files: `src/transform.x`, `src/expressions.x`.

Group 4 narrowed the printf-family warning to a format the transform can
read, adding `_static_printf_format` (`src/expressions.x`) beside the existing
`_printf_static_format` (`src/transform.x`). Both now describe the same set: a
quoted C literal, the cached canonical String, or the `String_new` of one.
Give them one owner. Neither session could do it, because the two files were
held by parallel sessions; take it with whichever of the two lands last.

## Group 16: one owner for precedence grouping

> Fixed 2026-09-17. `src/emit.x` owns precedence grouping; the autodiff and
> macro producer-side grouping is deleted, and generated C for `src/` and
> `lib/` is byte-identical (`builds/0 == builds/1`, 178 files). Gary decided
> 2026-09-17 to keep the `Expr` decorator's explicit `(parens ...)` in
> `src/macros.x`: it is redundant for emission but is a documented AST
> guarantee in `docs/src/reference/language.md`.

Files: `src/emit.x`, then `lib/autodiff.xmacro` and `src/macros.x` cleanup.

Nothing inserts parentheses by precedence, so every producer of canonical AST
must remember grouping for itself. Group 2 fixed macro holes (`src/macros.x`)
and autodiff (`lib/autodiff.xmacro`) separately; a third case is still open:
the book's `macro Expression $twice($value) => ($value + $value)` drops its
parenthesized body at definition, so `$twice(21) * 2` emits `21 + 21 * 2` and
gives 63 instead of 84. Compile-time Lisp forms have the same exposure.

Decided 2026-09-17: one precedence-aware `parens` insertion in `src/emit.x`
(the `op`, `cast`, and postfix cases and `_op_spine`) owns grouping, and the
per-producer bookkeeping Group 2 added to `lib/autodiff.xmacro` comes back out.
Sequence it after Group 1 and Group 2 land, since Group 1 owns
`src/expressions.x`. Verify with `make stage-1` plus
`tools/check-generated-stages.sh builds/0 builds/1`: Group 2 changed no
generated C, so this change should be inspected the same way, and any C
that does change must be reviewed line by line.

## Group 17: Pool as the public canonical-pool surface

Files: `lib/pool.x`, `lib/string.x`, `lib/list.x`, callers in `lib/thread.x`,
`lib/logger.x`, `lib/error.x`, `lib/context.x`, `lib/split.x`, and the memory
and symbols chapters.

`String.pool_*` and `List.pool_*` are both thin wrappers over the same
`x2c_pool_values_*` functions, so the pool is already shared; the Simplify
session removes the `List.pool_*` spelling first. The operation belongs to
neither type.

Decided 2026-09-17: move the thread-active bracket onto a public `Pool`
surface (`Pool.open`, `Pool.close`, `Pool.current`, `Pool.detach`, with the
named form) and take it out of the `String` namespace, adding
`docs/src/library/modules/pool.md`. The existing instance methods
`Pool.retain(inner)` and `Pool.release(inner)` build a child without making it
thread-active, so the bracket needs distinct verbs; decide then whether the
instance forms stay public. `Context` stays the aggregate that owns a Scope, a
pool, and Error and Match state, and the memory chapter should say so; the
bracket does not move onto `Context`, which is itself a consumer of it
(`lib/context.x:128`). Both changes land before 0.15.0, so one set of release
notes covers them.

## Assigned elsewhere

The "Simplify x2c source" session owns these, by the 2026-09-17 handoff:
`01.5` rejected (`lib/scan.x:584-589`); `%"a\400b"` compiler crash and
`String.unescape` NUL (`scan.x:301-306`, `string.x:1205-1215, 1282`);
`#pragma private` declarations published in `.xi` (`src/collect.x:219-254`);
`0o17` literals; package import with a runtime include; relative paths
resolved against the root; and reproduction of install-root-dependent tag
numbers. All of these landed on main in `ecdcea9..4a003c1`.

Tag numbers depend on the install root, reproduced there and still open: the
same file translated through a symlinked root tags `SourceView` as
261698358342 or 212421573704 and `Job` as 244620705480 or 253728524614.
`_sdk_type_tag_name` (`src/macros.x:285-296`) hashes the display path, and
`Compiler.display_path` strips the root only when it is spelled exactly as
`X2C_HOME`, never through `home_portable_path`. That session also reported,
unfixed: `%"a\0b"` compiles silently to `"ab"`; a malformed escape reports
"unexpected end of file" instead of naming the escape; `%"0${text + 2}"`
emits C that does not compile; generated declaration-default rows are
recorded unfiltered; `architecture.md` still says covered `.x` includes are
skipped; and the book documents neither `0o` nor `0b` as source syntax. The
public names removed there (`List.pool_retain`, `List.pool_retain_named`,
`List.pool_release`, `List.pool_detach`, `List.pool_current`, `Iter.reduce`,
`List.reduce`, `Array.reduce`, `Var.truthy`) need a 0.15.0 release note. It also removes `List.pool_*`, `Iter.reduce`, and `Var.truthy` in
favor of `String.pool_*`, `Iter.foldl`, and `Var.truth`.

## Backlog

Open questions with no owner yet, recorded so they are not lost:

- **The API reference generator drops the rest of a file after a `<(>`
  literal in an expression body.** Converting
  `Compiler.local_macro_form_is_definition` (`src/macros.x`) to a `=>` body
  cut `docs/src/internals/compiler-api/macros.md` from 28 documented
  callables to two, silently and with `make doc-generate` exiting 0; only the
  gate's later staleness check noticed. The body compares a token against the
  Symbol literal `<(>`, which `tools/x2c_source.py` reads as an unbalanced
  parenthesis. A sibling function two declarations below has used a `=>` body
  all along without a `<(>` and is unaffected. Reproduced by the review
  author at 93a42de5; the conversion is reverted with a comment saying why,
  so the page is whole. This is the regex pseudo-parser that
  [x2c-lint-and-format](x2c-lint-and-format.md) proposes to replace, and it
  is a concrete argument for doing so.
- **A namespace call does not resolve inside a macro template.**
  `Block.new(...)`, `Var.new(...)`, `Bytes.new(...)` and the `Scope.*` calls
  are reported as `type () has no method new` at
  `lib/array-generics.xmacro:193`, so the generics templates must keep the
  C-style `Block_new(...)` spelling for the twelve calls that have no
  receiver. Reproduced by a Phase 8 agent at that site; not rerun by the
  review author. A dotted call on a *receiver* inside a template works, which
  is what made the eleven converted sites possible.
- **The `in` operator accepts a narrower left operand than an ordinary
  argument.** `%"k" in m` and `i++ in a` both fail with `parse: expected ')'`
  at ecdcea9+, while `m.contains(%"k")` and `a.contains(i++)` compile. Found
  while converting membership tests in Phase 6 of
  [x2c-dogfooding-remediation](x2c-dogfooding-remediation.md); three sites in
  `src/` keep `.contains` for this reason.
- **A string-literal key caches at a different point through `in`.**
  `m.contains("k")` and `"k" in m` produce semantically equal but textually
  different C, because the literal is cached in a later pass through the call
  form, which renumbers every cached slot in the unit. Fourteen otherwise
  clean conversions in `src/` and one in `lib/path.x` were left alone to keep
  the phase translation-identical. They become free once both spellings cache
  in the same pass.

- **Why do torch's private protocol adoptions still work?** 2d84cd5 stopped a
  private region from publishing its adoptions, which broke blis (see
  "Resolved since the baseline"). `packages/torch/src/torch.x:1445-1450` has
  the same shape - `protocol Torch(Tensor);` and five `protocol Var(T);` below
  `#pragma private` - and its tests, which use `@` on `Tensor` from a
  consumer, still pass. Either the rule has an exception worth documenting or
  torch is relying on something about to change. Nothing outside packages
  depends on the answer, and `make check` covers none of it.
- **`make doc-examples` fails on `site/src/content/slides/power-10-imports.md`**
  because the sample imports pcre2 and the package archive is not built. The
  check is optional and ungated, so the failure is invisible until someone
  runs it in a tree without built packages. Either build packages for that
  check, or mark the sample so it is skipped without one.

## Decisions needed

Decided 2026-09-17 by Gary unless marked open.

- **Catch removal (Group 6).** The handler stack holds only active
  registrations, so a selected catch is unlinked before its arm runs, as the
  book says and as every stack-order check assumes. The caught error a running
  arm still reads moves to a separate per-thread list of running arms, which
  shutdown walks, keeping dd33e20's quiet `exit()` inside an arm.
- **List equality (Group 8).** Keep bit equality; equality and hashing stay
  constant time. Document the limitation instead: List elements compare by
  identity, which is value equality for small numbers, Symbols, Atoms,
  interned Strings, and nested Lists, and identity for boxed wide numbers
  (`long`, `ulong`, `long long`, `long double`), Arrays, and Maps. Canonical
  wide boxes were rejected: a program using wide numbers needs the range, and
  interning every one of them multiplies the memory a generator pays. Add a
  separately named linear helper only when a caller needs one.
- **Negative end bound in `setslice`/`remslice` (Group 8).** Match
  `getslice`; no test pins the other meaning.
- **Lisp numeric comparison (Group 9).** Numeric `=` and `<` across i32,
  long, and f64 compare by value, as documented.
- **Duplicate warnings (Group 4).** Report identical warnings once, as
  `language.md:2757` says.
- **Concurrent builds (Group 11).** Open: whether two builds in one project
  are supported. Either way they must not exit 1 silently. Recommended: make
  them safe through the `file_publish` and `file_lock` owners that landed
  2026-09-17, giving the fingerprint `.i` a per-process name and never
  unlinking the output before its replacement exists.
- **`volatile` locals and non-volatile parameters (Group 3).** Open. A local
  written across a `try` is `volatile`, and passing its address to an ordinary
  `self` or callee parameter discards the qualifier (C11 6.7.3 undefined).
  Narrowing which locals are qualified is not available: restricting it to
  protected-body writes broke three exception suites, and adding an
  address-escape rule qualified `foreach` cursors and `sigset_t` locals and
  produced more warnings than it removed. The decision is how the address is
  spelled at the call, not which locals carry the qualifier.
- **`make debug` (Group 13).** Open: the target rewrites tracked
  `etc/build-mode`, which is what it has always done (d7bb8da).

## Resolved since the baseline

At a0e5641: `translate` with `%` in the output directory (d17c1b5), `Args.usage`
argument order (2b22657), directives between match arms (755b274), the
`cli.c` missing-return warning (11ba05e), and bootstrap locking (656b5b4).

At f122d9d: blis lost `@` and unary `-` for every consumer, including its own
tests, because 2d84cd5 stopped a private region from publishing its protocol
adoptions and `protocol Blis(BlisObject);` sat below `#pragma private`. Fixed
in 2b68db4 by moving the adoption above the pragma. Packages are outside
`make check`, so nothing caught it. torch has the same shape at
`packages/torch/src/torch.x:1445-1450` and still passes; why those adoptions
survive is unexplained.

## Refuted or verified clean

Generated C/H/`.xi` is byte-identical across `-j 1`, `-j 8`, reversed input
order, and warm retranslation. Diagnostics JSON is valid for quotes,
non-ASCII, and `-j 4`. Build fingerprints hash contents, so same-size edits
rebuild. Map passed a 200k-operation model check; JSON read/write held under
200k random doubles and 60k mutated inputs with ASan; SHA-256 matches hashlib;
Diff edit scripts apply with `patch` in 400 random cases; Match machine and
reference agree on 300k random cases; Lisp AUTO and evaluator outputs agree;
`defer`/`finally` ordering across `break`, `continue`, `goto`, and catch arms
is correct; detached catch handles stay constant-memory over 200k iterations;
TSan found only a benign same-value write in `pool.x`. Release tooling,
`install.sh` asset names, and the package index match the v0.14.0 release.
Every `make help` target, workflow reference, and skill link exists.

## Not examined

Linux and Windows behavior, package adapters beyond `packages-check`, the
rendered site (`site-build` was not run), performance, and `bootstrap/`
content beyond stage diffs.

## Plan review

- The catalog proposes no new validators or diagnostics. Rows that add a
  diagnostic protect wrong output or a crash: the `#if 0` truncation, the
  `%` path segfault, `x2c new ""` overwriting files, and the silent build
  exit. Fixes to warnings narrow existing checks instead of adding new ones.
- Several rows remove duplicated owners rather than add code: the two slice
  count implementations (Group 7), the two primitive repr tables
  (Group 8), the two Match template instantiations (Group 9), the two
  `const` static filters (Group 3), and hand-rolled file and path work in the
  driver that `Path` owns (Group 11).
- Fixtures belong with rows that are wrong output or crashes; documentation
  rows need none.
