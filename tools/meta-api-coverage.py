#!/usr/bin/env python3
"""Report the standard meta-call surface without adding a build gate.

Run after building the current tree. By default, print a Markdown inventory;
--json prints the same evidence as JSON. --probe runs bounded inert examples.
--write refreshes docs/src/guide/meta-api-coverage.md. No mode edits bindings.
"""

from __future__ import annotations

import argparse
import hashlib
from collections import Counter
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from meta_api_disposition import KINDS, disposition

from x2c_source import definitions_for_path, function_spans, mask_non_code, split_signature
from x2c_symbols import (content_hash, load, _strip_param_name,
                         _unqualified, normalize_type)


ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "docs/src/guide/meta-api-coverage.md"
TYPES = ("String", "List", "Array", "Map", "Symbol", "Var")
STATES = ("verified example", "reproduced failure", "bound, unverified",
          "no binding found")

# These are adapter considerations, not explanations of historical intent.
CONSIDERATIONS = {
    "binding": "A binding/adapter candidate over represented values; inspect "
               "its contract before assuming a direct alias is sufficient.",
    "callback": "An interpreted callback needs a compatible call adapter, "
                "including order, empty input, and missing-value behavior.",
    "pointer": "Native pointer, output-parameter, or varargs arguments need "
               "a binding whose parameters take the C objects compile-time "
               "code keeps in native bytes.",
    "ownership": "Allocation ownership or lifetime transfer needs deliberate "
                 "compile-time semantics; evaluator objects cannot simply "
                 "be freed by their callers.",
    "resource": "Another resource or value type needs a supported "
                "representation and lifetime before this signature is useful.",
    "syntax": "Related language syntax has lowering, but this does not "
              "establish availability of the explicitly named method.",
    "internal": "Low-level representation or runtime-internal behavior "
                "needs investigation; feasibility is not established.",
}
OWNERSHIP = {
    "String": {"free", "intern_free", "malloc", "new_in", "promote",
               "try_own", "is_permanent"},
    "List": {"cons_in", "promote", "try_own"},
    "Array": {"cleanup", "free", "list_free"},
    "Map": {"cleanup", "export_to"},
    "Var": {"move_wide_to", "wide_owner", "register_object_tag"},
}
SYNTAX = {
    "String": {"truth"}, "List": {"truth"},
    "Array": {"truth", "updateindex", "postfixindex"},
    "Map": {"truth", "updateindex", "postfixindex"},
    "Var": {"truth", "binary", "add", "sub", "mul", "div", "mod",
            "neg", "matmul", "update", "postfix", "updateindex",
            "postfixindex"},
}
RESOURCES = re.compile(
    r"\b(?:Buffer|File|Split|Iter|Job|Pool|Scope|Context|Block|Bytes|AdNode|"
    r"JsonBool|Regex\w*|Token|Array(?:Char|Dbl|Float|Int|Long|Short|String)|"
    r"List(?:Char|Dbl|Float|Int|Short|String|Symbol)|"
    r"Map(?:IntInt|LongDouble|StringInt|StringString))\b"
)

# Each body returns a small integer checked through explicit evaluation.
# No file, process, arbitrary pointer, or ownership-transfer calls belong here.
SELECTOR_CHAINS = (
    "caaaar", "caaadr", "caaar", "caadar", "caaddr", "caadr",
    "cadaar", "cadadr", "cadar", "caddar", "cadddr", "cdaaar",
    "cdaadr", "cdaar", "cdadar", "cdaddr", "cdadr", "cdar",
    "cddaar", "cddadr", "cddar", "cdddar",
)


def _selector_probe(owner: str, method: str) -> tuple:
    value = "7" if method[1] == "a" else "(7 8)"
    for operation in method[1:-1]:
        value = f"({value})" if operation == "a" else "(0 " + value[1:]
    if method[1] == "a":
        result = f"xs.{method}() == 7 && empty.{method}() is void"
    else:
        result = (f"xs.{method}().equal(%(7 8)) && "
                  f"empty.{method}().len() == 0")
    body = f"{owner} xs = %{value}, empty = %(); return {result};"
    return ("present and exhausted selector chain", body, 1,
            ("list-selectors.x",))


