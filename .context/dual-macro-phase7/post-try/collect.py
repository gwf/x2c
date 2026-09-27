import os,pathlib,subprocess,re,json,hashlib,statistics
p=pathlib.Path(__file__).resolve().parent;root=pathlib.Path('/Users/gary/.codex/worktrees/agent-dual-transport/x2c');out=pathlib.Path('/tmp/dual-phase7-post-try-runs');out.mkdir(exist_ok=True)
expected={(r['source'],r.get('mode','fixture')):r for r in json.loads((p.parent/'comparison/final-manifest.json').read_text())['results']}
corpus=['src/transform.x','src/emit.x','src/expressions.x','src/generate.x','src/parse.x','src/type.x','lib/tokenizer.x','unittest/benchmarks/exception-hot-paths.x']
records=[];logs=[]
work=[(mode,0,src) for mode in ['default','live'] for src in corpus]+[('fixture',i,'unittest/compiler-fixtures/defer-try-cleanup.x') for i in range(3)]
for mode,sample,source in work:
 folder=out/mode/str(sample)/pathlib.Path(source).stem;folder.mkdir(parents=True,exist_ok=True)
 env=os.environ.copy();env['X2C_HOME']=str(root);env['X2C_DUAL_PROFILE']='1';env.pop('X2C_DUAL_EFFECT_PROBE',None);env.pop('X2C_DUAL_COUNTS',None)
 cmd=['/tmp/x2c-dual-phase7-post-try','translate',*(['--live-symbols'] if mode=='live' else []),'--out-dir',str(folder),str(root/source)]
 r=subprocess.run(cmd,cwd=root,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);logs.append('COMMAND '+repr(cmd)+'\n'+r.stdout.decode());metrics={n:dict(calls=int(c),inclusive_ns=int(i),exclusive_ns=int(e)) for n,c,i,e in re.findall(r'DUAL_PROFILE (\S+) (\d+) (\d+) (\d+)',r.stdout.decode())}
 files={str(f.relative_to(folder)):dict(bytes=f.stat().st_size,sha256=hashlib.sha256(f.read_bytes()).hexdigest()) for f in folder.rglob('*') if f.suffix in ['.c','.h']};b=expected[(source,mode)]
 records.append(dict(mode=mode,sample=sample,source=source,metrics=metrics,exit=r.returncode,parity=r.returncode==b['exit'] and files==b['files'],files=files));print(mode,source,'parity',records[-1]['parity'],flush=True)
(p/'results.json').write_text(json.dumps(records,indent=2));(p/'commands.log').write_text('\n'.join(logs));summary=[]
for mode in ['default','live','fixture']:
 for group in (['fixture'] if mode=='fixture' else ['compiler','exception']):
  selected=[r for r in records if r['mode']==mode and (group=='fixture' or ('exception-hot-paths' in r['source'])==(group=='exception'))];samples=[]
  for sample in sorted({r['sample'] for r in selected}):
   rows=[r for r in selected if r['sample']==sample];totals={n:{f:sum(r['metrics'].get(n, {}).get(f, 0) for r in rows) for f in ['calls','inclusive_ns','exclusive_ns']} for n in ['try_application','try_snapshot','scope_symbols_copy']};calls=totals['try_application']['calls'];total_ms=(totals['try_application']['inclusive_ns']+totals['try_snapshot']['inclusive_ns'])/1e6;samples.append(dict(sample=sample,totals=totals,nonoverlap_ms=total_ms,per_try_ms=total_ms/calls))
  summary.append(dict(mode=mode,group=group,all_parity=all(r['parity'] for r in selected),samples=samples,median_nonoverlap_ms=statistics.median(s['nonoverlap_ms'] for s in samples),median_per_try_ms=statistics.median(s['per_try_ms'] for s in samples)))
(p/'summary.json').write_text(json.dumps(summary,indent=2))
