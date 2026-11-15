#!/usr/bin/env python3
"""Run from a built checkout. Keep evidence; do not alter tracked sources."""
import os, pathlib, subprocess, tempfile, sys, time, signal
root = pathlib.Path.cwd()
probe = pathlib.Path(tempfile.mkdtemp(prefix='x2c-repl-manifest-'))
print(probe, flush=True)
(probe/'manifest.c').write_text('int dependency_value(void);\nint manifest_value(void) { return dependency_value() + SELECTED_VALUE; }\n')
(probe/'dependency.c').write_text('int dependency_value(void) { return DEPENDENCY_VALUE; }\n')
(probe/'extra.c').write_text('int extra_value(void) { return 5; }\n')
(probe/'x2c.toml').write_text('''[project]
name = "repl-program-probe"
default-target = "app"
[target.dependency]
kind = "static-library"
sources = ["dependency.c"]
c-flags = ["-DDEPENDENCY_VALUE=7"]
[target.app]
sources = ["manifest.c"]
dependencies = ["dependency"]
c-flags = ["-DSELECTED_VALUE=10", "-DDEPENDENCY_VALUE=99"]
''')
base = [str(root/'builds/0/x2c'), 'repl']
manifest = ['--manifest-path', str(probe/'x2c.toml'), '--target', 'app']
cases = [('empty', [], ''), ('manifest-start', manifest, ''), ('manifest-reload', manifest, f':load "{probe}/extra.c"\n:reload\n:reload\n:files\nmanifest_value() + extra_value();\n')]
for name, args, text in cases:
    inp = probe/(name+'.in'); inp.write_text(text)
    with inp.open('rb') as stdin, (probe/(name+'.log')).open('wb') as log:
        p = subprocess.Popen(base+args, stdin=stdin, stdout=log, stderr=subprocess.STDOUT, start_new_session=True, env={**os.environ,'TMPDIR':str(probe)})
        try:
            code = p.wait(timeout=90)
            print(name, 'exit', code, flush=True)
        except subprocess.TimeoutExpired:
            ps = subprocess.check_output(['ps','-eo','pid,ppid,pgid,stat,wchan:24,args'], text=True)
            (probe/(name+'.ps')).write_text(ps)
            rows = [line.split(None, 5) for line in ps.splitlines()[1:]]
            ids = {p.pid}
            while True:
                more = {int(r[0]) for r in rows if len(r)>1 and int(r[1]) in ids}
                if more <= ids: break
                ids |= more
            for pid in ids:
                for leaf in ['wchan','stack','status']:
                    try: (probe/f'{name}.{pid}.{leaf}').write_text(pathlib.Path(f'/proc/{pid}/{leaf}').read_text())
                    except OSError: pass
            for pid in ids:
                try: os.kill(pid, signal.SIGKILL)
                except ProcessLookupError: pass
            p.wait()
            print(name, 'TIMEOUT', sorted(ids), flush=True)
    print((probe/(name+'.log')).read_text(errors='replace')[-4000:], flush=True)
