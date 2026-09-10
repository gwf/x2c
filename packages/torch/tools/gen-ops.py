#!/usr/bin/env python3
"""Generate the tier-1 operator bindings for packages/torch.

Input is the pinned schema/native_functions-2.10.0.yaml (see schema/README.md).
Output is generated/xt_ops.h, generated/xt_ops.cpp, and src/torch-ops.x, all of
which are build outputs: regenerate with `make -C packages/torch gen-ops`
instead of editing them.

Conventions follow tch-rs and the hand-written shim in src/torch-shim.cpp:
`xt_<op>` or `xt_<op>_<overload>` C names, every body wrapped in a try/catch
that stores the message in the shim's thread-local error, a status-plus-out
parameter signature for every non-handle result, and a new handle for every
returned tensor.
"""

import argparse
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PACKAGE = os.path.dirname(HERE)

# Arguments whose value the generated binding always leaves at the ATen
# default. They are named here, in the generated headers, and counted in the
# summary, so nothing is dropped silently. Everything else that does not map
# excludes its operator instead.
DEFAULTED = {
    "Generator?": "::std::optional<at::Generator>()",
    "Layout?": "::std::optional<at::Layout>()",
    "MemoryFormat?": "::std::optional<at::MemoryFormat>()",
}
DEFAULTED_BY_NAME = {"pin_memory": "::std::optional<bool>()"}

# C and C++ words a generated name may not be, plus the x2c protocol member
# names a generated method may not take.
RESERVED = set("""
auto break case char const continue default do double else enum extern float
for goto if inline int long register restrict return short signed sizeof
static struct switch typedef union unsigned void volatile while bool class
delete new operator private protected public template this throw try catch
namespace using typename and or not xor
str repr hash equal compare truth iter contains getindex setindex updateindex
postfixindex var native free adopt check
""".split())


class Skip(Exception):
    def __init__(self, reason):
        Exception.__init__(self, reason)
        self.reason = reason


def split_top(text, sep=","):
    """Split on `sep` outside (), [], and quotes."""
    parts, depth, quote, current = [], 0, None, []
    for ch in text:
        if quote:
            current.append(ch)
            if ch == quote:
                quote = None
            continue
        if ch in "'\"":
            quote = ch
        elif ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        elif ch == sep and depth == 0:
            parts.append("".join(current).strip())
            current = []
            continue
        current.append(ch)
    tail = "".join(current).strip()
    if tail:
        parts.append(tail)
    return parts


def read_schema(path):
    """Return [(signature, variants)] in file order."""
    entries = []
    signature = None
    variants = None
    with open(path, "r") as handle:
        for line in handle:
            if line.startswith("- func:"):
                if signature is not None:
                    entries.append((signature, variants))
                signature = line[len("- func:"):].strip()
                variants = None
            elif signature is not None and line.startswith("  variants:"):
                variants = line.split(":", 1)[1].split("#")[0].strip()
    if signature is not None:
        entries.append((signature, variants))
    return entries


ARG_RE = re.compile(r"^(?P<type>.+?)\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)$")


def parse_signature(signature):
    head, _, returns = signature.rpartition("->")
    head, returns = head.strip(), returns.strip()
    call, _, _ = head.rpartition(")")
    name, _, arglist = call.partition("(")
    name = name.strip()
    base, _, overload = name.partition(".")
    args = []
    for piece in split_top(arglist):
        if piece == "*" or not piece:
            continue
        piece = piece.split("=")[0].strip()
        match = ARG_RE.match(piece)
        if not match:
            raise Skip("unparsed-argument")
        raw = match.group("type").strip()
        mutable = "!" in raw
        # Strip the alias annotation: Tensor(a!)? -> Tensor?
        clean = re.sub(r"\([^)]*\)", "", raw).strip()
        args.append({"type": clean, "name": match.group("name"),
                     "mutable": mutable})
    return base, overload, args, returns