PROBES = {
    'String.try_long': ('success and unchanged output on parse failure',
        'long value = 9; int parsed = "42".try_long(&value); '
        'int failed = "bad".try_long(&value); '
        'return parsed && value == 42 && !failed;', 1),
    'String.try_double': ('success and unchanged output on parse failure',
        'double value = 9.0; int parsed = "1.25".try_double(&value); '
        'int failed = "bad".try_double(&value); '
        'return parsed && value == 1.25 && !failed;', 1),
    'String.try_next': ('cursor advance and unchanged exhausted outputs',
        "int cursor = 0, value = 9; int advanced = \"A\".try_next(&cursor, &value); "
        'int exhausted = "A".try_next(&cursor, &value); '
        "return advanced && cursor == 1 && value == 'A' && !exhausted;", 1),
    'List.try_match': ('binding result and unchanged output on miss',
        'List bindings = %(old); int matched = %(tag value).try_match('
        '%(tag ?item), &bindings); int captured = '
        'bindings.assoc(<?item>) == <value>; List prior = bindings; '
        'int missed = %(tag value).try_match(%(other), &bindings); '
        'return matched && captured && !missed && bindings === prior;', 1),
    'List.try_match_replace': ('scalar result and unchanged output on miss',
        'Var result = <old>; int matched = %(tag value).try_match_replace('
        '%(tag ?item), <?item>, &result); int captured = result == <value>; '
        'result = <old>; int missed = %(tag value).try_match_replace('
        '%(other), <changed>, &result); '
        'return matched && captured && !missed && result == <old>;', 1),
    'List.try_search': ('dual outputs publish atomically on success',
        'Var found = <old>; List bindings = %(old); '
        'int matched = %((item 7)).try_search(%(item ?value), '
        '&found, &bindings); int captured = found == %(item 7).var() && '
        'bindings.assoc(<?value>) == 7; found = <old>; bindings = %(old); '
        'List prior = bindings; int missed = %((item 7)).try_search('
        '%(missing), &found, &bindings); return matched && captured && '
        '!missed && found == <old> && bindings === prior;', 1),
    'Array.heap_pop': ('heap order and true-void exhaustion',
        'Array heap = [3, 1, 2]; heap.heapify(); '
        'return heap.heap_pop() == 1 && heap.heap_pop() == 2 && '
        'heap.heap_pop() == 3 && heap.heap_pop() is void;', 1),
    'Map.get_hashed': ('hashed hit, raw Null value and true-void miss',
        'Map map = {}; Var key = "x"; map[key] = Var.null(); '
        'Var hit = map.get_hashed(key, key.hash()); '
        'Var miss = map.get_hashed("y", ((Var) "y").hash()); '
        'return hit.is_null() && miss is void;', 1),
    'Map.try_get': ('raw Null hit and unchanged output on miss',
        'Map map = {}; map["x"] = Var.null(); Var value = 7; '
        'int found = map.try_get("x", &value); int was_null = value.is_null(); '
        'value = 9; int missed = map.try_get("y", &value); '
        'return found && was_null && !missed && value == 9;', 1),
    'Map.try_del': ('removal and unchanged output on miss',
        'Map map = {"x": 7}; Var value = 9; '
        'int removed = map.try_del("x", &value); int got = value == 7; '
        'value = 9; int missed = map.try_del("x", &value); '
        'return removed && got && !missed && value == 9 && map.len() == 0;', 1),
    'Symbol.try_new': ('exact symbol and unchanged output on lossy spelling',
        'Symbol value = <old>; int exact = Symbol.try_new("valid", &value); '
        'int got = value == <valid>; value = <old>; '
        'int lossy = Symbol.try_new("read_only", &value); '
        'return exact && got && !lossy && value == <old>;', 1),
    'Var.clone_wide': ('fresh wide identity and true-void narrow result',
        'Var source = Var.box_long(7), clone = source.clone_wide(); '
        'Var narrow = 7; return clone.compare(source) == 0 && '
        '!clone.same(source) && narrow.clone_wide() is void;', 1),
    'Var.getindex': ('dynamic indexed hit and true-void absence',
        'Var values = %(7 8); return values.getindex(1) == 8 && '
        'values.getindex(9) is void;', 1),
    'Var.null': ('Null remains distinct from void and typed nil',
        'Var value = Var.null(); return value.is_null() && '
        '!value.is_void() && !value.is_nil();', 1),
    'String.contains_digit': ('positive, negative and empty bytes',
        'String empty = ""; return "a1".contains_digit() && !"abc".contains_digit() && !empty.contains_digit();', 1),
    'String.is_alpha': ('positive, negative and empty bytes',
        'String empty = ""; return "Ab".is_alpha() && !"a1".is_alpha() && !empty.is_alpha();', 1),
    'String.is_alpha_under': ('positive, negative and empty bytes',
        'String empty = ""; return "a_B".is_alpha_under() && !"a1".is_alpha_under() && !empty.is_alpha_under();', 1),
    'String.is_digit': ('positive, negative and empty bytes',
        'String empty = ""; return "123".is_digit() && !"12a".is_digit() && !empty.is_digit();', 1),
    'String.is_alnum': ('positive, negative and empty bytes',
        'String empty = ""; return "a1B".is_alnum() && !"a_".is_alnum() && !empty.is_alnum();', 1),
    'String.is_alnum_under': ('positive, negative and empty bytes',
        'String empty = ""; return "a_1".is_alnum_under() && !"a-".is_alnum_under() && !empty.is_alnum_under();', 1),
    'String.is_identifier': ('positive, negative and empty bytes',
        'String empty = ""; return "_a1".is_identifier() && !"1a".is_identifier() && !empty.is_identifier();', 1),
    'String.is_space': ('positive, negative and empty bytes',
        'String empty = ""; return " \\t".is_space() && !" a".is_space() && !empty.is_space();', 1),
    'String.is_lower': ('positive, negative and empty bytes',
        'String empty = ""; return "abc".is_lower() && !"Ab".is_lower() && !empty.is_lower();', 1),
    'String.is_lower_under': ('positive, negative and empty bytes',
        'String empty = ""; return "a_b".is_lower_under() && !"a_B".is_lower_under() && !empty.is_lower_under();', 1),
    'String.is_upper': ('positive, negative and empty bytes',
        'String empty = ""; return "ABC".is_upper() && !"aB".is_upper() && !empty.is_upper();', 1),
    'String.is_upper_under': ('positive, negative and empty bytes',
        'String empty = ""; return "A_B".is_upper_under() && !"a_B".is_upper_under() && !empty.is_upper_under();', 1),
    'String.compare': ('native text contract and boundaries',
        'return "abc".compare("abd") < 0 && "abc".compare("abc") == 0;', 1),
    'String.format': ('checked runtime formatting and canonical empty output',
        'return "%04d:%s:%%".format(%(7 "ok")).equal("0007:ok:%") && '
        '"".format(%()).len() == 0;', 1),
    'String.hash#constant-receiver': ('native text contract and boundaries',
        'return "abc".hash() == ("a" + "bc").hash();', 1),
    'String.symbol': ('native text contract and boundaries',
        'return "alpha".symbol() == <alpha>;', 1),
    'String.dedent': ('native text contract and boundaries',
        'return "\\n  a\\n    b\\n  ".dedent().equal("a\\n  b\\n");', 1),
    'String.keep': ('native text contract and boundaries',
        'return "abacad".keep("ac").equal("aaca") && "x".keep("").len() == 0;', 1),
    'String.reject': ('native text contract and boundaries',
        'return "abacad".reject("ac").equal("bd") && "x".reject("").equal("x");', 1),
    'String.squeeze': ('native text contract and boundaries',
        'return "aaabbbccc".squeeze("ac").equal("abbbc") && "aa".squeeze("").equal("aa");', 1),
    'String.pad_left': ('native text contract and boundaries',
        'return "x".pad_left(3, \'.\').equal("..x") && "abc".pad_left(1, \'.\').equal("abc");', 1),
    'String.pad_right': ('native text contract and boundaries',
        'return "x".pad_right(3, \'.\').equal("x..");', 1),
    'String.pad_center': ('native text contract and boundaries',
        'return "x".pad_center(4, \'.\').equal(".x..");', 1),
    'String.new_fill': ('native text contract and boundaries',
        'return String.new_fill(\'x\', 3).equal("xxx") && String.new_fill(\'x\', -1).len() == 0;', 1),
    'String.find_within': ('native text contract and boundaries',
        'return "abcabc".find_within("c", -4, -1) == 2 && "abc".find_within("x", 0, -1) == -1;', 1),
    'String.replace_n': ('native text contract and boundaries',
        'return "aaaa".replace_n("a", "b", 2).equal("bbaa") && "aa".replace_n("a", "b", 0).equal("aa");', 1),
    'String.split_n': ('native text contract and boundaries',
        'return "a:b:c".split_n(":", 1).equal(%("a" "b:c")) && "a:b".split_n(":", 0).equal(%("a:b"));', 1),
    'String.lstrip#NULL': ('native text contract and boundaries',
        'return "  a  ".lstrip(NULL).equal("a  ") && "xxax".lstrip("x").equal("ax") && " ".lstrip(NULL).len() == 0;', 1),
    'String.rstrip#NULL': ('native text contract and boundaries',
        'return "  a  ".rstrip(NULL).equal("  a") && "xaxx".rstrip("x").equal("xa") && " ".rstrip(NULL).len() == 0;', 1),
    "String.hash": ("nonzero canonical String hash",
        'return "abc".hash() != 0;', 1),
    "String.lstrip": ("explicit charset and typed null pointer",
        'return " a ".lstrip(" ").equal("a ") && '
        '" a ".lstrip((char *) 0).equal("a ");', 1),
    "String.rstrip": ("explicit charset and typed null pointer",
        'return " a ".rstrip(" ").equal(" a") && '
        '" a ".rstrip((char *) 0).equal(" a");', 1),
    'List.unique#collection': ("collection contract and boundaries",
        'List xs = %(2 1 2 3 1); return xs.unique().equal(%(2 1 3)) && %().unique().len() == 0;', 1),
    'List.sublis#collection': ("collection contract and boundaries",
        'List rules = %((a 7) (b (8 9))); return rules.sublis(%(a (b c))).equal(%(7 ((8 9) c)));', 1),
    'List.flatten#collection': ("collection contract and boundaries",
        'return %(1 (2 (3)) ()).flatten().equal(%(1 2 (3)));', 1),
    'List.flatten_all#collection': ("collection contract and boundaries",
        'return %(1 (2 (3)) ()).flatten_all().equal(%(1 2 3));', 1),
    'List.nth_cdr#collection': ("collection contract and boundaries",
        'List xs = %(1 2 3); return xs.nth_cdr(1).equal(%(2 3)) && xs.nth_cdr(9).len() == 0 && xs.nth_cdr(-1) === xs;', 1),
    'List.tail#collection': ("collection contract and boundaries",
        'List xs = %(1 2 3); return xs.tail(2).equal(%(2 3)) && xs.tail(9) === xs && xs.tail(0).len() == 0;', 1),
    'List.head#collection': ("collection contract and boundaries",
        'List xs = %(1 2 3); return xs.head(2).equal(%(1 2)) && xs.head(9) === xs && xs.head(0).len() == 0;', 1),
    'List.subseq#collection': ("collection contract and boundaries",
        'return %(0 1 2 3 4 5).subseq(-4, -1, 2).equal(%(2 4));', 1),
    'List.getslice#collection': ("collection contract and boundaries",
        'return %(0 1 2 3 4 5).getslice(5, 1, -2).equal(%(5 3));', 1),
    'List.hash#collection': ("collection contract and boundaries",
        'return %(1 2).hash() != 0;', 1),
    'List.compare#collection': ("collection contract and boundaries",
        'return %(1 2).compare(%(1 3)) < 0 && %().compare(%()) == 0;', 1),
    'List.replace#collection': ("collection contract and boundaries",
        'return %(a *m b).replace(%((*m (1 2)))).equal(%(a 1 2 b));', 1),
    'List.match_replace#collection': ("collection contract and boundaries",
        'return %(a 7).match_replace(%(a ?x), %(b ?x)).equal(%(b 7));', 1),
    'Array.copy#collection': ("collection contract and boundaries",
        'Array a = [1, 2]; Array b = a.copy(); b[0] = 9; return a[0] == 1 && b[0] == 9 && !(a === b);', 1),
    'Array.getslice#collection': ("collection contract and boundaries",
        'Array a = [0, 1, 2, 3]; Array b = a.getslice(3, 0, -2); return b.list().equal(%(3 1)) && !(a === b);', 1),
    'Array.concat#size_t-comparison': ("collection contract and boundaries",
        'Array a = [1]; Array b = [2]; Array c = a.concat(b); return c.list().equal(%(1 2)) && a.len() == 1 && b.len() == 1 && !(a === c);', 1),
    'Array.reverse#collection': ("collection contract and boundaries",
        'Array a = [1, 2, 3]; Array b = a.reverse(); return a === b && a.list().equal(%(3 2 1));', 1),
    'Array.compare#collection': ("collection contract and boundaries",
        'Array a = [1, 2]; Array b = [1, 3]; return a.compare(b) < 0;', 1),
    'Array.sort#collection': ("collection contract and boundaries",
        'Array a = [3, 1, 2]; Array b = a.sort(); return a === b && a.list().equal(%(1 2 3));', 1),
    'Array.equal#collection': ("collection contract and boundaries",
        'Array a = [1, 2]; Array b = [1, 2]; return a.equal(b) && !(a === b);', 1),
    'Array.indexof#collection': ("collection contract and boundaries",
        'Array a = [1, 2, 1]; return a.indexof(1) == 0 && a.indexof(9) == -1;', 1),
    'Array.truth#collection': ("collection contract and boundaries",
        'Array a = []; Array b = [1]; return !a.truth() && b.truth();', 1),
    'Map.copy#collection': ("collection contract and boundaries",
        'Map a = {"x": 1}; Map b = a.copy(); b["x"] = 2; return a["x"] == 1 && b["x"] == 2 && !(a === b);', 1),
    'Map.merge#collection': ("collection contract and boundaries",
        'Map a = {"x": 1}; Map b = {"x": 2, "y": 3}; Map c = a.merge(b); return a === c && a["x"] == 2 && a["y"] == 3 && b.len() == 2;', 1),
    'Map.compare#collection': ("collection contract and boundaries",
        'Map a = {"x": 1}; Map b = {"x": 1}; return a.compare(b) == 0;', 1),
    'Map.equal#collection': ("collection contract and boundaries",
        'Map a = {"x": 1}; Map b = {"x": 1}; return a.equal(b) && !(a === b);', 1),
    'Map.truth#collection': ("collection contract and boundaries",
        'Map a = {}; Map b = {"x": 1}; return !a.truth() && b.truth();', 1),
    "Array.concat": ("fresh concatenation with native size conversion",
        'Array a = [1]; Array b = [2]; Array c = a.concat(b); '
        'return c.list().equal(%(1 2)) && (int) a.len() == 1 && '
        '(int) b.len() == 1 && !(a === c);', 1),
    'String.intern#core': ("core value contract and boundaries",
        'String s = "abc"; return s.intern() === s;', 1),
    'String.parse#core': ("core value contract and boundaries",
        'return "\\"a\\\\nb\\"".parse().equal("a\\nb") && "".parse().len() == 0;', 1),
    'String.parse_char#core': ("core value contract and boundaries",
        'return "\'a\'tail".parse_char() == \'a\' && "\'\\\\n\'".parse_char() == \'\\n\' && "bad".parse_char() == -1;', 1),
    'String.withindex#core': ("core value contract and boundaries",
        'return "abc".withindex(-1, \'x\').equal("abx") && "abc".withindex(5, \'x\').equal("abc");', 1),
    'String.truth#core': ("core value contract and boundaries",
        'String empty = ""; return "x".truth() && !empty.truth();', 1),
    'Symbol.first#core': ("core value contract and boundaries",
        "Symbol empty = 0; return <abc>.first() == 'a' && empty.first() == 0;", 1),
    'Symbol.last#core': ("core value contract and boundaries",
        "Symbol empty = 0; return <abc>.last() == 'c' && empty.last() == 0;", 1),
    'Array.capacity#core': ("core value contract and boundaries",
        'Array a = [1, 2]; return a.capacity() >= a.len();', 1),
    'Array.remslice#core': ("core value contract and boundaries",
        'Array a = [0, 1, 2, 3]; Array removed = a.remslice(1, 3); return !(removed === a) && removed.list().equal(%(1 2)) && a.list().equal(%(0 3));', 1),
    'Array.setslice#core': ("core value contract and boundaries",
        'Array a = [0, 1, 2]; Array b = [8, 9]; return a.setslice(1, 2, b) === a && a.list().equal(%(0 8 9 2));', 1),
    'Array.splice#core': ("core value contract and boundaries",
        'Array a = [0, 1, 2]; Array b = [8]; Array removed = a.splice(1, 1, b); return removed.list().equal(%(1)) && !(removed === a) && a.list().equal(%(0 8 2));', 1),
    'Array.updateindex#core': ("core value contract and boundaries",
        'Array a = [1, 2]; return a.updateindex(-1, <+>, 3) == 5 && a[1] == 5;', 1),
    'Array.postfixindex#core': ("core value contract and boundaries",
        'Array a = [1, 2]; return a.postfixindex(-1, <++>) == 2 && a[1] == 3;', 1),
    'Array.clear#core': ("core value contract and boundaries",
        'Array a = [1, 2]; a.clear(); a.push(3); return a.list().equal(%(3));', 1),
    'Array.heap_push#core': ("core value contract and boundaries",
        'Array a = []; a.heap_push(3); a.heap_push(1); a.heap_push(2); return a[0] == 1 && a.len() == 3;', 1),
    'Array.heapify#core': ("core value contract and boundaries",
        'Array a = [3, 1, 2]; a.heapify(); return a[0] == 1 && a.len() == 3;', 1),
    'Array.pop#core': ("core value contract and boundaries",
        'Array a = [1, 2]; a.pop(); return a.list().equal(%(1));', 1),
    'Array.resize#core': ("core value contract and boundaries",
        'Array a = [1]; a.resize(3); Var v = a[2]; a.resize(1); return v.is_null() && a.list().equal(%(1));', 1),
    'Array.truncate#core': ("core value contract and boundaries",
        'Array a = [1, 2, 3]; a.truncate(1); return a.list().equal(%(1));', 1),
    'Map.new_capacity#core': ("core value contract and boundaries",
        'Map m = Map.new_capacity(8); m.set("x", 7); return m.len() == 1 && m["x"] == 7;', 1),
    'Map.updateindex#core': ("core value contract and boundaries",
        'Map m = {"x": 2}; return m.updateindex("x", <+>, 3) == 5 && m["x"] == 5;', 1),
    'Map.postfixindex#core': ("core value contract and boundaries",
        'Map m = {"x": 2}; return m.postfixindex("x", <++>) == 2 && m["x"] == 3;', 1),
    'Map.set#core': ("core value contract and boundaries",
        'Map m = {}; m.set("x", 2); m.set("x", 3); return m.len() == 1 && m["x"] == 3;', 1),
    'Var.array#core': ("core value contract and boundaries",
        'Array a = [1]; Var v = a; return v.array() === a;', 1),
    'Var.map#core': ("core value contract and boundaries",
        'Map m = {"x": 1}; Var v = m; return v.map() === m;', 1),
    'Var.string#core': ("core value contract and boundaries",
        'Var v = "abc"; return v.string().equal("abc");', 1),
    'Var.symbol#core': ("core value contract and boundaries",
        'Var v = <abc>; return v.symbol() == <abc>;', 1),
    'Var.compare#core': ("core value contract and boundaries",
        'Var a = 1, b = 2; return a.compare(b) < 0 && b.compare(a) > 0 && a.compare(a) == 0;', 1),
    'Var.contains#core': ("core value contract and boundaries",
        'Var a = %(1 2); return a.contains(2) && !a.contains(3);', 1),
    'Var.hash#core': ("core value contract and boundaries",
        'Var a = "abc"; return a.hash() != 0;', 1),
    'Var.same#core': ("core value contract and boundaries",
        'Array a = [1], b = [1]; Var x = a, y = b; return x.same(x) && !x.same(y);', 1),
    'Var.is_atom#core': ("core value contract and boundaries",
        'Var a = %(abc).car(), b = 1; return a.is_atom() && !b.is_atom();', 1),
    'Var.is_atom_binder#core': ("core value contract and boundaries",
        'Var a = %(?x).car(), b = %(abc).car(); return a.is_atom_binder() && !b.is_atom_binder();', 1),
    'Var.is_binder#core': ("core value contract and boundaries",
        'Var a = %(?x).car(), b = %(*xs).car(), c = 1; return a.is_binder() && b.is_binder() && !c.is_binder();', 1),
    'Var.is_list_binder#core': ("core value contract and boundaries",
        'Var a = %(*xs).car(), b = %(?x).car(); return a.is_list_binder() && !b.is_list_binder();', 1),
    'Var.is_match_op#core': ("core value contract and boundaries",
        'Var a = <!is>, b = 1; return a.is_match_op() && !b.is_match_op();', 1),
    'Var.is_floating#core': ("core value contract and boundaries",
        'Var a = 1.5, b = 1; return a.is_floating() && !b.is_floating();', 1),
    'Var.is_integer#core': ("core value contract and boundaries",
        'Var a = 1, b = 1.5; return a.is_integer() && !b.is_integer();', 1),
    'Var.is_pointer#core': ("core value contract and boundaries",
        'int n = 7; Var a = &n, b = 1; return a.is_pointer() && !b.is_pointer();', 1),
    'Var.is_reference#core': ("core value contract and boundaries",
        'String s = "x"; Var a = &s, b = 1; return a.is_reference() && !b.is_reference();', 1),
    'Var.is_object#core': ("core value contract and boundaries",
        'Var a = "x", b = 1; return a.is_object() && !b.is_object();', 1),
    'Var.is_wide#core': ("core value contract and boundaries",
        'Var a = 1L, b = 1; return a.is_wide() && !b.is_wide();', 1),
    'Var.is_nil#core': ("core value contract and boundaries",
        'Var a = %(), b = %(1); return a.is_nil() && !b.is_nil();', 1),
    'Var.is_null#core': ("core value contract and boundaries",
        'Array a = []; a.resize(1); Var v = a[0], b = %(); return v.is_null() && !b.is_null();', 1),
    'Var.add#core': ("core value contract and boundaries",
        'Var a = 7; return a.add(2) == 9;', 1),
    'Var.sub#core': ("core value contract and boundaries",
        'Var a = 7; return a.sub(2) == 5;', 1),
    'Var.mul#core': ("core value contract and boundaries",
        'Var a = 7; return a.mul(2) == 14;', 1),
    'Var.div#core': ("core value contract and boundaries",
        'Var a = 7; return a.div(2) == 3;', 1),
    'Var.mod#core': ("core value contract and boundaries",
        'Var a = 7; return a.mod(2) == 1;', 1),
    'Var.neg#core': ("core value contract and boundaries",
        'Var a = 7; return a.neg() == -7;', 1),
    'Var.truth#core': ("core value contract and boundaries",
        'Var a = 0, b = 1, c = %(); return !a.truth() && b.truth() && !c.truth();', 1),
    'Var.setindex#core': ("core value contract and boundaries",
        'Array a = [1]; Var v = a; v.setindex(0, 3); return a[0] == 3;', 1),
    'Var.updateindex#core': ("core value contract and boundaries",
        'Array a = [1]; Var v = a; return v.updateindex(0, <+>, 3) == 4 && a[0] == 4;', 1),
    'Var.postfixindex#core': ("core value contract and boundaries",
        'Array a = [1]; Var v = a; return v.postfixindex(0, <++>) == 1 && a[0] == 2;', 1),
    'List.truth#core': ("core value contract and boundaries",
        'return !%().truth() && %(1).truth();', 1),
    'Var.char#core': ("core value contract and boundaries",
        'Var v = 65; return (int) v.char() == 65;', 1),
    'Var.short#core': ("core value contract and boundaries",
        'Var v = 65537; return (int) v.short() == 1;', 1),
    'Var.int#core': ("core value contract and boundaries",
        'Var v = 65; return (int) v.int() == 65;', 1),
    'Var.long#core': ("core value contract and boundaries",
        'Var v = 65; return (int) v.long() == 65;', 1),
    'Var.long_long#core': ("core value contract and boundaries",
        'Var v = 65; return (int) v.long_long() == 65;', 1),
    'Var.unsigned#core': ("core value contract and boundaries",
        'Var v = 65; return (int) v.unsigned() == 65;', 1),
    'Var.ushort#core': ("core value contract and boundaries",
        'Var v = 65537; return (int) v.ushort() == 1;', 1),
    'Var.uchar#core': ("core value contract and boundaries",
        'Var v = 257; return (int) v.uchar() == 1;', 1),
    'Var.uint#core': ("core value contract and boundaries",
        'Var v = 65; return (int) v.uint() == 65;', 1),
    'Var.ulong#core': ("core value contract and boundaries",
        'Var v = 65; return (int) v.ulong() == 65;', 1),
    'Var.ulong_long#core': ("core value contract and boundaries",
        'Var v = 65; return (int) v.ulong_long() == 65;', 1),
    'Var.float#core': ("core value contract and boundaries",
        'Var v = 1.5; return v.float() == 1.5;', 1),
    'Var.double#core': ("core value contract and boundaries",
        'Var v = 1.5; return v.double() == 1.5;', 1),
    'Var.long_double#core': ("core value contract and boundaries",
        'Var v = 1.5; return v.long_double() == 1.5;', 1),
    'Var.long_value#core': ("core value contract and boundaries",
        'Var a = (long) 7, b = "x"; return (int) a.long_value() == 7 && (int) b.long_value() == 0;', 1),
    'Var.ulong_value#core': ("core value contract and boundaries",
        'Var a = (unsigned long) 7, b = "x"; return (int) a.ulong_value() == 7 && (int) b.ulong_value() == 0;', 1),
    'Var.long_long_value#core': ("core value contract and boundaries",
        'Var a = (long long) 7, b = "x"; return (int) a.long_long_value() == 7 && (int) b.long_long_value() == 0;', 1),
    'Var.ulong_long_value#core': ("core value contract and boundaries",
        'Var a = (unsigned long long) 7, b = "x"; return (int) a.ulong_long_value() == 7 && (int) b.ulong_long_value() == 0;', 1),
    'Var.long_double_value#core': ("core value contract and boundaries",
        'Var a = (long double) 7, b = "x"; return (int) a.long_double_value() == 7 && (int) b.long_double_value() == 0;', 1),
    'Symbol.first#represented': ("represented Symbol, including empty payload",
        "Symbol empty = \"\".symbol(); return <abc>.first() == 'a' && empty.first() == 0;", 1),
    'Symbol.last#represented': ("represented Symbol, including empty payload",
        "Symbol empty = \"\".symbol(); return <abc>.last() == 'c' && empty.last() == 0;", 1),
    'List.listchar#optional': ("native canonical value contract",
        'List xs = %(${(char) 65}); ListChar view = xs.listchar(), empty = %().listchar(); return view === xs && empty.len() == 0;', 1, ('typed-list.x',)),
    'List.listshort#optional': ("native canonical value contract",
        'List xs = %(${(short) 65}); ListShort view = xs.listshort(), empty = %().listshort(); return view === xs && empty.len() == 0;', 1, ('typed-list.x',)),
    'List.listint#optional': ("native canonical value contract",
        'List xs = %(${65}); ListInt view = xs.listint(), empty = %().listint(); return view === xs && empty.len() == 0;', 1, ('typed-list.x',)),
    'List.listfloat#optional': ("native canonical value contract",
        'List xs = %(${(float) 1.5}); ListFloat view = xs.listfloat(), empty = %().listfloat(); return view === xs && empty.len() == 0;', 1, ('typed-list.x',)),
    'List.listdbl#optional': ("native canonical value contract",
        'List xs = %(${1.5}); ListDbl view = xs.listdbl(), empty = %().listdbl(); return view === xs && empty.len() == 0;', 1, ('typed-list.x',)),
    'List.liststring#optional': ("native canonical value contract",
        'List xs = %(${"abc"}); ListString view = xs.liststring(), empty = %().liststring(); return view === xs && empty.len() == 0;', 1, ('typed-list.x',)),
    'List.listsymbol#optional': ("native canonical value contract",
        'List xs = %(${<abc>}); ListSymbol view = xs.listsymbol(), empty = %().listsymbol(); return view === xs && empty.len() == 0;', 1, ('typed-list.x',)),
    'List.cdddr#optional': ("native canonical value contract",
        'List xs = %(1 2 3 4 5), short_list = %(1); return xs.cdddr().equal(%(4 5)) && short_list.cdddr().len() == 0;', 1, ('list-selectors.x',)),
    'List.cddddr#optional': ("native canonical value contract",
        'List xs = %(1 2 3 4 5), short_list = %(1); return xs.cddddr().equal(%(5)) && short_list.cddddr().len() == 0;', 1, ('list-selectors.x',)),
    'Var.listchar#optional': ("native canonical value contract",
        'List xs = %(${(char) 65}); Var value = xs, other = 7; ListChar view = value.listchar(), empty = other.listchar(); return view === xs && empty.len() == 0;', 1, ('typed-list.x',)),
    'Var.listshort#optional': ("native canonical value contract",
        'List xs = %(${(short) 65}); Var value = xs, other = 7; ListShort view = value.listshort(), empty = other.listshort(); return view === xs && empty.len() == 0;', 1, ('typed-list.x',)),
    'Var.listint#optional': ("native canonical value contract",
        'List xs = %(${65}); Var value = xs, other = 7; ListInt view = value.listint(), empty = other.listint(); return view === xs && empty.len() == 0;', 1, ('typed-list.x',)),
    'Var.listfloat#optional': ("native canonical value contract",
        'List xs = %(${(float) 1.5}); Var value = xs, other = 7; ListFloat view = value.listfloat(), empty = other.listfloat(); return view === xs && empty.len() == 0;', 1, ('typed-list.x',)),
    'Var.listdbl#optional': ("native canonical value contract",
        'List xs = %(${1.5}); Var value = xs, other = 7; ListDbl view = value.listdbl(), empty = other.listdbl(); return view === xs && empty.len() == 0;', 1, ('typed-list.x',)),
    'Var.liststring#optional': ("native canonical value contract",
        'List xs = %(${"abc"}); Var value = xs, other = 7; ListString view = value.liststring(), empty = other.liststring(); return view === xs && empty.len() == 0;', 1, ('typed-list.x',)),
    'Var.listsymbol#optional': ("native canonical value contract",
        'List xs = %(${<abc>}); Var value = xs, other = 7; ListSymbol view = value.listsymbol(), empty = other.listsymbol(); return view === xs && empty.len() == 0;', 1, ('typed-list.x',)),
    'Var.cdddr#optional': ("native canonical value contract",
        'Var xs = %(1 2 3 4 5), short_list = %(1); return xs.cdddr().equal(%(4 5)) && short_list.cdddr().len() == 0;', 1, ('list-selectors.x',)),
    'Var.cddddr#optional': ("native canonical value contract",
        'Var xs = %(1 2 3 4 5), short_list = %(1); return xs.cddddr().equal(%(5)) && short_list.cddddr().len() == 0;', 1, ('list-selectors.x',)),
    'String.sha256#optional': ("native canonical value contract",
        'return "abc".sha256().equal("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") && "".sha256().equal("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");', 1, ('digest.x',)),
    'Var.json#optional': ("native canonical value contract",
        'Var v = {"b": 2, "a": 1}; return v.json().equal("{\\"a\\":1,\\"b\\":2}");', 1, ('json.x',)),
    'Var.pretty_json#optional': ("native canonical value contract",
        'Var v = [1, 2]; return v.pretty_json().contains("\\n") && v.pretty_json().contains("1");', 1, ('json.x',)),
    'String.new_len#optional': ("native canonical value contract",
        'return String.new_len("abcd", 2).equal("ab") && String.new_len("abcd", 0).len() == 0;', 1, ()),
    'String.c_len#optional': ("native canonical value contract",
        'return "abcd".c_len() == 4;', 1, ()),
    'String.c_compare#optional': ("native canonical value contract",
        'return "ab".c_compare("ac") < 0 && "ab".c_compare("ab") == 0;', 1, ()),
    'Symbol.new#optional': ("native canonical value contract",
        'return Symbol.new("abc") == <abc>;', 1, ()),
    'Symbol.new_len#optional': ("native canonical value contract",
        'return Symbol.new_len("abcdef", 3) == <abc> && Symbol.new_len("abc", 0) == "".symbol();', 1, ()),
    'Symbol.parse#optional': ("native canonical value contract",
        'return Symbol.parse("<abc>") == <abc> && Symbol.parse("abc") == <abc>;', 1, ()),
    'Var.box_i8#numeric': ("valid numeric encoding and boundary values",
        'Var v = Var.box_i8(-7); return v.tag() == <i8> && v.integer() == -7;', 1),
    'Var.box_u8#numeric': ("valid numeric encoding and boundary values",
        'Var v = Var.box_u8(255); return v.tag() == <u8> && v.integer() == 255;', 1),
    'Var.box_i16#numeric': ("valid numeric encoding and boundary values",
        'Var v = Var.box_i16(-300); return v.tag() == <i16> && v.integer() == -300;', 1),
    'Var.box_u16#numeric': ("valid numeric encoding and boundary values",
        'Var v = Var.box_u16(65535); return v.tag() == <u16> && v.integer() == 65535;', 1),
    'Var.box_i32_bits#numeric': ("valid numeric encoding and boundary values",
        'Var v = Var.box_i32_bits(0xfffffff9u); return v.tag() == <i32> && v.integer() == -7;', 1),
    'Var.box_u32#numeric': ("valid numeric encoding and boundary values",
        'Var v = Var.box_u32(4000000000u); return v.tag() == <u32> && v.unsigned() == 4000000000u;', 1),
    'Var.box_f32#numeric': ("valid numeric encoding and boundary values",
        'Var v = Var.box_f32(1.25); return v.tag() == <f32> && v.decode_f32() == 1.25;', 1),
    'Var.box_f64#numeric': ("valid numeric encoding and boundary values",
        'Var v = Var.box_f64(1.25); return v.tag() == <f64> && v.decode_f64() == 1.25;', 1),
    'Var.box_long#numeric': ("valid numeric encoding and boundary values",
        'Var v = Var.box_long(-7); return v.tag() == <long> && v.long_value() == -7;', 1),
    'Var.box_ulong#numeric': ("valid numeric encoding and boundary values",
        'Var v = Var.box_ulong(7); return v.tag() == <ulong> && v.ulong_value() == 7;', 1),
    'Var.box_long_long#numeric': ("valid numeric encoding and boundary values",
        'Var v = Var.box_long_long(-7); return v.tag() == <llong> && v.long_long_value() == -7;', 1),
    'Var.box_ulong_long#numeric': ("valid numeric encoding and boundary values",
        'Var v = Var.box_ulong_long(7); return v.tag() == <ullong> && v.ulong_long_value() == 7;', 1),
    'Var.box_long_double#numeric': ("valid numeric encoding and boundary values",
        'Var v = Var.box_long_double(1.25); return v.tag() == <ldouble> && v.long_double_value() == 1.25;', 1),
    'Var.custom_descriptor_index#numeric': ("valid numeric encoding and boundary values",
        'Var a = 7, b = "x"; return a.custom_descriptor_index() == -1 && b.custom_descriptor_index() == -1;', 1),
    'Var.decode_f32#numeric': ("valid numeric encoding and boundary values",
        'Var a = (float) 1.25; return a.decode_f32() == 1.25;', 1),
    'Var.decode_f64#numeric': ("valid numeric encoding and boundary values",
        'Var a = 1.25; return a.decode_f64() == 1.25;', 1),
    'Var.encoding_valid#numeric': ("valid numeric encoding and boundary values",
        'Var a = 7, b = "x", c = 1.25; return a.encoding_valid() && b.encoding_valid() && c.encoding_valid();', 1),
    'Var.fallback_compare#numeric': ("valid numeric encoding and boundary values",
        'Var a = 7, b = 8; return a.fallback_compare(b) < 0 && a.fallback_compare(a) == 0;', 1),
    'Var.fallback_equal#numeric': ("valid numeric encoding and boundary values",
        'Var a = 7, b = 8; return a.fallback_equal(a) && !a.fallback_equal(b);', 1),
    'Var.fallback_hash#numeric': ("valid numeric encoding and boundary values",
        'Var a = 7, b = 7; return a.fallback_hash() == b.fallback_hash();', 1),
    'Var.fallback_repr#numeric': ("valid numeric encoding and boundary values",
        'Var a = 7; return a.fallback_repr().equal("7");', 1),
    'Var.fallback_str#numeric': ("valid numeric encoding and boundary values",
        'Var a = 7; return a.fallback_str().equal("7");', 1),
    'Var.fallback_truth#numeric': ("valid numeric encoding and boundary values",
        'Var a = 0, b = 7; return !a.fallback_truth() && b.fallback_truth();', 1),
    'Var.integer_box#numeric': ("valid numeric encoding and boundary values",
        'Var a = Var.integer_box(<i8>, 255); return a.tag() == <i8> && a.integer() == -1;', 1),
    'Var.integer_compare#numeric': ("valid numeric encoding and boundary values",
        'Var a = -1, b = 1u; return a.integer_compare(b) < 0 && b.integer_compare(a) > 0;', 1),
    'Var.integer_floating_compare#numeric': ("valid numeric encoding and boundary values",
        'Var a = 7, b = 7.5; return a.integer_floating_compare(b) < 0;', 1),
    'Var.integer_tag#numeric': ("valid numeric encoding and boundary values",
        'return Var.integer_tag(1, 0) == <i32> && Var.integer_tag(5, 1) == <ulong>;', 1),
    'Var.is_row#numeric': ("valid numeric encoding and boundary values",
        'Var a = 7, b = (float) 7; return a.is_row(0x8002u, 0xffff00000000ul, 0x600000000ul) && !b.is_row(0x8002u, 0xffff00000000ul, 0x600000000ul);', 1),
    'Var.known_tag#numeric': ("valid numeric encoding and boundary values",
        'return Var.known_tag(<i32>) && !Var.known_tag(<bogus>);', 1),
    'Var.payload32#numeric': ("valid numeric encoding and boundary values",
        'Var a = -7; return a.payload32() == 0xfffffff9u;', 1),
    'Var.signed_from_bits#numeric': ("valid numeric encoding and boundary values",
        'return Var.signed_from_bits(255, 8) == -1 && Var.signed_from_bits(127, 8) == 127;', 1),
    'Var.wide_compare#numeric': ("valid numeric encoding and boundary values",
        'Var a = 7L, b = 8L, c = 1; return a.wide_compare(b) < 0 && a.wide_compare(c) == 0;', 1),
    'Var.wide_equal#numeric': ("valid numeric encoding and boundary values",
        'Var a = 7L, b = 7L, c = 7; return a.wide_equal(b) && !a.wide_equal(c);', 1),
    'Var.wide_hash#numeric': ("valid numeric encoding and boundary values",
        'Var a = 7L, b = 7L, c = 7; return a.wide_hash() == b.wide_hash() && c.wide_hash() == 0;', 1),
    'Var.width_mask#numeric': ("valid numeric encoding and boundary values",
        'return Var.width_mask(0) == 0 && Var.width_mask(8) == 255 && Var.width_mask(16) == 65535;', 1),
    'String.add#existing': ("existing binding with native control",
        'return "ab".add("cd").equal("abcd");', 1),
    'String.capitalize#existing': ("existing binding with native control",
        'return "hELLO".capitalize().equal("Hello");', 1),
    'String.contains#existing': ("existing binding with native control",
        'return "abc".contains("bc") && !"abc".contains("z");', 1),
    'String.count#existing': ("existing binding with native control",
        'return "aaaa".count("aa") == 2;', 1),
    'String.endswith#existing': ("existing binding with native control",
        'return "abc".endswith("bc") && !"abc".endswith("ab");', 1),
    'String.equal#existing': ("existing binding with native control",
        'return "abc".equal("abc") && !"abc".equal("abd");', 1),
    'String.escape#existing': ("existing binding with native control",
        'return "a\\nb".escape().equal("a\\\\nb");', 1),
    'String.find#existing': ("existing binding with native control",
        'return "abcabc".find("bc") == 1 && "abc".find("z") == -1;', 1),
    'String.find_all#existing': ("existing binding with native control",
        'return "ababa".find_all("a", 0, -1).equal(%(0 2 4));', 1),
    'String.getindex#existing': ("existing binding with native control",
        'return "abc".getindex(-1) == \'c\' && "abc".getindex(9) == -1;', 1),
    'String.getslice#existing': ("existing binding with native control",
        'return "abcde".getslice(4, 0, -2).equal("ec");', 1),
    'String.join#existing': ("existing binding with native control",
        'return ":".join(%("a" "b")).equal("a:b") && ":".join(%()).len() == 0;', 1),
    'String.lower#existing': ("existing binding with native control",
        'return "AbC".lower().equal("abc");', 1),
    'String.new#existing': ("existing binding with native control",
        'return String.new("abc").equal("abc");', 1),
    'String.partition#existing': ("existing binding with native control",
        'return "a:b:c".partition(":").equal(%("a" ":" "b:c"));', 1),
    'String.remove_prefix#existing': ("existing binding with native control",
        'return "abc".remove_prefix("ab").equal("c") && "abc".remove_prefix("x").equal("abc");', 1),
    'String.remove_suffix#existing': ("existing binding with native control",
        'return "abc".remove_suffix("bc").equal("a") && "abc".remove_suffix("x").equal("abc");', 1),
    'String.repeat#existing': ("existing binding with native control",
        'return "ab".repeat(2).equal("abab") && "ab".repeat(0).len() == 0;', 1),
    'String.replace#existing': ("existing binding with native control",
        'return "ababa".replace("a", "x").equal("xbxbx");', 1),
    'String.repr#existing': ("existing binding with native control",
        'return "abc".repr().equal("\\"abc\\"");', 1),
    'String.rfind#existing': ("existing binding with native control",
        'return "abcabc".rfind("bc") == 4 && "abc".rfind("z") == -1;', 1),
    'String.rpartition#existing': ("existing binding with native control",
        'return "a:b:c".rpartition(":").equal(%("a:b" ":" "c"));', 1),
    'String.split#existing': ("existing binding with native control",
        'return "a:b".split(":").equal(%("a" "b"));', 1),
    'String.split_lines#existing': ("existing binding with native control",
        'return "a\\nb\\n".split_lines(0).equal(%("a" "b"));', 1),
    'String.startswith#existing': ("existing binding with native control",
        'return "abc".startswith("ab") && !"abc".startswith("bc");', 1),
    'String.str#existing': ("existing binding with native control",
        'String s = "abc"; return s.str() === s;', 1),
    'String.unescape#existing': ("existing binding with native control",
        'return "a\\\\nb".unescape().equal("a\\nb");', 1),
    'String.upper#existing': ("existing binding with native control",
        'return "Abc".upper().equal("ABC");', 1),
    'String.var#existing': ("existing binding with native control",
        'String s = "abc"; return s.var().tag() == <string> && s.var().string() === s;', 1),
    'List.append#existing': ("existing binding with native control",
        'List a = %(1), b = %(2 3); List c = a.append(b); return c.equal(%(1 2 3)) && c.cdr() === b;', 1),
    'List.array#existing': ("existing binding with native control",
        'List xs = %(1 2); Array a = xs.array(); a[0] = 7; return xs.car() == 1 && a[0] == 7;', 1),
    'List.assoc#existing': ("existing binding with native control",
        'return %((a 1) (b 2)).assoc(<b>) == 2;', 1),
    'List.contains#existing': ("existing binding with native control",
        'return %(1 2).contains(2) && !%(1 2).contains(3);', 1),
    'List.equal#existing': ("existing binding with native control",
        'return %(1 2).equal(%(1 2)) && !%(1 2).equal(%(2 1));', 1),
    'List.filter#existing': ("existing binding with native control",
        'Func pred = %!(v) => v > 1; return %(1 2 3).filter(pred).equal(%(2 3));', 1),
    'List.get#existing': ("existing binding with native control",
        'return %(1 2).get(-1) == 2 && %((a 7)).get(<a>) == 7;', 1),
    'List.getindex#existing': ("existing binding with native control",
        'return %(1 2).getindex(-1) == 2;', 1),
    'List.index#existing': ("existing binding with native control",
        'return %(1 2 1).index(1) == 0 && %(1 2).index(9) == -1;', 1),
    'List.last#existing': ("existing binding with native control",
        'return %(1 2).last() == 2;', 1),
    'List.len#existing': ("existing binding with native control",
        'return %(1 2).len() == 2 && %().len() == 0;', 1),
    'List.map#existing': ("existing binding with native control",
        'Func twice = %!(v) => v * 2; return %(1 2).map(twice).equal(%(2 4));', 1),
    'List.match#existing': ("existing binding with native control",
        'return %(a 7).match(%(a ?x)).assoc(<?x>) == 7;', 1),
    'List.repr#existing': ("existing binding with native control",
        'return %(1 2).repr().contains("1") && %(1 2).repr().contains("2");', 1),
    'List.reverse#existing': ("existing binding with native control",
        'return %(1 2 3).reverse().equal(%(3 2 1));', 1),
    'List.search#existing': ("existing binding with native control",
        'return %(a (a 7)).search(%(a ?x)).len() == 2;', 1),
    'List.search_replace#existing': ("existing binding with native control",
        'return %(a (b 7)).search_replace(%(b ?x), %(c ?x)).equal(%(a (c 7)));', 1),
    'List.sort#existing': ("existing binding with native control",
        'return %(3 1 2).sort().equal(%(1 2 3));', 1),
    'List.str#existing': ("existing binding with native control",
        'return %(1 2).str().contains("1") && %(1 2).str().contains("2");', 1),
    'List.try_next#existing': ("existing binding with native control",
        'List xs = %(7), cursor = xs; Var value = 0; int first = xs.try_next(&cursor, &value); int last = xs.try_next(&cursor, &value); return first == 1 && last == 0 && value == 7;', 1),
    'List.var#existing': ("existing binding with native control",
        'List xs = %(1 2); return xs.var().tag() == <list> && xs.var().list() === xs;', 1),
    'Array.contains#existing': ("existing binding with native control",
        'Array a = [1, 2]; return a.contains(2) && !a.contains(3);', 1),
    'Array.count#existing': ("existing binding with native control",
        'Array a = [1, 2, 1]; return a.count(1) == 2 && a.count(3) == 0;', 1),
    'Array.find#existing': ("existing binding with native control",
        'Array a = [1, 2, 1]; return a.find(1) == 0 && a.find(3) == -1;', 1),
    'Array.getindex#existing': ("existing binding with native control",
        'Array a = [1, 2]; return a.getindex(-1) == 2;', 1),
    'Array.insert#existing': ("existing binding with native control",
        'Array a = [1, 2]; return a.insert(-1, 3) == 3 && a.list().equal(%(1 2 3));', 1),
    'Array.join#existing': ("existing binding with native control",
        'Array a = ["a", "b"]; return a.join(":").equal("a:b");', 1),
    'Array.len#existing': ("existing binding with native control",
        'Array a = [1, 2]; return a.len() == 2;', 1),
    'Array.list#existing': ("existing binding with native control",
        'Array a = [1, 2]; List xs = a.list(); a[0] = 7; return xs.equal(%(1 2));', 1),
    'Array.new#existing': ("existing binding with native control",
        'Array a = Array.new(), b = Array.new(); return a.len() == 0 && !(a === b);', 1),
    'Array.remove#existing': ("existing binding with native control",
        'Array a = [1, 2]; return a.remove(-1) == 2 && a.list().equal(%(1));', 1),
    'Array.repr#existing': ("existing binding with native control",
        'Array a = [1, 2]; return a.repr().contains("1") && a.repr().contains("2");', 1),
    'Array.setindex#existing': ("existing binding with native control",
        'Array a = [1, 2]; return a.setindex(-1, 7) == 7 && a[1] == 7;', 1),
    'Array.shift#existing': ("existing binding with native control",
        'Array a = [1, 2]; return a.shift() == 1 && a.list().equal(%(2));', 1),
    'Array.str#existing': ("existing binding with native control",
        'Array a = [1, 2]; return a.str().contains("1") && a.str().contains("2");', 1),
    'Array.take_last#existing': ("existing binding with native control",
        'Array a = [1, 2]; return a.take_last() == 2 && a.list().equal(%(1));', 1),
    'Array.try_next#existing': ("existing binding with native control",
        'Array a = [7]; int cursor = 0; Var value = 0; int first = a.try_next(&cursor, &value); int last = a.try_next(&cursor, &value); return first == 1 && last == 0 && value == 7 && cursor == 1;', 1),
    'Array.unshift#existing': ("existing binding with native control",
        'Array a = [1, 2]; return a.unshift(7) == 7 && a.list().equal(%(7 1 2));', 1),
    'Array.var#existing': ("existing binding with native control",
        'Array a = [1]; return a.var().tag() == <array> && a.var().array() === a;', 1),
    'Map.contains#existing': ("existing binding with native control",
        'Map m = {"a": 1}; return m.contains("a") && !m.contains("b");', 1),
    'Map.del#existing': ("existing binding with native control",
        'Map m = {"a": 1}; return m.del("a") == 1 && m.len() == 0;', 1),
    'Map.get#existing': ("existing binding with native control",
        'Map m = {"a": 1}; return m.get("a") == 1;', 1),
    'Map.getdefault#existing': ("existing binding with native control",
        'Map m = {"a": 1}; return m.getdefault("a", 7) == 1 && m.getdefault("b", 7) == 7;', 1),
    'Map.getindex#existing': ("existing binding with native control",
        'Map m = {"a": 1}; return m.getindex("a") == 1;', 1),
    'Map.len#existing': ("existing binding with native control",
        'Map m = {"a": 1}; return m.len() == 1;', 1),
    'Map.list#existing': ("existing binding with native control",
        'Map m = {"a": 1}; return m.list().len() == 1;', 1),
    'Map.new#existing': ("existing binding with native control",
        'Map a = Map.new(), b = Map.new(); return a.len() == 0 && !(a === b);', 1),
    'Map.repr#existing': ("existing binding with native control",
        'Map m = {"a": 1}; return m.repr().contains("a") && m.repr().contains("1");', 1),
    'Map.setdefault#existing': ("existing binding with native control",
        'Map m = {"a": 1}; return m.setdefault("a", 7) == 1 && m.setdefault("b", 7) == 7 && m.len() == 2;', 1),
    'Map.str#existing': ("existing binding with native control",
        'Map m = {"a": 1}; return m.str().contains("a") && m.str().contains("1");', 1),
    'Map.try_next#existing': ("existing binding with native control",
        'Map m = {"a": 7}; unsigned cursor = 0; Var key = 0, value = 0; int first = m.try_next(&cursor, &key, &value); int last = m.try_next(&cursor, &key, &value); return first == 1 && last == 0 && key == "a" && value == 7;', 1),
    'Map.var#existing': ("existing binding with native control",
        'Map m = {"a": 1}; return m.var().tag() == <map> && m.var().map() === m;', 1),
    'Symbol.str#existing': ("existing binding with native control",
        'return <abc>.str().equal("abc");', 1),
    'Symbol.var#existing': ("existing binding with native control",
        'Symbol s = <abc>; return s.var().tag() == <symbol> && s.var().symbol() == s;', 1),
    'Var.caar#existing': ("existing binding with native control",
        'Var v = %((7)); return v.caar() == 7;', 1),
    'Var.caddr#existing': ("existing binding with native control",
        'Var v = %(1 2 3); return v.caddr() == 3;', 1),
    'Var.car#existing': ("existing binding with native control",
        'Var v = %(7); return v.car() == 7;', 1),
    'Var.cddr#existing': ("existing binding with native control",
        'Var v = %(1 2 3); return v.cddr().equal(%(3));', 1),
    'Var.cdr#existing': ("existing binding with native control",
        'Var v = %(1 2 3); return v.cdr().equal(%(2 3));', 1),
    'Var.convert#existing': ("existing binding with native control",
        'Var v = 257; Var narrowed = v.convert(<u8>); return narrowed.tag() == <u8> && narrowed.integer() == 1;', 1),
    'Var.equal#existing': ("existing binding with native control",
        'Var a = 7, b = 8; return a.equal(a) && !a.equal(b);', 1),
    'Var.is#existing': ("existing binding with native control",
        'Var a = 7; return a.is(<i32>) && !a.is(<string>);', 1),
    'Var.list#existing': ("existing binding with native control",
        'Var a = %(1 2), b = 7; return a.list().equal(%(1 2)) && b.list().len() == 0;', 1),
    'Var.parse#existing': ("existing binding with native control",
        'Var a = Var.parse("42", <int>); return a.tag() == <i32> && a.integer() == 42;', 1),
    'Var.repr#existing': ("existing binding with native control",
        'Var a = 7; return a.repr().equal("7");', 1),
    'Var.str#existing': ("existing binding with native control",
        'Var a = 7; return a.str().equal("7");', 1),
    'Var.tag#existing': ("existing binding with native control",
        'Var a = 7, b = "x"; return a.tag() == <i32> && b.tag() == <string>;', 1),
    "String.len": ("nonempty text", 'return "abc".len();', 3),
    "String.strip#null": ("default whitespace through NULL", 'return " a ".strip(NULL).len();', 1),
    "String.strip#charset": ("explicit character set", 'return " a ".strip(" ").len();', 1),
    "String.map": ("interpreted byte callback",
        'return "abc".map(%!(x) => x.integer() + 1).equal("bcd");', 1),
    "String.filter": ("native Var truth for x2c callback",
        'return "abc".filter(%!(x) => x.integer() > 97).len();', 2),
    "String.iter": ("Scope-owned lazy byte iterator",
        'return "abc".iter().count();', 3),
    "List.car": ("first element", 'List xs = %(7 8); return xs.car();', 7),
    "List.cdr": ("tail", 'List xs = %(7 8); return xs.cdr().len();', 1),
    **{f"{owner}.{method}": _selector_probe(owner, method)
       for owner in ("List", "Var") for method in SELECTOR_CHAINS},
    "List.caar": ("nested head", 'List xs = %((7) 8); return xs.caar();', 7),
    "List.cadr": ("second element", 'List xs = %(7 8); return xs.cadr();', 8),
    "List.cadr#absent": ("absent element distinguishes void from nil",
        'List xs = %(7); Var value = xs.cadr(); return value.kind() == <void>;', 1),
    "List.cddr": ("empty second tail", 'List xs = %(7 8); return xs.cddr().len();', 0),
    "List.caddr": ("third element", 'List xs = %(7 8 9); return xs.caddr();', 9),
    "List.cons": ("prepend", 'return List.cons(7, %(8)).len();', 2),
    "List.map": ("interpreted callback",
        'List ys = %(1 2).map(%!(x) => x.integer() + 1); return ys[1];', 3),
    "List.filter": ("native Var truth for x2c callback",
        'return %(0 1 2).filter(%!(x) => x).len();', 2),
    "List.any": ("interpreted predicate",
        'return %(0 0 2).any(%!(x) => x);', 1),
    "List.all": ("interpreted predicate",
        'return %(1 2 3).all(%!(x) => x);', 1),
    "List.map2": ("pairwise interpreted callback",
        'List ys = %(1 2).map2(%(10 20), '
        '%!(a, b) => a.integer() + b.integer()); return ys[1];', 22),
    "List.sort_by": ("interpreted key callback",
        'return %(1 3 2).sort_by(%!(x) => -x.integer()).car();', 3),
    "List.sort_with": ("interpreted comparator",
        'return %(3 1 2).sort_with(%!(a, b) => '
        'a.integer() - b.integer()).car();', 1),
    "List.zip_with": ("interpreted pair callback",
        'List ys = %(1 2).zip_with(%(10 20), '
        '%!(a, b) => a.integer() + b.integer()); return ys[1];', 22),
    "List.iter": ("Scope-owned lazy List iterator",
        'return %(1 2 3).iter().sum();', 6),
    "List.foldl": (
        "ordered fold with true void seed",
        'return %(1 2 3).foldl(void, '
        '%!(a, b) => a.integer() + b.integer());', 6),
    "List.find": ("interpreted predicate with native Var truth",
        'return %(0 2 3).find(%!(x) => x);', 2),
    "Array.push": (
        "append and read", 'Array xs = []; xs.push(7); return xs[0];', 7),
    "Array.map": (
        "interpreted callback", 'Array xs = [1, 2]; '
        'Array ys = xs.map(%!(x) => x + 1); return ys[1];', 3),
    "Array.map2": ("pairwise interpreted callback",
        'Array ys = [1, 2].map2([10, 20], '
        '%!(a, b) => a.integer() + b.integer()); return ys[1];', 22),
    "Array.sort_by": ("interpreted key callback",
        'Array xs = [1, 3, 2]; xs.sort_by(%!(x) => -x.integer()); '
        'return xs[0];', 3),
    "Array.sort_with": ("interpreted comparator",
        'Array xs = [3, 1, 2]; xs.sort_with(%!(a, b) => '
        'a.integer() - b.integer()); return xs[0];', 1),
    "Array.iter": ("Scope-owned lazy Array iterator",
        'return [1, 2, 3].iter().sum();', 6),
    "Array.foldl": ("ordered fold with true void seed",
        'return [1, 2, 3].foldl(void, '
        '%!(a, b) => a.integer() + b.integer());', 6),
    "Array.truth": (
        "explicit empty-array method", 'Array xs = []; return xs.truth();', 0),
    "Map.setindex": (
        "store and read", 'Map m = {}; m.setindex("x", 7); return m["x"];', 7),
    "Map.keys": (
        "one key through Scope-owned iterator", 'Map m = {"x": 7}; '
        'return m.keys().count();', 1),
    "Map.iter": ("Scope-owned lazy value iterator",
        'Map m = {"x": 7}; return m.iter().sum();', 7),
    "Map.enumerate": ("Scope-owned lazy entry iterator",
        'Map m = {"x": 7}; return m.enumerate().count();', 1),
    "Iter.next": ("true void on exhausted iterator",
        'return range(1, 0, 1).next() is void;', 1),
    "Iter.foldl": ("ordered fold with true void seed",
        'return range(1, 3, 1).foldl(void, '
        '%!(a, b) => a.integer() + b.integer());', 6),
    "Iter.find": ("interpreted predicate and true void absence",
        'return range(1, 3, 1).find(%!(x) => x.integer() > 1);', 2),
    "Iter.min": ("true void on empty iterator",
        'return range(1, 0, 1).min() is void;', 1),
    "Iter.max": ("maximum remaining element",
        'return range(1, 3, 1).max();', 3),
    "Symbol.len": ("short symbol", 'return <abc>.len();', 3),
    "Symbol.compare": ("lexical comparison", 'return <abc>.compare(<abd>) < 0;', 1),
    "Symbol.repr": ("symbol rendering", 'return <abc>.repr().equal("<abc>");', 1),
    "Var.integer": ("raw integer payload and wrong-tag zero",
        'Var integer = 7; Var floating = 3.5; '
        'return integer.integer() == 7 && floating.integer() == 0;', 1),
    "Var.floating": ("raw floating payload and wrong-tag zero",
        'Var integer = 7; Var floating = 3.5; '
        'return floating.floating() == 3.5 && integer.floating() == 0.0;', 1),
    "Var.kind": ("integer kind", 'Var value = 7; return value.kind() == <integer>;', 1),
    "Var.is_void": ("true void stays distinct from nil",
        'Var value = void, nil = %(); '
        'return value.is_void() && !nil.is_void();', 1),
    "Var.cadr": ("boxed List selector", 'Var value = %(7 8); return value.cadr();', 8),
    "Var.cons": ("prepend", 'return Var.cons(7, %(8)).len();', 2),
    "Var.iter": ("Scope-owned lazy boxed iterator",
        'Var value = %(1 2 3); return value.iter().sum();', 6),
    "Var.array": (
        "explicit Array conversion", 'Var xs = [7]; return xs.array().len();', 1),
    "Var.binary": ("integer addition", 'return Var.binary(2, <+>, 3);', 5),
}


