"""Exercise editor semantics through an installed compiler's command dispatch."""
from pathlib import Path
import sys

from client import Client

root, compiler, source = (Path(value).resolve() for value in sys.argv[1:4])
client = Client(root, Path.cwd(), sys.argv[4:] or ["build"], compiler=compiler)
try:
    client.opened(source, source.read_text())
    diagnostics = client.diagnostics()
    assert diagnostics == [], diagnostics
    response = client.request("textDocument/hover", {
        "textDocument": {"uri": source.as_uri()},
        "position": {"line": 0, "character": 0}})
    assert "result" in response, response
finally:
    client.close()
print("installed language server analyzes without installing dependencies")