def parse_returns(returns):
    text = returns.strip()
    if text in ("()", ""):
        return []
    if text.startswith("(") and text.endswith(")"):
        text = text[1:-1]
        items = split_top(text)
    else:
        items = [text]
    kinds = []
    for item in items:
        item = item.strip()
        item = re.sub(r"\([^)]*\)", "", item).strip()
        item = item.split(" ")[0].strip()
        kinds.append(item)
    return kinds


# --- argument mapping ------------------------------------------------------

def norm(kind):
    """Normalize a schema type: SymInt is bound through the int64 overload."""
    kind = kind.replace("SymInt", "int")
    kind = re.sub(r"\[\d+\]", "[]", kind)
    return kind


def map_arg(arg):
    """Return (cparams, callexpr, xparams, xpre, xargs) for one argument."""
    kind = norm(arg["type"])
    name = arg["name"]
    if name in RESERVED:
        name = name + "_"
    if arg["type"] in DEFAULTED:
        return None, DEFAULTED[arg["type"]], None, None, None
    if name in DEFAULTED_BY_NAME and kind == "bool?":
        return None, DEFAULTED_BY_NAME[name], None, None, None

    if kind == "Tensor":
        return ([("xt_tensor", name)], "%s->t" % name,
                [("Tensor", name)], [], ["_native(%s)" % name])
    if kind == "Tensor?":
        return ([("xt_tensor", name)],
                "%s ? ::std::optional<at::Tensor>(%s->t) "
                ": ::std::optional<at::Tensor>()" % (name, name),
                [("Tensor", name)], [], ["_native(%s)" % name])
    if kind == "Tensor[]":
        return ([("const xt_tensor *", name), ("int64_t", name + "_n")],
                "at::TensorList(xg_to_tensors(%s, %s_n))" % (name, name),
                [("List", name)],
                ["int64_t %s_n = 0;" % name,
                 "xt_tensor *%s_items = _handles(%s, &%s_n);"
                 % (name, name, name)],
                ["%s_items" % name, "%s_n" % name])
    if kind in ("Scalar", "Scalar?"):
        maker = "xg_to_scalar" if kind == "Scalar" else "xg_to_opt_scalar"
        return ([("int", name + "_kind"), ("int64_t", name + "_int"),
                 ("double", name + "_dbl")],
                "%s(%s_kind, %s_int, %s_dbl)" % (maker, name, name, name),
                [("Var", name)],
                ["int64_t %s_int = 0;" % name,
                 "double %s_dbl = 0;" % name,
                 "int %s_kind = _scalar(%s, &%s_int, &%s_dbl);"
                 % (name, name, name, name)],
                ["%s_kind" % name, "%s_int" % name, "%s_dbl" % name])
    if kind == "int":
        return ([("int64_t", name)], name, [("int64_t", name)], [], [name])
    if kind == "int?":
        return ([("int64_t", name), ("int", name + "_set")],
                "%s_set ? ::std::optional<int64_t>(%s) "
                ": ::std::optional<int64_t>()" % (name, name),
                [("int64_t", name), ("int", name + "_set")], [],
                [name, name + "_set"])
    if kind == "float":
        return ([("double", name)], name, [("double", name)], [], [name])
    if kind == "float?":
        return ([("double", name), ("int", name + "_set")],
                "%s_set ? ::std::optional<double>(%s) "
                ": ::std::optional<double>()" % (name, name),
                [("double", name), ("int", name + "_set")], [],
                [name, name + "_set"])
    if kind == "bool":
        return ([("int", name)], "%s != 0" % name,
                [("int", name)], [], [name])
    if kind == "bool?":
        return ([("int", name), ("int", name + "_set")],
                "%s_set ? ::std::optional<bool>(%s != 0) "
                ": ::std::optional<bool>()" % (name, name),
                [("int", name), ("int", name + "_set")], [],
                [name, name + "_set"])
    if kind == "int[]":
        return ([("const int64_t *", name), ("int64_t", name + "_n")],
                "at::IntArrayRef(%s, %s_n)" % (name, name),
                [("List", name)],
                ["int64_t %s_n = 0;" % name,
                 "int64_t *%s_dims = _dims(%s, &%s_n);" % (name, name, name)],
                ["%s_dims" % name, "%s_n" % name])
    if kind == "int[]?":
        return ([("const int64_t *", name), ("int64_t", name + "_n")],
                "%s ? at::OptionalIntArrayRef(at::IntArrayRef(%s, %s_n)) "
                ": at::OptionalIntArrayRef()" % (name, name, name),
                [("List", name)],
                ["int64_t %s_n = 0;" % name,
                 "int64_t *%s_dims = %s ? _dims(%s, &%s_n) : NULL;"
                 % (name, name, name, name)],
                ["%s_dims" % name, "%s_n" % name])
    if kind == "ScalarType":
        return ([("int", name)], "static_cast<at::ScalarType>(%s)" % name,
                [("int", name)], [], [name])
    if kind == "ScalarType?":
        return ([("int", name)],
                "%s < 0 ? ::std::optional<at::ScalarType>() "
                ": ::std::optional<at::ScalarType>("
                "static_cast<at::ScalarType>(%s))" % (name, name),
                [("int", name)], [], [name])
    if kind == "Device":
        return ([("const char *", name)], "at::Device(%s)" % name,
                [("String", name)], [], [name])
    if kind == "Device?":
        return ([("const char *", name)],
                "%s ? ::std::optional<at::Device>(at::Device(%s)) "
                ": ::std::optional<at::Device>()" % (name, name),
                [("String", name)], [], [name])
    if kind == "str":
        return ([("const char *", name)], "::std::string_view(%s)" % name,
                [("String", name)], [], [name])
    if kind == "str?":
        return ([("const char *", name)],
                "%s ? ::std::optional<::std::string_view>("
                "::std::string_view(%s)) "
                ": ::std::optional<::std::string_view>()" % (name, name),
                [("String", name)], [], [name])
    raise Skip("unmappable-argument:" + kind)