def library_files() -> list[str]:
    """Use the compiler's loader table, not a second list of Lisp layers."""
    text = (ROOT / "src/macros.x").read_text()
    for span in function_spans(mask_non_code(text), include_static=True):
        if span.name == "_library_files":
            return re.findall(r'"([^"\n]+\.xlisp)"',
                              text[span.body_start:span.end])
    raise ValueError("cannot find the compiler's _library_files loader")


def lisp_definitions(text: str):
    """Read names in top-level def/defun/defmacro forms, skipping bodies."""
    tokens = re.finditer(r'//[^\n]*|"(?:\\.|[^"\\])*"|[()]|[^\s()]+', text)
    depth, head, start = 0, [], 0
    for token in tokens:
        value = token.group()
        if value.startswith("//"):
            continue
        if value == "(":
            if depth == 0:
                head, start = [], token.start()
            depth += 1
        elif value == ")":
            depth -= 1
        elif depth == 1 and len(head) < 2:
            head.append(value)
            if len(head) == 2 and head[0] in ("def", "defun", "defmacro"):
                yield head[1], text.count("\n", 0, start) + 1


def session_bindings(files: list[str]) -> dict[str, list[str]]:
    bindings: dict[str, list[str]] = {}
    for name in files:
        for binding, line in lisp_definitions((ROOT / name).read_text()):
            bindings.setdefault(binding, []).append(f"{name}:{line}")
    # Native installation is separate from the loader's Lisp files.
    text = (ROOT / "src/macros.x").read_text()
    for match in re.finditer(r'\$lisp\.bind\([^,]+,\s*"([^"\n]+)"', text):
        line = text.count("\n", 0, match.start()) + 1
        bindings.setdefault(match[1], []).append(f"src/macros.x:{line}")
    return bindings


