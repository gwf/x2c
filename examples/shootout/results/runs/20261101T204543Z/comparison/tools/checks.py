from pathlib import Path
import subprocess,json,random,hashlib,os
p=Path('debug/plso-regex-20261101').resolve();rng=random.Random(20261101);rows=[];env={**os.environ,'MallocNanoZone':'0'}
choices=[b'tHaN',b'tHaT',b'aND',b'caN',b'HaD',b'HaS',b'WaS',b'aN',b'aS',b'at',b'BY',b'<abc>',b'|ab|cd|',b'agggtaaa',b'tttaccct']
for n in range(80):
 data=b'>ONE\n'+b''.join(rng.choice(choices+[b'ACGT\n',b'>next\n',b'\r\n'])for _ in range(rng.randrange(0,1000)))
 if n%3==0:data+=b'\n'
 old=subprocess.check_output([p/'before/regexredux/program'],input=data,env=env);new=subprocess.check_output([p/'final/regexredux/program'],input=data,env=env);assert old==new,n;rows.append({'case':n,'input_bytes':len(data),'input_sha256':hashlib.sha256(data).hexdigest(),'output_sha256':hashlib.sha256(new).hexdigest()})
(p/'generated-checks.json').write_text(json.dumps({'seed':20261101,'status':'complete','checks':rows},indent=2)+'\n');print(len(rows),'generated replacement/count checks pass')