# --- selection -------------------------------------------------------------

RETURN_SCALARS = {"bool": ("int", "int"), "int": ("int64_t", "int64_t"),
                  "float": ("double", "double")}


def classify_return(kinds):
    if not kinds:
        return ("void", 0)
    if all(k == "Tensor" for k in kinds):
        if len(kinds) == 1:
            return ("tensor", 1)
        if 2 <= len(kinds) <= 4:
            return ("tuple", len(kinds))
        raise Skip("unsupported-return:tuple%d" % len(kinds))
    if len(kinds) == 1:
        kind = kinds[0]
        if kind == "Tensor[]":
            return ("tensors", 0)
        if kind in RETURN_SCALARS:
            return (kind, 1)
        if kind == "Scalar":
            return ("Scalar", 1)
    raise Skip("unsupported-return:" + ",".join(kinds))


def select(entries, existing, counts):
    chosen = []
    cnames = {}
    xnames = set(existing)
    for signature, variants in entries:
        counts["parsed"] += 1
        try:
            base, overload, args, returns = parse_signature(signature)
            if base.startswith("_"):
                raise Skip("private-name")
            if "backward" in base:
                raise Skip("backward")
            if overload == "out" or overload.endswith("_out") \
               or base.endswith("_out"):
                raise Skip("out-variant")
            if any(a["mutable"] and index > 0
                   for index, a in enumerate(args)):
                raise Skip("out-argument")
            if any(a["name"] in ("out", "values", "indices")
                   and a["mutable"] for a in args):
                raise Skip("out-argument")
            if any("Dimname" in a["type"] for a in args) \
               or "Dimname" in returns:
                raise Skip("dimname")
            style = "function"
            if variants is not None and "function" not in variants.split(", "):
                if "method" in variants.split(", ") and args \
                   and norm(args[0]["type"]) == "Tensor":
                    style = "method"
                else:
                    raise Skip("method-only")
            symint = any("SymInt" in a["type"] for a in args)
            kinds = parse_returns(returns)
            rkind, rcount = classify_return(kinds)

            mapped, defaulted = [], []
            for arg in args:
                cparams, call, xparams, xpre, xargs = map_arg(arg)
                if cparams is None:
                    defaulted.append(arg["name"])
                    mapped.append({"call": call, "c": [], "x": [],
                                   "pre": [], "xargs": []})
                else:
                    mapped.append({"call": call, "c": cparams, "x": xparams,
                                   "pre": xpre, "xargs": xargs})

            cname = "xt_" + base + ("_" + overload.lower() if overload else "")
            if cname in cnames:
                raise Skip("c-name-collision")

            method = None
            for candidate in x2c_candidates(base, overload):
                if candidate not in xnames:
                    method = candidate
                    break
            if method is None:
                raise Skip("x2c-name-collision")
            if base in existing:
                counts["reason:collision-torch-x"] += 1
            if base in RESERVED:
                raise Skip("reserved-name")

            receiver = "Tensor" if (args and norm(args[0]["type"]) == "Tensor"
                                    and not args[0]["mutable"]) else "Torch"
            if args and args[0]["mutable"]:
                receiver = "Tensor"
            cnames[cname] = True
            xnames.add(method)
            chosen.append({
                "signature": signature, "base": base, "overload": overload,
                "cname": cname, "method": method, "receiver": receiver,
                "args": args, "mapped": mapped, "defaulted": defaulted,
                "rkind": rkind, "rcount": rcount, "symint": symint,
                "style": style,
                "aliasing": any(a["mutable"] for a in args),
            })
            counts["selected"] += 1
            counts["style-" + style] += 1
            if symint:
                counts["symint-mapped"] += 1
            if defaulted:
                counts["args-defaulted"] += 1
        except Skip as skip:
            counts["reason:" + skip.reason] += 1
    return chosen


