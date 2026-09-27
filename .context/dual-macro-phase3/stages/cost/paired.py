import subprocess,pathlib,os,time,json,statistics,hashlib
root=pathlib.Path('/Users/gary/.codex/worktrees/agent-dual-transport/x2c');out=pathlib.Path('/tmp/dual-try-paired');out.mkdir(exist_ok=True)
env=os.environ.copy();env['X2C_HOME']=str(root)
compilers={'baseline':'/tmp/x2c-dual-compiler-baseline','candidate':'/Users/gary/.codex/worktrees/dual-macro-match-probe/x2c/builds/0/x2c'}
groups={'compiler-translation':['src/transform.x','src/emit.x','src/expressions.x','src/generate.x','src/parse.x','src/type.x','lib/tokenizer.x'],'exception-translation':['unittest/benchmarks/exception-hot-paths.x']}
checksums={k:hashlib.sha256(pathlib.Path(v).read_bytes()).hexdigest() for k,v in compilers.items()}
samples=[]
def run(label,mode,group):
 flags=['--live-symbols'] if mode=='live' else []
 t=time.perf_counter()
 for source in groups[group]:
  directory=out/label/mode/pathlib.Path(source).stem;directory.mkdir(parents=True,exist_ok=True)
  r=subprocess.run([compilers[label],'translate',*flags,'--out-dir',str(directory),str(root/source)],cwd=root,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
  (directory/'command.log').write_bytes(r.stdout)
  if r.returncode:raise RuntimeError((label,mode,source,r.returncode))
 return time.perf_counter()-t
for group in groups:
 for mode in ['default','live']:
  for label in compilers:run(label,mode,group)
  for sample in range(1,6):
   order=['baseline','candidate'] if sample%2 else ['candidate','baseline']
   for label in order:
    seconds=run(label,mode,group);row=dict(group=group,mode=mode,label=label,sample=sample,seconds=seconds);samples.append(row);print(json.dumps(row),flush=True)
   (out/'samples.json').write_text(json.dumps(dict(x2c_home=str(root),checksums=checksums,samples=samples),indent=2))
print('COMPLETE',flush=True)
