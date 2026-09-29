# Coverage probe

The probe counts which lines of `src/*.x` and `lib/*.x` run during the
repository's own workload. It builds an instrumented compiler and runtime
whose generated C carries `--source-map` markers, runs the workload, and
attributes clang source-based coverage to `.x` lines. `llvm-cov` reports
physical lines of the generated C and ignores `#line` markers, so an awk
program applies the markers.

Run the commands from the repository root after `make build-safe`. The host
C compiler must be clang; on Linux, drop `xcrun`. On a 16-core Mac the build
takes about 15 seconds, and the workload and attribution about 3 minutes.

## Build

`builds/9` holds the instrumented stage. `make -C builds clean` removes it.
`BUILD_LDFLAGS` adds the profile runtime to the link; a command-line
`LDFLAGS` would replace the runtime link flags.

```sh
mkdir -p builds/9
make -f ../stage.mk -C builds/9 -j"$(getconf _NPROCESSORS_ONLN)" \
  X2C_COMPILER=../0/x2c X2C_FLAGS=--source-map \
  EXTRA_CFLAGS='-fprofile-instr-generate -fcoverage-mapping' \
  BUILD_LDFLAGS='-pthread -fprofile-instr-generate'
```

## Run the workload

The workload translates the runtime and the compiler, runs the compiler
fixtures, and runs the unit suites. Each process writes its own profile.
`%c` selects continuous mode, which keeps the counts of exit handlers such
as `Scope` shutdown hooks, forked workers, and crashed processes. A program
that links the instrumented runtime also needs the profile runtime. The
`cc` wrapper adds it to meta helper links, `BUILD_CFLAGS` adds it to fixture
program links and puts `builds/9` ahead of stage 0, and `STAGE=9` links the
unit suites against `builds/9`. `X2C_CACHE_DIR` keeps the instrumented meta
helpers out of the shared cache. Expect one fixture failure:
`var-chain-stack` limits the stack to 256 KB, and the instrumented compiler
overflows it. Removing `unittest/test-all` makes the next unit build relink
it against stage 0.

```sh
cov=$PWD/unittest/build/coverage x2c=$PWD/builds/9/x2c
rm -rf "$cov"; mkdir -p "$cov/prof" "$cov/lib" "$cov/src"
printf '#!/bin/sh\nexec cc -fprofile-instr-generate "$@"\n' > "$cov/cc"
chmod +x "$cov/cc"
export LLVM_PROFILE_FILE="$cov/prof/%p%c.profraw"
export X2C_META_CC="$cov/cc" X2C_CACHE_DIR="$cov/cache"
X2C_CC=false "$x2c" translate --fatal-warnings --out-dir "$cov/lib" \
  $(ls lib/*.x | grep -v '^lib/x2c\.x$')
X2C_CC=false "$x2c" translate --fatal-warnings --out-dir "$cov/src" src/*.x
X2C=$x2c FIXTURE_BUILD=$cov/fixtures FIXTURE_TIMEOUT_SECONDS=600 \
  BUILD_CFLAGS="-L$PWD/builds/9 -fprofile-instr-generate" \
  unittest/compiler-fixtures/run.sh check
make -C unittest -j"$(getconf _NPROCESSORS_ONLN)" STAGE=9 \
  BUILD="$cov/unittest" BUILD_LDFLAGS='-pthread -fprofile-instr-generate' \
  COMPILER_OBJECTS="$(printf '../builds/9/src/%s.o ' \
    ast diagnostics report sourceview)" test-all
(cd unittest && ./test-all)
rm -f unittest/test-all
unset LLVM_PROFILE_FILE X2C_META_CC X2C_CACHE_DIR
```

## Attribute counts to .x lines

The merged profile replaces about 1 GB of raw profiles. `x.tsv` holds one
row per executable `.x` line, `.x` function, never-executed run, and file.