def ledger(path: str) -> dict:
    rows = {}
    for line in (ROOT / path).read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        source, kind, tail = line.split("|", 2)
        if path.endswith("tiers.txt"):
            for name in tail.split(","):
                rows[source, name] = kind
        else:
            rows[source] = kind
    return rows


def classify(row: dict) -> list[str]:
    owner, method = row["name"].split(".", 1)
    signature = row["signature"]
    flags = []
    if method in OWNERSHIP.get(owner, ()):
        flags.append("ownership")
    if RESOURCES.search(signature):
        flags.append("resource")
    if "*" in signature or "..." in signature:
        flags.append("pointer")
    if "Func " in signature:
        flags.append("callback")
    if method in SYNTAX.get(owner, ()):
        flags.append("syntax")
    if row["tier"] == "internal" or row["visibility"] == "internal":
        flags.append("internal")
    elif owner == "Var" and any(part in method for part in (
        "box_", "decode", "payload", "encoding", "descriptor", "numeric_",
        "fallback", "wide_", "is_row", "integer_tag", "integer_box",
        "signed_from_bits", "width_mask", "pointer", "try_dispatch",
        "known_tag",
    )):
        flags.append("internal")
    return flags or ["binding"]


def inventory(stage: Path) -> dict:
    symbols = load(stage)
    files = library_files()
    bindings = session_bindings(files)
    tiers = ledger("docs/library-api-tiers.txt")
    visibility = ledger("docs/library-manifest.txt")
    rows, warnings = {}, []
    for path in sorted((ROOT / "lib").glob("*.x")):
        if path.name == "x2c.x":
            continue
        relative = path.relative_to(ROOT).as_posix()
        for item in definitions_for_path(path):
            owner, dot, method = item.name.partition(".")
            if owner not in TYPES or not dot or method.startswith("_"):
                continue
            key = relative, item.name, item.signature
            rows[key] = dict(name=item.name, signature=item.signature,
                             path=relative, line=item.line, runtime_contract=item.doc or "",
                             origin="source or unit macro")
    # Protocol/class methods and foreign aliases can lack a source definition.
    authored = {row["name"].replace(".", "_") for row in rows.values()}
    generated = set()
    for path in symbols.paths():
        if not path.startswith("lib/"):
            continue
        for native, signature in symbols.functions(path).items():
            owner, sep, method = native.partition("_")
            if owner not in TYPES or not sep or method.startswith("_"):
                continue
            key = native, signature.returns, signature.params
            if native in authored or key in generated:
                continue
            generated.add(key)
            name = f"{owner}.{method}"
            declaration = (f"{signature.returns} {name}("
                           f"{', '.join(signature.params) or 'void'})")
            rows[path, name, declaration] = dict(
                name=name, signature=declaration, path=path, line=None,
                runtime_contract="", origin="generated or foreign interface")
    for row in rows.values():
        path, name = row["path"], row["name"]
        native = name.replace(".", "_")
        row["tier"] = tiers.get((path, name), "primary" if row["line"]
                                else "unclassified generated")
        row["visibility"] = visibility.get(path, "unclassified")
        row["binding"] = bindings.get(native, [])
        row["call"] = name + "(...)"
        row["state"] = "bound, unverified" if row["binding"] else "no binding found"
        row["considerations"] = classify(row)
        row["evidence"] = []
        row.update(disposition(row))
        if path not in symbols.paths() or native not in symbols.functions(path):
            warnings.append(f"{name}: no matching callable in {path}'s interface")
        elif row["line"]:
            entry = symbols.functions(path)[native]
            returns, _, params = split_signature(row["signature"])
            owner = name.split(".", 1)[0]
            returns = re.sub(r"\bSelf\b", owner, returns)
            params = tuple(_strip_param_name(re.sub(r"\bSelf\b", owner, p))
                           for p in params)
            params = tuple(p for p in params if p)
            if (_unqualified(returns) != _unqualified(entry.returns) or
                tuple(map(normalize_type, params)) !=
                    tuple(map(normalize_type, entry.params))):
                warnings.append(f"{name}: source/interface signature mismatch")
    paths = sorted({row["path"] for row in rows.values()})
    for path in paths:
        if path in symbols.paths() and content_hash((ROOT / path).read_bytes()) != symbols.file_hash(path):
            warnings.append(f"{path}: source differs from the stage interface")
    paths += ["tools/meta-api-coverage.py", "tools/meta_api_disposition.py", "docs/library-api-tiers.txt",
              "docs/library-manifest.txt"] + files + ["src/macros.x", "src/comptime.x", "src/expressions.x",
                     "src/parse.x", "src/type.x", "lib/lisp.x"]
    digest = hashlib.sha256()
    for path in sorted(set(paths)):
        digest.update(path.encode())
        digest.update((ROOT / path).read_bytes())
    return dict(
        fingerprint=digest.hexdigest(), layers=files, warnings=warnings,
        rows=sorted(rows.values(), key=lambda row: (TYPES.index(
            row["name"].split(".")[0]), row["name"], row["path"],
            row["signature"])), probes_run=False,
    )


