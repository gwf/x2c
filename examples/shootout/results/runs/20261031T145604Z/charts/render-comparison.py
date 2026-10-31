"""Render the archived quiet serial/parallel binary-trees comparison."""
from pathlib import Path
import csv,gzip,hashlib,json,sys
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
source=Path(sys.argv[1]);output=Path(sys.argv[2]);output.mkdir(exist_ok=True,parents=True)
r=json.loads(gzip.decompress(source.read_bytes()) if source.suffix=='.gz' else source.read_bytes())
plt.rcParams.update({'font.family':'DejaVu Sans','font.size':11,'svg.fonttype':'none'})
fig,axes=plt.subplots(1,2,figsize=(11,5.5))
fig.suptitle('Binary-trees: serial and ordinary x2c threads',x=.07,ha='left',y=.98,fontsize=19)
fig.text(.07,.88,'Same Node allocation workload | depth 14 | sixteen alternating fresh-process pairs',fontsize=11,color='#53606b')
rows=[]
for ax,metric,title in zip(axes,('elapsed_ns','cpu_ns'),('Elapsed time (ms)','Total CPU time (ms)')):
 for x,(name,color) in enumerate((('serial','#53606b'),('parallel','#087e8b'))):
  values=[(v['elapsed_ns'] if metric=='elapsed_ns' else v['user_ns']+v['system_ns'])/1e6 for v in r['raw'] if v['implementation']==name]
  med=float(np.median(values));ax.scatter(x+np.linspace(-.08,.08,len(values)),values,color=color,alpha=.6,s=22)
  ax.hlines(med,x-.22,x+.22,color=color,lw=3);ax.annotate(f'{med:.2f}',(x,med),xytext=(0,13),textcoords='offset points',ha='center',color=color)
  rows.append({'implementation':name,'metric':title,'median_ms':med,'samples':len(values),'workers':r['workers'][name]})
 ax.set_title(title,pad=15);ax.set_xticks([0,1],['Serial','Parallel\n6 workers']);ax.set_xlim(-.5,1.5);ax.set_ylim(0,max(ax.get_ylim()[1]*1.2,1));ax.grid(axis='y',color='#e4e8ec');ax.set_axisbelow(True)
 for spine in ('top','right'):ax.spines[spine].set_visible(False)
fig.text(.07,.035,'Apple M4 Max | pre-run quiet window: six 10-second observations >=90% idle\nDots are individual samples; bars mark medians. CPU time sums user and system time across threads.',fontsize=10,color='#53606b')
fig.subplots_adjust(left=.08,right=.97,top=.74,bottom=.22,wspace=.28)
for ext in ('png','svg','pdf'):fig.savefig(output/('binarytrees-serial-parallel.'+ext),dpi=180,facecolor='white',metadata={'Creator':'matplotlib'})
with (output/'binarytrees-serial-parallel.csv').open('w',newline='') as f:
 w=csv.DictWriter(f,fieldnames=rows[0]);w.writeheader();w.writerows(rows)
(output/'binarytrees-serial-parallel-provenance.json').write_text(json.dumps({'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'revision':r['revision'],'source_sha256_by_variant':r['source_sha256'],'workers':r['workers'],'summary':r['summary'],'ordering':r['ordering'],'limit':r['limit']},indent=2)+'\n')
