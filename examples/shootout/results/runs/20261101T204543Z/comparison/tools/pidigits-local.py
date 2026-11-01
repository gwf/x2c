from pathlib import Path
import subprocess,json,statistics as st,os,hashlib
r=Path.cwd();p=r/'debug/plso-regex-20261101';rec=json.loads((p/'pidigits-receipt.json').read_text());env={**os.environ,'MallocNanoZone':'0','LC_ALL':'C','TZ':'UTC'};checks=[];samples=[]
for mode,stem in[('idiomatic','main'),('tuned','tuned')]:
 e=rec[mode];d=p/'pidigits-new'/('pidigits-'+mode);d.mkdir(parents=True,exist_ok=True);a=e['translate_command'][:];a[a.index('--out-dir')+1]=str(d/'generated');subprocess.run(a,check=True);c=e['compile_command'][:];c[c.index('-o')+1]=str(d/'program');c=[str(d/'generated'/f'{stem}.c')if x.endswith(f'pidigits/{mode}/generated/{stem}.c')else x for x in c];subprocess.run(c,check=True);(d/f'{stem}.x').write_bytes((r/f'examples/shootout/benchmarks/pidigits/{stem}.x').read_bytes());(d/'build.json').write_text(json.dumps({'translate_command':a,'compile_command':c},indent=2))
for mode in['idiomatic','tuned']:
 def run(tag,n,measured=False):
  cmd=[p/tag/('pidigits-'+mode)/'program',str(n)]
  if measured:cmd=[p/'measure',*cmd]
  z=subprocess.run(list(map(str,cmd)),stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=True,env=env);assert not z.stderr,z.stderr
  return json.loads(z.stdout)if measured else z.stdout
 for n in[10000]:
  old,new=run('before',n),run('pidigits-new',n);assert old==new,(mode,n);checks.append({'variant':mode,'n':n,'output_sha256':hashlib.sha256(old).hexdigest()})
  if n not in[10000]:continue
  for tag in['before','pidigits-new']:run(tag,n,True)
  for i in range(12):
   for tag in(['before','pidigits-new']if i%2==0 else['pidigits-new','before']):samples.append({**run(tag,n,True),'variant':mode,'n':n,'mode':'before'if tag=='before'else'after','round':i+1})
  vals={m:st.median(x['elapsed_ns']for x in samples if x['variant']==mode and x['n']==n and x['mode']==m)/1e6 for m in['before','after']};print(mode,n,vals,vals['after']/vals['before'],flush=True)
  (p/'pidigits-local-comparison.json').write_text(json.dumps({'status':'running','checks':checks,'samples':samples},indent=2)+'\n')
(p/'pidigits-local-comparison.json').write_text(json.dumps({'status':'complete','checks':checks,'samples':samples},indent=2)+'\n')