def probe(report: dict, compiler: Path) -> None:
    """Only the fixed inert cases above execute; never synthesize calls."""
    report["probes_run"] = True
    counts = Counter(row["name"] for row in report["rows"])
    report["compiler_sha256"] = hashlib.sha256(compiler.read_bytes()).hexdigest()
    with tempfile.TemporaryDirectory(prefix="x2c-meta-api-") as directory:
        work = Path(directory)
        for key, example in PROBES.items():
            case, body, expected = example[:3]
            includes = example[3] if len(example) > 3 else ()
            name = key.split("#", 1)[0]
            source, binary = work / "probe.x", work / "probe"
            template = ('#include "x2c.x"\n' +
                        "".join(f'#include "{path}"\n' for path in includes) +
                        f'int audit_probe(void) {{ {body} }}\n'
                        'int main(void) { printf("%d\\n", '
                        'audit_probe()); return 0; }\n')
            evidence = dict(case=case, body=body, expected=str(expected),
                            includes=includes)
            try:
                def build(text):
                    source.write_text(text)
                    return subprocess.run(
                        [str(compiler), "build", "--output", str(binary),
                         str(source)], cwd=work, env=os.environ | {
                             "X2C_HOME": str(ROOT)}, capture_output=True,
                        text=True, timeout=30,
                    )

                native = build(template)
                evidence["native_compile_status"] = native.returncode
                if native.returncode:
                    evidence["diagnostic"] = "native control did not compile: " + (
                        native.stdout + native.stderr).replace(str(work), "<probe>").strip()
                    for row in report["rows"]:
                        if row["name"] == name and counts[name] == 1:
                            row["evidence"].append(evidence)
                    continue
                native_run = subprocess.run([str(binary)], capture_output=True,
                                            text=True, timeout=5)
                evidence["native_output"] = native_run.stdout.strip()
                if native_run.returncode or native_run.stdout.strip() != str(expected):
                    evidence["diagnostic"] = "native control did not produce the expected result"
                    for row in report["rows"]:
                        if row["name"] == name and counts[name] == 1:
                            row["evidence"].append(evidence)
                    continue
                built = build(template.replace("int audit_probe", "meta int audit_probe")
                              .replace("audit_probe());", "$audit_probe());"))
                evidence["compile_status"] = built.returncode
                if built.returncode:
                    evidence["diagnostic"] = (built.stdout + built.stderr).replace(
                        str(work), "<probe>").strip()
                else:
                    ran = subprocess.run([str(binary)], capture_output=True,
                                         text=True, timeout=5)
                    evidence.update(run_status=ran.returncode,
                                    output=ran.stdout.strip(),
                                    diagnostic=ran.stderr.strip())
            except subprocess.TimeoutExpired:
                evidence["diagnostic"] = "probe exceeded its time limit"
            okay = (evidence.get("compile_status") == 0 and
                    evidence.get("run_status") == 0 and
                    evidence.get("output") == str(expected))
            for row in report["rows"]:
                if row["name"] == name and counts[name] == 1:
                    row["evidence"].append(evidence)
                    if not okay or row["state"] != "reproduced failure":
                        row["state"] = "verified example" if okay else "reproduced failure"


