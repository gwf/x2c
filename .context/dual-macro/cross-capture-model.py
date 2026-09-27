# Isolated incidence model, with producer-supplied region ownership and maps.
def binding(identity, label): return ('binding', identity, label)
def relocate(node, mapping):
    if not isinstance(node, tuple): return node
    if len(node) == 3 and node[0] == 'binding':
        return mapping.get(node[1], node)
    return tuple(relocate(x, mapping) for x in node)
prefix = ('declare', ('int',), ('bind', binding(7, 'x')))
value = ('op', '+', ('ident', binding(7, 'x')),
         ('ident', binding(10, 'outside')))
# Mapping belongs to the entire output region, not each capture separately.
first = relocate(('seq', prefix, ('return', value)), {7: binding(27, 'fresh')})
assert first[1][2][1] == first[2][1][2][1] == binding(27, 'fresh')
assert first[2][1][3][1] == binding(10, 'outside')
second = relocate(('seq', prefix, ('return', value)), {7: binding(28, 'other')})
assert second[1][2][1] == second[2][1][2][1] == binding(28, 'other')
assert first[1][2][1] != second[1][2][1]
# A mapping with two destinations cannot select the target by the label x.
def select_destination(destinations, explicit=None):
    if explicit is not None: return destinations[explicit]
    if len(destinations) != 1: raise ValueError('ambiguous relocation')
    return destinations[0]
try:
    select_destination([binding(27, 'x'), binding(28, 'x')])
except ValueError as e:
    assert str(e) == 'ambiguous relocation'
else: raise AssertionError('ambiguous target accepted')
assert select_destination([binding(27, 'x'), binding(28, 'x')], 1) == binding(28, 'x')
print('PASS: cross-capture incidence, rigid free preservation, distinct copies, explicit destination and ambiguity rejection')
