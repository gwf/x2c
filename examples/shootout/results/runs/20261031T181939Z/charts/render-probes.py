#!/usr/bin/env python3
"""Render completed reference probes; never build or execute a benchmark.

Usage: python render-probes.py DIRECTORY [--output DIRECTORY]
Requires the complete eight-round confirmation. Missing baselines, missing rounds,
duplicate samples, failed outputs, and nonpositive timings are errors.
"""
import argparse
from collections import defaultdict
import csv
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
from statistics import median

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.ticker import FuncFormatter, LogLocator, NullFormatter

SERIES = {
    'c': ('C', '#39434d'),
    'idiomatic': ('Idiomatic x2c', '#007e87'),
    'tuned': ('Tuned x2c', '#7655aa'),
    'python': ('Python', '#b47712'),
    'rust': ('Rust', '#bd5038'),
    'cpp': ('C++', '#346caf'),
    'go': ('Go', '#477435'),
    'java': ('Java', '#a34783'),
}
PROBLEMS = ['nbody', 'spectralnorm', 'fannkuchredux', 'mandelbrot', 'fasta',
            'revcomp', 'binarytrees', 'regexredux', 'pidigits', 'knucleotide']
TITLES = {'nbody': 'n-body', 'spectralnorm': 'spectral-norm',
          'fannkuchredux': 'fannkuch-redux', 'revcomp': 'reverse-complement',
          'binarytrees': 'binary-trees', 'regexredux': 'regex-redux',
          'knucleotide': 'k-nucleotide'}
ROUNDS = 8
STEM = 'reference-audit-probes'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def quantile(values, fraction):
    values = sorted(values)
    index = fraction * (len(values) - 1)
    lo = math.floor(index)
    hi = math.ceil(index)
    return values[lo] + (values[hi] - values[lo]) * (index - lo)


def load(directory):
    required = ['screen.json', 'confirm-selected.json', 'confirm-raw.jsonl', 'decisions.json']
    for name in required:
        if not (directory / name).is_file():
            raise ValueError(f'Missing required evidence: {directory / name}')
    screen = json.loads((directory / 'screen.json').read_text())
    selected = json.loads((directory / 'confirm-selected.json').read_text())
    decisions = {record['id']: record for record in json.loads((directory / 'decisions.json').read_text())['decisions']}
    indexed = {record['id']: record for record in screen}
    if len(indexed) != len(screen):
        raise ValueError('Duplicate candidate IDs in screen.json')
    if not selected:
        raise ValueError('No selected candidates')
    if len({record['id'] for record in selected}) != len(selected):
        raise ValueError('Duplicate selected candidate IDs')
    observations = defaultdict(list)
    for number, line in enumerate((directory / 'confirm-raw.jsonl').read_text().splitlines(), 1):
        if not line.strip():
            continue
        record = json.loads(line)
        elapsed = record.get('elapsed_ns')
        if isinstance(elapsed, bool) or not isinstance(elapsed, (int, float)) or elapsed <= 0:
            raise ValueError(f'Invalid elapsed_ns at confirmation line {number}')
        for key in ['exit_code', 'returncode', 'status']:
            if key in record and isinstance(record[key], int) and record[key] != 0:
                raise ValueError(f'Failed measurement at confirmation line {number}: {key}')
        observations[record['id']].append(record)

    def samples(identifier):
        values = observations.get(identifier, [])
        if len(values) != ROUNDS or sorted(value.get('turn', -1) for value in values) != list(range(ROUNDS)):
            raise ValueError(f'{identifier}: require exactly 8 samples, one per round 0-7; found {len(values)}')
        return [value['elapsed_ns'] for value in values]

    rows = []
    for chosen in selected:
        identifier = chosen['id']
        source = {**indexed.get(identifier, {}), **chosen}
        if not source.get('correct'):
            raise ValueError(f'{identifier}: candidate did not pass output checks')
        problem, language = source['problem'], source['language']
        if problem not in PROBLEMS or language not in SERIES:
            raise ValueError(f'Unknown problem/language: {problem}/{language}')
        baseline_id = f'baseline-{problem}-{language}'
        if baseline_id not in observations:
            raise ValueError(f'Missing corresponding before baseline: {baseline_id}')
        candidate = samples(identifier)
        before = samples(baseline_id)
        candidate_median, before_median = median(candidate), median(before)
        archive_path = source.get('archive_path', '')
        name = Path(archive_path or source.get('source', identifier)).name
        label = f'{SERIES[language][0]} | {name} [{identifier.split("-")[0]}]'
        if identifier == 'knucleotide-parallel':
            label = 'Idiomatic x2c | ordinary threading'
        adopted = decisions[identifier]['adopted']
        label = ('* ' if adopted else '') + label
        rows.append({
            'problem': problem, 'language': language, 'candidate_id': identifier,
            'candidate_label': label, 'archive_path': archive_path,
            'source_sha256': source.get('sha256', ''),
            'binary_sha256': source.get('binary_sha256', ''),
            'baseline_id': baseline_id, 'profile': 'local', 'adopted': adopted,
            'paired_wins': decisions[identifier]['paired_wins'],
            'candidate_median_cpu_ms': median(v['user_ns'] + v['system_ns'] for v in observations[identifier]) / 1e6,
            'baseline_median_cpu_ms': median(v['user_ns'] + v['system_ns'] for v in observations[baseline_id]) / 1e6,
            'candidate_samples': ROUNDS, 'baseline_samples': ROUNDS,
            'candidate_median_elapsed_ns': candidate_median,
            'baseline_median_elapsed_ns': before_median,
            'candidate_median_ms': candidate_median / 1e6,
            'baseline_median_ms': before_median / 1e6,
            'candidate_over_baseline': candidate_median / before_median,
            'candidate_q25_over_baseline': quantile(candidate, .25) / before_median,
            'candidate_q75_over_baseline': quantile(candidate, .75) / before_median,
            'candidate_min_over_baseline': min(candidate) / before_median,
            'candidate_max_over_baseline': max(candidate) / before_median,
            'notes': source.get('notes', ''),
        })
    rows.sort(key=lambda row: (PROBLEMS.index(row['problem']),
                              list(SERIES).index(row['language']), row['candidate_id']))
    return screen, selected, observations, rows


