from pathlib import Path
import subprocess,json,os,sys,statistics,hashlib,time
r=Path.cwd();p=r/'debug/plso-regex-20261101';problem,before,after=sys.argv[1:4];reps=int(sys.argv[4])if len(sys.argv)>4 else 12;env={**os.environ,'MallocNanoZone':'0','LC_ALL':'C','TZ':'UTC'};d=p/'inputs';d.mkdir(exist_ok=True);cases=[]
def add(n,args=[],data=None,timed=False):
 f=None
 if data is not None:f=d/(problem+'-'+str(n)+'.in');f.write_bytes(data)
 cases.append({'case':problem+'-'+str(n),'args':args,'stdin':str(f)if f else None,'timed':timed})
if problem=='regexredux':
 for n in [1000,6500,6600,100000,1000000]:
  f=d/f'fasta-{n}.in'
  if not f.exists():
   with f.open('wb')as out:subprocess.run([p/'fasta-input',str(n)],stdout=out,check=True)
  cases.append({'case':f'regexredux-{n}','args':[],'stdin':str(f),'timed':True})
 for n,data in [('empty',b''),('short',b'>ONE\nACGT\n'),('replace',b'>ONE\ntHaNtHaT aND caN HaD HaS WaS aN aS at BY <abc> |ab|cd|\n'),('no-final',b'>ONE\nACGT'),('count',b'>one\nagggtaaa tttaccct cgggtaaa tttacccg\n')]:add(n,data=data)
elif problem=='fasta':
 for n in [0,1,2,29,30,59,60,61,286,287,288,1000,100000,1000000]:add(n,args=[str(n)],timed=n in[1000,100000,1000000])
elif problem=='nbody':
 for n in [0,1,2,10,1000,100000,500000,1000000]:add(n,args=[str(n)],timed=n in[1000,500000,1000000])
samples=[];checks=[];snapshots=[]
def run(c,mode,measure=False):
 binary=p/(before if mode=='before'else after)/problem/'program';cmd=[binary,*c['args']]
 if measure:cmd=[p/'measure',*cmd]
 with open(c['stdin']or os.devnull,'rb')as inp:v=subprocess.run(list(map(str,cmd)),stdin=inp,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env,timeout=180,check=True)
 assert not v.stderr,v.stderr
 return json.loads(v.stdout)if measure else v.stdout
for c in cases:
 a,b=run(c,'before'),run(c,'after');assert a==b,(c,a[:100],b[:100]);checks.append({**c,'output_bytes':len(a),'sha256':hashlib.sha256(a).hexdigest()})
 if not c['timed']:continue
 snapshots.append({'case':c['case'],'time':time.time(),'ps':subprocess.check_output(['ps','-axo','pid,pcpu,comm','-r'],text=True)})
 for m in['before','after']:run(c,m,True)
 for i in range(reps):
  for m in(['before','after']if i%2==0 else['after','before']):
   v=run(c,m,True);assert v['exit_code']==v['signal']==0; samples.append({**v,'case':c['case'],'mode':m,'round':i+1})
 med={m:statistics.median(x['elapsed_ns']for x in samples if x['case']==c['case']and x['mode']==m)/1e6 for m in['before','after']};print(c['case'],med,'ratio',med['after']/med['before'],flush=True)
 (p/f'{problem}-{before}-{after}-comparison.json').write_text(json.dumps({'before':before,'after':after,'checks':checks,'samples':samples,'quiet_snapshots':snapshots},indent=2)+'\n')
(p/f'{problem}-{before}-{after}-comparison.json').write_text(json.dumps({'status':'complete','before':before,'after':after,'checks':checks,'samples':samples,'quiet_snapshots':snapshots},indent=2)+'\n');print('complete',len(checks),'checks',len(samples),'samples',flush=True)
