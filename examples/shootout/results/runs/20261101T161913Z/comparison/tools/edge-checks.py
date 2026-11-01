from pathlib import Path
import subprocess,random,json,hashlib,os
r=Path.cwd();p=r/'debug/plso-kernels-20261101';rng=random.Random(20261101);rows=[]
def check(n,data):
 a=subprocess.check_output([p/'before/revcomp/program'],input=data)
 b=subprocess.check_output([p/'rev-batched/revcomp/program'],input=data)
 assert a==b,n
 rows.append({'case':n,'input_bytes':len(data),'input_sha256':hashlib.sha256(data).hexdigest(),'output_sha256':hashlib.sha256(a).hexdigest()})
for size in [0,1,59,60,61,15359,15360,15361,16376,16377,16378,16379,16380,16381,16382,16383,16384,16385,32767,32768]:
 seq=bytes(rng.choice(b'ACGTUMRWSYKVHDBNacgtumrwsykvhdbn')for _ in range(size))
 for newline in[b'\n',b'\r\n']:
  data=b'>ONE'+newline+newline.join(seq[i:i+60]for i in range(0,len(seq),60))+newline+b'>TWO'+newline+b'ACG'
  check(str(size)+'-'+repr(newline),data)
# Put LF, CRLF and header markers on either side of each read boundary.
for offset in range(-4,5):
 for sep in[b'\n',b'\r\n']:
  check('header-'+str(offset)+repr(sep),b'>ONE\n'+b'A'*(16384-5+offset)+sep+b'>TWO'+sep+b'GT'+sep)
(p/'edge-checks.json').write_text(json.dumps({'status':'complete','seed':20261101,'checks':rows},indent=2)+'\n');print(len(rows),'boundary checks pass')
