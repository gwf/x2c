#!/usr/bin/env python3
"""Project compiler-labelled native regions after configured preprocessing."""
from dataclasses import dataclass
import json
from pathlib import Path
import re
import sys
import subprocess

MARKER = re.compile(r'^\s*#\s*pragma\s+x2c_region_(begin|end)\s+([A-Za-z0-9_]+)\s*$')
PACK = re.compile(r'^\s*#\s*pragma\s+pack\s*\((.*)\)\s*$')
PRAGMA = re.compile(r'^\s*#\s*pragma\s+(.*)$')
LINE = re.compile(r'^\s*#\s+(?:line\s+)?(\d+)\s+("(?:\\.|[^"\\])*")(?:\s+.*)?$')

class ProjectionError(Exception):
    pass

@dataclass(frozen=True)
class Region:
    name: str
    text: str
    alignment: int | None
    unsupported_pragmas: tuple[str, ...]
    children: tuple[str, ...] = ()
    demands: tuple[str, ...] = ()

class Packing:
    def __init__(self):
        self.alignment = None
        self.stack = []

    def apply(self, arguments):
        words = [word.strip() for word in arguments.split(',')]
        if words == ['']:
            self.alignment = None
        elif len(words) == 1 and words[0].isdigit():
            self.alignment = int(words[0]) or None
        elif words[0] == 'push':
            if len(words) > 3:
                raise ProjectionError(f'unsupported pack arguments: {arguments}')
            alignment = int(words[-1]) if words[-1].isdigit() else self.alignment
            label = words[1] if len(words) > 1 and not words[1].isdigit() else None
            self.stack.append((label, self.alignment))
            self.alignment = alignment or None
        elif words[0] == 'pop':
            label = words[1] if len(words) > 1 and not words[1].isdigit() else None
            if not self.stack:
                raise ProjectionError('pack pop without matching push')
            while self.stack:
                found, self.alignment = self.stack.pop()
                if label is None or found == label:
                    break
            else:
                raise ProjectionError(f'unknown pack label: {label}')
            if len(words) > 1 and words[-1].isdigit():
                self.alignment = int(words[-1]) or None
        else:
            raise ProjectionError(f'unsupported pack arguments: {arguments}')


def extract(text, selected_edges=None):
    """Keep native tokens intact; region ownership comes from the compiler."""
    packing, regions, stack = Packing(), {}, []
    initializer_edges = {}
    origin_file, origin_line = None, 0
    for line in text.splitlines(keepends=True):
        marker = MARKER.fullmatch(line.strip())
        if marker:
            operation, name = marker.groups()
            if operation == 'begin':
                if name in regions or any(row['name'] == name for row in stack):
                    raise ProjectionError(f'duplicate region: {name}')
                if stack:
                    stack[-1]['children'].append(name)
                    stack[-1]['lines'].append('#pragma x2c_region_ref ' + name + '\n')
                lines = []
                if origin_file is not None:
                    lines.append(f'#line {origin_line + 1} {json.dumps(origin_file)}\n')
                stack.append(dict(name=name, lines=lines,
                                  alignment=packing.alignment, pragmas=[],
                                  children=[], demands=[]))
            elif not stack or stack[-1]['name'] != name:
                raise ProjectionError(f'unmatched region end: {name}')
            else:
                row = stack.pop()
                regions[name] = Region(name, ''.join(row['lines']),
                    row['alignment'], tuple(row['pragmas']),
                    tuple(row['children']), tuple(row['demands']))
            origin_line += 1
            continue
        edge = re.fullmatch(r'\s*#\s*pragma\s+x2c_init_edge\s+(\w+)\s+(\w+)\s*', line)
        if edge:
            initializer_edges.setdefault(edge[1], set()).add(edge[2])
            continue
        demand = re.fullmatch(r'\s*#\s*pragma\s+x2c_family_require\s+(\w+)\s*', line)
        if demand:
            if not stack:
                raise ProjectionError('family demand outside declaration')
            stack[-1]['demands'].append(demand[1])
            continue
        location = LINE.fullmatch(line.strip())
        if location:
            origin_line, origin_file = int(location[1]), json.loads(location[2])
        else:
            origin_line += 1
        pack = PACK.fullmatch(line.strip())
        if pack:
            packing.apply(pack[1])
        else:
            pragma = PRAGMA.match(line)
            if pragma and pragma[1].strip() != 'once':
                if not stack:
                    raise ProjectionError('unowned native pragma: ' + pragma[1].strip())
                stack[-1]['pragmas'].append(pragma[1].strip())
        if stack:
            if pack:
                value = '' if packing.alignment is None else str(packing.alignment)
                stack[-1]['lines'].append('#pragma pack(' + value + ')\n')
            else:
                stack[-1]['lines'].append(line)
        elif line.strip() and not LINE.match(line) and not pack:
            raise ProjectionError('unowned preprocessed tokens: ' + line.strip())
    if stack:
        raise ProjectionError(f'unclosed region: {stack[-1]["name"]}')
    if selected_edges is not None:
        selected_edges.extend((source, target) for source, targets in
                              initializer_edges.items() for target in targets)
    visiting, finished = set(), set()
    def check(binding):
        if binding in visiting:
            raise ProjectionError('selected initializer cycle: ' + binding)
        if binding in finished:
            return
        visiting.add(binding)
        for dependency in initializer_edges.get(binding, ()):
            check(dependency)
        visiting.remove(binding)
        finished.add(binding)
    for binding in initializer_edges:
        check(binding)
    return regions


