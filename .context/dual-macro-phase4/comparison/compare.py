import json,sys
left=json.load(open(sys.argv[1]));right=json.load(open(sys.argv[2]))
def indexed(m):return {(r['source'],r.get('mode','fixture')):r for r in m['results']}
a,b=indexed(left),indexed(right)
changes=[]
for key in sorted(a.keys()|b.keys()):
 if key not in a or key not in b:changes.append({'key':key,'reason':'missing'})
 elif (a[key]['exit'],a[key]['files'])!=(b[key]['exit'],b[key]['files']):changes.append({'key':key,'baseline':a[key],'candidate':b[key]})
print(json.dumps({'source_root_equal':left['source_root']==right['source_root'],'case_count':len(a),'changed_cases':changes},indent=2))
sys.exit(bool(changes))
