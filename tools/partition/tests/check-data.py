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
    (root / 'lib').mkdir()
    (root / 'src/a.x').write_text('one\ntwo\n')
    (root / 'lib/b.x').write_text('three\n')
    (root / 'lib/x2c.x').write_text('generated\n')
    (root / 'functions.tsv').write_text(
        'function_id\tunit\tvisibility\tkind\texternal_calls\tindirect_calls\tsource_name\temitted_name\tsource_order\n'
        'A\tsrc/a.x\tpublic\tfunction\t0\t1\ta\ta\t1\n'
        'B\tlib/b.x\tstatic\tfunction\t2\t0\tb\tb\t1\n')
    header = 'caller_id\tcallee_id\tstatic_calls\n'
    (root / 'src-calls.tsv').write_text(header)
    (root / 'lib-calls.tsv').write_text(header + 'A\tB\t3\n')
    output = root / 'graph.json'
    subprocess.run([sys.executable, str(HERE / 'build-data.py'), str(root), str(root), str(output)], check=True, stdout=subprocess.DEVNULL)
    data = json.loads(output.read_text())
    assert len(data['files']) == 2
    assert data['edges'] == [[0, 1, 3]]
    assert data['stats']['crossCalls'] == 3
    assert data['stats']['callSites'] == 6
    assert data['files'][0]['lines'] == 2
    assert data['functions'][1]['s'] == 1
print('PASS: source discovery, generated prelude exclusion, visibility, line counts, weighted edges')
