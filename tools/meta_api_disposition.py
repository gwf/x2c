"""Contract-based work disposition for every meta API inventory row.

Evidence and binding discovery live in meta-api-coverage.py. These rules assign
work; they do not infer historical intent or promise unsupported semantics.
"""

import re


KINDS = (
    "implementable with current values", "needs callback adapter",
    "needs representation decision", "native resource contract",
    "covered by alternate operation", "needs bounded probe",
)


def disposition(row):
    """Return an explicit owner, disposition and next action for one signature."""
    name, signature, path = row["name"], row["signature"], row["path"]
    receiver, method = name.split(".", 1)
    owner = path
    kind = "implementable with current values"
    reason = "The signature uses represented values and an existing runtime owner."
    action = (f"Bind {name} to its native owner and compare normal, empty and "
              "boundary inputs without changing the public contract.")
    group = f"{receiver} value operations"

    if path == "lib/list-selectors.x" or re.fullmatch(r"c[ad]+r", method):
        group = "canonical List selectors"
        owner = "lib/list-selectors.x; lib/list.x"
        if "a" in method[1:-1]:
            kind = "needs representation decision"
            reason = ("A car step may return runtime void; current adapters collapse "
                      "that absence into an empty List.")
            action = "Use the value-contract decision before extending absent-selector adapters."
        else:
            reason = "Only cdr steps occur; exhaustion is a representable empty List."
            action = f"Compose the existing nil-safe cdr owner for {name}; test short chains."
    elif method == "foldl":
        group = "seeded folds"
        kind = "needs representation decision"
        reason = "Runtime void means no seed; an empty List is a distinct valid seed; null callbacks are permitted."
        action = "Settle true-void transport, then bridge the callback preserving seed, order and empty-input behavior."
    elif "Func" in signature:
        group = f"{receiver} interpreted callbacks"
        kind = "needs callback adapter"
        reason = "The runtime takes native Func while meta closures are evaluator callables."
        action = (f"Use Lisp.apply through a reusable Func context for {name}; "
                  "check its documented callback order, null callback and empty-input cases.")
    elif path == "lib/typed-list.x":
        group = "typed canonical List views"
        reason = "Typed Lists share ordinary canonical cells; conversion validates element tags."
        action = f"Load typed-list.x and bind {name}; test matching and rejected tags and shared identity."
    elif path in ("lib/typed-array.x", "lib/typed-map.x"):
        group = "packed typed collection conversions"
        kind = "needs representation decision"
        reason = "The target owns packed native storage, not the ordinary Array/Map element layout."
        action = f"Specify a tagged handle and owner for {name}'s target before exposing its conversion and accessors."
    elif re.search(r"\bIter\b", signature):
        group = "native iterator state"
        kind = "needs representation decision"
        reason = "Iter contains caller-owned state and a native next callback; collection producers are lazy."
        action = f"Give {name} real bounded Iter storage and lifetime; preserve source mutation and exhaustion semantics."
    elif re.search(r"\bSplit\b", signature):
        group = "lazy String split state"
        kind = "needs representation decision"
        reason = "Split is native lazy traversal state, not the List returned by String.split."
        action = f"Specify Split state/lifetime for {name}; do not replace lazy traversal with an eager List."
    elif method in {"free", "cleanup", "intern_free", "list_free", "malloc", "promote", "try_own", "is_permanent", "move_wide_to", "wide_owner", "new_in", "cons_in", "export_to", "try_export_context", "register_object_tag"}:
        group = "allocation and ownership contracts"
        kind = "native resource contract"
        reason = "The operation frees, allocates, observes or transfers storage/registry ownership that the evaluator currently owns."
        action = f"Define which session-owned objects {name} may observe or transfer; never alias a destructive native owner blindly."
    elif re.search(r"\b(?:File|Job|Context|Scope|Pool|Buffer|Block|Bytes|AdNode|Token|JsonBool|Regex\w*)\b", signature):
        resources = sorted(set(re.findall(r"\b(?:File|Job|Context|Scope|Pool|Buffer|Block|Bytes|AdNode|Token|JsonBool|Regex\w*)\b", signature)))
        group = "native " + "/".join(resources) + " contracts"
        kind = "native resource contract"
        reason = f"The signature crosses {', '.join(resources)} handles whose storage, lifetime or effects are outside ordinary value bindings."
        action = f"Review {path}'s handle and effect contract for {name}; add only a scoped native adapter after those obligations are specified."
    elif (receiver in {"List", "Array", "Map", "Var"} and method in {
        "getindex", "get", "assoc", "last", "find", "get_hashed", "heap_pop",
        "take_last", "shift", "remove", "del", "is_void", "null"
    }):
        group = "absence and null values"
        kind = "needs representation decision"
        reason = "Missing values or null tests can distinguish runtime void, Null and empty List, which current transport can conflate."
        action = f"Apply the value-contract decision to {name}; retain separate success, absence and empty-value probes."
    elif receiver == "Var" and method in {"is_pointer", "is_reference"}:
        group = "source address tags"
        kind = "needs representation decision"
        reason = "The native predicate reads its argument tag correctly, but meta local addresses currently use evaluator cells instead of their declared native pointer/reference tag."
        action = "Preserve the declared pointee tag when representing addresses; compare int and String local addresses with native execution."
    elif "..." in signature:
        group = "native variadic calls"
        kind = "needs bounded probe"
        reason = "Native ellipsis arguments have no fixed Func adapter signature."
        action = f"Inspect {name}'s count/format owner and prototype a List/rest adapter preserving argument count, type and order."
    elif "*" in signature:
        if method.startswith("try_") and receiver != "Var":
            group = "status and output cells"
            kind = "implementable with current values"
            reason = "The status result can separate success from absence while a compiler local cell carries the output."
            action = f"Wrap {name} with native temporary outputs and C.store only on success; test untouched outputs on failure."
        elif receiver in ("String", "Symbol") and method in {"new", "new_len", "parse", "c_compare", "c_len", "c_find", "decode", "lstrip", "rstrip", "strip"}:
            group = "text pointer boundaries"
            kind = "needs bounded probe"
            reason = "Canonical String storage is represented, but the native signature accepts raw character pointers or a writable destination."
            action = f"For {name}, verify null/length/bounds and whether the pointer is read-only, interior or writable before choosing a String/cell adapter."
        else:
            group = "native pointer crossings"
            kind = "needs representation decision"
            reason = "The signature passes an actual native address; a lowered local cell is not that address."
            action = f"Specify the pointee layout, mutation and lifetime for {name}; reuse status/cell adapters only where the complete signature permits."
    elif receiver == "Var" and method in {"array", "map", "string", "symbol"}:
        group = "boxed value extraction"
        reason = "The native extractor decodes a represented payload. Pointer forms borrow storage and do not prove the target family or lifetime."
        action = f"Preserve {name}'s caller preconditions; test valid typed handles and shared mutation, and inspect raw mismatch results without dereferencing them."
    elif receiver == "Var" and (method.startswith(("box_", "decode_", "wide_", "fallback_")) or method in {"integer_box", "integer_compare", "integer_floating_compare", "integer_tag", "known_tag", "payload32", "encoding_valid", "is_row", "width_mask", "signed_from_bits", "clone_wide", "custom_descriptor_index", "pointer_string"}):
        group = "numeric and descriptor internals"
        if method == "clone_wide":
            kind = "needs representation decision"
            reason = "Valid wide inputs allocate a fresh box in the active Scope; a nonwide input returns true void."
            action = "Settle true-void transport, then verify fresh identity, equal payload and session-owned lifetime for wide inputs."
        elif method == "pointer_string":
            kind = "needs representation decision"
            reason = "The result formats a raw address; meta locals and native pointer/reference values do not yet share their declared tags or address identity."
            action = "Specify which native-address observations are supported; do not claim numerical address parity across separate executions."
        else:
            reason = "The existing native owner consumes represented scalar/Var values. Numeric encoders retain exact tags; wide boxes belong to the active evaluator Scope."
            action = f"Use {name}'s native Func adapter with valid tags/encodings; test width boundaries, signedness and the documented mismatch behavior without inventing raw invalid payloads."
    elif receiver == "Var" and method == "matmul":
        group = "registered matrix protocols"
        kind = "needs bounded probe"
        reason = "The native owner only dispatches a registered matmul behavior; builtin numeric values raise bad-op."
        action = "Identify a session-owned represented matrix protocol and verify its result lifetime before installing and testing this entry point."
    elif "syntax" in row["considerations"]:
        group = "explicit syntax operations"
        reason = "Syntax lowering exists separately; it does not install this explicitly named method."
        action = f"Bind {name}'s native operation or prove exact equivalence with its lowering, including mutation, coercion and failure results."
    elif signature.startswith("void "):
        group = "mutations returning no value"
        reason = "The function mutates an existing represented object and returns C void. The existing Func adapter returns Var.null for that C result."
        action = f"Reuse the generated native Func adapter for {name}; verify mutation and distinguish this return from a Var containing void."
    elif path == "lib/common.x" and row["line"] == 0:
        group = "generated numeric/value interfaces"
        kind = "needs bounded probe"
        reason = "This row comes from a generated or foreign interface; its underlying adapter owner must be identified."
        action = f"Trace {name} through generated stage code to its macro/foreign owner and verify conversion or alias semantics before binding."

    if row["binding"]:
        action = f"Validate the existing binding against this contract. Next: {action}"
    return dict(owner=owner, group=group, disposition=kind,
                contract=reason, next_action=action)