def load_metadata(path):
    """Load immutable portable companion records without inspecting C names."""
    seen, records, edges = set(), {}, {}
    primary = json.loads(path.read_text())
    def load(current):
        current = current.resolve()
        if current in seen:
            return
        seen.add(current)
        metadata = json.loads(current.read_text())
        if metadata['format'] != primary['format']:
            raise ProjectionError('mixed native metadata formats')
        for row in metadata['regions']:
            previous = records.get(row['id'])
            if previous is not None and previous != row:
                raise ProjectionError('conflicting region identity: ' + row['id'])
            records[row['id']] = row
        for family, dependencies in metadata.get('familyEdges', {}).items():
            if family in edges and edges[family] != dependencies:
                raise ProjectionError('conflicting family identity: ' + family)
            edges[family] = dependencies
        for companion in metadata.get('companions', []):
            load(current.parent / companion)
    load(path)
    primary['regions'] = list(records.values())
    primary['familyEdges'] = edges
    primary['_inputs'] = sorted(str(path) for path in seen)
    return primary


def project(text, metadata, selected_edges=None):
    """Order exact regions using producer-supplied binding prerequisites."""
    if metadata['format'] not in (1, 2):
        raise ProjectionError('unknown metadata format')
    regions = extract(text, selected_edges)
    records = {row['id']: row for row in metadata['regions']}
    if len(records) != len(metadata['regions']):
        raise ProjectionError('duplicate metadata identity')
    if set(regions) - set(records):
        raise ProjectionError('emitted region missing metadata')
    families = {}
    for name, region in regions.items():
        family = records[name].get('family')
        if family:
            families.setdefault(family, name)
    selected, active, emitted_families, output = set(), set(), set(), []
    def visit(name):
        if name in selected:
            return
        if name in active:
            raise ProjectionError('selected complete layout cycle: ' + name)
        if name not in regions or name not in records:
            raise ProjectionError('missing selected prerequisite: ' + name)
        active.add(name)
        row, region = records[name], regions[name]
        dependencies = list(row.get('requires', []))
        family = row.get('family')
        for needed in (*metadata.get('familyEdges', {}).get(family, []),
                       *region.demands):
            if needed not in families:
                raise ProjectionError('missing selected complete family: ' + needed)
            dependencies.append(families[needed])
        for dependency in dependencies:
            visit(dependency)
        if family in emitted_families:
            active.remove(name)
            selected.add(name)
            return
        if region.unsupported_pragmas:
            raise ProjectionError('pragma state requires projection: ' + ', '.join(region.unsupported_pragmas))
        # Pack state is a native-compiler property, so restore the state at the
        # original region boundary. A private stack frame prevents a region's
        # trailing setting from changing another provider's incoming state.
        value = '' if region.alignment is None else str(region.alignment)
        output.append('#pragma pack(push)\n#pragma pack(' + value + ')\n')
        for line in region.text.splitlines(keepends=True):
            reference = re.fullmatch(r'\s*#\s*pragma\s+x2c_region_ref\s+(\w+)\s*', line)
            if reference:
                visit(reference[1])
            else:
                output.append(line)
        output.append('\n#pragma pack(pop)\n')
        active.remove(name)
        selected.add(name)
        if family:
            emitted_families.add(family)
    for name in metadata['order']:
        if name in regions:
            visit(name)
        elif not records[name].get('optional', False):
            raise ProjectionError('missing required region: ' + name)
    return ''.join(output)


def retain_projection_inputs(depfile, metadata):
    """Extend the first native dependency rule, retaining its search inputs."""
    path = Path(depfile)
    text = path.read_text()
    end = re.search(r'(?<!\\)\n', text)
    position = end.start() if end else len(text)
    inputs = [*metadata['_inputs'], str(Path(__file__).resolve())]
    def escape(value):
        return value.replace('\\', '\\\\').replace('$', '$$').replace(
            ' ', '\\ ').replace('#', '\\#').replace(':', '\\:')
    insertion = ' \\\n  ' + ' '.join(escape(value) for value in inputs)
    path.write_text(text[:position] + insertion + text[position:])


def compile_native(arguments):
    source, destination, object_file, depfile, *compiler = arguments
    if not compiler or compiler.pop(0) != '--':
        raise ProjectionError('missing configured native compiler arguments')
    source, destination = Path(source), Path(destination)
    metadata = source.with_suffix('.xnm')
    if not metadata.exists():
        return subprocess.run([*compiler, '-MMD', '-MP', '-MF', depfile,
                               '-MT', object_file, '-c', str(source),
                               '-o', object_file]).returncode
    destination.parent.mkdir(parents=True, exist_ok=True)
    expanded = destination.with_suffix('.i')
    status = subprocess.run([*compiler, '-E', '-MMD', '-MP', '-MF', depfile,
                             '-MT', object_file, str(source),
                             '-o', str(expanded)]).returncode
    if status:
        return status
    try:
        configuration = load_metadata(metadata)
        edges = []
        destination.write_text(project(expanded.read_text(), configuration, edges))
        Path(str(destination) + ".xne").write_text(json.dumps(sorted(edges)))
        retain_projection_inputs(depfile, configuration)
    finally:
        expanded.unlink(missing_ok=True)
    # The preprocessing receipt remains authoritative for original headers.
    return subprocess.run([*compiler, '-c', str(destination),
                           '-o', object_file]).returncode


def main():
    try:
        if sys.argv[1:2] == ['--compile']:
            return compile_native(sys.argv[2:])
        expanded, metadata, destination = map(Path, sys.argv[1:4])
        configuration = load_metadata(metadata)
        edges = []
        result = project(expanded.read_text(), configuration, edges)
        Path(str(destination) + ".xne").write_text(json.dumps(sorted(edges)))
        if len(sys.argv) == 5:
            retain_projection_inputs(sys.argv[4], configuration)
        destination.write_text(result)
        return 0
    except (ProjectionError, OSError, ValueError) as failure:
        print(f'native-layout projection: {failure}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
