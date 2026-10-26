#!/usr/bin/env python3
"""Check persistent query parity, request lifetimes, and pinned snapshots."""
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    tool = Path('builds/0/libexec/x2c-graph').resolve()
    with tempfile.TemporaryDirectory(prefix='x2c-serve-') as temporary:
        root = Path(temporary).resolve()
        source, snapshot, query_file = root/'source.x', root/'snapshot', root/'query.json'
        source.write_text('int leaf(int x) => x + 1;\nint entry(int x) => leaf(x);\n')

        def command(*args):
            result = subprocess.run([tool, *map(str, args)], capture_output=True,
                                    text=True, check=True)
            return json.loads(result.stdout)

        command('snapshot', snapshot, source)
        queries = [
            {'op': 'find', 'where': {'name': 'entry'}},
            {'op': 'inspect', 'select': {'name': 'entry'}, 'view': 'typed_ast'},
            {'op': 'traverse', 'select': {'name': 'entry'}, 'relations': ['calls']},
            {'op': 'path', 'select': {'name': 'entry'}, 'target': {'name': 'leaf'}},
            {'op': 'match', 'select': {'name': 'entry'},
             'pattern': '(expr ?type (call ?callee (args *args)))'},
            {'op': 'find', 'where': {'reachable_from': {
                'select': {'name': 'entry'}, 'relations': ['calls']}}},
        ]
        expected = []
        for query in queries:
            query_file.write_text(json.dumps(query))
            expected.append(command('query', snapshot, query_file))
        process = subprocess.Popen([tool, 'serve', snapshot], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            assert 'ready' in process.stderr.readline()

            def send(query):
                line = query if isinstance(query, str) else json.dumps(query)
                process.stdin.write(line + '\n')
                process.stdin.flush()
                response = process.stdout.readline()
                assert response, process.poll()
                return json.loads(response)

            for _ in range(3):
                for query, answer in zip(queries, expected):
                    assert send(query) == answer, query
                for invalid in ('{', '[]', '', {'op': 'unknown'},
                                {'op': 'match', 'pattern': '('}):
                    assert 'error' in send(invalid), invalid
            for index in range(200):
                query = {'op': 'find', 'where': {'reachable_from': {
                    'select': {'name': f'absent_{index}'}, 'relations': ['calls']}}}
                assert send(query)['total'] == 0
            assert send(queries[2]) == expected[2]
            # Replacing the saved snapshot must not replace a running session.
            source.write_text('int replacement(void) => 42;\n')
            rebuilt = command('snapshot', snapshot, source)
            assert rebuilt['snapshot'] != expected[0]['snapshot']
            assert send(queries[0]) == expected[0]
            query_file.write_text(json.dumps(queries[0]))
            assert command('query', snapshot, query_file)['total'] == 0
            process.stdin.close()
            assert process.wait(timeout=10) == 0
            # A final request without a newline is still processed before EOF.
            result = subprocess.run([tool, 'serve', snapshot], input=json.dumps(queries[0]),
                                    capture_output=True, text=True, check=True)
            assert json.loads(result.stdout)['snapshot'] == rebuilt['snapshot']
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
    print('snapshot serve passed')


if __name__ == '__main__':
    main()
