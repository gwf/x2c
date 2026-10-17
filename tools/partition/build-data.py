#!/usr/bin/env python3
"""Convert x2c-graph datasets to the browser snapshot.

Called by generate.py with REPO_ROOT DATASETS_DIR OUT_JSON.
The exporter owns parsing and call resolution; this adapter aggregates its TSVs.
"""
import csv, glob, hashlib, json, os, subprocess, sys
from collections import defaultdict

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from sources import sources

def unit_sources(root):
    """Entry units of src and lib, without the generated prelude."""
    units = [os.path.relpath(p, root) for area in ("src", "lib") for p in sources(root, area)]
    return [unit for unit in units if unit != "lib/x2c.x"]

def git_revision(root):
    try:
        revision = subprocess.check_output(["git", "-C", root, "rev-parse", "--short", "HEAD"], text=True, stderr=subprocess.DEVNULL).strip()
        dirty = subprocess.check_output(["git", "-C", root, "status", "--porcelain", "--", "src", "lib"], text=True)
        if dirty:
            paths = sorted(glob.glob(os.path.join(root, "src", "**", "*.x"), recursive=True) +
                           glob.glob(os.path.join(root, "lib", "**", "*.x"), recursive=True))
            digest = hashlib.sha256()
            for path in paths:
                if os.path.basename(path) == "x2c.x":
                    continue
                digest.update(os.path.relpath(path, root).encode())
                with open(path, "rb") as source:
                    digest.update(source.read())
            revision += "-dirty-" + digest.hexdigest()[:12]
        return revision
    except Exception:
        return ""

root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
datasets = sys.argv[2] if len(sys.argv) > 2 else os.path.join(root, "explorer", "data")
out_path = sys.argv[3] if len(sys.argv) > 3 else os.path.join(root, "explorer", "data", "graph.json")

# ---- discover units ---------------------------------------------------------
# Each file is a translation unit; a module unit's member files are spliced
# into its entry, and functions.tsv names the file holding each definition.
module_ids = unit_sources(root)

def count_lines(rel):
    with open(os.path.join(root, rel), "rb") as fh:
        return sum(1 for _ in fh)

def read_source(rel):
    with open(os.path.join(root, rel), encoding="utf-8") as fh:
        return fh.read()

files, fidx = [], {}
for mid in module_ids:
    fidx[mid] = len(files)
    files.append({
        "id": mid,
        "subtree": mid.split("/", 1)[0],
        "dir": os.path.dirname(mid) or ".",
        "name": os.path.basename(mid),
        "lines": count_lines(mid),
        "source": read_source(mid),
        "members": {},
        "functions": 0, "staticFns": 0, "moduleFns": 0, "publicFns": 0, "topLevel": 0,
        "internalCalls": 0, "outCalls": 0, "inCalls": 0,
        "externalCalls": 0, "indirectCalls": 0,
        "outFiles": set(), "inFiles": set(),
    })

# ---- functions --------------------------------------------------------------
functions, fnidx, fn_unit = [], {}, []
skipped_units = set()
with open(os.path.join(datasets, "functions.tsv"), newline="") as fh:
    for row in csv.DictReader(fh, delimiter="\t"):
        unit = row["unit"]
        if unit not in fidx:
            skipped_units.add(unit)
            continue
        fi = fidx[unit]
        f = files[fi]
        tier, member = row["visibility"], row["file"]
        if member != unit and member not in f["members"]:
            f["members"][member] = read_source(member)
            f["lines"] += count_lines(member)
        kind = 1 if row["kind"] == "top-level" else 0
        ext, ind = int(row["external_calls"]), int(row["indirect_calls"])
        f["functions"] += 1
        if kind:
            f["topLevel"] += 1
        else:
            f[tier + "Fns"] += 1
        f["externalCalls"] += ext
        f["indirectCalls"] += ind
        fnidx[row["function_id"]] = len(functions)
        fn_unit.append(unit)
        # `s` marks a definition private to its unit: file-private or module.
        functions.append({"f": fi, "p": member, "n": row["source_name"], "e": row["emitted_name"],
                          "s": 0 if tier == "public" else 1, "v": tier, "k": kind,
                          "o": int(row["source_order"]), "x": ext, "i": ind})

