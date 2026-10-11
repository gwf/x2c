#!/usr/bin/env python3
"""Optional serial package make, bundle, relocation, and local-install probe.

Run against an isolated compiler with --root and --compiler. The probe retains
its /tmp scratch tree and receipts for inspection. It is outside recurring gates.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, required=True)
parser.add_argument('--compiler', type=Path, required=True)
args = parser.parse_args()
root, compiler = args.root.resolve(), args.compiler.resolve()
work = Path(tempfile.mkdtemp(prefix='x2c-nested-package-delivery-', dir='/tmp'))
rows = []
env = dict(os.environ, X2C_HOME=str(root), BUILD_JOBS='1')

def run(name, command, cwd=work, environment=env):
    log = work / f'{name}.log'
    with log.open('w') as stream:
        completed = subprocess.run([str(x) for x in command], cwd=cwd,
                                   env=environment, stdout=stream,
                                   stderr=subprocess.STDOUT)
    rows.append(dict(name=name, status=completed.returncode, log=str(log),
                     command=[str(x) for x in command]))
    if completed.returncode:
        raise RuntimeError(f'{name} failed: {log}')

package = work / 'packages/demo'
source = package / 'src'
(source / 'demo/child').mkdir(parents=True)
(source / 'demo.x').write_text('module {"demo/child.x"}\n'
                              'int root_answer(void) => child_answer();\n')
(source / 'demo/child.x').write_text('module {"child/value.x"}\n')
(source / 'config.h').write_text('typedef int NativeWord;\n')
(source / 'demo/child/value.x').write_text('#include "config.h"\n'
                                         'module NativeWord helper(void) => 42;\n'
                                         'NativeWord child_answer(void) => helper();\n')
(package / 'Makefile').write_text(f'PACKAGE := demo\ninclude {root}/packages/package.mk\n')
client = work / 'client.x'
client.write_text('import "demo" as d with child_answer as child;\n'
                  'int main(void) => d.root_answer() == 42 && child() == 42 ? 0 : 1;\n')

def consume(name, package_dir, selected=compiler, environment=env):
    program = work / name
    run(name + '-build', [selected, 'build', '-j', '1', '--package-dir', package_dir,
                          '--output', program, '--build-dir', work / (name + '-build'),
                          client], environment=environment)
    run(name + '-run', [program], environment=environment)

try:
    make = ['make', '-j1', f'X2C={compiler}', f'ROOT={root}', 'BUILD_JOBS=1']
    run('make-package', [*make, 'build'], package)
    consume('make-consumer', package.parent)
    (package / 'builds/demo.link').write_text('')
    run('bundle-relative-1', [*make, 'bundle'], package)
    run('bundle-relative-2', [*make, 'bundle'], package)
    consume('bundle-consumer', package / 'builds/bundle')
    run('build-after-relative-bundle', [*make, 'build'], package)
    absolute_bundle = package / 'builds/bundle'
    run('bundle-absolute', [*make, 'bundle', f'BUNDLE_DIR={absolute_bundle}'], package)
    run('build-after-absolute-bundle', [*make, 'build', f'BUNDLE_DIR={absolute_bundle}'], package)
    consume('absolute-bundle-consumer', absolute_bundle)
    relocated = work / 'relocated-packages/demo'
    shutil.copytree(absolute_bundle / 'demo', relocated)
    moved_package = package.with_name('original-demo')
    package.rename(moved_package)
    try:
        generated = sorted((relocated / 'builds').rglob('*.c'))
        generated = [path for path in generated if path.relative_to(
            relocated / 'builds').parts[0] not in ('cc', 'module', 'native')]
        quote_roots = sorted({path.parent for path in generated})
        native_flags = [argument for directory in quote_roots
                        for argument in ('-Xcc', '-iquote', '-Xcc', directory)]
        run('relocated-native-bundle-rebuild', [compiler, 'build', '-j', '1',
            '--kind', 'static-library', '--output', relocated / 'builds/libdemo.a',
            '--build-dir', work / 'relocated-native-rebuild',
            *native_flags, *generated])
        consume('relocated-native-bundle-consumer', relocated.parent)
    except RuntimeError:
        pass
    finally:
        moved_package.rename(package)
    flat = work / 'flat-packages/flat'
    (flat / 'src').mkdir(parents=True)
    (flat / 'src/flat.x').write_text('int answer(void) => 42;\n')
    (flat / 'Makefile').write_text(f'PACKAGE := flat\ninclude {root}/packages/package.mk\n')
    run('flat-make', [*make, 'build'], flat)
    (flat / 'builds/flat.link').write_text('')
    run('bundle-builds-1', [*make, 'bundle', 'BUNDLE_DIR=builds'], flat)
    run('bundle-builds-2', [*make, 'bundle', 'BUNDLE_DIR=builds'], flat)
    run('build-after-builds-bundle', [*make, 'build', 'BUNDLE_DIR=builds'], flat)
    flat_client = work / 'flat-client.x'
    flat_client.write_text('import "flat" as f;\nint main(void) => f.answer() == 42 ? 0 : 1;\n')
    flat_program = work / 'flat-program'
    run('flat-bundle-consumer-build', [compiler, 'build', '-j', '1',
        '--package-dir', flat / 'builds', '--output', flat_program,
        '--build-dir', work / 'flat-client-build', flat_client])
    run('flat-bundle-consumer-run', [flat_program])
    home = work / 'home'
    for directory in ['bin', 'packages', 'include/x2c']:
        (home / directory).mkdir(parents=True)
    shutil.copytree(root / 'etc', home / 'etc')
    shutil.copytree(root / 'lib', home / 'lib')
    shutil.copytree(root / 'src', home / 'src')
    (home / 'tools').mkdir()
    shutil.copy2(root / 'tools/native-layout-project.py', home / 'tools/native-layout-project.py')
    for path in (root / 'lib').glob('*.x'):
        shutil.copy2(path, home / 'include/x2c' / path.name)
    for path in (root / 'builds/0/lib').iterdir():
        if path.is_file() and path.suffix in {'.h', '.xi', '.c', '.xnm'}:
            shutil.copy2(path, home / 'include/x2c' / path.name)
            shutil.copy2(path, home / 'lib' / path.name)
    shutil.copy2(root / 'builds/0/libx2c.a', home / 'lib/libx2c.a')
    installed_compiler = home / 'bin/x2c'
    shutil.copy2(compiler, installed_compiler)
    install_env = dict(env, X2C_HOME=str(home))
    run('source-install', [installed_compiler, 'install', '-q', package], environment=install_env)
    moved_package = package.with_name('original-demo')
    package.rename(moved_package)
    try:
        consume('installed-native-header-consumer', home / 'packages', installed_compiler, install_env)
    finally:
        moved_package.rename(package)
except Exception as error:
    rows.append(dict(name='fixture-error', status=1, detail=str(error)))
finally:
    passed = not any(row['status'] for row in rows)
    rows.append(dict(name='fixture-summary', status=0 if passed else 1,
                     passed=passed, completed=len(rows)))
    receipt = work / 'results.json'
    receipt.write_text(json.dumps(rows, indent=2) + '\n')
    print(receipt)
raise SystemExit(any(row['status'] for row in rows))