def markdown(report: dict) -> str:
    lines = [
        "<!-- Generated by tools/meta-api-coverage.py. -->",
        "# Meta API coverage", "",
        "This inventory covers every non-static, non-underscore callable on",
        "String, List, Array, Map, Symbol and Var in the runtime sources and",
        "stage interfaces. It includes generated methods, foreign aliases and",
        "optional modules. Module visibility and API tier distinguish supported",
        "user operations from exported internals; neither group is hidden.", "",
        "Run `python3 tools/meta-api-coverage.py --probe --write` after building",
        "the current tree to refresh this report. Omit `--probe` for a source-only",
        "inventory; `--json` emits full signatures, provenance and diagnostics.",
        "This optional command is not a build or publication gate. Each behavioral",
        "case first compiles and runs as native code; an invalid native control",
        "leaves the operation unverified rather than blaming meta execution.", "",
        "The meta case declares `meta int audit_probe(void)` and invokes it as",
        "`$audit_probe()`. The corresponding native control calls `audit_probe()`",
        "without `meta`. Thus the examples exercise ordinary x2c function bodies",
        "and explicit x2c meta-call syntax, not hand-written Lisp calls.",
        "Each case below uses the `x2c.x` prelude; optional module includes are",
        "shown where needed. Invoke its displayed helper with `$audit_probe()`.", "",
        "## What the states establish", "",
        "A **verified example** establishes only its listed case. A **reproduced",
        "failure** records that case's compilation or execution failure, which",
        "may involve a dependency called by the example. **Bound, unverified**",
        "means the session defines the resolved name; **no binding found** means",
        "the standard loaded files contain no definition of that name. Neither",
        "binding search result is a behavioral test. User-installed bindings can",
        "extend this surface.", "",
        "Bindings are discovered from the compiler's library loader and native",
        "installation. A dotted Lisp name alone does not expose an ordinary",
        "method: that call uses its resolved underscore name. Templates, indexing,",
        "truth tests and conversions can have separate lowering. Their presence",
        "does not imply that a similarly named direct method works.", "",
        "Loaded layers: " + ", ".join(f"`{path}`" for path in report["layers"]) + ".",
        "", "Source fingerprint: `" + report["fingerprint"] + "`.", "",
    ]
    if report["probes_run"]:
        lines += ["Compiler fingerprint: `" + report["compiler_sha256"] + "`.", ""]
    else:
        lines += ["No behavioral probes were run for this report.", ""]
    if report["warnings"]:
        lines += ["### Interface discrepancies", ""]
        lines += ["- " + warning for warning in report["warnings"]]
        lines += [""]
    lines += ["| Type | Callables | Binding found | No binding found |",
              "| --- | ---: | ---: | ---: |"]
    for owner in TYPES:
        rows = [r for r in report["rows"] if r["name"].startswith(owner + ".")]
        found = sum(bool(r["binding"]) for r in rows)
        lines += [f"| {owner} | {len(rows)} | {found} | {len(rows) - found} |"]
    lines += ["", "## Exhaustive work ledger", "",
              "Every signature below retains its source and binding evidence and",
              "has an implementation owner, contract group and next action. The",
              "disposition is a work assignment, not a claim that all argument",
              "combinations have been tested. A resource contract is not a claim",
              "of impossibility. No alternate operation counts as coverage until",
              "its complete contract is shown to agree.", "",
              "| Evidence state | Signature rows |", "| --- | ---: |"]
    state_counts = Counter(row["state"] for row in report["rows"])
    lines += [f"| {state} | {state_counts[state]} |" for state in STATES]
    lines += ["", "| Disposition | All rows | Binding absent | Bound, unverified |",
              "| --- | ---: | ---: | ---: |"]
    for kind in KINDS:
        assigned = [r for r in report["rows"] if r["disposition"] == kind]
        lines += [f"| {kind} | {len(assigned)} | "
                  f"{sum(not r['binding'] for r in assigned)} | "
                  f"{sum(r['state'] == 'bound, unverified' for r in assigned)} |"]
    lines += ["", "### Implementation groups", "",
              "| Group | Owners | Rows | Binding absent | Bound, unverified |",
              "| --- | --- | ---: | ---: | ---: |"]
    for group in sorted({r["group"] for r in report["rows"]}):
        assigned = [r for r in report["rows"] if r["group"] == group]
        owners = ", ".join(sorted({r["owner"] for r in assigned}))
        lines += [f"| {group} | {owners} | {len(assigned)} | "
                  f"{sum(not r['binding'] for r in assigned)} | "
                  f"{sum(r['state'] == 'bound, unverified' for r in assigned)} |"]
    lines += ["", "## What a missing operation may need", "",
              "These are contract and signature considerations, not claims about",
              "why an operation was historically omitted. Multiple considerations",
              "can apply. No label promises that adding an alias is sufficient.", ""]
    lines += [f"- **{name}:** {text}" for name, text in CONSIDERATIONS.items()]
    lines += ["", "Raw evaluator slots preserve runtime `void` separately from an",
              "empty List. Missing values, null arguments, callbacks and ownership",
              "still need explicit checks before claiming runtime equivalence.", ""]
    for owner in TYPES:
        rows = [r for r in report["rows"] if r["name"].startswith(owner + ".")]
        lines += [f"## {owner}", ""]
        for state in STATES:
            names = [r["name"].split(".", 1)[1] for r in rows if r["state"] == state]
            if names:
                lines += [f"**{state}:** " + ", ".join(f"`{n}`" for n in names) + ".", ""]
        lines += ["| Direct callable | State | Binding provenance | Considerations | Tier/module | Source |",
                  "| --- | --- | --- | --- | --- | --- |"]
        for row in rows:
            source = row["path"] + (f":{row['line']}" if row["line"] else " (interface)")
            provenance = "; ".join(row["binding"]) or "none found"
            lines += [f"| `{row['signature']}` | {row['state']} | {provenance} | "
                      f"{', '.join(row['considerations'])} | {row['tier']}/{row['visibility']} | {source} |"]
        lines += ["", "### Contract and next action for every signature", "",
                  "| Callable | Implementation owner / group | Disposition | Runtime contract | Contract and next action |",
                  "| --- | --- | --- | --- | --- |"]
        for row in rows:
            runtime_contract = row["runtime_contract"].split("\n\n", 1)[0]
            runtime_contract = " ".join(runtime_contract.split()).replace("|", "&#124;")
            next_action = row["next_action"]
            if row["state"] == "verified example":
                next_action = ("The listed native/meta comparison is verified; no "
                               "binding work remains for that case.")
            lines += [f"| `{row['name']}` | {row['owner']} / {row['group']} | "
                      f"{row['disposition']} | {runtime_contract or 'Interface only; inspect the producer.'} | {row['contract']} {next_action} |"]
        cases = [r for r in rows if r["evidence"]]
        if cases:
            lines += ["", "### Evaluated cases", ""]
            for row in cases:
                for evidence in row["evidence"]:
                    result = (f"returned {evidence['output']}" if
                              evidence.get("output") == evidence["expected"] and
                              evidence.get("run_status") == 0 else
                              evidence.get("diagnostic") or
                              f"returned {evidence.get('output')}, expected {evidence['expected']}")
                    if "\n" in result:
                        notes = [line.strip() for line in result.splitlines()
                                 if "reason:" in line or ": error:" in line]
                        result = "; ".join(notes) or result.splitlines()[0]
                    lines += [f"- `{row['name']}`: {evidence['case']}; {result}.",
                              "", "```x2c"]
                    lines += [f'#include "{path}"'
                              for path in evidence.get("includes", ())]
                    lines += [f"meta int audit_probe(void) {{ {evidence['body']} }}",
                              "```", ""]
        lines += [""]
    lines += ["## Remaining evidence gaps", "",
              "Unlisted argument combinations, every callback signature, native",
              "pointer interoperability, resource lifetimes and optional-module",
              "effects remain unverified. The fixed probes do not exercise file or",
              "process operations or transfer ownership of evaluator objects.", ""]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, default=ROOT / "builds/0")
    parser.add_argument("--probe", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    if args.json and args.write:
        parser.error("--json writes to stdout; --write writes the Markdown report")
    try:
        report = inventory(args.stage.resolve())
        if args.probe:
            probe(report, args.stage.resolve() / "x2c")
        output = json.dumps(report, indent=2) if args.json else markdown(report)
        if args.write:
            REPORT.write_text(output)
            print(f"wrote {REPORT.relative_to(ROOT)}")
        else:
            print(output)
        return 0
    except (OSError, ValueError) as error:
        print(f"meta-api-coverage: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
