#!/usr/bin/env bash
set -euo pipefail

# The call deadline covers partial writes while a reset has not returned.
ROOT=$(cd "$(dirname "$0")/../.." && pwd -P)
BUILD=${META_TRANSPORT_BUILD:-"$ROOT/unittest/build/meta-transport"}
X2C=${X2C:-"$ROOT/builds/0/x2c"}
mkdir -p "$BUILD/out"
python3 - "$X2C" "$BUILD" <<'PY'
from pathlib import Path
import os
import signal
import subprocess
import sys
import time

compiler, directory = sys.argv[1:]
build = Path(directory).resolve()
environment = {**os.environ, "X2C_CACHE_DIR": str(build / "cache")}
(build / "calls.xmacro").write_text('''
meta static int initialize(void) {
  FILE *out = fopen(getenv("META_TRANSPORT_PID"), "w");
  fprintf(out, "%ld\\n", (long) getpid());
  fclose(out);
  const char *mode = getenv("META_TRANSPORT_MODE");
  if (mode && !strcmp(mode, "spin") &&
      access(getenv("META_TRANSPORT_MARKER"), F_OK)) {
    out = fopen(getenv("META_TRANSPORT_MARKER"), "w");
    fclose(out);
    for (;;) {}
  }
  if (mode && !strcmp(mode, "exit")) _exit(17);
  if (mode && !strcmp(mode, "delay")) usleep(100000);
  return 0;
}
meta static int state = initialize();
meta static int text_length(String text) => text.len() + state;
meta static int twice(int n) => n * 2;
''')
for name, size in (("small", 1), ("large", 200000)):
    (build / (name + ".x")).write_text('''#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
$(import "calls.xmacro")
int answer(void) => $text_length("''' + "a" * size + '''");
int recovered(void) => $twice(21);
''')


def run(name, label, mode="", timeout="0", bound=20):
    pid_file = build / (label + ".helper.pid")
    marker = build / (label + ".marker")
    pid_file.unlink(missing_ok=True)
    marker.unlink(missing_ok=True)
    env = {**environment, "X2C_META_TIMEOUT": timeout,
           "META_TRANSPORT_MODE": mode, "META_TRANSPORT_PID": str(pid_file),
           "META_TRANSPORT_MARKER": str(marker)}
    start = time.monotonic()
    with (build / (label + ".stdout")).open("wb") as out, \
            (build / (label + ".stderr")).open("wb") as err:
        child = subprocess.Popen(
            [compiler, "translate", "-q", "--out-dir", str(build / "out"),
             str(build / (name + ".x"))], env=env, stdout=out, stderr=err,
            start_new_session=True)
        (build / (label + ".compiler.pid")).write_text(str(child.pid) + "\n")
        try:
            status = child.wait(timeout=bound)
            if pid_file.exists():
                pid = int(pid_file.read_text())
                try:
                    os.killpg(pid, 0)
                except ProcessLookupError:
                    pass
                else:
                    raise AssertionError(label + " left its helper running")
        except subprocess.TimeoutExpired:
            raise AssertionError(label + " exceeded its external bound")
        finally:
            # Only the exact processes started and recorded by this case.
            if child.poll() is None:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait()
            if pid_file.exists():
                try:
                    os.killpg(int(pid_file.read_text()), signal.SIGKILL)
                except ProcessLookupError:
                    pass
    elapsed = time.monotonic() - start
    error = (build / (label + ".stderr")).read_text()
    print(label, "status", status, "seconds", round(elapsed, 3), flush=True)
    return status, error


# Warm both source-specific helpers outside the short call budget.
for name in ("small", "large"):
    assert run(name, name + "-warm")[0] == 0
    status, error = run(name, name + "-timeout", "spin", "0.25", 5)
    assert status != 0 and "this meta call ran longer than 0.25 s" in error
    assert ":7:" not in error, "the call after timeout did not recover"

for label, mode, timeout in (("partial", "delay", "2"),
                             ("unlimited", "delay", "0")):
    assert run("large", label, mode, timeout)[0] == 0
    code = (build / "out/large.c").read_text()
    assert "return 200000;" in code and "return 42;" in code

status, error = run("large", "ended", "exit", "2", 5)
assert status != 0 and "this meta call stopped" in error
assert "the body exited with status 17" in error
assert run("large", "after-ended")[0] == 0
print("meta transport probes passed")
PY
