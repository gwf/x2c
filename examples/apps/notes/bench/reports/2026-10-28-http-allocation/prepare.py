import pathlib,subprocess,shutil,tempfile,json,os,importlib.util,types,statistics
r=pathlib.Path('/Users/gary/.codex/worktrees/216e/x2c');p=pathlib.Path(tempfile.mkdtemp(prefix='notes-http-allocation-',dir='/tmp'));(r/'.context/notes-http-allocation').write_text(str(p));before=pathlib.Path((r/'.context/notes-pool-fast-path').read_text());old=before/'libx2c.a';new=p/'libx2c.a';shutil.copy2(old,new)
subprocess.run(['ar','r',str(new),str(r/'builds/0/lib/http.o'),str(r/'builds/0/lib/json.o')],check=True)
members=[n for n in subprocess.check_output(['ar','t',str(old)],text=True).splitlines()if not n.startswith('__.SYMDEF')];changed=[n for n in members if subprocess.check_output(['ar','p',str(old),n])!=subprocess.check_output(['ar','p',str(new),n])];assert sorted(changed)==['http.o','json.o'],changed
prefix=pathlib.Path('/Users/gary/Git/x2c/.git/x2c-integrations/entries/sqlite/ce1e69efa2f64069cf806ec48abc9132b2b63b3667de22fcb5361ad90222f7e9/prefix')
for n,d in [('mutex','mutex-build'),('database_thread','database-thread-build')]:
 obj=next((pathlib.Path('/tmp/notes-architectures-build-sjdyyky_')/d/'obj').glob('*.o'));subprocess.run(['cc',str(obj),str(r/'packages/sqlite/builds/libsqlite.a'),str(prefix/'lib/libsqlite3.a'),'-pthread',str(new),'-lm','-o',str(p/n)],check=True);subprocess.run(['python3',str(r/'examples/apps/notes/tests/test_notes.py'),str(p/n)],cwd=r,check=True)
subprocess.run(['python3',str(r/'examples/apps/notes/bench/test-threaded.py'),str(p/'database_thread')],cwd=r,check=True)
print('BUILD_PREFLIGHT_COMPLETE',p,flush=True)
if os.environ.get('NOTES_BUILD_ONLY'):raise SystemExit(0)