```sh
find "$cov/prof" -name '*.profraw' > "$cov/prof.list"
xcrun llvm-profdata merge -sparse -f "$cov/prof.list" -o "$cov/x2c.profdata"
rm -r "$cov/prof"
xcrun llvm-cov export -format=lcov builds/9/x2c \
  -instr-profile="$cov/x2c.profdata" > "$cov/c.lcov"
cat > "$cov/xcov.awk" <<'EOF'
# Attribute llvm-cov lcov counts for --source-map generated C to .x lines.
# Output rows:
#   line FILE LINE COUNT        an executable .x line and the largest count
#                               of a generated C line that maps to it
#   func FILE FIRST LAST COUNT NAMES
#                               an .x function from its column-0 line to
#                               its closing brace, with its C functions
#   run FILE FIRST LAST ZEROS   3 or more zero-count lines inside an
#                               executed function, no executed line between
#   file FILE PERCENT HIT LINES line coverage of one .x file

# Record the .x file and line of each physical line of generated C.
function load(path,   text, n, w, file, line) {
  delete xf; delete xl; file = ""
  while ((getline text < path) > 0) {
    n++
    if (text ~ /^#line [0-9]/) {
      split(text, w, " "); line = w[2] - 1
      if (w[3] != "") {
        file = w[3]; gsub(/"/, "", file); sub(/^(\.\.\/)+/, "", file)
      }
      continue
    }
    line++
    if (file ~ /\.x$/) { xf[n] = file; xl[n] = line }
  }
  close(path)
  return n
}

# Fold one C file's line counts into .x lines, and give each C function
# the .x lines between its start and the next function's start.
function flush(   l, k, i, j, t, top, file, lo, hi) {
  for (l in da) if (l in xf) {
    k = xf[l] SUBSEP xl[l]
    if (!(k in cnt) || da[l] > cnt[k]) cnt[k] = da[l]
  }
  for (i = 2; i <= nf; i++)
    for (j = i; j > 1 && fl[j - 1] > fl[j]; j--) {
      t = fl[j]; fl[j] = fl[j - 1]; fl[j - 1] = t
      t = fn[j]; fn[j] = fn[j - 1]; fn[j - 1] = t
    }
  for (i = 1; i <= nf; i++) {
    for (j = i + 1; j <= nf && fl[j] == fl[i]; j++) ;
    top = j <= nf ? fl[j] - 1 : nc
    file = ""; lo = hi = 0
    for (l = fl[i]; l <= top; l++) {
      if (!(l in da) || !(l in xf) || (file != "" && xf[l] != file))
        continue
      file = xf[l]
      if (!lo || xl[l] < lo) lo = xl[l]
      if (xl[l] > hi) hi = xl[l]
    }
    if (file == "") continue
    nx++; xfile[nx] = file; xlo[nx] = lo; xhi[nx] = hi
    xcount[nx] = fc[fn[i]]; xname[nx] = fn[i]
  }
}

function source(f,   text, n) {
  if (f in size) return
  while ((getline text < f) > 0) src[f, ++n] = text
  close(f); size[f] = n
}

/^SF:/ { nc = load(substr($0, 4)); nf = 0; delete da }
/^FN:/ {
  i = index($0, ","); nf++
  fl[nf] = substr($0, 4, i - 4) + 0; fn[nf] = substr($0, i + 1)
}
/^FNDA:/ {
  i = index($0, ","); fc[substr($0, i + 1)] = substr($0, 6, i - 6) + 0
}
/^DA:/ { split(substr($0, 4), w, ","); da[w[1] + 0] = w[2] + 0 }
/^end_of_record/ { flush() }

END {
  for (k in cnt) {
    split(k, w, SUBSEP); print "line", w[1], w[2], cnt[k]
    lines[w[1]]++; if (cnt[k]) hit[w[1]]++
  }
  for (f in lines)
    printf "file %s %.1f %d %d\n", f, 100 * hit[f] / lines[f], hit[f],
      lines[f]
  # A function starts at the nearest column-0 line at or above its first
  # .x line. It ends at the next column-0 brace, or at its last .x line
  # when another definition starts first.
  for (i = 1; i <= nx; i++) {
    f = xfile[i]; source(f)
    for (a = xlo[i]; a > 1 && src[f, a] !~ /^[A-Za-z_$]/; a--) ;
    for (b = xhi[i]; b < size[f] && src[f, b] !~ /^}/; b++)
      if (b > xhi[i] && src[f, b] ~ /^[A-Za-z_$#\/]/) { b = xhi[i]; break }
    k = f SUBSEP a; name = xname[i]; sub(/^[^:]*:/, "", name)
    if (!(k in last) || b > last[k]) last[k] = b
    if (!(k in calls) || xcount[i] > calls[k]) calls[k] = xcount[i]
    if (!(k in names)) names[k] = name
    else if (!index("," names[k] ",", "," name ","))
      names[k] = names[k] "," name
  }
  for (k in last) {
    split(k, w, SUBSEP); f = w[1]
    print "func", f, w[2], last[k], calls[k], names[k]
    if (!calls[k]) continue
    zeros = 0
    for (l = w[2] + 0; l <= last[k] + 1; l++) {
      if (l <= last[k] && !((f, l) in cnt)) continue
      if (l <= last[k] && !cnt[f, l]) {
        if (!zeros++) start = l
        stop = l
        continue
      }
      if (zeros >= 3) print "run", f, start, stop, zeros
      zeros = 0
    }
  }
}
EOF
awk -f "$cov/xcov.awk" "$cov/c.lcov" | sort -k1,1 -k2,2 -k3,3n > "$cov/x.tsv"
```