def x2c_candidates(base, overload):
    yield base
    if overload:
        pieces = [p.lower() for p in overload.split("_") if p]
        for count in range(1, len(pieces) + 1):
            yield base + "_" + "_".join(pieces[:count])


# --- emission --------------------------------------------------------------

HEADER_NOTE = """\
/*  %s -- GENERATED by tools/gen-ops.py from
    schema/native_functions-2.10.0.yaml (pytorch v2.10.0). Do not edit; run
    `make -C packages/torch gen-ops`.

    One entry per selected aten operator, in schema order. Every body catches
    and stores the libtorch message in the shim's thread-local error, then
    returns NULL (handle results), -1 (list length), or nonzero (status).
    Every returned tensor is a new handle; a view or an in-place result
    aliases its input's storage.

    Argument encoding: Tensor and Tensor? are handles, NULL meaning nullopt;
    Tensor[] is a handle array with its length; Scalar is the triple
    (kind, int64, double) with kind 0 int64, 1 double, 2 bool, -1 nullopt;
    int[] is an int64 array with its length, NULL meaning nullopt; an optional
    int, float, or bool carries a separate has_value flag; ScalarType? is an
    int with -1 meaning nullopt; Device? and str? are const char *, NULL
    meaning nullopt. `generator`, `layout`, `memory_format`, and `pin_memory`
    arguments are named in each comment and always left at the ATen default.
*/
"""


