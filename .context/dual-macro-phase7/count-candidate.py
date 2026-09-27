import os,pathlib,subprocess,re,json,hashlib
p=pathlib.Path(__file__).resolve().parent;root=pathlib.Path('/Users/gary/.codex/worktrees/agent-dual-transport/x2c');out=pathlib.Path('/tmp/dual-phase7-counts');out.mkdir(exist_ok=True)
corpus=['src/transform.x','src/emit.x','src/expressions.x','src/generate.x','src/parse.x','src/type.x','lib/tokenizer.x','unittest/benchmarks/exception-hot-paths.x']
b=json.loads((p.parent/'dual-macro-phase5/final-manifest.json').read_text());expected={(r['source'],r.get('mode','fixture')):r for r in b['results']};records=[];logs=[]
for mode,flags in [('default',[]),('live',['--live-symbols'])]:
 for source in corpus:
  folder=out/mode/pathlib.Path(source).stem;folder.mkdir(parents=True,exist_ok=True)
  env=os.environ.copy();env['X2C_HOME']=str(root);env['X2C_DUAL_COUNTS']='1';env.pop('X2C_DUAL_EFFECT_PROBE',None);env.pop('X2C_DUAL_PROFILE',None)
  cmd=['/tmp/x2c-dual-phase7-counts','translate',*flags,'--out-dir',str(folder),str(root/source)]
  r=subprocess.run(cmd,cwd=root,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);logs.append('COMMAND '+repr(cmd)+'\n'+r.stdout.decode());m=re.search(rb'DUAL_COUNTS transactions (\d+) extended (\d+) applications (\d+)',r.stdout);counts=dict(zip(['transactions','extended','applications'],map(int,m.groups())))
  files={str(f.relative_to(folder)):{'bytes':f.stat().st_size,'sha256':hashlib.sha256(f.read_bytes()).hexdigest()} for f in folder.rglob('*') if f.suffix in ['.c','.h']};e=expected[(source,mode)]
  records.append(dict(source=source,mode=mode,counts=counts,exit=r.returncode,parity=r.returncode==e['exit'] and files==e['files'],files=files));print(mode,source,counts,'parity',records[-1]['parity'],flush=True)
(p/'candidate-counts.json').write_text(json.dumps(records,indent=2));(p/'candidate-counts.log').write_text('\n'.join(logs))
