import os, pathlib, subprocess, re, json, hashlib, statistics
root=pathlib.Path('/Users/gary/.codex/worktrees/agent-dual-transport/x2c')
here=pathlib.Path(__file__).resolve().parent
out=here/'runs';out.mkdir(exist_ok=True)
compiler='/tmp/x2c-dual-phase7-instrumented'
corpus=['src/transform.x','src/emit.x','src/expressions.x','src/generate.x','src/parse.x','src/type.x','lib/tokenizer.x','unittest/benchmarks/exception-hot-paths.x']
baseline=json.loads((here.parents[1]/'dual-macro-phase5/final-manifest.json').read_text())
expected={(r['source'],r.get('mode','fixture')):r for r in baseline['results']}
records=[]
for kind,samples,sources in [('timed',range(3),corpus),('counts',range(1),corpus),('fixture',range(3),['unittest/compiler-fixtures/defer-try-cleanup.x'])]:
 for mode in (['default'] if kind=='fixture' else ['default','live']):
  for sample in samples:
   for source in sources:
    folder=out/kind/mode/str(sample)/pathlib.Path(source).stem;folder.mkdir(parents=True,exist_ok=True)
    env=os.environ.copy();env['X2C_HOME']=str(root);env['X2C_DUAL_PROFILE']='counts' if kind=='counts' else '1';env.pop('X2C_DUAL_EFFECT_PROBE',None)
    cmd=[compiler,'translate',*(['--live-symbols'] if mode=='live' else []),'--out-dir',str(folder),str(root/source)]
    r=subprocess.run(cmd,cwd=root,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);(folder/'command.log').write_bytes(r.stdout)
    metrics={name:{'calls':int(count),'inclusive_ns':int(inc),'exclusive_ns':int(exc)} for name,count,inc,exc in re.findall(r'DUAL_PROFILE (\S+) (\d+) (\d+) (\d+)',r.stdout.decode())}
    files={str(f.relative_to(folder)):{'bytes':f.stat().st_size,'sha256':hashlib.sha256(f.read_bytes()).hexdigest()} for f in sorted(folder.rglob('*')) if f.suffix in ['.c','.h']}
    key=(source,'fixture' if kind=='fixture' else mode);b=expected[key]
    records.append(dict(kind=kind,mode=mode,sample=sample,source=source,exit=r.returncode,metrics=metrics,parity=r.returncode==b['exit'] and files==b['files'],files=files))
    print(kind,mode,sample,source,'parity',records[-1]['parity'],flush=True)
(here/'results.json').write_text(json.dumps(records,indent=2))
summary=[]
for kind in ['timed','counts','fixture']:
 for group in ['compiler','exception','fixture']:
  for mode in ['default','live']:
   rows=[r for r in records if r['kind']==kind and r['mode']==mode and (group=='fixture' and kind=='fixture' or group=='exception' and 'exception-hot-paths' in r['source'] or group=='compiler' and 'exception-hot-paths' not in r['source'] and kind!='fixture')]
   if not rows:continue
   sums=[]
   for sample in sorted({r['sample'] for r in rows}):
    current=[r for r in rows if r['sample']==sample];names=current[0]['metrics'];sums.append({n:{f:sum(r['metrics'][n][f] for r in current) for f in ['calls','inclusive_ns','exclusive_ns']} for n in names})
   aggregate={n:{f:{'median':statistics.median(s[n][f] for s in sums),'min':min(s[n][f] for s in sums),'max':max(s[n][f] for s in sums)} for f in ['calls','inclusive_ns','exclusive_ns']} for n in sums[0]}
   summary.append(dict(kind=kind,group=group,mode=mode,all_parity=all(r['parity'] for r in rows),samples=len(sums),aggregate=aggregate))
(here/'summary.json').write_text(json.dumps(summary,indent=2))