def c_signature(op):
    params = []
    for entry in op["mapped"]:
        for ctype, name in entry["c"]:
            params.append("%s%s" % (ctype if ctype.endswith("*")
                                    else ctype + " ", name))
    rkind = op["rkind"]
    if rkind == "tensor":
        ret = "xt_tensor"
    elif rkind == "tensors":
        ret = "int64_t"
        params.append("xt_tensor **out")
    elif rkind == "tuple":
        ret = "int"
        params += ["xt_tensor *out%d" % i for i in range(op["rcount"])]
    elif rkind == "Scalar":
        ret = "int"
        params += ["int *out_kind", "int64_t *out_int", "double *out_dbl"]
    elif rkind == "void":
        ret = "int"
    else:
        ret = "int"
        params.append("%s *out" % RETURN_SCALARS[rkind][0])
    return "%s %s(%s)" % (ret, op["cname"], ", ".join(params) or "void")


def c_call(op):
    calls = [e["call"] for e in op["mapped"]]
    if op["style"] == "method":
        return "%s.%s(%s)" % (calls[0], op["base"], ", ".join(calls[1:]))
    return "at::%s(%s)" % (op["base"], ", ".join(calls))


def emit_header(ops):
    lines = [HEADER_NOTE % "xt_ops.h",
             "#ifndef X2C_XT_OPS_H", "#define X2C_XT_OPS_H", "",
             '#include "torch-2.10.h"', '#include "xt_ops_support.h"', "",
             "#ifdef __cplusplus", 'extern "C" {', "#endif", ""]
    for op in ops:
        lines.append("/* %s */" % op["signature"])
        lines.append(c_signature(op) + ";")
    lines += ["", "#ifdef __cplusplus", "}", "#endif", "#endif", ""]
    return "\n".join(lines)


CPP_PRELUDE = """\
#include <torch/torch.h>
#include <cstdlib>
#include <optional>
#include <string_view>
#include <vector>

#include "xt_ops.h"

struct xt_tensor_s { at::Tensor t; };

#define XT_TRY(fail, ...) \\
  try { __VA_ARGS__ } \\
  catch (const std::exception &e) { xt_note_error(e.what()); return fail; }

static xt_tensor xg_wrap(at::Tensor t) { return new xt_tensor_s{std::move(t)}; }

static at::Scalar xg_to_scalar(int kind, int64_t i, double d) {
  if (kind == 2) return at::Scalar(i != 0);
  if (kind == 1) return at::Scalar(d);
  return at::Scalar(i);
}

static ::std::optional<at::Scalar> xg_to_opt_scalar(int kind, int64_t i,
                                                 double d) {
  if (kind < 0) return ::std::optional<at::Scalar>();
  return ::std::optional<at::Scalar>(xg_to_scalar(kind, i, d));
}

static void xg_from_scalar(const at::Scalar &s, int *kind, int64_t *i,
                        double *d) {
  *i = 0;
  *d = 0;
  if (s.isFloatingPoint()) { *kind = 1; *d = s.toDouble(); }
  else if (s.isBoolean()) { *kind = 2; *i = s.toBool() ? 1 : 0; }
  else { *kind = 0; *i = s.toLong(); }
}

static ::std::vector<at::Tensor> xg_to_tensors(const xt_tensor *items,
                                            int64_t n) {
  ::std::vector<at::Tensor> values;
  values.reserve(n > 0 ? (size_t) n : 0);
  for (int64_t k = 0; k < n; k++) values.push_back(items[k]->t);
  return values;
}

extern "C" {

void xt_free_handles(xt_tensor *handles) { free(handles); }
"""


