import argparse, pathlib, re, subprocess, hashlib, json, time, os
p=argparse.ArgumentParser();p.add_argument('--compiler',required=True);p.add_argument('--source-root',required=True);p.add_argument('--out',required=True);p.add_argument('--samples',type=int,default=0);p.add_argument('--x2c-home',required=True);a=p.parse_args()
env=os.environ.copy();env.pop('X2C_DUAL_EFFECT_PROBE',None);env['X2C_HOME']=str(pathlib.Path(a.x2c_home).resolve())
root=pathlib.Path(a.source_root).resolve();out=pathlib.Path(a.out).resolve();out.mkdir(parents=True,exist_ok=True)
# Lexical inventory only: governing-statement syntax is established by parser owner.
def has_try(text):
    stripped=re.sub(r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'',lambda m:' '*len(m.group()),text,flags=re.S)
    return bool(re.search(r'\btry\b',stripped))
fixtures=[x for x in sorted((root/'unittest/compiler-fixtures').glob('*.x')) if has_try(x.read_text())]
corpus=[root/x for x in ['src/transform.x','src/emit.x','src/expressions.x','src/generate.x','src/parse.x','src/type.x','lib/tokenizer.x','unittest/benchmarks/exception-hot-paths.x']]
def run(src,folder,flags=[]):
    folder.mkdir(parents=True,exist_ok=True)
    r=subprocess.run([a.compiler,'translate',*flags,'--out-dir',str(folder),str(src)],cwd=root,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    (folder/'command.log').write_bytes(r.stdout)
    files={str(f.relative_to(folder)):{'bytes':f.stat().st_size,'sha256':hashlib.sha256(f.read_bytes()).hexdigest()} for f in sorted(folder.rglob('*')) if f.suffix in ['.c','.h']}
    return {'source':str(src.relative_to(root)),'exit':r.returncode,'files':files}
records=[run(src,out/'fixtures'/src.stem) for src in fixtures]
records += [run(src,out/'corpus'/mode/src.stem,flags) | {'mode':mode} for mode,flags in [('default',[]),('live',['--live-symbols'])] for src in corpus]
(out/'manifest.json').write_text(json.dumps({'compiler':a.compiler,'source_root':str(root),'x2c_home':env['X2C_HOME'],'try_inventory':'lexical token after stripping ordinary C comments and quoted strings; not a parser proof','results':records},indent=2))
if a.samples:
    samples=[]
    for group,sources in [('compiler-translation',corpus[:-1]),('exception-hot-paths',corpus[-1:])]:
      for mode,flags in [('default',[]),('live',['--live-symbols'])]:
        for i in range(a.samples):
          t=time.perf_counter()
          current=[run(src,out/'timed'/mode/src.stem,flags) for src in sources]
          samples.append({'group':group,'mode':mode,'sample':i+1,'seconds':time.perf_counter()-t,'all_pass':all(r['exit']==0 for r in current)})
    (out/'samples.json').write_text(json.dumps(samples,indent=2))
print(json.dumps({'fixture_count':len(fixtures),'manifest':str(out/'manifest.json'),'samples':a.samples}))