## Read the result

`Tokenizer.scan` runs for every translated file, so its row must show a
large count. A missing row or a zero count means the markers did not reach
the report.

```sh
awk '$1 == "func" && $6 ~ /(^|,)Tokenizer_scan(,|$)/' "$cov/x.tsv"
# Line coverage per file, lowest first: percent, hit, lines, file.
awk '$1 == "file" { print $3, $4, $5, $2 }' "$cov/x.tsv" | sort -n
# Never-executed functions, longest first: lines, file:line, C names.
awk '$1 == "func" && $5 == 0 { print $4 - $3 + 1, $2 ":" $3, $6 }' \
  "$cov/x.tsv" | sort -rn | head -150
# One file: never-executed runs inside executed functions, then the
# source annotated with counts.
f=lib/tokenizer.x
awk -v f="$f" '$1 == "run" && $2 == f' "$cov/x.tsv"
awk -v f="$f" 'NR == FNR { if ($1 == "line" && $2 == f) n[$3] = $4; next }
  { printf "%5d|%9s|%s\n", FNR, n[FNR], $0 }' "$cov/x.tsv" "$f"
```

A count is the largest execution count of a generated C line that maps to
the `.x` line. A blank count means no mapped code: a comment, a declaration,
or code the compiler generates without a source location, such as class
boilerplate. A function row merges every C function that maps into one `.x`
function, including lambdas, defer cleanups, protocol adapters, and inline
copies from headers, so an unexecuted lambda appears as a run. A run counts
executable lines, so a statement that spans lines counts once. The first
statement after a `try` block can read 0 while the next line ran; clang
gives the gap after the lowered block a zero count. Error, diagnostic, and
fatal paths legitimately stay unexecuted, and so does code that only other
workloads reach: `x2c build`, `run`, `script`, `env`, `new`, `install`,
project manifests, packages, and external commands such as the REPL. A zero
count is a candidate, not proof. Every deletion still needs a caller check
across `src`, `lib`, `commands`, `packages`, `tools`, `etc`, `unittest`,
and `examples`, including macro templates, compile-time Lisp, protocol
hooks, and function pointers.