# ---- call edges -------------------------------------------------------------
edges = []
pair = defaultdict(lambda: {"calls": 0, "pairs": 0})
for name in ("src-calls.tsv", "lib-calls.tsv"):
    with open(os.path.join(datasets, name), newline="") as fh:
        for row in csv.DictReader(fh, delimiter="\t"):
            c, t = fnidx.get(row["caller_id"]), fnidx.get(row["callee_id"])
            if c is None or t is None:
                continue
            n = int(row["static_calls"])
            edges.append([c, t, n])
            cu, tu = fn_unit[c], fn_unit[t]
            if cu == tu:
                files[fidx[cu]]["internalCalls"] += n
            else:
                files[fidx[cu]]["outCalls"] += n
                files[fidx[tu]]["inCalls"] += n
                files[fidx[cu]]["outFiles"].add(tu)
                files[fidx[tu]]["inFiles"].add(cu)
                k = (fidx[cu], fidx[tu])
                pair[k]["calls"] += n
                pair[k]["pairs"] += 1

# ---- include edges (module dependency overlay) ------------------------------
include_edges = []
for mid in module_ids:
    f = files[fidx[mid]]
    for path, text in [(mid, f["source"]), *f["members"].items()]:
        for line in text.splitlines():
            line = line.strip()
            if not line.startswith('#include "'):
                continue
            target = line[len('#include "'):].split('"', 1)[0]
            cand = [os.path.normpath(os.path.join(os.path.dirname(path), target)),
                    os.path.normpath(os.path.join("src", target)),
                    os.path.normpath(os.path.join("lib", target))]
            for c in cand:
                if c in fidx:
                    if c != mid:
                        include_edges.append([fidx[mid], fidx[c]])
                    break
# dedupe includes
seen = set()
include_edges = [e for e in include_edges if not (tuple(e) in seen or seen.add(tuple(e)))]

# ---- finalize per-file stats ------------------------------------------------
file_edges = []
for (s, t), v in sorted(pair.items()):
    file_edges.append({"s": s, "t": t, "calls": v["calls"], "pairs": v["pairs"]})

for f in files:
    f["outDegree"] = len(f["outFiles"])
    f["inDegree"] = len(f["inFiles"])
    f["degree"] = len(f["outFiles"] | f["inFiles"])
    f["resolvedCalls"] = f["internalCalls"] + f["outCalls"]
    f["callSites"] = f["resolvedCalls"] + f["externalCalls"] + f["indirectCalls"]
    del f["outFiles"], f["inFiles"]

stats = {
    "files": len(files),
    "functions": len(functions),
    "staticFns": sum(1 for f in functions if f["v"] == "static" and not f["k"]),
    "moduleFns": sum(1 for f in functions if f["v"] == "module" and not f["k"]),
    "publicFns": sum(1 for f in functions if f["v"] == "public" and not f["k"]),
    "topLevel": sum(1 for f in functions if f["k"]),
    "edges": len(edges),
    "fileEdges": len(file_edges),
    "includeEdges": len(include_edges),
    "callSites": sum(f["callSites"] for f in files),
    "resolvedCalls": sum(f["resolvedCalls"] for f in files),
    "externalCalls": sum(f["externalCalls"] for f in files),
    "indirectCalls": sum(f["indirectCalls"] for f in files),
    "internalCalls": sum(f["internalCalls"] for f in files),
    "crossCalls": sum(f["outCalls"] for f in files),
    "srcLines": sum(f["lines"] for f in files if f["subtree"] == "src"),
    "libLines": sum(f["lines"] for f in files if f["subtree"] == "lib"),
}

model = {
    "generated": __import__("time").strftime("%Y-%m-%dT%H:%M:%SZ", __import__("time").gmtime()),
    "revision": git_revision(root),
    "stats": stats,
    "files": files,
    "fileEdges": file_edges,
    "includeEdges": include_edges,
    "functions": functions,
    "edges": edges,
}

os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, "w") as fh:
    json.dump(model, fh, separators=(",", ":"))

if skipped_units:
    print("WARNING skipped function units not in module list:", sorted(skipped_units))
print(json.dumps(stats, indent=2))
print("wrote", out_path, os.path.getsize(out_path), "bytes")
