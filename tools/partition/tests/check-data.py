"""Check adapter output against its TSV input, without building the compiler."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    (root / 'src').mkdir()
    (root / 'lib/m').mkdir(parents=True)
    (root / 'src/a.x').write_text('one\ntwo\n')
    (root / 'lib/b.x').write_text('three\n')
    (root / 'lib/m/m.x').write_text('module {\n  "part.x",\n}\n')
    (root / 'lib/m/part.x').write_text('#include "../b.x"\nfour\nfive\n')
    (root / 'lib/x2c.x').write_text('generated\n')
    (root / 'functions.tsv').write_text(
        'function_id\tunit\tfile\tvisibility\tneeded\tkind\texternal_calls\tindirect_calls\tsource_name\temitted_name\tsource_order\n'
        'A\tsrc/a.x\tsrc/a.x\tpublic\tnone\tfunction\t0\t1\ta\ta\t1\n'
        'B\tlib/b.x\tlib/b.x\tstatic\tpublic\tfunction\t2\t0\tb\tb\t1\n'
        'C\tlib/m/m.x\tlib/m/part.x\tmodule\tstatic\tfunction\t0\t0\tc\tc\t1\n'
        'D\tlib/m/m.x\tlib/m/part.x\tstatic\tnone\tfunction\t0\t0\td\tf1_part___d\t2\n')
    header = 'caller_id\tcallee_id\tstatic_calls\n'
    (root / 'src-calls.tsv').write_text(header)
    (root / 'lib-calls.tsv').write_text(header + 'A\tB\t3\n')
    output = root / 'graph.json'
    subprocess.run([sys.executable, str(HERE / 'build-data.py'), str(root), str(root), str(output)], check=True, stdout=subprocess.DEVNULL)
    data = json.loads(output.read_text())
    assert [f['id'] for f in data['files']] == ['src/a.x', 'lib/b.x', 'lib/m/m.x']
    assert data['edges'] == [[0, 1, 3]]
    assert data['stats']['crossCalls'] == 3
    assert data['stats']['callSites'] == 6
    assert data['files'][0]['lines'] == 2
    assert [(f['v'], f['s']) for f in data['functions']] == [
        ('public', 0), ('static', 1), ('module', 1), ('static', 1)]
    assert [f['r'] for f in data['functions']] == [None, 'public', 'static', None]
    assert [data['stats'][k] for k in ('staticFns', 'moduleFns', 'publicFns')] == [2, 1, 1]
    module = data['files'][2]
    assert data['functions'][2]['p'] == 'lib/m/part.x'
    assert module['members'] == {'lib/m/part.x': '#include "../b.x"\nfour\nfive\n'}
    assert module['lines'] == 6
    assert data['includeEdges'] == [[2, 1]]
print('PASS: unit discovery, prelude exclusion, storage tiers, needed storage, member files, line counts, weighted edges')
