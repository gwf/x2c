import subprocess,pathlib,os,time,json,statistics,hashlib,argparse
p=argparse.ArgumentParser()
for option in ['source-root','x2c-home','out','baseline','phase5','candidate']:p.add_argument('--'+option,required=True)
p.add_argument('--samples',type=int,default=5);a=p.parse_args()
root=pathlib.Path(a.source_root).resolve();out=pathlib.Path(a.out).resolve();out.mkdir(parents=True,exist_ok=True)
env=os.environ.copy();env.pop('X2C_DUAL_EFFECT_PROBE',None);env.pop('X2C_DUAL_PROFILE',None);env['X2C_HOME']=str(pathlib.Path(a.x2c_home).resolve())
compilers={'baseline':a.baseline,'phase5':a.phase5,'candidate':a.candidate}
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
   labels=list(compilers);offset=(sample-1)%3
   order=labels[offset:]+labels[:offset]
   if sample%2==0:order.reverse()
   for label in order:
    seconds=run(label,mode,group);row=dict(group=group,mode=mode,label=label,sample=sample,seconds=seconds);samples.append(row);print(json.dumps(row),flush=True)
   (out/'samples.json').write_text(json.dumps(dict(x2c_home=env['X2C_HOME'],source_root=str(root),effect_probe_unset=True,checksums=checksums,samples=samples),indent=2))
after={k:hashlib.sha256(pathlib.Path(v).read_bytes()).hexdigest() for k,v in compilers.items()}
assert after==checksums, (checksums,after)
(out/'checksums-after.json').write_text(json.dumps(after,indent=2))
print('COMPLETE',flush=True)

summary=[]
for group in groups:
 for mode in ['default','live']:
  values={label:[r['seconds'] for r in samples if r['group']==group and r['mode']==mode and r['label']==label] for label in compilers}
  stats={label:dict(median=statistics.median(v),min=min(v),max=max(v)) for label,v in values.items()}
  ratios={label:100*(stats[label]['median']/stats['baseline']['median']-1) for label in compilers}
  summary.append(dict(group=group,mode=mode,statistics=stats,ratios_percent=ratios,removal_increment_percentage_points=ratios['candidate']-ratios['phase5']))
(out/'summary.json').write_text(json.dumps(summary,indent=2))
# Retain unnormalized digests for every final timed output.
digests={}
for label in compilers:
 digests[label]={str(f.relative_to(out/label)):{'bytes':f.stat().st_size,'sha256':hashlib.sha256(f.read_bytes()).hexdigest()} for f in sorted((out/label).rglob('*')) if f.suffix in ['.c','.h']}
assert digests['baseline']==digests['phase5']==digests['candidate']
(out/'timed-artifact-digests.json').write_text(json.dumps(digests,indent=2))
