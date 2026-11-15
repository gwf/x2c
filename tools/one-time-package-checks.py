#!/usr/bin/env python3
"""One-time, retained installed-package evidence; run in exact candidate checkout."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

p = argparse.ArgumentParser()
p.add_argument('--identity', required=True)
p.add_argument('--source-sha', required=True)
p.add_argument('--target', required=True)
a = p.parse_args()
root = Path.cwd()
work = Path(tempfile.mkdtemp(prefix='x2c-twenty-' + a.target + '-'))
print('ARTIFACT_DIRECTORY=' + str(work), flush=True)
rows = []
manifest = {}
manifest_hash = None
compiler_hash = None
compiler_legal = {}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def run(command, cwd, log, timeout=300):
    try:
        r = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        out, err, code = r.stdout, r.stderr, r.returncode
    except subprocess.TimeoutExpired as e:
        out = e.stdout or b''; err = e.stderr or b''
        out = out.decode(errors='replace') if isinstance(out, bytes) else out
        err = err.decode(errors='replace') if isinstance(err, bytes) else err
        err += '\nTimed out after %s seconds\n' % timeout; code = 124
    (work / (log + '.stdout')).write_text(out)
    (work / (log + '.stderr')).write_text(err)
    record = dict(command=command, cwd=str(cwd), exit_code=code,
                  stdout=out, stderr=err, stdout_log=str(work/(log+'.stdout')),
                  stderr_log=str(work/(log+'.stderr')))
    return record

def checked(command, cwd, log):
    result = run(command, cwd, log)
    assert result['exit_code'] == 0, result
    return result

def asset(name):
    dest = work / name
    checked(['curl', '-fsSL', '--retry', '3', base + '/' + name, '-o', str(dest)], work, 'download-'+name)
    assert digest(dest) == manifest['assets'][name]['sha256'], 'hash mismatch: '+name
    return dest

def save():
    (work/'results.json').write_text(json.dumps(dict(identity=a.identity, source_sha=a.source_sha,
        target=a.target, manifest_sha256=manifest_hash, compiler_sha256=compiler_hash, compiler_legal=compiler_legal,
        artifact_directory=str(work), results=rows), indent=2)+'\n')

packages = {'yyjson':'release-catalog.x', 'libcurl':'page-titles.x',
            'termbox2':'game-of-life.x', 'libuv':'process-report.x', 'blis':'page-rank.x'}
base = 'https://github.com/gwf/x2c-staging/releases/download/' + a.identity
try:
    assert subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip() == a.source_sha
    assert platform.system().lower()+'-'+platform.machine() == a.target
    for tool in ('curl','cc'):
        assert shutil.which(tool), 'missing tool: '+tool
    checked(['curl','-fsSL','--retry','3',base+'/candidate.json','-o',str(work/'candidate.json')],work,'manifest')
    manifest = json.loads((work/'candidate.json').read_text())
    manifest_hash = digest(work/'candidate.json')
    assert manifest['identity'] == a.identity and manifest['source_sha'] == a.source_sha
    compiler = asset('x2c-'+manifest['version']+'-'+a.target+'.tar.gz')
    compiler_hash = digest(compiler)
    tree = work/'compiler-tree'; tree.mkdir()
    checked(['tar','-xzf',str(compiler),'-C',str(tree)],work,'unpack-compiler')
    installs = [x for x in tree.iterdir() if x.is_dir() and (x/'.x2c-install-manifest').is_file()]
    assert len(installs) == 1, 'compiler archive installation layout'
    prefix = work/'prefix'; installs[0].rename(prefix)
    for name in ('LICENSE', 'NOTICE'):
        legal = prefix/'licenses'/name
        assert legal.read_bytes() == (root/name).read_bytes(), 'compiler legal content differs: '+name
        compiler_legal[name] = dict(path=str(legal), sha256=digest(legal), source=str(root/name))
    x2c = str(prefix/'bin/x2c')
    version = checked([x2c,'--version'],work,'version')
    assert version['stdout'].strip() == 'x2c '+manifest['version']
except Exception as e:
    for package in packages:
        rows.append(dict(package=package,status='blocked',reason=str(e)))
    save(); raise

for package, example in packages.items():
    row = dict(package=package, identity=a.identity, source_sha=a.source_sha, target=a.target,
               manifest_sha256=manifest_hash, compiler_sha256=compiler_hash, commands=[])
    rows.append(row)
    try:
        archive = asset(package+'-'+a.target+'-native.tar.gz')
        row['archive'] = archive.name; row['archive_sha256'] = digest(archive)
        with tarfile.open(archive) as tar:
            legal = [m for m in tar.getmembers() if m.isfile() and
                     (Path(m.name).name.upper().startswith('LICENSE') or Path(m.name).name.upper().startswith('NOTICE') or 'LICENSES' in Path(m.name).parts)]
            for name in ('LICENSE', 'NOTICE'):
                members = [m for m in legal if m.name.removeprefix('./') == package+'/'+name]
                assert len(members)==1, 'missing package root '+name
                assert tar.extractfile(members[0]).read() == (root/'packages'/package/name).read_bytes(), 'package legal content differs: '+name
            bundle_members = [m for m in tar.getmembers() if m.name.removeprefix('./') == package+'/BUNDLE.json']
            assert len(bundle_members)==1, 'missing archive BUNDLE.json'
            row['archive_identity'] = json.loads(tar.extractfile(bundle_members[0]).read())
            row['legal_files'] = {m.name:dict(sha256=hashlib.sha256(tar.extractfile(m).read()).hexdigest(), size=m.size) for m in legal}
            assert any(Path(m.name).name.upper().startswith('LICENSE') for m in legal), 'missing LICENSE'
            assert any(Path(m.name).name.upper().startswith('NOTICE') for m in legal), 'missing NOTICE'
            for i,m in enumerate(legal):
                (work/(package+'-legal-'+str(i)+'.txt')).write_bytes(tar.extractfile(m).read())
        install = run([x2c,'install','-q',str(archive)],work,package+'-install')
        row['commands'].append(install); assert install['exit_code']==0, 'install failed'
        bundle = prefix/'packages'/package/'BUNDLE.json'
        assert bundle.is_file(), 'missing installed BUNDLE.json'
        row['installed_identity'] = json.loads(bundle.read_text())
        assert row['installed_identity']['package'] == package
        assert row['installed_identity']['platform'] + '-' + row['installed_identity']['machine'] == a.target
        assert row['installed_identity']['x2c_version'] == 'x2c '+manifest['version']
        assert row['installed_identity'] == row['archive_identity']
        row['installed_files'] = [str(f.relative_to(prefix)) for f in (prefix/'packages'/package).rglob('*') if f.is_file()]
        if a.target.startswith('darwin-'):
            for i,lib in enumerate((prefix/'packages'/package).rglob('*.dylib')):
                link = run(['otool','-L',str(lib)],work,package+'-linkage-'+str(i))
                row['commands'].append(link); assert link['exit_code']==0
                assert not re.search(r'/opt/homebrew|/usr/local/(?:opt|Cellar)/', '\n'.join(link['stdout'].splitlines()[1:])), 'Homebrew linkage'
        app = work/package; app.mkdir(); shutil.copy2(root/'packages'/package/'examples'/example, app/example)
        output = 'program'
        if package=='termbox2':
            if not shutil.which('expect'):
                row['status']='blocked'; row['reason']='missing required expect'; continue
            (app/'builds').mkdir(); output='builds/game-of-life'
            shutil.copy2(root/'packages/termbox2/tests/run-life.expect',app/'run-life.expect')
        if package=='libcurl':
            shutil.copy2(root/'packages/libcurl/tools/run-fixture.py',app/'run-fixture.py')
        build = run([x2c,'build','-q','--output',output,example],app,package+'-build')
        row['commands'].append(build); assert build['exit_code']==0, 'build failed'
        command = ['expect','run-life.expect'] if package=='termbox2' else ([sys.executable,'run-fixture.py','./program'] if package=='libcurl' else ['./program'])
        result = run(command,app,package+'-run',timeout=60); row['commands'].append(result)
        assert result['exit_code']==0, 'run failed'
        text=result['stdout']
        if package=='yyjson':
            row['expected']='published service edge-api; stable downloads 2270; two region entries'
            assert 'published service: edge-api' in text and 'stable downloads: 2270' in text and 'region entries: 2' in text
        elif package=='libcurl':
            row['expected']='guide/reference/source titles match local fixture'
            assert text.strip()=='guide: x2c Language Guide\nreference: x2c Reference\nsource: x2c Source'
        elif package=='libuv':
            row['expected']='ALPHA/BETA/GAMMA; line count 3; both exits 0'
            assert re.search(r'normalized:\s+ALPHA\s+BETA\s+GAMMA',text)
            assert re.search(r'line count:\s*3\s',text) and 'exits: normalized=0 counted=0' in text
        elif package=='blis':
            row['expected']='five finite page scores; convergence before 100 rounds'
            match=re.search(r'converged after (\d+) rounds, shift (\S+)',text)
            assert match and int(match[1])<100 and math.isfinite(float(match[2])) and float(match[2])<=1e-15
            scores=re.findall(r'^\s+(index|guide|reference|download|blog)\s+(\S+)',text,re.M)
            assert len(scores)==5 and len({n for n,v in scores})==5 and all(math.isfinite(float(v)) for n,v in scores)
        else:
            row['expected']='existing PTY helper sees cell, sends q, confirms exit 0'
        row['status']='passed'
    except Exception as e:
        row['status']='failed'; row['reason']=str(e)
    finally:
        save()
print(json.dumps(rows,indent=2))
sys.exit(0 if all(r['status']=='passed' for r in rows) else 1)
