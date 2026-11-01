from pathlib import Path
import subprocess,os,json,statistics as st
p=Path('debug/plso-regex-20261101').resolve();rows=[];env={**os.environ,'MallocNanoZone':'0','LC_ALL':'C','TZ':'UTC'}
for n in[1000,100000,1000000]:
 f=p/f'fasta-{n}.in'
 with f.open('wb')as out:subprocess.run([p/'fasta-input',str(n)],stdout=out,check=True)
 for i in range(8):
  with f.open('rb')as inp:v=subprocess.run([p/'profiled/regexredux/program'],stdin=inp,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env,check=True)
  rows.append({'input':n,'sample':i+1,'stderr':v.stderr.decode()})
 print('input',n)
 for key in['read','strip_compile','strip','launch','chain','join_print','total','size','write','intern','count_compile','count_match']:
  a=[]
  for row in rows:
   if row['input']!=n:continue
   vs=[float(line.split()[2])for line in row['stderr'].splitlines()if line.startswith('P '+key+' ')];a.append(sum(vs)if key in['size','write','intern','count_compile','count_match']else vs[0])
  print(key,round(st.median(a),4))
(p/'profile-before.json').write_text(json.dumps(rows,indent=2)+'\n')