def emit_body(op):
    call = c_call(op)
    rkind = op["rkind"]
    if rkind == "tensor":
        inner = "return xg_wrap(%s);" % call
        fail = "nullptr"
    elif rkind == "tensors":
        inner = ("auto result = %s;\n"
                 "    size_t count = result.size();\n"
                 "    xt_tensor *handles = (xt_tensor *) malloc(\n"
                 "      sizeof(xt_tensor) * (count ? count : 1));\n"
                 "    if (!handles) { xt_note_error(\"out of memory\");"
                 " return -1; }\n"
                 "    for (size_t k = 0; k < count; k++)\n"
                 "      handles[k] = xg_wrap(result[k]);\n"
                 "    *out = handles;\n"
                 "    return (int64_t) count;" % call)
        fail = "-1"
    elif rkind == "tuple":
        stores = "\n".join(
            "    *out%d = xg_wrap(::std::get<%d>(result));" % (i, i)
            for i in range(op["rcount"]))
        inner = "auto result = %s;\n%s\n    return 0;" % (call, stores)
        fail = "1"
    elif rkind == "Scalar":
        inner = ("xg_from_scalar(%s, out_kind, out_int, out_dbl);\n"
                 "    return 0;" % call)
        fail = "1"
    elif rkind == "void":
        inner = "%s;\n    return 0;" % call
        fail = "1"
    elif rkind == "bool":
        inner = "*out = (%s) ? 1 : 0;\n    return 0;" % call
        fail = "1"
    else:
        inner = "*out = %s;\n    return 0;" % call
        fail = "1"
    note = ""
    if op["defaulted"]:
        note = "/* default: %s */\n" % " ".join(op["defaulted"])
    if op["aliasing"]:
        note += "/* result aliases the input's storage */\n"
    return "%s%s%s {\n  XT_TRY(%s,\n    %s)\n}" % (
        note, "/* %s */\n" % op["signature"], c_signature(op), fail, inner)


def emit_cpp(ops, part, total):
    if part == 0:
        head = HEADER_NOTE % "xt_ops.cpp" + CPP_PRELUDE
    else:
        head = (HEADER_NOTE % ("xt_ops-%d.cpp" % (part + 1))
                + CPP_PRELUDE.replace(
                    "void xt_free_handles(xt_tensor *handles) "
                    "{ free(handles); }\n", ""))
    bodies = "\n\n".join(emit_body(op) for op in ops)
    return head + "\n" + bodies + "\n\n}  /* extern \"C\" */\n"


X_PRELUDE = '''\
/*  torch-ops.x -- GENERATED by tools/gen-ops.py from
    schema/native_functions-2.10.0.yaml (pytorch v2.10.0). Do not edit; run
    `make -C packages/torch gen-ops`.

    One wrapper per generated C binding in generated/xt_ops.h, in schema
    order. A failure raises `<bad-state>` through `Torch.check`, exactly as
    the hand-written operations in torch.x do.

    Naming: the method is the operator's schema name. When that name is
    already taken, by torch.x or by an earlier overload, the shortest prefix
    of the schema's overload name that is still free is appended, so
    `sum.dim_IntList` becomes `Tensor.sum_dim`.

    Arguments: `List` for an int[] shape or a Tensor[] list, `Var` for a
    Scalar (an integer Var crosses as int64 and a floating Var as double),
    `int` for bool, `int64_t` for int64, `String` for a device or a str, and a
    NULL `Tensor`, `List`, or `String`, or `Var.null()`, for an absent
    optional. An optional
    int, float, or bool takes a separate `_set` flag; an optional ScalarType
    takes -1. A tuple or list result comes back as a `List` of Tensors, and
    a Scalar result as a `Var` of its own kind.
*/

#include <stdint.h>
#include "torch.x"
#include "xt_ops.h"

#pragma private

static xt_tensor _native(Tensor t) => t ? t.native() : NULL;

static int64_t *_dims(List sizes, int64_t *count) {
  int len = sizes.len();
  int64_t *dims = Scope.calloc(len ? len : 1, sizeof(int64_t));
  int index = 0;
  foreach (Var size, sizes) dims[index++] = size.integer();
  *count = len;
  return dims;
}

static xt_tensor *_handles(List tensors, int64_t *count) {
  int len = tensors ? tensors.len() : 0;
  xt_tensor *items = Scope.calloc(len ? len : 1, sizeof(xt_tensor));
  int index = 0;
  if (tensors) foreach (Var item, tensors) items[index++] = _native(
    item.tensor());
  *count = len;
  return items;
}

/* Crosses a Scalar exactly: 0 int64, 1 double, -1 absent. */
static int _scalar(Var value, int64_t *integer, double *floating) {
  if (value.is_null() || value.is_void()) return -1;
  if (value.is_floating()) {
    *floating = value.double();
    return 1;
  }
  if (value.is_integer()) {
    *integer = value.integer();
    return 0;
  }
  raise %(bad-arg (library "torch")
          (reason "a Scalar argument takes an integer or a floating Var"));
}

static List _pair(xt_tensor a, xt_tensor b, String operation) {
  Tensor first = Tensor.adopt(a, operation);
  Tensor second = Tensor.adopt(b, operation);
  return %($first $second);
}

#pragma public
'''


