import subprocess,time,json,os
from pathlib import Path
p=Path('debug/plso-kernels-20261101');rows=[]
with (p/'full-run.log').open('w')as log:
 child=subprocess.Popen(['python3','examples/shootout/tools/shootout.py','update','--profile','local'],stdout=log,stderr=subprocess.STDOUT)
 while child.poll()is None:
  rows.append({'time':time.time(),'processes':subprocess.check_output(['ps','-axo','pid,ppid,pcpu,comm','-r'],text=True)})
  (p/'quiet-monitor.json').write_text(json.dumps({'root_pid':child.pid,'snapshots':rows},indent=2)+'\n')
  time.sleep(1)
code=child.returncode;(p/'full-status.json').write_text(json.dumps({'exit_code':code,'snapshots':len(rows)},indent=2)+'\n');raise SystemExit(code)
