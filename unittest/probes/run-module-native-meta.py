#!/usr/bin/env python3
"""Optional native-meta module acceptance probes; no gate registration.

Use run-module-native-meta.py COMPILER [--home HOME] [--case NAME ...].
All native builds use one job. Fixtures, receipts, and full logs remain in /tmp.
The indirect initializer-call cycle deliberately remains a failing requirement.
"""

import argparse
from collections import Counter
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


CASES = {'module_prerequisite': ({'box.x': 'meta module int left(void);\n'
                                   'meta module int right(void);\n'
                                   'module {"box/left.x","box/right.x","box/value.x"}\n',
                          'box/left.x': '#include "right.x"\n'
                                        'enum {LEFT=$right()};\n'
                                        'meta module int left(void)=>LEFT;\n',
                          'box/right.x': 'meta module int right(void)=>42;\n',
                          'box/value.x': 'int answer(void)=>$left();\n',
                          'main.x': '#include "box.x"\n'
                                    'int main(void)=>answer()==42?0:1;\n'},
                         ['box.x', 'main.x'],
                         False),
 'module_cycle': ({'box.x': 'meta module int left(void);\n'
                            'meta module int right(void);\n'
                            'module {"box/left.x","box/right.x","box/value.x"}\n',
                   'box/left.x': '#include "right.x"\n'
                                 'enum {LEFT=$right()};\n'
                                 'meta module int left(void)=>LEFT;\n',
                   'box/right.x': '#include "left.x"\n'
                                  'enum {RIGHT=$left()};\n'
                                  'meta module int right(void)=>RIGHT;\n',
                   'box/value.x': 'int answer(void)=>$left();\n',
                   'main.x': '#include "box.x"\nint main(void)=>answer();\n'},
                  ['box.x', 'main.x'],
                  True),
 'nested_private_meta': ({'box.x': 'meta module int base(void)=>40;\n'
                                   'module {"box/child.x"}\n',
                          'box/child.x': 'module {"child/leaf.x"}\n',
                          'box/child/leaf.x': 'meta module int own(void)=>$base()+2;\n'
                                              'int answer(void)=>$own();\n',
                          'main.x': '#include "box.x"\n'
                                    'int main(void)=>answer()==42?0:1;\n'},
                         ['box.x', 'main.x'],
                         False),
 'parent_private_rejection': ({'box.x': 'module {"box/child.x"}\n'
                                        'int leak(void)=>$child_only();\n',
                               'box/child.x': 'module {"child/leaf.x"}\n',
                               'box/child/leaf.x': 'meta module int '
                                                   'child_only(void)=>42;\n',
                               'main.x': '#include "box.x"\nint main(void)=>leak();\n'},
                              ['box.x', 'main.x'],
                              True),
 'active_ordinary_prefix': ({'a.x': '#include "b.x"\nmeta int a(void)=>bhelper();\n',
                             'b.x': 'int bhelper(void)=>42;\n'
                                    '#include "a.x"\n'
                                    'enum {VALUE=$a()};\n'
                                    'meta int b(void)=>VALUE;\n',
                             'main.x': '#include "b.x"\nint main(void)=>$b()==42?0:1;\n'},
                            ['a.x', 'b.x', 'main.x'],
                            False),
 'active_reached_ordinary_prefix': ({'a.x': 'int bhelper(void);\n'
                                            'meta int a(void)=>bhelper();\n'
                                            '#include "b.x"\n',
                                     'b.x': 'int bhelper(void)=>42;\n'
                                            '#include "a.x"\n'
                                            'enum {VALUE=$a()};\n'
                                            'meta int b(void)=>VALUE;\n',
                                     'main.x': '#include "b.x"\n'
                                               'int main(void)=>$b()==42?0:1;\n'},
                                    ['a.x', 'b.x', 'main.x'],
                                    False),
 'ordinary_runtime_cycle': ({'left.x': 'meta int left(int n);\n'
                                       '#include "right.x"\n'
                                       'meta int left(int n)=>n?right(n-1):42;\n',
                             'right.x': 'meta int right(int n);\n'
                                        '#include "left.x"\n'
                                        'meta int right(int n)=>n?left(n-1):42;\n',
                             'main.x': '#include "left.x"\n'
                                       'int main(void)=>$left(4)==42?0:1;\n'},
                            ['left.x', 'right.x', 'main.x'],
                            False),
 'module_ordinary_shared_variable': ({'box.x': 'module {"box/state.x","box/use.x"}\n',
                                      'box/state.x': 'static int initial(void)=>40;\n'
                                                     'module int state=initial();\n'
                                                     'meta module int '
                                                     'next(void)=>++state;\n'
                                                     'int shared(void)=>state;\n',
                                      'box/use.x': 'enum '
                                                   '{FIRST=$next(),SECOND=$next()};\n'
                                                   'int '
                                                   'computed(void)=>FIRST*100+SECOND;\n'
                                                   'int answer(void)=>++state;\n',
                                      'main.x': '#include "box.x"\n'
                                                'int main(void)=>computed()==4142 && '
                                                'answer()==41 && shared()==41?0:1;\n'},
                                     ['box.x', 'main.x'],
                                     False),
 'module_ordinary_cleanup': ({'box.x': 'module {"box/state.x","box/use.x"}\n',
                              'box/state.x': '#include <stdio.h>\n'
                                             '#include <stdlib.h>\n'
                                             '#include <unistd.h>\n'
                                             'static void cleanup(void) { FILE '
                                             '*out=fopen("@MARKER@","a"); '
                                             'fprintf(out,"%ld\\n",(long)getpid()); '
                                             'fclose(out); }\n'
                                             'static int initial(void) { '
                                             'atexit(cleanup); return 40; }\n'
                                             'module int state=initial();\n'
                                             'meta module int next(void)=>++state;\n'
                                             'int shared(void)=>state;\n',
                              'box/use.x': 'enum {FIRST=$next(),SECOND=$next()};\n'
                                           'int computed(void)=>FIRST*100+SECOND;\n'
                                           'int answer(void)=>++state;\n',
                              'main.x': '#include "box.x"\n'
                                        'int main(void)=>computed()==4142 && '
                                        'answer()==41 && shared()==41?0:1;\n'},
                             ['box.x', 'main.x'],
                             False),
 'module_initializer_cycle': ({'box.x': 'module int read_a(void);\n'
                                        'module int read_b(void);\n'
                                        'module {"box/a.x","box/b.x","box/use.x"}\n',
                               'box/a.x': 'module int a=read_b();\n'
                                          'module int read_a(void)=>a;\n',
                               'box/b.x': 'module int b=read_a();\n'
                                          'module int read_b(void)=>b;\n',
                               'box/use.x': 'meta module int value(void)=>read_a();\n'
                                            'int answer(void)=>$value();\n',
                               'main.x': '#include "box.x"\nint main(void)=>answer();\n'},
                              ['box.x', 'main.x'],
                              True),
 'module_meta_shared_variable': ({'box.x': 'module {"box/state.x","box/use.x"}\n',
                                  'box/state.x': 'meta module int state=40;\n'
                                                 'meta module int next(void)=>++state;\n',
                                  'box/use.x': 'enum {FIRST=$next(),SECOND=$next()};\n'
                                               'int answer(void)=>FIRST*100+SECOND;\n',
                                  'main.x': '#include "box.x"\n'
                                            'int main(void)=>answer()==4142?0:1;\n'},
                                 ['box.x', 'main.x'],
                                 False),
 'package_private_meta': ({'packages/geo/src/geo.x': 'meta module int base(void)=>40;\n'
                                                     'module {"geo/child.x"}\n',
                           'packages/geo/src/geo/child.x': 'module {"child/leaf.x"}\n',
                           'packages/geo/src/geo/child/leaf.x': 'meta module int '
                                                                'own(void)=>$base()+2;\n'
                                                                'int '
                                                                'answer(void)=>$own();\n',
                           'main.x': 'import "geo" as g with answer;\n'
                                     'int main(void)=>answer()==42?0:1;\n'},
                          ['main.x'],
                          False),
 'package_private_rejection': ({'packages/geo/src/geo.x': 'meta module int '
                                                          'base(void)=>40;\n'
                                                          'module {"geo/child.x"}\n',
                                'packages/geo/src/geo/child.x': 'module '
                                                                '{"child/leaf.x"}\n',
                                'packages/geo/src/geo/child/leaf.x': 'meta module int '
                                                                     'own(void)=>$base()+2;\n'
                                                                     'int '
                                                                     'answer(void)=>$own();\n',
                                'main.x': 'import "geo" as g;\n'
                                          'int main(void)=>$g.base();\n'},
                               ['main.x'],
                               True),
 'module_lifetime_entry_state': ({'box.x': 'meta static int state=40;\n'
                                           'meta module int tick(void)=>++state;\n'
                                           'module '
                                           '{"box/one.x","box/child.x","box/last.x"}\n',
                                  'box/one.x': 'enum '
                                               '{ONE_FIRST=$tick(),ONE_SECOND=$tick()};\n'
                                               'int '
                                               'first(void)=>ONE_FIRST*100+ONE_SECOND;\n',
                                  'box/child.x': 'module {"child/two.x"}\n',
                                  'box/child/two.x': 'enum '
                                                     '{TWO_FIRST=$tick(),TWO_SECOND=$tick()};\n'
                                                     'int '
                                                     'second(void)=>TWO_FIRST*100+TWO_SECOND;\n',
                                  'box/last.x': 'enum '
                                                '{LAST_FIRST=$tick(),LAST_SECOND=$tick()};\n'
                                                'int '
                                                'third(void)=>LAST_FIRST*100+LAST_SECOND;\n',
                                  'main.x': '#include "box.x"\n'
                                            'int main(void)=>first()==4142 && '
                                            'second()==4142 && third()==4142?0:1;\n'},
                                 ['box.x', 'main.x'],
                                 False),
 'module_lifetime_direct_state': ({'box.x': 'meta static int state=40;\n'
                                            'meta module int tick(void)=>++state;\n'
                                            'module '
                                            '{"box/one.x","box/child.x","box/last.x"}\n',
                                   'box/one.x': 'enum '
                                                '{ONE_FIRST=$tick(),ONE_SECOND=$tick()};\n'
                                                'int '
                                                'first(void)=>ONE_FIRST*100+ONE_SECOND;\n',
                                   'box/child.x': 'module {"child/two.x"}\n',
                                   'box/child/two.x': 'enum '
                                                      '{TWO_FIRST=$tick(),TWO_SECOND=$tick()};\n'
                                                      'int '
                                                      'second(void)=>TWO_FIRST*100+TWO_SECOND;\n',
                                   'box/last.x': 'enum '
                                                 '{LAST_FIRST=$tick(),LAST_SECOND=$tick()};\n'
                                                 'int '
                                                 'third(void)=>LAST_FIRST*100+LAST_SECOND;\n',
                                   'main.x': '#include "box.x"\n'
                                             'int main(void)=>first()==4142 && '
                                             'second()==4142 && third()==4142?0:1;\n'},
                                  ['box/one.x',
                                   'box/child/two.x',
                                   'box/last.x',
                                   'main.x'],
                                  False),
 'package_public_meta_probe_alias': ({'packages/geo/src/geo.x': 'meta module int '
                                                                'private_base(void)=>40;\n'
                                                                'module '
                                                                '{"geo/child.x"}\n',
                                      'packages/geo/src/geo/child.x': 'module '
                                                                      '{"child/leaf.x"}\n',
                                      'packages/geo/src/geo/child/leaf.x': 'meta int '
                                                                           'package_probe_value(void)=>private_base()+2;\n'
                                                                           'int '
                                                                           'answer(void)=>$package_probe_value();\n',
                                      'main.x': 'import "geo" as g with '
                                                'package_probe_value, answer;\n'
                                                'enum '
                                                '{A=$g.package_probe_value(),B=$package_probe_value()};\n'
                                                'int main(void)=>A==42 && B==42 && '
                                                'answer()==42?0:1;\n'},
                                     ['main.x'],
                                     False),
 'module_direct_initializer_cycle': ({'box.x': 'module int a;\n'
                                               'module int b;\n'
                                               'module '
                                               '{"box/a.x","box/b.x","box/use.x"}\n',
                                      'box/a.x': 'module int a=b+1;\n',
                                      'box/b.x': 'module int b=a+1;\n',
                                      'box/use.x': 'meta module int value(void)=>a+b;\n'
                                                   'int answer(void)=>$value();\n',
                                      'main.x': '#include "box.x"\n'
                                                'int main(void)=>answer();\n'},
                                     ['box.x', 'main.x'],
                                     True)}