def x_signature(op):
    params = []
    for entry in op["mapped"]:
        for xtype, name in entry["x"]:
            params.append("%s %s" % (xtype, name))
    rkind = op["rkind"]
    if rkind == "tensor":
        ret = "Tensor"
    elif rkind in ("tuple", "tensors"):
        ret = "List"
    elif rkind == "Scalar":
        ret = "Var"
    elif rkind == "void":
        ret = "void"
    else:
        ret = RETURN_SCALARS[rkind][1]
    return "%s %s.%s(%s)" % (ret, op["receiver"], op["method"],
                             ", ".join(params) or "void")


def wrap_lines(text, indent):
    """Fold one generated line onto 79 columns, breaking after a comma."""
    if len(indent) + len(text) <= 79:
        return [indent + text]
    tokens, current = [], ""
    for piece in text.split(", "):
        tokens.append(piece)
    tokens = [t + ", " for t in tokens[:-1]] + tokens[-1:]
    lines, current = [], indent
    continuation = indent + "    "
    for token in tokens:
        if len(current) + len(token) > 79 and current.strip():
            lines.append(current.rstrip())
            current = continuation
        current += token
    if current.strip():
        lines.append(current.rstrip())
    return lines


def emit_x(op):
    pre = []
    cargs = []
    for entry in op["mapped"]:
        pre += entry["pre"]
        cargs += entry["xargs"]
    name = op["base"]
    rkind = op["rkind"]
    call = "%s(%s)" % (op["cname"], ", ".join(cargs))

    def with_outs(extra):
        return "%s(%s)" % (op["cname"], ", ".join(cargs + extra))

    if rkind == "tensor" and not pre:
        head = wrap_lines(x_signature(op) + " =>", "")
        return "\n".join(head
                         + wrap_lines('Tensor.adopt(%s, "%s");' % (call, name),
                                      "  "))
    body = list(pre)
    if rkind == "tensor":
        body.append('return Tensor.adopt(%s, "%s");' % (call, name))
    elif rkind == "tuple" and op["rcount"] == 2:
        body += ["xt_tensor out0 = NULL, out1 = NULL;",
                 'Torch.check(%s, "%s");'
                 % (with_outs(["&out0", "&out1"]), name),
                 'return _pair(out0, out1, "%s");' % name]
    elif rkind == "tuple":
        outs = ["out%d" % i for i in range(op["rcount"])]
        body += ["xt_tensor %s;" % ", ".join("%s = NULL" % o for o in outs),
                 'Torch.check(%s, "%s");'
                 % (with_outs(["&" + o for o in outs]), name),
                 "List result = %();"]
        for out in outs:
            body += ['Tensor %s_t = Tensor.adopt(%s, "%s");' % (out, out,
                                                                name),
                     "result = result.append(%%($%s_t));" % out]
        body.append("return result;")
    elif rkind == "tensors":
        body += ["xt_tensor *items = NULL;",
                 "int64_t count = %s;" % with_outs(["&items"]),
                 'if (count < 0) Torch.check(1, "%s");' % name,
                 "List result = %();",
                 "for (int64_t i = 0; i < count; i++) {",
                 '@Tensor item = Tensor.adopt(items[i], "%s");' % name,
                 "@result = result.append(%($item));",
                 "}",
                 "xt_free_handles(items);",
                 "return result;"]
    elif rkind == "Scalar":
        body += ["int kind = 0;", "int64_t integer = 0;", "double floating = 0;",
                 'Torch.check(%s, "%s");'
                 % (with_outs(["&kind", "&integer", "&floating"]), name),
                 "if (kind == 1) {",
                 "@Var result = floating;",
                 "@return result;",
                 "}",
                 "Var whole = integer;",
                 "return whole;"]
    elif rkind == "void":
        body.append('Torch.check(%s, "%s");' % (call, name))
    else:
        ctype = RETURN_SCALARS[rkind][1]
        body += ["%s result = 0;" % ctype,
                 'Torch.check(%s, "%s");' % (with_outs(["&result"]), name),
                 "return result;"]

    lines = wrap_lines(x_signature(op) + " {", "")
    for statement in body:
        indent = "    " if statement.startswith("@") else "  "
        lines += wrap_lines(statement.lstrip("@"), indent)
    lines.append("}")
    return "\n".join(lines)


