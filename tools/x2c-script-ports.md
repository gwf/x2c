# x2c script port ledger

This ledger records what each operational x2c script under `tools/` replaced.
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
- The inventory is every tracked file below `tools/` whose first line is
  `#!/usr/bin/env -S x2c script`. Native programs built from `.x` modules and
  non-executable compiler inputs are not scripts.

## Inventory

| Current tool | Port commit | Replaced source | Lines: old / x2c at port / current | Old dependencies | Current x2c dependencies | Port evidence and complications |
| --- | --- | --- | ---: | --- | --- | --- |
| `tools/check-release` | `cf508267` | `tools/check-release.sh` | 42 / 57 / 75 | 0 modules; 6 host commands: `curl`, `head`, `sh`, `grep`, `mktemp`, `rm` | 0 explicit modules; prelude `Env`, `Path`, `Job`, collections; host `curl`, `sh`, and the installed x2c | The delivery added environment lookup, which the script needed, and executable-permission inspection as an adjacent scripting gap. Process capture, temporary directories, and tree removal already covered the other shell work. Both versions matched stdout and status against the live 0.13.0 site on success and wrong-version failure. No timing was recorded; a live network download and installation make script overhead uninformative. Later release-route coverage accounts for the current growth. |
| `tools/gen-package-index` | `cb9fdb82` | `tools/gen-package-index.py` | 104 / 142 / 133 | 9 standard-library modules: `argparse`, `hashlib`, `json`, `pathlib`, `shutil`, `subprocess`, `sys`, `tarfile`, `tempfile`; queried x2c | 1 explicit module: `json.x`; prelude `Args`, `Path`, `File.sha256`, `Job`, collections; host `tar` and the stage compiler | JSON, SHA-256, declarative arguments, and process capture were the enabling surfaces. The system `tar` was deliberately reused because installation already depends on it. Status and stdout matched across success and failure cases; indexes were byte-identical except source-archive hashes, which cannot be stable even across two Python runs because `tarfile` timestamps the gzip header. Archive members and metadata matched instead. No timing was recorded; archive and digest I/O dominate. |
| `tools/gen-llms-txt` | `18c81d4b` | `tools/gen-llms-txt.py` | 236 / 266 / 266 | 6 standard-library modules: `argparse`, `difflib`, `pathlib`, `posixpath`, `re`, `sys` | 0 explicit modules; prelude `Args`, `Diff`, `Path`, `Regex`, collections; no host commands | Current regex, unified diff, path, and argument operations covered the port. URL-path normalization remained a small private helper instead of becoming a general library. Default, `--check`, and `--write` status, stdout, stderr, and both generated files matched byte for byte. The Makefile invokes the stage compiler explicitly because an executable shebang still requires `x2c` on `PATH`. No timing was recorded; this is bounded local text processing. |

## What the ports currently say

- The two Python ports grew at translation time. The package-index port later
  recovered nine lines as Path, Job, Args, and collection idioms improved; the
  llms.txt port still carries 30 more physical lines, mostly explicit result,
  diagnostic, and ordered-output handling.
- Only package indexing needs an optional x2c module. Regex and diff are in the
  script prelude because they serve general repository automation.
- Host-process removal is not a goal by itself. `tar`, `curl`, and `sh` remain
  where they are the repository's existing interoperability boundary.
- No port produced useful performance evidence. Future ports should retain a
  timing only when both versions can run on the same representative input and
  the result reveals a scripting-runtime cost rather than network or toolchain
  work.