REJECTIONS = {
    "module_cycle": r"native meta prerequisite cycle",
    "parent_private_rejection": r"module-private declaration 'child_only' is not accessible",
    "package_private_rejection": r"package 'geo' has no public name 'base'",
    "module_initializer_cycle": r"initializer dependency cycle|selected initializer cycle",
    "module_direct_initializer_cycle": r"initializer dependency cycle|selected initializer cycle",
}


def run(command, directory, environment, log, timeout=120):
    try:
        result = subprocess.run(command, cwd=directory, env=environment, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                timeout=timeout)
    except subprocess.TimeoutExpired as failure:
        output = failure.stdout or ""
        if isinstance(output, bytes):
            output = output.decode("utf-8", errors="replace")
        log.write_text(output, encoding="utf-8")
        raise
    log.write_text(result.stdout, encoding="utf-8")
    return result


def prepare_package(compiler, directory, environment, record):
    package = directory / "packages/geo"
    builds = package / "builds"
    builds.mkdir()
    command = [str(compiler), "translate", "-j", "1", "--out-dir", str(builds),
               "--package-dir", str(directory / "packages"),
               str(package / "src/geo.x")]
    log = directory / "package-translate.log"
    result = run(command, directory, environment, log)
    record["package_translation"] = {"command": command, "status": result.returncode,
                                     "log": str(log)}
    if result.returncode:
        return False
    generated = sorted(builds.rglob("*.c"))
    (builds / "geo.native.rsp").write_text("")
    native_paths = [flag for parent in sorted({str(path.parent) for path in generated})
                    for flag in ("-Xcc", "-iquote", "-Xcc", parent)]
    command = [str(compiler), "build", "-j", "1", "--kind", "static-library",
               "--output", str(builds / "libgeo.a"), "--build-dir", str(builds / "cc"),
               *native_paths, *map(str, generated)]
    log = directory / "package-archive.log"
    result = run(command, directory, environment, log)
    record["package_archive"] = {"command": command, "status": result.returncode,
                                 "log": str(log)}
    record["public_c_name"] = any("geo__answer" in path.read_text() for path in generated)
    return result.returncode == 0 and record["public_c_name"]


