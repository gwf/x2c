import subprocess,pathlib,os,time,json,statistics,hashlib,argparse
p=argparse.ArgumentParser()
for option in ['source-root','x2c-home','out','baseline','candidate']:p.add_argument('--'+option,required=True)
p.add_argument('--samples',type=int,default=5);a=p.parse_args()
root=pathlib.Path(a.source_root).resolve();out=pathlib.Path(a.out).resolve();out.mkdir(parents=True,exist_ok=True)
env=os.environ.copy();env.pop('X2C_DUAL_EFFECT_PROBE',None);env['X2C_HOME']=str(pathlib.Path(a.x2c_home).resolve())
compilers={'baseline':a.baseline,'candidate':a.candidate}
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
  for sample in range(1,a.samples+1):
   order=['baseline','candidate'] if sample%2 else ['candidate','baseline']
   for label in order:
    seconds=run(label,mode,group);row=dict(group=group,mode=mode,label=label,sample=sample,seconds=seconds);samples.append(row);print(json.dumps(row),flush=True)
   (out/'samples.json').write_text(json.dumps(dict(x2c_home=env['X2C_HOME'],source_root=str(root),effect_probe_unset=True,checksums=checksums,samples=samples),indent=2))
after={k:hashlib.sha256(pathlib.Path(v).read_bytes()).hexdigest() for k,v in compilers.items()}
assert after==checksums, (checksums,after)
(out/'checksums-after.json').write_text(json.dumps(after,indent=2))
print('COMPLETE',flush=True)
