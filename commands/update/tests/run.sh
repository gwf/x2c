#!/bin/sh
# The update target follows its executable, not the selected compilation home.
set -eu
cd "$(dirname "$0")/../../.."
root=$PWD
work=$(mktemp -d "${TMPDIR:-/tmp}/x2c-update-command.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
work=$(cd "$work" && pwd -P)
prefix="$work/installed compiler"
other="$work/other compiler"
for home in "$prefix" "$other"; do
  mkdir -p "$home/bin" "$home/libexec/x2c" "$home/include" "$home/etc"
  cp builds/0/x2c "$home/bin/x2c"
  cp builds/0/libexec/x2c-update "$home/libexec/x2c/x2c-update"
  : >"$home/etc/compiler-prelude.x"
done
cat >"$prefix/etc/install.sh" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$@"
exit 19
SCRIPT
cat >"$other/etc/install.sh" <<'SCRIPT'
#!/bin/sh
printf 'wrong installation\n'
exit 20
SCRIPT
run() {
  status=0
  "$@" >"$work/out" 2>&1 || status=$?
}
# The installed command passes literal arguments and preserves backend status.
run "$prefix/libexec/x2c/x2c-update" --version '1.2.3; literal'
[ "$status" = 19 ]
printf '%s\n' --update --prefix "$prefix" --version '1.2.3; literal' \
  >"$work/expected"
cmp "$work/expected" "$work/out"
# The driver also resolves update from its executable when X2C_HOME differs.
run env X2C_HOME="$other" "$prefix/bin/x2c" update --check
[ "$status" = 19 ]
printf '%s\n' --update --prefix "$prefix" --check >"$work/expected"
cmp "$work/expected" "$work/out"
run env X2C_HOME="$other" "$prefix/bin/x2c" help update
[ "$status" = 19 ]
printf '%s\n' --update --prefix "$prefix" --help >"$work/expected"
cmp "$work/expected" "$work/out"
# A checkout has no installed release to replace.
run "$root/builds/0/libexec/x2c-update" --check
[ "$status" = 2 ]
grep -q 'development checkout; run.*make install' "$work/out"
# make build-install also places the command under checkout/libexec/x2c.
checkout="$work/development checkout"
mkdir -p "$checkout/libexec/x2c" "$checkout/site/public"
cp builds/0/libexec/x2c-update "$checkout/libexec/x2c/x2c-update"
cp "$prefix/etc/install.sh" "$checkout/site/public/install.sh"
run "$checkout/libexec/x2c/x2c-update" --check
[ "$status" = 2 ]
grep -q 'development checkout; run.*make install' "$work/out"
run "$checkout/libexec/x2c/x2c-update" --help
[ "$status" = 19 ]
printf '%s\n' --update --prefix "$checkout" --help >"$work/expected"
cmp "$work/expected" "$work/out"
printf 'update command: passed\n'
