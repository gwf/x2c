"""Render saved quiet source-probe data without running benchmark programs."""
from pathlib import Path
import csv,gzip,hashlib,json,sys
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
source=Path(sys.argv[1]);out=Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=True)
r=json.loads(gzip.decompress(source.read_bytes()) if source.suffix=='.gz' else source.read_bytes())
plt.rcParams.update({'font.family':'DejaVu Sans','font.size':11,'svg.fonttype':'none'})
fig,axes=plt.subplots(1,2,figsize=(12,6.5));fig.suptitle('Ordinary x2c source experiments',x=.07,ha='left',y=.98,fontsize=21)
fig.text(.07,.89,'Sixteen alternating fresh-process pairs per size | recorded quiet window',color='#53606b')
rows=[]
for ax,problem,before,after,title in [(axes[0],'knucleotide','knucleotide-before','knucleotide-counter','K-nucleotide: Counter objects (rejected)'),(axes[1],'spectralnorm','spectralnorm-before','spectralnorm-parallel','Spectral-norm: ordinary threads (adopted)')]:
 groups=[v for v in r['summaries'] if v['problem']==problem]
 for name,label,color,marker,delta in [(before,'Previous source','#53606b','o',-.06),(after,'Candidate','#087e8b','^',.06)]:
  xs=[];ys=[]
  for x,v in enumerate(groups):
   med=v[name]['median_elapsed_ms'];xs.append(v['n']);ys.append(med)
   ax.annotate(f'{med:.2f}',(v['n'],med),xytext=(10, -22 if delta<0 else 13) if problem=='knucleotide' and x==0 else ((10 if x==0 else -8) if delta<0 else 8,16 if delta<0 else -17),textcoords='offset points',ha='right' if delta<0 and x!=0 else 'left',fontsize=10,color=color,bbox=dict(facecolor='white',edgecolor='none',alpha=.85,pad=1.5))
   rows.append({'problem':problem,'n':v['n'],'implementation':name,**v[name],'candidate_pair_wins':v['wins'],'pairs':16})
  ax.plot(xs,ys,marker=marker,color=color,label=label,lw=1.2,ms=7)
 ax.set_title(title,pad=16,fontsize=12.5);ax.set_xscale('log');ax.set_xticks([v['n'] for v in groups],[f"{v['n']:,}" for v in groups]);ax.set_xlim(groups[0]['n']*.8,groups[-1]['n']*1.25);ax.xaxis.set_minor_formatter(matplotlib.ticker.NullFormatter());ax.set_xlabel('FASTA generator N' if problem=='knucleotide' else 'Matrix dimension N',labelpad=12)
 ax.set_yscale('log');ax.set_ylabel('Median elapsed time (ms)');ax.set_ylim(min(ys)*.65,max(v[n]['median_elapsed_ms'] for v in groups for n in (before,after))*1.6);ax.grid(axis='y',color='#e4e8ec');ax.set_axisbelow(True);ax.legend(frameon=False,loc='upper left')
 for spine in ('top','right'):ax.spines[spine].set_visible(False)
fig.text(.07,.045,'Apple M4 Max | serial path below N=256 in the spectral candidate\nCounter results are an experiment, not a ninth chart column. CPU medians and all samples are retained with the data.',fontsize=10,color='#53606b')
fig.subplots_adjust(left=.08,right=.96,top=.76,bottom=.22,wspace=.29)
for ext in ('png','svg','pdf'):fig.savefig(out/('counter-spectral-probes.'+ext),dpi=180,facecolor='white',metadata={'Creator':'matplotlib'})
with (out/'counter-spectral-probes.csv').open('w',newline='') as f:
 w=csv.DictWriter(f,fieldnames=rows[0]);w.writeheader();w.writerows(rows)
(out/'counter-spectral-probes-provenance.json').write_text(json.dumps({'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'source_sha256_by_variant':r['source_sha256'],'revision':r['revision'],'samples':r['samples'],'quiet_window':r['quiet_window'],'limit':r['limit']},indent=2)+'\n')
