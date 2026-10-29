#!/usr/bin/env python3
"""Native REPL process, transcript, and terminal checks."""
import errno
import fcntl
import os
from pathlib import Path
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time

BINARY = Path(sys.argv[1] if len(sys.argv) > 1 else
              "builds/0/libexec/x2c-repl").resolve()
ROOT = Path(__file__).resolve().parents[3]
TIMEOUT = 90


def require(condition, evidence):
    if not condition:
        raise AssertionError(evidence)


def result(text, number):
    return re.search(r"=> (?:int )?" + str(number) + r"(?:\r?\n|$)", text)


class Terminal:
    def __init__(self, arguments, environment):
        self.pid, self.fd = pty.fork()
        if not self.pid:
            os.chdir(ROOT)
            os.execve(str(BINARY), [str(BINARY), *arguments], environment)
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ,
                    struct.pack("HHHH", 24, 120, 0, 0))
        self.output = b""
        self.consumed = 0
        self.status = None

    def send(self, text):
        os.write(self.fd, text.encode())

    def prompt(self):
        return self.until(rb"\x1b\[\?2004hx2c> ")

    def until(self, pattern, timeout=TIMEOUT):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            match = re.search(pattern, self.output[self.consumed:])
            if match:
                self.consumed += match.end()
                return self.output.decode(errors="replace")
            if not select.select([self.fd], [], [], 0.1)[0]:
                continue
            try:
                chunk = os.read(self.fd, 65536)
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                raise
            if not chunk:
                break
            self.output += chunk
            if b"\x1b[6n" in chunk:
                os.write(self.fd, b"\x1b[1;1R")
        raise AssertionError(self.output.decode(errors="replace"))

    def close(self):
        if self.status is None:
            found, status = os.waitpid(self.pid, os.WNOHANG)
            if not found:
                os.kill(self.pid, signal.SIGTERM)
                _, status = os.waitpid(self.pid, 0)
            self.status = status
        os.close(self.fd)

    def finish(self):
        end = time.monotonic() + TIMEOUT
        while time.monotonic() < end:
            found, status = os.waitpid(self.pid, os.WNOHANG)
            if found:
                self.status = status
                return os.waitstatus_to_exitcode(status)
            if select.select([self.fd], [], [], 0.1)[0]:
                try:
                    self.output += os.read(self.fd, 65536)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
        raise AssertionError(self.output.decode(errors="replace"))


def run(source, arguments, environment):
    return subprocess.run([str(BINARY), *arguments], input=source, text=True,
                          capture_output=True, env=environment, cwd=ROOT,
                          timeout=TIMEOUT)


def pipe_until(process, token):
    output = b""
    end = time.monotonic() + TIMEOUT
    while time.monotonic() < end:
        if token in output:
            return output
        if select.select([process.stdout], [], [], 0.1)[0]:
            chunk = os.read(process.stdout.fileno(), 65536)
            if not chunk:
                break
            output += chunk
    raise AssertionError(output.decode(errors="replace"))


with tempfile.TemporaryDirectory(prefix="x2c-repl-terminal-") as temporary:
    directory = Path(temporary)
    environment = dict(os.environ, TERM="xterm-256color",
                       XDG_STATE_HOME=str(directory / "state"))
    source = directory / "terminal.c"
    source.write_text("""#include <stdio.h>
#include <unistd.h>
int terminal_counter = 5;
int terminal_answer(void) { return 42; }
int terminal_input(void) {
  write(1, "native input\\n", 13);
  return getchar();
}
void terminal_hang(void) {
  write(1, "native waiting\\n", 15);
  while (1) pause();
}
void terminal_crash(void) { __builtin_trap(); }
""")
    bad = directory / "bad.c"
    bad.write_text("int broken( {\n")
    load = f':load "{source}"\n'

    piped = run(load + "terminal_input();\nterminal_answer();\n",
                [], environment)
    require(piped.returncode == 0 and result(piped.stdout, -1) and
            result(piped.stdout, 42), (piped.stdout, piped.stderr))
    print("piped native stdin stays separate from source", flush=True)

    preserved = run(load + "int kept = 17;\nterminal_counter = 99;\n" +
                    f':load "{bad}"\n' +
                    "kept;\nterminal_counter;\nterminal_answer();\n",
                    [], environment)
    require(preserved.returncode == 1 and result(preserved.stdout, 17) and
            result(preserved.stdout, 99) and result(preserved.stdout, 42),
            (preserved.stdout, preserved.stderr))
    require("session unchanged" in preserved.stderr,
            (preserved.stdout, preserved.stderr))
    print("failed candidate preserves prompt and native state", flush=True)

    candidate = directory / "candidate.c"
    candidate.write_text("""#include <unistd.h>
__attribute__((constructor)) static void candidate_wait(void) {
  write(1, "candidate waiting\\n", 18);
  while (1) pause();
}
int candidate_value(void) { return 1; }
""")
    waiting = subprocess.Popen([str(BINARY)], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               env=environment, cwd=ROOT)
    try:
        waiting.stdin.write((load + "int kept = 17;\nterminal_counter = 99;\n" +
                             f':load "{candidate}"\n').encode())
        waiting.stdin.flush()
        before = pipe_until(waiting, b"candidate waiting\n")
        waiting.send_signal(signal.SIGINT)
        after, errors = waiting.communicate(
            b"kept;\nterminal_counter;\nterminal_answer();\n", timeout=TIMEOUT)
        output = (before + after).decode()
        require(waiting.returncode == 1 and result(output, 17) and
                result(output, 99) and result(output, 42),
                (output, errors.decode()))
    finally:
        if waiting.poll() is None:
            waiting.send_signal(signal.SIGINT)
            waiting.kill()
            waiting.wait()
    print("canceling candidate initialization preserves the active session",
          flush=True)

    crashed = run(load + "terminal_crash();\nterminal_counter;\n"
                  "terminal_answer();\n", [], environment)
    require(crashed.returncode == 1 and result(crashed.stdout, 5) and
            result(crashed.stdout, 42) and "state was lost" in crashed.stderr,
            (crashed.stdout, crashed.stderr))
    print("native crash leaves the terminal client usable", flush=True)

    saved = directory / "saved.repl"
    replayed = run(load + "int kept = 11;\nkept += 3;\n" +
                   f':save "{saved}"\n:reset\n:replay "{saved}"\nkept;\n',
                   [], environment)
    require(replayed.returncode == 0 and result(replayed.stdout, 14),
            (replayed.stdout, replayed.stderr))
    print("saved instructions replay in a fresh session", flush=True)

    terminal = Terminal([str(source)], environment)
    try:
        terminal.prompt()
        terminal.send("terminal_input();\r")
        terminal.until(rb"native input\r?\n")
        terminal.send("Z\n")
        terminal.until(rb"=> int 90\r?\n")
        terminal.prompt()
        terminal.send("terminal_hang();\r")
        terminal.until(rb"native waiting\r?\n")
        terminal.send("\x03")
        terminal.until(rb"state was lost")
        terminal.prompt()
        terminal.send("terminal_answer();\r")
        terminal.until(rb"=> int 42\r?\n")
        terminal.prompt()
        terminal.send("int unfinished")
        terminal.send("\x03")
        terminal.prompt()
        terminal.send(":quit\r")
        require(terminal.finish() == 0,
                terminal.output.decode(errors="replace"))
    finally:
        terminal.close()
    history = directory / "state/x2c/repl-history"
    require(history.is_file() and "terminal_answer" in history.read_text(),
            "interactive history was not saved")
    print("native terminal input, forced stop, edit cancellation, and history pass",
          flush=True)

print("REPL terminal checks passed")
