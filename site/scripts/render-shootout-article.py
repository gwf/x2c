"""Render reading-column figures from the recorded shootout; run no benchmarks."""
from pathlib import Path
import hashlib
import json
import runpy
from statistics import geometric_mean

ROOT = Path(__file__).resolve().parents[2]
renderer = runpy.run_path(str(ROOT / 'examples/shootout/tools/render-charts.py'))
plt = renderer['plt']
report_path = ROOT / 'examples/shootout/results/current.json'
report, rows = renderer['read_rows'](report_path)
output = ROOT / 'site/public/charts/shootout'
output.mkdir(parents=True, exist_ok=True)
plt.rcParams.update({'font.family': 'sans-serif', 'font.sans-serif': ['Arial', 'DejaVu Sans'], 'font.size': 12,
                     'text.color': '#34312e', 'axes.labelcolor': '#625d56',
                     'xtick.color': '#625d56', 'ytick.color': '#34312e',
                     'svg.fonttype': 'none'})
RED, GRAY = '#c92719', '#74716c'
labels = {'nbody': 'n-body', 'spectralnorm': 'Spectral norm',
          'fannkuchredux': 'Fannkuch-redux', 'mandelbrot': 'Mandelbrot',
          'fasta': 'FASTA', 'knucleotide': 'k-nucleotide',
          'revcomp': 'Reverse complement', 'binarytrees': 'Binary trees',
          'regexredux': 'Regex-redux', 'pidigits': 'Pi digits'}
lookup = {(r['problem'], r['implementation']): r for r in rows}


def finish(fig, name):
    for ext in ['svg', 'png']:
        fig.savefig(output / f'{name}.{ext}', dpi=180, facecolor='#f3f0e9')
    svg = output / f'{name}.svg'
    svg.write_text('\n'.join(line.rstrip() for line in svg.read_text().splitlines()) + '\n')
    plt.close(fig)


def style(ax):
    ax.set_facecolor('#f3f0e9')
    ax.grid(axis='x', color='#d8d3cb', linewidth=.6)
    ax.set_axisbelow(True)
    ax.tick_params(length=0, pad=8)
    for spine in ax.spines.values():
        spine.set_visible(False)


def pairs(metric, name, xlabel, logarithmic=False):
    order = report['benchmark_order']
    fig, ax = plt.subplots(figsize=(9, 7.2))
    style(ax)
    for y, problem in enumerate(order):
        a, b = [lookup[problem, key][metric] for key in ['idiomatic', 'tuned']]
        ax.plot([a, b], [y, y], color='#aaa49a', linewidth=2, zorder=2)
        ax.scatter([a], [y], color=GRAY, s=48, zorder=3, label='Idiomatic x2c' if y == 0 else None)
        ax.scatter([b], [y], color=RED, marker='D', s=42, zorder=4, label='Tuned x2c' if y == 0 else None)
        # Separate direct labels vertically even when the two points coincide.
        fmt = (lambda n: f'{n:.2f}x') if logarithmic else (lambda n: str(int(n)))
        ax.annotate(fmt(a), (a, y), xytext=(0, 10), textcoords='offset points', ha='center', va='center', color=GRAY, fontsize=10)
        ax.annotate(fmt(b), (b, y), xytext=(0, -10), textcoords='offset points', ha='center', va='center', color=RED, fontsize=10)
    ax.set_yticks(range(len(order)), [labels[n] for n in order])
    ax.set_ylim(len(order)-.3, -.8)
    ax.set_xlabel(xlabel, labelpad=15)
    if logarithmic:
        ax.set_xscale('log')
        ax.set_xlim(.8, 16)
        ax.set_xticks([1, 2, 5, 10], ['1x', '2x', '5x', '10x'])
        ax.xaxis.set_minor_formatter(renderer['NullFormatter']())
        ax.axvline(1, color='#8d857a', linestyle='--', linewidth=1)
    else:
        ax.set_xlim(0, max(r[metric] for r in rows if r['implementation'] in ['idiomatic','tuned']) * 1.12)
    ax.legend(loc='lower left', bbox_to_anchor=(0, 1.025), frameon=False, ncol=2, borderaxespad=0)
    fig.subplots_adjust(left=.23, right=.965, top=.89, bottom=.13)
    finish(fig, name)


pairs('time_ratio', 'runtime', 'Elapsed time relative to C (log scale; lower is faster)', True)
pairs('source_lines', 'source', 'Source lines, excluding comments and blank lines')
shared = set(report['summary_benchmarks'])
series = [('c', 'C'), ('tuned', 'x2c tuned'), ('rust', 'Rust'), ('cpp', 'C++'),
          ('go', 'Go'), ('idiomatic', 'x2c idiomatic'), ('java', 'Java'), ('python', 'Python')]
fig, axes = plt.subplots(1, 2, figsize=(9, 5.6), sharey=True)
for ax, metric, title in zip(axes, ['time_ratio','loc_ratio'], ['Elapsed time / C', 'Source lines / Python']):
    style(ax)
    for y, (key, label) in enumerate(series):
        value = geometric_mean(r[metric] for r in rows if r['problem'] in shared and r['implementation'] == key)
        color = RED if key in ('tuned', 'idiomatic') else GRAY
        ax.scatter(value, y, color=color, s=48, marker='D' if key == 'tuned' else 'o', zorder=3)
        ax.annotate(f'{value:.2f}x', (value,y), xytext=(9,0), textcoords='offset points', va='center', color=color, fontsize=10)
    ax.set_title(title, loc='left', fontsize=12, pad=22)
    ax.axvline(1, color='#8d857a', linestyle='--', linewidth=1)
    ax.set_ylim(len(series)-.4,-.6)
axes[0].set_yticks(range(len(series)), [label for _,label in series])
axes[0].set_xscale('log'); axes[0].set_xlim(.8, 35)
axes[0].set_xticks([1,2,5,10,20], ['1x','2x','5x','10x','20x'])
axes[0].xaxis.set_minor_formatter(renderer['NullFormatter']())
axes[0].set_xlabel('Log scale; lower is faster', labelpad=15)
axes[1].set_xlim(.85,2.2); axes[1].set_xticks([1,1.5,2],['1x','1.5x','2x'])
axes[1].set_xlabel('Linear scale; lower is shorter',labelpad=15)
fig.subplots_adjust(left=.21,right=.96,top=.88,bottom=.15,wspace=.25)
finish(fig,'summary')
(output/'provenance.json').write_text(json.dumps({
    'report': 'examples/shootout/results/current.json',
    'sha256': hashlib.sha256(report_path.read_bytes()).hexdigest(),
    'run_id': report['run_id'], 'shared_problems': report['summary_benchmarks'],
    'runtime_and_source_problems': report['benchmark_order'],
    'summary': 'Geometric means of per-problem ratios over the shared eight problems',
    'command': 'uv run --with matplotlib python site/scripts/render-shootout-article.py'
},indent=2)+'\n')
print('Rendered three article figures from',report['run_id'])
