# x2c script port ledger

This ledger records what each operational x2c script replaced.
It is evidence about the cost of dogfooding: size growth can identify missing
language or library leverage, while extra modules and host commands identify
capabilities that the script environment does not own.

Update the ledger before deleting a predecessor. Record parity and any useful
timing while both implementations can still run on the same inputs. A timing
is optional for these scripts; do not reconstruct one later from unlike trees.

## Measurement

- **Lines** are physical source lines from `wc -l`, including comments and
  blanks. The x2c column records the replacement commit and the current file,
  so later feature growth is not mistaken for porting overhead.
- **Modules** counts direct imports or includes. Every x2c script receives the
  standard scripting prelude implicitly; the prelude operations actually used
  are named but do not count as explicit modules. Python's `__future__`
  directive does not count as a module.
- **Host commands** are distinct external programs launched by the script,
  excluding its interpreter. A compiler installed or queried by the tool is
  called out separately.
- The inventory is every tracked port to a file whose first line is
  `#!/usr/bin/env -S x2c script`. Native programs built from `.x` modules and
  non-executable compiler inputs are not scripts.

## Inventory

| Current tool | Port commit | Replaced source | Lines: old / x2c at port / current | Old dependencies | Current x2c dependencies | Port evidence and complications |
| --- | --- | --- | ---: | --- | --- | --- |
| `tools/check-release` | `cf508267` | `tools/check-release.sh` | 42 / 57 / 75 | 0 modules; 6 host commands: `curl`, `head`, `sh`, `grep`, `mktemp`, `rm` | 0 explicit modules; prelude `Env`, `Path`, `Job`, collections; host `curl`, `sh`, and the installed x2c | The delivery added environment lookup, which the script needed, and executable-permission inspection as an adjacent scripting gap. Process capture, temporary directories, and tree removal already covered the other shell work. Both versions matched stdout and status against the live 0.13.0 site on success and wrong-version failure. No timing was recorded; a live network download and installation make script overhead uninformative. Later release-route coverage accounts for the current growth. |
| `tools/gen-package-index` | `cb9fdb82` | `tools/gen-package-index.py` | 104 / 142 / 133 | 9 standard-library modules: `argparse`, `hashlib`, `json`, `pathlib`, `shutil`, `subprocess`, `sys`, `tarfile`, `tempfile`; queried x2c | 1 explicit module: `json.x`; prelude `Args`, `Path`, `File.sha256`, `Job`, collections; host `tar` and the stage compiler | JSON, SHA-256, declarative arguments, and process capture were the enabling surfaces. The system `tar` was deliberately reused because installation already depends on it. Status and stdout matched across success and failure cases; indexes were byte-identical except source-archive hashes, which cannot be stable even across two Python runs because `tarfile` timestamps the gzip header. Archive members and metadata matched instead. No timing was recorded; archive and digest I/O dominate. |
| `tools/gen-llms-txt` | `18c81d4b` | `tools/gen-llms-txt.py` | 236 / 266 / 266 | 6 standard-library modules: `argparse`, `difflib`, `pathlib`, `posixpath`, `re`, `sys` | 0 explicit modules; prelude `Args`, `Diff`, `Path`, `Regex`, collections; no host commands | Current regex, unified diff, path, and argument operations covered the port. URL-path normalization remained a small private helper instead of becoming a general library. Default, `--check`, and `--write` status, stdout, stderr, and both generated files matched byte for byte. The Makefile invokes the stage compiler explicitly because an executable shebang still requires `x2c` on `PATH`. No timing was recorded; this is bounded local text processing. |
| `tools/check-doc-examples` | `6508a6e5` | `tools/check-doc-examples.py` | 263 / 210 / 210, plus 137 in the shared `tools/doc-samples.x` | 7 standard-library modules: `concurrent.futures`, `os`, `pathlib`, `re`, `subprocess`, `sys`, `tempfile`; the stage compiler and each built sample | 1 local module: `tools/doc-samples.x`; prelude `Job`, `Path`, `Regex`, `Env`, collections; the stage compiler and each built sample | `Job.start` and `Job.wait_any` replace the thread pool, with results stored by sample index so diagnostics keep document order. The fence pattern used a backreference, which `Regex` lacks, so the shared module scans lines for an opening fence and its matching indented close. Page order follows a sorted recursive `list_dir`, because `Path.glob` sorts whole strings and Python sorts path components. Ordinary and `--outputs` status, stdout, and stderr matched; stderr differed only in temporary directory names and compiler timings. The Python per-run 30-second limit was dropped because `Job` has no timeout. One run each on the full tree took 44.6 s for Python and 35.8 s for x2c, dominated by sample builds. |
| `tools/check-gallery-examples` | `6508a6e5` | `tools/check-gallery-examples.py` | 112 / 134 / 134, plus the shared `tools/doc-samples.x` | 5 standard-library modules: `argparse`, `importlib.util`, `json`, `pathlib`, `sys`; imported `check-doc-examples.py` | 2 explicit modules: `tools/doc-samples.x`, `json.x`; prelude `Args`, `Path`, collections; no host commands | The Python file loaded the example checker as a module; both scripts now include `tools/doc-samples.x`. Ordinary and `--update` status, stdout, stderr, and rewritten examples matched in temporary copies, except the `--update` hint now names the extensionless script. No timing was recorded; the check is bounded local text processing. |
| `tools/check-docs` | `6b27b809` | `tools/check-docs.py` | 455 / 479 / 479 | 4 standard-library modules: `pathlib`, `re`, `subprocess`, `sys`; host `python3` for the catalog and API generators | 0 explicit modules; prelude `Path`, `Regex`, `Job`, collections; host `python3` for the same two generators | The Python flag pattern used a lookbehind, which `Regex` lacks; the script rejects a match whose preceding byte is a letter, digit or hyphen, which selects the same flags because every byte of a rejected match is itself such a byte. `Path.walk` supplies path-component order, so page and error order match `rglob`. A cited page whose markers are missing, or an empty link target, now reports an error where Python raised a traceback; both exit 1. Status, stdout and stderr matched on the current tree, on a missing `builds/0`, and on four broken copies covering every check; the flag and workflow checks iterated Python sets, so only their error order differed. The two generator checks now run concurrently: one run each on the full tree took 9.2 s for Python and 6.4 s for x2c. |
| `unittest/probes/run-artifact-atomicity` | `aa4bb8cf` | `unittest/probes/run-artifact-atomicity.sh` | 74 / 90 / 90, plus 32 in the shared `unittest/probes/probe.x` | bash; 6 host commands: `mkdir`, `rm`, `cmp`, `grep`, `ls`, `ln`; the stage compiler | 1 local module: `unittest/probes/probe.x`; prelude `Path`, `Job`, `Regex`, `Env`; host `sh` and the stage compiler | The C write must fail under the compiler's own process id, so a one-line `sh -c` still links the dangling sibling at `$$` and execs the compiler; `Job` cannot name a child's id before it starts. Byte comparisons read both files as text. Success output and status matched; with `X2C=/usr/bin/true` both printed the same failure and exited 1. With `X2C=/usr/bin/false` both exit 1, and the script also prints the failed command, where the shell's `set -e` printed nothing. |
| `unittest/probes/run-scope-shutdown` | `a28618f2` | `unittest/probes/run-scope-shutdown.sh` | 140 / 110 / 110, plus the shared `unittest/probes/probe.x` | bash; 4 host commands: `mkdir`, `cc`, `head`, `cat`; the stage compiler and the two built probes | 1 local module: `unittest/probes/probe.x`; prelude `Path`, `Job`; host `cc`, the stage compiler and the two built probes | Standard output and error are captured by the jobs instead of written to files below `unittest/build/scope-probes`. Three helpers replace fourteen repeated run-and-test blocks. A failed `test` ended the shell probe silently with status 1; the script names the mode and the check, also with status 1, and a mode that must succeed now reports its status and exits 1 rather than exiting with the child's status. Success output and status matched; with the finalizer's expected output changed in copies of both, both exited 1. |
| `unittest/probes/run-error-floor` | this commit | `unittest/probes/run-error-floor.sh` | 158 / 133 / 133, plus 13 lines added to the shared `unittest/probes/probe.x` | bash; 7 host commands: `cat`, `mkdir`, `cc` or `$CC`, `tail`, `head`, `sed`, `grep`; the stage compiler and the two built probes | 1 local module: `unittest/probes/probe.x`, which gains the build-mode flags; prelude `Path`, `Job`, `Env`; host `cc` or `$CC`, the stage compiler and the two built probes | The five exit cases are one table of name, status and whether standard error must be empty. Captured output replaces the files below `unittest/build/error-probes`. Explicit shell messages are unchanged; checks that `set -e` ended silently now name the mode and check, still with status 1. Success output and status matched; with the preinit reason changed in copies of both, both printed the same line and exited 1. |

## What the ports currently say

- The first two Python ports grew at translation time. The package-index port
  later recovered nine lines as Path, Job, Args, and collection idioms
  improved; the llms.txt port still carries 30 more physical lines, mostly
  explicit result, diagnostic, and ordered-output handling. The two
  documentation checks grew from 375 to 481 lines, mostly in the line-based
  fence scanner and the explicit job scheduling.
- Package indexing and the gallery check need the optional `json.x` module,
  and the two documentation checks share one local module. Regex and diff are
  in the script prelude because they serve general repository automation.
- Host-process removal is not a goal by itself. `tar`, `curl`, and `sh` remain
  where they are the repository's existing interoperability boundary.
- No port produced useful performance evidence. Future ports should retain a
  timing only when both versions can run on the same representative input and
  the result reveals a scripting-runtime cost rather than network or toolchain
  work.
