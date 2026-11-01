from pathlib import Path
import subprocess,time,json,os,sys
r=Path.cwd();p=r/'debug/plso-regex-20261101';root=os.getpid();rows=[];reasons=[]
def snapshot():
 raw=subprocess.check_output(['ps','-axo','pid,ppid,pcpu,comm','-r'],text=True);ls=[x.strip().split(None,3)for x in raw.splitlines()[1:]];own={root}
 for _ in range(15):
  for x in ls:
   if len(x)==4 and int(x[1])in own:own.add(int(x[0]))
 busy=[]
 for x in ls:
  if len(x)<4 or int(x[0])in own:continue
  name=Path(x[3]).name
  if int(x[0])==50146 or ((name in['cc','clang','clang++','rustc','x2c','ld','ld64']or name.startswith('x2c-')or name=='(x2c-build)')and float(x[2])>0.5):busy.append(x)
 rows.append({'time':time.time(),'processes':raw,'busy':busy});return busy
quiet=0
while quiet<10:
 busy=snapshot();quiet=0 if busy else quiet+1
 (p/'repeat-quiet.json').write_text(json.dumps({'status':'waiting','root_pid':root,'snapshots':rows},indent=2)+'\n')
 time.sleep(1)
print('quiet window acquired',flush=True)
commands=[('final-repeat',['python3',str(p/'source/compare.py'),'regexredux','before','final']),('pidigits-local',['python3',str(p/'source/pidigits-local.py')])]
for tag,cmd in commands:
 print('starting',tag,flush=True)
 with (p/(tag+'-accepted.log')).open('w')as log:child=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT)
 while child.poll()is None:
  busy=snapshot()
  if busy:
   reasons.append({'phase':tag,'busy':busy});child.terminate();child.wait();(p/'repeat-quiet.json').write_text(json.dumps({'status':'contaminated','root_pid':root,'snapshots':rows,'reasons':reasons},indent=2)+'\n');raise SystemExit('outside build started; campaign stopped')
  time.sleep(0.5)
 if child.returncode:raise SystemExit(f'{tag} failed {child.returncode}')
 (p/'repeat-quiet.json').write_text(json.dumps({'status':'running','completed':tag,'root_pid':root,'snapshots':rows},indent=2)+'\n')
(p/'repeat-quiet.json').write_text(json.dumps({'status':'complete','root_pid':root,'snapshots':rows},indent=2)+'\n');print('all accepted phases complete',flush=True)
