import pathlib,subprocess,shutil,tempfile,json
r=pathlib.Path('/Users/gary/.codex/worktrees/216e/x2c');p=pathlib.Path(tempfile.mkdtemp(prefix='notes-root-index-',dir='/tmp'));(r/'.context/notes-root-index').write_text(str(p));base=pathlib.Path((r/'.context/notes-http-allocation').read_text());shutil.copy2(base/'libx2c.a',p/'libx2c.a');subprocess.run(['ar','r',str(p/'libx2c.a'),str(r/'builds/0/lib/pool.o'),str(r/'builds/0/lib/string.o')],check=True)
members=[n for n in subprocess.check_output(['ar','t',str(base/'libx2c.a')],text=True).splitlines()if not n.startswith('__.SYMDEF')];changed=[n for n in members if subprocess.check_output(['ar','p',str(base/'libx2c.a'),n])!=subprocess.check_output(['ar','p',str(p/'libx2c.a'),n])];assert sorted(changed)==['pool.o','string.o'],changed
prefix=pathlib.Path('/Users/gary/Git/x2c/.git/x2c-integrations/entries/sqlite/ce1e69efa2f64069cf806ec48abc9132b2b63b3667de22fcb5361ad90222f7e9/prefix')
for n,d in [('mutex','mutex-build'),('database_thread','database-thread-build')]:
 obj=next((pathlib.Path('/tmp/notes-architectures-build-sjdyyky_')/d/'obj').glob('*.o'));subprocess.run(['cc',str(obj),str(r/'packages/sqlite/builds/libsqlite.a'),str(prefix/'lib/libsqlite3.a'),'-pthread',str(p/'libx2c.a'),'-lm','-o',str(p/n)],check=True);subprocess.run(['python3',str(r/'examples/apps/notes/tests/test_notes.py'),str(p/n)],cwd=r,check=True)
subprocess.run(['python3',str(r/'examples/apps/notes/bench/test-threaded.py'),str(p/'database_thread')],cwd=r,check=True)
print('PREPARED',p,changed)
