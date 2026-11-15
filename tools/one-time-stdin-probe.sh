#!/bin/sh
set -eu
probe=$(mktemp -d /tmp/repl-stdin-fork.XXXXXX)
echo "$probe"
cc -Wall -Wextra /tmp/repl-stdin-fork-probe.c -o "$probe/probe"
printf 'one\ntwo\nthree\n' >"$probe/input"
printf 'first: one\nnext: two\nnext: three\n' >"$probe/expected"
for variant in baseline close; do
  arg=
  if [ "$variant" = close ]; then arg=close; fi
  "$probe/probe" $arg <"$probe/input" >"$probe/$variant-file.out" 2>"$probe/$variant-file.err"
  cat "$probe/input" | "$probe/probe" $arg >"$probe/$variant-pipe.out" 2>"$probe/$variant-pipe.err"
  for mode in file pipe; do
    echo "$variant $mode"
    cat "$probe/$variant-$mode.err" "$probe/$variant-$mode.out"
    if cmp -s "$probe/expected" "$probe/$variant-$mode.out"; then echo PASS; else echo MISMATCH; fi
  done
done
cmp "$probe/expected" "$probe/close-file.out"
cmp "$probe/expected" "$probe/close-pipe.out"
