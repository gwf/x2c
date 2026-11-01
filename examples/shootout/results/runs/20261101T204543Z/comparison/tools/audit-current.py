from pathlib import Path
import importlib.util,json,hashlib,gzip,subprocess
r=Path(subprocess.check_output(['git','rev-parse','--show-toplevel'],text=True).strip());p=r/'debug/plso-regex-20261101';p.mkdir(parents=True,exist_ok=True);a=r/'examples/shootout/results/runs/20261101T204543Z';d=json.loads((a/'current.json').read_text());spec=importlib.util.spec_from_file_location('independent',Path(__file__).with_name('audit-independent.py'));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);rows=[]
for n in d['benchmark_order']:
 for mode,fname in m.FILENAMES.items():
  e=d['benchmarks'][n];entry=e.get(mode)if mode in['idiomatic','tuned']else e['references'].get(mode)
  if not entry:continue
  path=r/'examples/shootout/benchmarks'/n/fname;data=path.read_bytes();metrics=m.metrics(data.decode(),mode);expected={k:entry['source'][k]for k in['source_lines','game_style_gzip_bytes']};rows.append({'problem':n,'implementation':mode,'path':str(path.relative_to(r)),'source_sha256':hashlib.sha256(data).hexdigest(),'harness':expected,'independent':metrics,'matches':all(expected[k]==metrics[k]for k in expected)})
result={'revision':d['machine']['repository']['revision'],'run_id':d['run_id'],'audited_program_count':len(rows),'mismatch_count':sum(not v['matches']for v in rows),'programs':rows};assert len(rows)==75 and not result['mismatch_count'];out=p/'source-size-current-audit.json';out.write_text(json.dumps(result,indent=2)+'\n');(a/'comparison/source-size-current-audit.json.gz').write_bytes(gzip.compress(out.read_bytes(),mtime=0));print('current corpus: all75 independent counts match')
