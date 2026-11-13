#!/usr/bin/env python3
"""Verify the live staging website and every retained release file."""
import argparse
import hashlib
import json
from pathlib import Path
import time
from urllib.request import urlopen

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--site", type=Path, required=True)
args = parser.parse_args()
expected = json.loads((args.site / "website-deployment.json").read_text())
base = "https://staging.x2c-lang.dev/"

for attempt in range(12):
    try:
        def read(path):
            with urlopen(base + path + "?website=" + expected["source_sha"], timeout=30) as response:
                return response.read()
        actual = json.loads(read("website-deployment.json"))
        if actual != expected:
            raise ValueError("live website deployment differs")
        html = read("index.html").decode()
        if f'name="x2c-site-source" content="{expected["source_sha"]}"' not in html:
            raise ValueError("live homepage source differs")
        for path, digest in expected["preserved_sha256"].items():
            if hashlib.sha256(read(path)).hexdigest() != digest:
                raise ValueError(f"retained release file differs: {path}")
        programs = json.loads((args.site / "playground/programs/programs.json").read_text())
        if not programs:
            raise ValueError("website has no precompiled programs")
        for program in programs:
            for suffix in (".js", ".wasm"):
                path = "playground/programs/" + program + suffix
                if hashlib.sha256(read(path)).digest() != hashlib.sha256(
                        (args.site / path).read_bytes()).digest():
                    raise ValueError(f"live browser program differs: {path}")
        print(f"Live staging website verified with {len(programs)} browser programs; "
              "retained release files are unchanged.")
        break
    except Exception:
        if attempt == 11:
            raise
        time.sleep(10)
