import pathlib, subprocess, shutil, tempfile, json, os, importlib.util, types, hashlib
r=pathlib.Path('/Users/gary/.codex/worktrees/216e/x2c')
p=pathlib.Path(tempfile.mkdtemp(prefix='notes-pool-fast-',dir='/tmp'))
(r/'.context/notes-pool-fast-path').write_text(str(p))
old=pathlib.Path('/tmp/notes-no-names-vikm548j/libx2c.a')
new=p/'libx2c.a'
shutil.copy2(old,new)
subprocess.run(['ar','r',str(new),str(r/'builds/0/lib/pool.o')],check=True)
members=[n for n in subprocess.check_output(['ar','t',str(old)],text=True).splitlines() if not n.startswith('__.SYMDEF')]
changed=[n for n in members if subprocess.check_output(['ar','p',str(old),n])!=subprocess.check_output(['ar','p',str(new),n])]
assert changed==['pool.o'],changed
prefix=pathlib.Path('/Users/gary/Git/x2c/.git/x2c-integrations/entries/sqlite/ce1e69efa2f64069cf806ec48abc9132b2b63b3667de22fcb5361ad90222f7e9/prefix')
for n,d in [('mutex','mutex-build'),('database_thread','database-thread-build')]:
 obj=next((pathlib.Path('/tmp/notes-architectures-build-sjdyyky_')/d/'obj').glob('*.o'))
 subprocess.run(['cc',str(obj),str(r/'packages/sqlite/builds/libsqlite.a'),str(prefix/'lib/libsqlite3.a'),'-pthread',str(new),'-lm','-o',str(p/n)],check=True)
 subprocess.run(['python3',str(r/'examples/apps/notes/tests/test_notes.py'),str(p/n)],cwd=r,check=True)
subprocess.run(['python3',str(r/'examples/apps/notes/bench/test-threaded.py'),str(p/'database_thread')],cwd=r,check=True)
spec=importlib.util.spec_from_file_location('compare',r/'examples/apps/notes/bench/compare.py');c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)
os.environ.pop('X2C_SCOPE_ACCOUNTING',None)
bins={'mutex_before':pathlib.Path('/tmp/notes-no-names-vikm548j/mutex'),'mutex_after':p/'mutex','thread_before':pathlib.Path('/tmp/notes-no-names-vikm548j/database_thread'),'thread_after':p/'database_thread','go':pathlib.Path('/tmp/x2c-notes-go-w10r0v0i/notes-go')}
args=types.SimpleNamespace(warmup=1,seconds=5);base=list(bins)
res={'scratch':str(p),'runs':3,'clients':64,'seconds':5,'warmup_s':1,'naming':'disabled in both x2c runtimes','accounting':False,'changed_archive_members':changed,'samples':{k:[] for k in bins},'order':[],'binary_sha256':{k:c.digest(v) for k,v in bins.items()},'fixture_sha256':c.digest(pathlib.Path('/tmp/notes-compare-vlib4wkr/fixture.db'))}
for i in range(3):
 order=base[i:]+base[:i];res['order'].append(order)
 for n in order:
  row=c.measure(bins[n],pathlib.Path('/tmp/notes-compare-vlib4wkr/fixture.db'),args,pathlib.Path('/tmp/notes-compare-vlib4wkr/load'),'lookup',64,p/f'{i}-{n}')
  res['samples'][n].append(row);(p/'comparison.json').write_text(json.dumps(res,indent=2)+'\n');print(i+1,n,row['requests_per_s'],flush=True)
res['summary']={n:c.summarize(a) for n,a in res['samples'].items()}
(p/'comparison.json').write_text(json.dumps(res,indent=2)+'\n');print(json.dumps(res['summary'],indent=2),flush=True)
