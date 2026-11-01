from pathlib import Path
import json,subprocess,sys,hashlib,shutil
r=Path.cwd();p=r/'debug/plso-regex-20261101';name,tag=sys.argv[1:];d=p/tag/name;d.mkdir(parents=True,exist_ok=True)
e=json.loads((p/'receipt.json').read_text());a=e['translate_command'][:];a[a.index('--out-dir')+1]=str(d/'generated');subprocess.run(a,check=True)
a=e['compile_command'][:];a[a.index('-o')+1]=str(d/'program');a=[str(d/'generated/tuned.c')if x.endswith(f'{name}/tuned/generated/tuned.c')else x for x in a];subprocess.run(a,check=True)
shutil.copy2(r/f'examples/shootout/benchmarks/{name}/tuned.x',d/'tuned.x');(d/'build.json').write_text(json.dumps({'translate_command':e['translate_command'],'actual_translate_dir':str(d/'generated'),'compile_command':a,'source_sha256':hashlib.sha256((d/'tuned.x').read_bytes()).hexdigest(),'binary_sha256':hashlib.sha256((d/'program').read_bytes()).hexdigest()},indent=2))
