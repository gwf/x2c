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
LINE = re.compile(r'^\s*#\s+(?:line\s+)?(\d+)\s+("(?:\\.|[^"\\])*")(?:\s+(.*))?$')

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
    epoch: int = 0
    origins: tuple[str, ...] = ()
    namespace_demands: tuple[str, ...] = ()

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
    origin_file, origin_line, epoch = None, 0, 0
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
                                  children=[], demands=[], epoch=epoch, origins=set(), namespaces=[]))
            elif not stack or stack[-1]['name'] != name:
                raise ProjectionError(f'unmatched region end: {name}')
            else:
                row = stack.pop()
                regions[name] = Region(name, ''.join(row['lines']),
                    row['alignment'], tuple(row['pragmas']),
                    tuple(row['children']), tuple(row['demands']), row['epoch'],
                    tuple(sorted(row['origins'])), tuple(row['namespaces']))
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
        namespace = re.fullmatch(r'\s*#\s*pragma\s+x2c_namespace_require\s+(\w+)\s*', line)
        if namespace:
            if not stack:
                raise ProjectionError('namespace demand outside declaration')
            stack[-1]['namespaces'].append(namespace[1])
            continue
        location = LINE.fullmatch(line.strip())
        if location:
            origin_line, origin_file = int(location[1]), json.loads(location[2])
        else:
            origin_line += 1
        if stack and origin_file and not origin_file.startswith('<'):
            stack[-1]['origins'].add(str(Path(origin_file).resolve()))
        pack = PACK.fullmatch(line.strip())
        if pack:
            packing.apply(pack[1])
        else:
            pragma = PRAGMA.match(line)
            if pragma and pragma[1].strip() != 'once':
                if not stack:
                    raise ProjectionError('unowned native pragma: ' + pragma[1].strip())
                epoch += 1
                stack[-1]['lines'].append('#pragma x2c_opaque_epoch ' + str(epoch) + '\n')
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


def load_metadata(path, streams=()):
    """Load immutable portable companion records without inspecting C names."""
    seen, records, edges, namespace_edges, native_providers = set(), {}, {}, {}, {}
    owner_sources, region_providers = {}, {}
    primary = json.loads(path.read_text())
    def load(current):
        current = current.resolve()
        if current in seen:
            return
        seen.add(current)
        metadata = json.loads(current.read_text())
        if metadata.get('active') is False:
            return
        if metadata['format'] != primary['format']:
            raise ProjectionError('mixed native metadata formats')
        provider = metadata.get('provider')
        if provider:
            owner_sources[provider] = str(current.parent / metadata['source'])
        for row in metadata['regions']:
            region_providers[row['id']] = provider
            previous = records.get(row['id'])
            if previous is not None and previous != row:
                raise ProjectionError('conflicting region identity: ' + row['id'])
            records[row['id']] = row
        for family, dependencies in metadata.get('familyEdges', {}).items():
            if family in edges and edges[family] != dependencies:
                raise ProjectionError('conflicting family identity: ' + family)
            edges[family] = dependencies
        namespace_edges.update(metadata.get('namespaceEdges') or {})
        native_providers.update(metadata.get('nativeProviders') or {})
        for companion in metadata.get('companions', []):
            load(current.parent / companion)
    load(path)
    for text in streams:
        physical, include_stack = None, []
        for line in text.splitlines():
            location = LINE.fullmatch(line.strip())
            if location:
                filename = json.loads(location[2])
                flags = (location[3] or '').split()
                if '1' in flags:
                    include_stack.append(physical)
                    physical = filename
                elif '2' in flags:
                    if not include_stack:
                        raise ProjectionError('native include return without entry')
                    physical = include_stack.pop()
                elif physical is None:
                    physical = filename
                continue
            marker = MARKER.fullmatch(line.strip())
            if not marker or marker[1] != 'begin' or marker[2] in records:
                continue
            if physical is None or physical.startswith('<'):
                raise ProjectionError('region has no physical provider: ' + marker[2])
            provider = Path(physical).with_suffix('.xnm')
            if not provider.exists():
                raise ProjectionError('missing selected provider metadata: ' + str(provider))
            load(provider)
            if marker[2] not in records:
                raise ProjectionError('selected provider does not define region: ' + marker[2])
    primary['regions'] = list(records.values())
    primary['familyEdges'] = edges
    primary['namespaceEdges'] = namespace_edges
    primary['nativeProviders'] = native_providers
    primary['_ownerSources'] = owner_sources
    primary['_regionProviders'] = region_providers
    primary['_inputs'] = sorted(str(path) for path in seen)
    return primary