def run_case(compiler, home, base, name):
    files, inputs, reject = CASES[name]
    directory = base / name
    directory.mkdir()
    environment = dict(os.environ, X2C_HOME=str(home), BUILD_JOBS="1")
    record = {"name": name, "passed": False, "expect_rejection": reject}
    for filename, source in files.items():
        path = directory / filename
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(source.replace("@MARKER@", str(directory / "cleanup-pids.txt")),
                        encoding="ascii")
    try:
        if name.startswith("package") and not prepare_package(
                compiler, directory, environment, record):
            return record
        command = [str(compiler)]
        # Translation forces value()'s native helper without compiling the
        # ordinary executable. Keep that phase distinct in the rejection receipt.
        direct_cycle = name == "module_direct_initializer_cycle"
        if direct_cycle:
            command.extend(["translate", "-j", "1", "--out-dir", str(directory / "gen")])
            record["rejection_phase"] = "translation"
            record["native_loading_trigger"] = "answer() expands $value() reading a and b"
        else:
            command.extend(["build", "-j", "1", "--build-dir", str(directory / "build"),
                            "--output", str(directory / "program")])
        if name.startswith("package"):
            command.extend(["--package-dir", str(directory / "packages")])
        command.extend(str(directory / filename) for filename in inputs)
        log = directory / "build.log"
        result = run(command, directory, environment, log)
        record.update(command=command, build_status=result.returncode, log=str(log))
        if reject:
            pattern = REJECTIONS[name]
            record["expected_diagnostic"] = pattern
            record["diagnostic_matched"] = bool(re.search(pattern, result.stdout))
            record["passed"] = result.returncode > 0 and record["diagnostic_matched"]
            return record
        if result.returncode:
            return record
        executable = subprocess.run([str(directory / "program")], cwd=directory,
                                    env=environment, text=True, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, timeout=10)
        (directory / "run.log").write_text(executable.stdout)
        record.update(run_status=executable.returncode,
                      passed=executable.returncode == 0)
        if name == "module_ordinary_cleanup":
            marker = directory / "cleanup-pids.txt"
            counts = dict(Counter(marker.read_text().splitlines())) if marker.exists() else {}
            record["cleanup_counts"] = counts
            record["cleanup_once_per_process"] = bool(counts) and all(
                count == 1 for count in counts.values())
            record["passed"] &= record["cleanup_once_per_process"]
    except subprocess.TimeoutExpired as failure:
        record.update(timeout=True, failed_command=failure.cmd)
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("compiler", type=Path)
    parser.add_argument("--home", type=Path)
    parser.add_argument("--case", action="append", choices=list(CASES))
    arguments = parser.parse_args()
    compiler = arguments.compiler.resolve()
    home = arguments.home
    if home is None:
        result = subprocess.run([str(compiler), "env", "home"], text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        if result.returncode:
            parser.error("compiler env home failed; pass --home explicitly")
        home = Path(result.stdout.strip())
    home = home.resolve()
    base = Path(tempfile.mkdtemp(prefix="x2c-module-native-meta-", dir="/tmp"))
    rows = []
    for name in arguments.case or CASES:
        record = run_case(compiler, home, base, name)
        rows.append(record)
        print(json.dumps(record), flush=True)
    receipt = base / "results.json"
    receipt.write_text(json.dumps(rows, indent=2) + "\n")
    print(json.dumps({"results": str(receipt), "passed": all(row["passed"] for row in rows)}))
    return 0 if all(row["passed"] for row in rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
