"""Render preserved source-probe observations; never execute a benchmark."""
import argparse,csv,hashlib,json,statistics
from collections import defaultdict
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter,FixedLocator,NullFormatter

STEM='three-idiomatic-probes'
COLORS={'before':'#66727d','batched-serial':'#7655aa','parallel':'#007e87','buffer':'#007e87'}
LABELS={'before':'Previous idiomatic source','batched-serial':'Batched serial control','parallel':'Ordinary Threads','buffer':'Keep Buffer through output'}
PROBLEMS={'regexredux':'regex-redux','revcomp':'reverse-complement','mandelbrot':'Mandelbrot'}
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def render(directory,output):
 raw_path=directory/'raw-quiet.jsonl';build_path=directory/'build.json';decision_path=directory/'decisions.json';receipt_path=directory/'quiet-receipt.json'
 records=[json.loads(l) for l in raw_path.read_text().splitlines()];assert all(v['exit_code']==v['signal']==0 for v in records)
 grouped=defaultdict(list)
 for v in records:grouped[(v['problem'],v['n'],v['id'])].append(v)
 assert set(len(v) for v in grouped.values())=={12}
 builds={v['id']:v for v in json.loads(build_path.read_text())['variants']};decision=json.loads(decision_path.read_text());rows=[]
 for (problem,n,name),samples in grouped.items():
  before=grouped[(problem,n,problem+'-before')];base=statistics.median(v['elapsed_ns'] for v in before);kind=name[len(problem)+1:];by_turn={v['turn']:v for v in before};candidate=statistics.median(v['elapsed_ns'] for v in samples)
  row={'problem':problem,'n':n,'variant':kind,'id':name,'samples':12,'source_sha256':builds[name]['source_sha256'],'binary_sha256':builds[name]['binary_sha256'],'median_elapsed_ms':candidate/1e6,'median_cpu_ms':statistics.median(v['user_ns']+v['system_ns'] for v in samples)/1e6,'elapsed_over_before':candidate/base,'paired_wins':sum(v['elapsed_ns']<by_turn[v['turn']]['elapsed_ns'] for v in samples),'adopted':decision['adopted'].get(problem)==name}
  for metric,key in [('elapsed','elapsed_ns'),('cpu',None)]:
   values=sorted((v[key] if key else v['user_ns']+v['system_ns'])/1e6 for v in samples);cuts=statistics.quantiles(values,n=4,method='inclusive');row[metric+'_q1_ms']=cuts[0];row[metric+'_q3_ms']=cuts[2]
  rows.append(row)
 rows.sort(key=lambda r:(list(PROBLEMS).index(r['problem']),r['n'],r['variant']))
 output.mkdir(parents=True,exist_ok=True)
 with (output/(STEM+'.csv')).open('w',newline='') as f:
  w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
 plt.rcParams.update({'font.family':'DejaVu Sans','font.size':11,'svg.fonttype':'none'})
 fig,axes=plt.subplots(3,2,figsize=(13,13))
 fig.suptitle('Three idiomatic source experiments',x=.08,y=.985,ha='left',fontsize=22)
 fig.text(.08,.948,'Quiet local and larger-input probes | 12 fresh-process samples per source/input\nMedians and interquartile ranges; these probes are separate from the full calibration.',ha='left',va='top',fontsize=11,color='#53606b',linespacing=1.5)
 for index,(problem,title) in enumerate(PROBLEMS.items()):
  group=[r for r in rows if r['problem']==problem];kinds=[k for k in ['before','batched-serial','buffer','parallel'] if any(r['variant']==k for r in group)]
  for col,metric in enumerate(['elapsed','cpu']):
   ax=axes[index,col]
   for kind in kinds:
    values=sorted((r for r in group if r['variant']==kind),key=lambda r:r['n']);xs=[r['n'] for r in values];ys=[r['median_'+metric+'_ms'] for r in values];label=LABELS[kind]
    if values[0]['adopted']:label+=' (adopted)'
    ax.plot(xs,ys,'o-',color=COLORS[kind],label=label,markersize=5,linewidth=1.6)
    ax.fill_between(xs,[r[metric+'_q1_ms'] for r in values],[r[metric+'_q3_ms'] for r in values],color=COLORS[kind],alpha=.12)
   ax.set_xscale('log');ax.set_yscale('log');ax.set_title(title+' | '+('elapsed time' if metric=='elapsed' else 'total CPU time'),loc='left',pad=13)
   ax.set_xlabel('Image width N' if problem=='mandelbrot' else 'FASTA generator N',labelpad=9);ax.set_ylabel('Milliseconds',labelpad=8)
   if problem=='mandelbrot':
    ax.xaxis.set_major_locator(FixedLocator([64,128,256,512,1024]));ax.axvline(256,color='#b5bdc3',ls='--',lw=.8)
   else:ax.xaxis.set_major_locator(FixedLocator([1000,10000,100000,1000000]))
   ax.xaxis.set_major_formatter(FuncFormatter(lambda x,_,problem=problem:f'{x:g}' if problem=='mandelbrot' else f'{x/1e6:g}m' if x>=1e6 else f'{x/1000:g}k' if x>=1000 else f'{x:g}'));ax.xaxis.set_minor_formatter(NullFormatter())
   ax.yaxis.set_major_formatter(FuncFormatter(lambda x,_:f'{x:g}'));ax.yaxis.set_minor_formatter(NullFormatter());ax.grid(which='major',color='#e4e8ec',lw=.7);ax.set_axisbelow(True)
   for spine in ax.spines.values():spine.set_color('#bec6cd')
   ax.legend(loc='upper left',frameon=False,fontsize=9)
 fig.subplots_adjust(left=.08,right=.975,top=.865,bottom=.11,wspace=.25,hspace=.55)
 fig.text(.08,.055,'Regex: serial below 65,536 cleaned bytes. Mandelbrot: serial below N=256; at most six 16-row batches.\nCPU means user plus system time, including worker threads. Canonical-size timing remains unrun.',ha='left',va='top',fontsize=10,color='#53606b',linespacing=1.5)
 for ext in ['png','svg','pdf']:fig.savefig(output/(STEM+'.'+ext),dpi=180,facecolor='white',metadata={'Creator':'matplotlib'})
 plt.close(fig)
 provenance={'inputs':{p.name:digest(p) for p in [raw_path,build_path,decision_path,receipt_path]},'renderer_sha256':digest(Path(__file__)),'observations':len(records),'summary_rows':len(rows),'samples_per_source_input':12,'process_model':'fresh process per sample; no benchmark execution by this renderer','metrics':'elapsed wall time and total user+system CPU milliseconds','quiet':json.loads(receipt_path.read_text()),'decisions':decision,'canonical_size_timing':'unrun'}
 (output/(STEM+'-provenance.json')).write_text(json.dumps(provenance,indent=2)+'\n')
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('directory',type=Path);p.add_argument('output',type=Path);a=p.parse_args();render(a.directory,a.output)