def project(text, metadata, selected_edges=None, owner_streams=None):
    """Order exact regions using producer-supplied binding prerequisites."""
    if metadata['format'] not in (1, 2):
        raise ProjectionError('unknown metadata format')
    regions = extract(text, selected_edges)
    records = {row['id']: row for row in metadata['regions']}
    if len(records) != len(metadata['regions']):
        raise ProjectionError('duplicate metadata identity')
    if set(regions) - set(records):
        raise ProjectionError('emitted region missing metadata: ' +
                              ', '.join(sorted(set(regions) - set(records))))
    families = {}
    for name, region in regions.items():
        family = records[name].get('family')
        if family:
            families.setdefault(family, name)
        for supplied in records[name].get('suppliesFamilies', []):
            families.setdefault(supplied, name)
    for provider, stream in (owner_streams or {}).items():
        owned = extract(stream)
        for name, region in owned.items():
            row = records.get(name, {})
            family = row.get('family')
            if family and row.get('familyOwner') == provider and \
                    metadata['_regionProviders'].get(name) == provider:
                regions[name] = region
                families[family] = name
                # Native aliases and prerequisites must use this same stream.
                for sibling, value in owned.items():
                    if metadata['_regionProviders'].get(sibling) == provider and (
                            records.get(sibling, {}).get('role') == 'h' or
                            records.get(sibling, {}).get('family')):
                        regions[sibling] = value
                        for supplied in records.get(sibling, {}).get('suppliesFamilies', []):
                            families[supplied] = sibling
    namespaces = {}
    for name, region in regions.items():
        for namespace in records[name].get('defines', []):
            namespaces.setdefault(namespace, name)
        origins = set(region.origins)
        for namespace, provider in metadata.get('nativeProviders', {}).items():
            if str(Path(provider).resolve()) in origins:
                namespaces.setdefault(namespace, name)
    selected, active, emitted_families, output = set(), set(), set(), []
    current_epoch = 0
    def visit(name):
        nonlocal current_epoch
        if name in selected:
            return
        if name in active:
            raise ProjectionError('selected complete layout cycle: ' + name)
        if name not in regions or name not in records:
            raise ProjectionError('missing selected prerequisite: ' + name)
        active.add(name)
        row, region = records[name], regions[name]
        dependencies = list(row.get('requires', []))
        defines = row.get('defines', [])
        requirements = list(region.namespace_demands)
        for definition in defines:
            if not row.get('selectedNamespaces'):
                requirements.extend((metadata.get('namespaceEdges') or {}).get(definition, []))
        for needed in requirements:
            if needed in defines:
                continue
            if needed not in namespaces:
                raise ProjectionError('missing selected namespace: ' + needed)
            dependencies.append(namespaces[needed])
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
        if region.epoch != current_epoch:
            raise ProjectionError('declaration crosses opaque pragma state: ' + name)
        # Pack state is a native-compiler property, so restore the state at the
        # original region boundary. A private stack frame prevents a region's
        # trailing setting from changing another provider's incoming state.
        value = '' if region.alignment is None else str(region.alignment)
        output.append('#pragma pack(push)\n#pragma pack(' + value + ')\n')
        for line in region.text.splitlines(keepends=True):
            reference = re.fullmatch(r'\s*#\s*pragma\s+x2c_region_ref\s+(\w+)\s*', line)
            barrier = re.fullmatch(r'\s*#\s*pragma\s+x2c_opaque_epoch\s+(\d+)\s*', line)
            if reference:
                visit(reference[1])
            elif barrier:
                if int(barrier[1]) != current_epoch + 1:
                    raise ProjectionError('opaque pragma state order changed: ' + name)
                current_epoch += 1
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
    for owner_receipt in metadata.get('_ownerReceipts', []):
        owner_text = Path(owner_receipt).read_text()
        owner_end = re.search(r'(?<!\\)\n', owner_text)
        rule = owner_text[:owner_end.start()] if owner_end else owner_text
        delimiter = re.search(r'(?<!\\):', rule)
        if delimiter is None:
            raise ProjectionError('malformed owner preprocessing receipt')
        insertion += ' \\\n  ' + rule[delimiter.end():].strip()
    path.write_text(text[:position] + insertion + text[position:])


def preprocess_owners(metadata, compiler, directory, consumer_text):
    """Use each defining source's configured CPP environment exactly once."""
    streams = {}
    selected = extract(consumer_text)
    required = {row.get('familyOwner') for row in metadata['regions']
                if row.get('family') and row['id'] in selected and
                row.get('familyOwner') != metadata.get('provider')}
    for ordinal, (provider, source) in enumerate(
            metadata.get('_ownerSources', {}).items()):
        if provider not in required:
            continue
        source = Path(source)
        if not source.exists():
            raise ProjectionError('missing defining native source: ' + str(source))
        expanded = directory / f'owner-{ordinal}.i'
        receipt = directory / f'owner-{ordinal}.d'
        status = subprocess.run([*compiler, '-E', '-MMD', '-MP', '-MF',
            str(receipt), '-MT', str(expanded), str(source), '-o',
            str(expanded)]).returncode
        if status:
            raise ProjectionError('defining source preprocessing failed: ' + str(source))
        streams[provider] = expanded.read_text()
        expanded.unlink()
        metadata['_inputs'].append(str(source))
        metadata.setdefault('_ownerReceipts', []).append(str(receipt))
    return streams