def existing_names(path):
    names = set()
    with open(path, "r") as handle:
        text = handle.read()
    for match in re.finditer(r"\b(?:Tensor|Torch|double|Var)\."
                             r"([A-Za-z_][A-Za-z0-9_]*)\s*\(", text):
        names.add(match.group(1))
    return names


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--schema",
                        default=os.path.join(PACKAGE, "schema",
                                             "native_functions-2.10.0.yaml"))
    parser.add_argument("--parts", type=int, default=1,
                        help="number of generated .cpp files")
    args = parser.parse_args()

    with open(args.schema, "rb") as handle:
        digest = hashlib.sha256(handle.read()).hexdigest()
    entries = read_schema(args.schema)
    existing = existing_names(os.path.join(PACKAGE, "src", "torch.x"))

    class Counter(dict):
        def __missing__(self, key):
            return 0
    counts = Counter()
    counts["parsed"] = 0
    counts["selected"] = 0
    ops = select(entries, existing, counts)

    generated = os.path.join(PACKAGE, "generated")
    os.makedirs(generated, exist_ok=True)
    with open(os.path.join(generated, "xt_ops.h"), "w") as handle:
        handle.write(emit_header(ops))
    parts = max(1, args.parts)
    size = (len(ops) + parts - 1) // parts
    for index in range(parts):
        chunk = ops[index * size:(index + 1) * size]
        name = "xt_ops.cpp" if index == 0 else "xt_ops-%d.cpp" % (index + 1)
        with open(os.path.join(generated, name), "w") as handle:
            handle.write(emit_cpp(chunk, index, parts))
    for stale in range(parts, 8):
        path = os.path.join(generated, "xt_ops-%d.cpp" % (stale + 1))
        if os.path.exists(path):
            os.remove(path)
    with open(os.path.join(PACKAGE, "src", "torch-ops.x"), "w") as handle:
        handle.write(X_PRELUDE + "\n"
                     + "\n\n".join(emit_x(op) for op in ops) + "\n")

    print("schema %s" % os.path.relpath(args.schema, PACKAGE))
    print("sha256 %s" % digest)
    print("ops parsed   %d" % counts["parsed"])
    print("ops selected %d" % counts["selected"])
    print("symint mapped to int64 %d" % counts["symint-mapped"])
    print("ops with a defaulted argument %d" % counts["args-defaulted"])
    print("bound as an at:: function %d, as a Tensor method %d"
          % (counts["style-function"], counts["style-method"]))
    print("collides with torch.x, renamed %d"
          % counts["reason:collision-torch-x"])
    print("skipped:")
    for key in sorted(k for k in counts if k.startswith("reason:")):
        if key == "reason:collision-torch-x":
            continue
        print("  %-34s %d" % (key[len("reason:"):], counts[key]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
