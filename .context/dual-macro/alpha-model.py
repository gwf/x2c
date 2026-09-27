# Model only: canonical binding nodes plus an explicit declaration interface.
def norm(node, owned):
    slots = {identity: ordinal for ordinal, identity in enumerate(owned)}
    def walk(value):
        if isinstance(value, tuple):
            if len(value) == 3 and value[0] == 'binding':
                return ('local', slots[value[1]]) if value[1] in slots else ('free', value[1])
            return tuple(walk(x) for x in value)
        return value
    return walk(node)
def b(i, name): return ('binding', i, name)
a=('block', ('declare', b(1,'x')), ('block', ('declare', b(2,'x')), ('ident',b(2,'x'))), ('ident',b(1,'x')), ('ident',b(10,'external')))
c=('block', ('declare', b(4,'a')), ('block', ('declare', b(5,'b')), ('ident',b(5,'b'))), ('ident',b(4,'a')), ('ident',b(10,'renamed-label')))
assert norm(a,[1,2]) == norm(c,[4,5])
wrong_shadow=('block', ('declare', b(4,'a')), ('block', ('declare', b(5,'b')), ('ident',b(4,'a'))), ('ident',b(4,'a')), ('ident',b(10,'external')))
assert norm(a,[1,2]) != norm(wrong_shadow,[4,5])
wrong_free=('block', ('declare', b(4,'a')), ('block', ('declare', b(5,'b')), ('ident',b(5,'b'))), ('ident',b(4,'a')), ('ident',b(11,'external')))
assert norm(a,[1,2]) != norm(wrong_free,[4,5])
# In an extracted subtree, an outer local is free relative to that subtree.
assert norm(('ident',b(1,'x')),[]) != norm(('ident',b(2,'x')),[])
print('PASS: alpha rename, shadow rejection, rigid free rejection, subtree interface')
print(norm(a,[1,2]))

def capture(node, owned_by_capture, surrounding):
    refs=set()
    def scan(x):
        if isinstance(x,tuple):
            if len(x)==3 and x[0]=='binding': refs.add(x[1])
            else:
                for child in x: scan(child)
    scan(node)
    external=refs-set(owned_by_capture)
    return {'syntax':node,'owned':tuple(owned_by_capture),
            'boundary':{i:surrounding[i] for i in external if i in surrounding},
            'free':external-set(surrounding)}
def reconstruct(cap, destination):
    # Destination keys are template-local slots; remap external local refs only.
    missing=set(cap['boundary'].values())-set(destination)
    if missing: raise ValueError('escaping local reference')
    remap={old:destination[slot] for old,slot in cap['boundary'].items()}
    def walk(x):
        if isinstance(x,tuple):
            if len(x)==3 and x[0]=='binding' and x[1] in remap: return remap[x[1]]
            return tuple(walk(c) for c in x)
        return x
    return walk(cap['syntax'])
cap=capture(('op','+',('ident',b(1,'x')),('ident',b(10,'free'))),[],{1:0,2:1})
assert cap['boundary']=={1:0} and cap['free']=={10}
rebuilt=reconstruct(cap,{0:b(20,'new'),1:b(21,'other')})
assert rebuilt==('op','+',('ident',b(20,'new')),('ident',b(10,'free')))
try:
    reconstruct(cap,{1:b(21,'other')})
except ValueError as error:
    assert str(error)=='escaping local reference'
else: raise AssertionError('escaping capture accepted')
# Hole-owned local 2 remains untouched, even when template surrounds it with slot 1.
inner=capture(('block',('declare',b(2,'x')),('ident',b(2,'x')),('ident',b(1,'x'))),[2],{1:0})
assert inner['boundary']=={1:0}
assert reconstruct(inner,{0:b(20,'outer')})==('block',('declare',b(2,'x')),('ident',b(2,'x')),('ident',b(20,'outer')))
# Two unique declarations must occupy two unique slots: collapsed candidate rejects.
assert norm(('refs',b(1,'x'),b(2,'y')),[1,2]) != norm(('refs',b(4,'a'),b(4,'a')),[4])
print('PASS: boundary extraction, scoped remap, free preservation, escape rejection, hole-local preservation, bijection rejection')
# Structural first-match plus postcheck loses valid later sequence split.
first=('block',('declare',b(30,'x')),('ident',b(30,'x')))
wrong=('block',('declare',b(31,'y')),('ident',b(10,'free')))
later=('block',('declare',b(32,'z')),('ident',b(32,'z')))
subject=[first,wrong,later]
def occurrence_key(node): return norm(node,[node[1][1][1]])
# Pattern shape ?occ1 *between ?occ2 *tail: second node is the shortest split.
assert occurrence_key(subject[0]) != occurrence_key(subject[1])
solutions=[i for i in range(1,len(subject)) if occurrence_key(subject[0])==occurrence_key(subject[i])]
assert solutions == [2]
print('PASS: contextual rejection must retry interior sequence split; valid second occurrence at index 2')