def compile_native(arguments):
    source, destination, object_file, depfile, *compiler = arguments
    if not compiler or compiler.pop(0) != '--':
        raise ProjectionError('missing configured native compiler arguments')
    source, destination = Path(source), Path(destination)
    metadata = source.with_suffix('.xnm')
    if not metadata.exists() or json.loads(metadata.read_text()).get('active') is False:
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
        consumer_text = expanded.read_text()
        configuration = load_metadata(metadata, [consumer_text])
        edges = []
        streams = preprocess_owners(configuration, compiler, destination.parent, consumer_text)
        receipts = configuration.get('_ownerReceipts', [])
        configuration = load_metadata(metadata, [consumer_text, *streams.values()])
        configuration['_ownerReceipts'] = receipts
        destination.write_text(project(consumer_text, configuration, edges, streams))
        Path(str(destination) + ".xne").write_text(json.dumps(sorted(edges)))
        retain_projection_inputs(depfile, configuration)
    finally:
        expanded.unlink(missing_ok=True)
    # The preprocessing receipt remains authoritative for original headers.
    return subprocess.run([*compiler, '-c', str(destination),
                           '-o', object_file]).returncode


def project_external(arguments):
    """Enroll a deliberate C consumer without assigning language ownership."""
    source, destination, depfile, *arguments = arguments
    divider = arguments.index('--')
    companions, compiler = arguments[:divider], arguments[divider + 1:]
    source, destination = Path(source).resolve(), Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    wrapper = destination.parent / 'consumer-wrapper.c'
    metadata = wrapper.with_suffix('.xnm')
    identity = 'x2c_external_consumer'
    wrapper.write_text(f'#pragma x2c_region_begin {identity}\n'
                       f'#include {json.dumps(str(source))}\n'
                       f'#pragma x2c_region_end {identity}\n')
    metadata.write_text(json.dumps(dict(format=2, source=wrapper.name,
        header='', regions=[dict(id=identity, role='c', kind='native',
        optional=False, defines=[])], order=[identity], headerOrder=[],
        companions=[str(Path(path).resolve()) for path in companions])))
    expanded = wrapper.with_suffix('.i')
    status = subprocess.run([*compiler, '-E', '-MMD', '-MP', '-MF', depfile,
        '-MT', str(destination), str(wrapper), '-o', str(expanded)]).returncode
    if status:
        return status
    try:
        text = expanded.read_text()
        configuration = load_metadata(metadata, [text])
        streams = preprocess_owners(configuration, compiler,
                                    destination.parent, text)
        receipts = configuration.get('_ownerReceipts', [])
        configuration = load_metadata(metadata, [text, *streams.values()])
        configuration['_ownerReceipts'] = receipts
        edges = []
        destination.write_text(project(text, configuration, edges, streams))
        Path(str(destination) + '.xne').write_text(json.dumps(sorted(edges)))
        retain_projection_inputs(depfile, configuration)
    finally:
        expanded.unlink(missing_ok=True)
    return 0


def main():
    try:
        if sys.argv[1:2] == ['--external']:
            return project_external(sys.argv[2:])
        if sys.argv[1:2] == ['--compile']:
            return compile_native(sys.argv[2:])
        arguments = sys.argv[1:]
        compiler = None
        if arguments[:1] == ['--project']:
            arguments = arguments[1:]
            divider = arguments.index('--')
            compiler = arguments[divider + 1:]
            arguments = arguments[:divider]
        expanded, metadata, destination = map(Path, arguments[:3])
        consumer_text = expanded.read_text()
        configuration = load_metadata(metadata, [consumer_text])
        edges = []
        streams = preprocess_owners(configuration, compiler, destination.parent, consumer_text) if compiler else None
        receipts = configuration.get('_ownerReceipts', [])
        if streams:
            configuration = load_metadata(metadata, [consumer_text, *streams.values()])
            configuration['_ownerReceipts'] = receipts
        result = project(consumer_text, configuration, edges, streams)
        Path(str(destination) + ".xne").write_text(json.dumps(sorted(edges)))
        if len(arguments) == 4:
            retain_projection_inputs(arguments[3], configuration)
        destination.write_text(result)
        return 0
    except (ProjectionError, OSError, ValueError) as failure:
        print(f'native-layout projection: {failure}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