def render(rows, output):
    problems = [problem for problem in PROBLEMS if any(row['problem'] == problem for row in rows)]
    groups = {problem: [row for row in rows if row['problem'] == problem] for problem in problems}
    pairs = [problems[start:start + 2] for start in range(0, len(problems), 2)]
    heights = [max(2.1, max(len(groups[p]) for p in pair) * .44 + 1.0) for pair in pairs]
    total_height = sum(heights) + 3.35
    plt.rcParams.update({'font.family': 'DejaVu Sans', 'font.size': 10,
                         'svg.fonttype': 'none', 'pdf.fonttype': 42})
    fig = plt.figure(figsize=(18, total_height), facecolor='white')
    grid = fig.add_gridspec(len(pairs), 2, height_ratios=heights,
                           left=.24, right=.965, top=1 - 1.8 / total_height,
                           bottom=1.65 / total_height, hspace=.58, wspace=1.2)
    fig.text(.035, 1 - .25 / total_height, 'Official reference audit and idiomatic k-nucleotide probe',
             ha='left', va='top', fontsize=20)
    fig.text(.035, 1 - .67 / total_height,
             'Local profile | quiet eight-round rotating confirmation | eight elapsed-time samples per program\n'
             'Each candidate is divided by its own language/problem before baseline. Below 1x is faster.',
             ha='left', va='top', fontsize=11.5, linespacing=1.6, color='#53606b')
    present = [language for language in SERIES if any(row['language'] == language for row in rows)]
    handles = [Line2D([], [], color=SERIES[language][1], marker='o', linestyle='none',
                      markersize=7, label=SERIES[language][0]) for language in present]
    fig.legend(handles=handles, loc='upper left', bbox_to_anchor=(.03, 1 - 1.13 / total_height),
               frameon=False, ncol=len(handles), columnspacing=1.5, handletextpad=.5)
    for band, pair in enumerate(pairs):
        for col, problem in enumerate(pair):
            ax = fig.add_subplot(grid[band, col])
            group = groups[problem]
            for index, row in enumerate(group):
                ratio = row['candidate_over_baseline']
                low = row['candidate_q25_over_baseline']
                high = row['candidate_q75_over_baseline']
                color = SERIES[row['language']][1]
                ax.errorbar(ratio, index, xerr=[[ratio - low], [high - ratio]],
                            fmt='o', color=color, markersize=6, capsize=3, linewidth=1.6, zorder=4)
                ax.annotate(f'{ratio:.3g}x', (ratio, index), xytext=(8, 0),
                            textcoords='offset points', va='center', fontsize=9, color=color)
            low = min(row['candidate_q25_over_baseline'] for row in group)
            high = max(row['candidate_q75_over_baseline'] for row in group)
            ax.set_xscale('log')
            ax.set_xlim(min(low * .75, .8), max(high * 1.65, 1.2))
            ax.axvline(1, color='#76828d', linewidth=1, linestyle='--', zorder=2)
            ax.set_yticks(range(len(group)), [row['candidate_label'] for row in group], fontsize=9)
            ax.set_ylim(len(group) - .35, -.65)
            ax.set_title(TITLES.get(problem, problem), loc='left', pad=14, fontsize=13)
            ax.xaxis.set_major_locator(LogLocator(base=10, subs=(1, 2, 5)))
            ax.xaxis.set_major_formatter(FuncFormatter(lambda value, _: f'{value:g}x'))
            ax.xaxis.set_minor_formatter(NullFormatter())
            ax.set_xlabel('candidate elapsed / corresponding before baseline', fontsize=9, labelpad=8)
            ax.set_axisbelow(True)
            ax.grid(axis='x', color='#e4e8ec', linewidth=.7)
            ax.tick_params(which='both', length=0, pad=6)
            for spine in ax.spines.values():
                spine.set_color('#bec6cd')
    fig.text(.035, .17 / total_height,
             '* adopted. Dots: median; whiskers: candidate interquartile range divided by baseline median. '
             'Absolute medians are in the CSV.\n'
             'Focused probes are separate from full-suite calibration. '
             'Java includes fresh-JVM startup/JIT. Canonical-size timing remains unrun.',
             ha='left', va='bottom', fontsize=10, color='#53606b', linespacing=1.6)
    for extension in ['png', 'svg', 'pdf']:
        fig.savefig(output / f'{STEM}.{extension}', dpi=180, facecolor='white', bbox_inches='tight',
                    pad_inches=.25, metadata={'Creator': 'matplotlib'})
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    directory = args.directory.resolve()
    output = (args.output or directory).resolve()
    screen, selected, observations, rows = load(directory)
    output.mkdir(parents=True, exist_ok=True)
    csv_path = output / f'{STEM}.csv'
    with csv_path.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    render(rows, output)
    inputs = {}
    for name in ['screen.json', 'confirm-selected.json', 'confirm-raw.jsonl',
                 'confirm-receipt.json', 'confirm-quiet.jsonl', 'profile-receipt.json']:
        path = directory / name
        if path.is_file():
            inputs[name] = {'path': str(path), 'sha256': digest(path)}
    provenance = {
        'generated_at': datetime.now(timezone.utc).isoformat(),
        'renderer_sha256': digest(Path(__file__)),
        'profile': 'local', 'method': 'quiet eight-round rotating confirmation',
        'samples_per_candidate_and_corresponding_before_baseline': ROUNDS,
        'candidate_count': len(rows), 'problem_count': len({row['problem'] for row in rows}),
        'ratio_definition': 'candidate median elapsed_ns / same-language same-problem before-baseline median elapsed_ns',
        'whiskers': 'candidate25th/75th elapsed percentiles divided by before-baseline median',
        'java_method': 'fresh JVM per sample; startup and JIT included',
        'distinction': 'Focused local-profile probes; separate from full-suite calibration. Canonical-size timing unrun.',
        'screen_candidate_count': len(screen), 'inputs': inputs,
        'candidates': rows,
        'artifacts': {path.name: digest(path) for path in [csv_path] +
                      [output / f'{STEM}.{extension}' for extension in ['png', 'svg', 'pdf']]},
    }
    receipt = directory / 'confirm-receipt.json'
    if receipt.is_file():
        provenance['confirmation_receipt'] = json.loads(receipt.read_text())
    (output / f'{STEM}-provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    print(f'Rendered {len(rows)} confirmed candidates across {provenance["problem_count"]} problems to {output}')


if __name__ == '__main__':
    main()
