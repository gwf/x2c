/*  lookup.x -- protocol member lookup

   A base default is generated for a participant by exactly one adopted
   protocol. Two candidates are a collision, reported once per member. */

static typedef struct GeneratedOwners {
  Type participant;
  String member;
  Array candidates;
  List result, first_linkage;
  Symbol first_storage;
} GeneratedOwners;

/* Runs visit once for each conformance participant adopts, in protocols
   order, after setting the caller's base to the protocol and rows to its
   member rows. */
static macro Decorator $adopted_rows(
  Stmt $visit, Expr $compiler, Expr $protocols,
  Expr $participant, Name $base, Name $rows) {
  foreach (List entry in $protocols) {
    $base = entry.car();
    if (!_is_adopted($compiler, $base, $participant)) continue;
    List conformance = $compiler.protocol_members_for($participant, $base);
    if (!conformance) continue;
    $rows = conformance.last().list().cdr();
    $visit;
  }
}

// conformance lookup

/** Returns unique member spellings from the participant's visible adopted
    conformances. Resolution remains responsible for selecting a binding.
*/
List Compiler.protocol_member_names(Compiler c, Type participant) {
  Map seen = {};
  Array names = [];
  List protocols = _ordered_occurrences(c), rows = NULL;
  Type base = NULL;
  foreach (Type current in _ancestry(c, participant.canonicalize()))
    $adopted_rows(c, protocols, current, base, rows) {
      foreach (List row in rows) {
        String name = row.car();
        if (name && !(name in seen)) {
          seen[name] = 1;
          names.push(name);
        }
      }
    }
  names.sort();
  return names.list_free();
}

/** Reports whether conformance supersedes an ambient direct member: 0 when
    it does not, 1 when the participant's own adoption does, and 2 when an
    ancestor's adoption does. The answer is cached for the canonical
    participant and uses the first visible adopted ancestor that declares
    the member.
*/
int Compiler.protocol_rejects_direct_member(
  Compiler c, Type participant, String member) {
  Type owner = participant.canonicalize();
  int rejects = 0;
  $memo(c.proto_cache, $("protocol-rejects", owner, member), rejects) {
    List protocols = _ordered_occurrences(c);
    foreach (Type ancestor in _ancestry(c, owner)) {
      List row = _member_row(c, protocols, ancestor, member);
      if (row) {
        Symbol status = row.cadr();
        if (status != <implmntd>) rejects = ancestor == owner ? 1 : 2;
        break;
      }
    }
  }
  return rejects;
}

/** Prints stable conformance rows for typedefs in `globs`.
    Rows are ordered by participant and protocol and identify whether each
    adoption is owned by this unit, so prelude and live symbol modes can be
    compared.
*/
void Compiler.dump_conformance(Compiler c, Map globs) {
  Array names = [];
  foreach (Var (key, value) in globs)
    if ($(key, value) ~= %((?(String name)) (typedef *)))
      names.push(name);
  names.sort();
  List protocols = _ordered_occurrences(c), rows = NULL;
  Type base = NULL;
  foreach (String candidate in names) {
    Type participant = $(candidate);
    $adopted_rows(c, protocols, participant, base, rows) {
      _dump_row(
        "conformance", _owns_adoption(c, base, participant), base,
        participant, rows);
    }
  }
  names.free();
}

// member resolution

/** Resolves a protocol member for `participant`.
    Returns a `(binding signature)` pair for the selected implementation or
    null when no eligible resolved member exists; positive and negative
    results are cached. Inside the selected implementation itself the result
    is null, so the member's own body keeps the native operation.
*/
List Compiler.resolve_protocol_member(
  Compiler c, Type participant, String member_name) {
  // A const or volatile receiver adopts exactly what its unqualified type
  // adopts, so conformance is keyed on the unqualified participant.
  List resolved = _resolve_member(c, participant.canonicalize(), member_name);
  if (!resolved) return NULL;
  (String spelling, Type signature) = resolved;
  if (spelling == c.fn_name) return NULL;
  return $(c.sym.reference($(spelling), NULL), signature);
}



/** Returns the resolved conformance for `participant` and `base`, if any.
    Lookup canonicalizes the participant and may use the nearest adopted
    typedef ancestor. Native conformances install their generated bindings
    before the cached conformance row is returned.
*/
List Compiler.protocol_members_for(Compiler c, Type participant, Type base) {
  participant = participant.canonicalize();
  if (c.import_protocols) _install_imports(c);
  Type owner = participant;
  if (!_is_adopted(c, base, owner)) {
    List ancestry = _ancestry(c, participant).cdr();
    for (; ancestry; ancestry = ancestry.cdr()) {
      owner = ancestry.car();
      if (_is_adopted(c, base, owner)) break;
    }
    if (!ancestry) return NULL;
  }
  List key = $(base, owner);
  Var stored = c.conforms[key];
  /* One adoption is resolved where it is asked for when the parse has not
     resolved it. `_publish` already skips resolving during
     a shallow pass, and an import installed just above resolves nothing.
     `adoptions` holds only the adoptions this compiler may use, and the full
     parse resolves all of them before it starts, except those an included
     interface recorded, which are installed here on first use. */
  if (stored is void) {
    if (!_reuse_conformance(c, base, owner))
      _resolve_adoption(c, base, owner, NULL);
    stored = c.conforms[key];
  }
  if (stored is not <list>) return NULL;
  List conformance = stored;
  _install_native_bindings(c, owner, conformance.last().list().cdr());
  return conformance;
}

// protocol member lookup

module List _ancestry(Compiler c, Type participant) {
  List result = NULL;
  $memo(c.proto_cache, $("protocol-ancestry", participant), result) {
    Array ancestry = [], Type current = participant;
    for (int distance = 0; current && distance <= 128; distance++) {
      ancestry.push(current);
      if (!current.is_typedef_name() && !current.is_typedef()) break;
      current = c.sym.get(current).type().canonicalize();
    }
    result = ancestry.list_free();
  }
  return result;
}

static List _ordered_occurrences(Compiler c) {
  if (c.import_protocols) _install_imports(c);
  List result = NULL;
  $memo(c.proto_cache, <proto-ordr>, result) {
    Array ordered = [];
    foreach ((Type base, List occurrence) in c.protocols)
      ordered.push($(base, occurrence));
    ordered.sort();
    result = ordered.list_free();
  }
  return result;
}

/* Collection skips bodies and leaves protocol registries empty. A canonical
   template can need protocols before full parsing, so install the visible
   symbols on first use and resolve only the conformance requested. */
static void _install_imports(Compiler c) {
  c.import_protocols = 0;
  c.rebuild_protocols(c.sym.unit_symbols());
}

static List _member_row(
  Compiler c, List protocols, Type participant, String member) {
  Type base = NULL;
  List rows = NULL;
  $adopted_rows(c, protocols, participant, base, rows) {
    foreach (List row in rows) if (row.car() == member) return row;
  }
  return NULL;
}

static void _dump_row(
  const char *kind, int owned, Type base, Type participant, List rows) {
  printf(
    "(%s %s %s %s", kind, owned ? "owned" : "visible",
    base.repr(), participant.repr());
  foreach (List row in rows)
    if (row ~= %(?(String member) ?(Symbol status) ?(String source) ? ? ?)) {
      const char *name = NULL, *punctuation = "none";
      switch (status) {
        case <implmntd>: name = "implemented"; break;
        case <base-dflt>: name = "base-default"; break;
        case <sig-cnflct>: name = "sig-conflict"; break;
        case <no-member>: name = "no-member"; break;
        case <native>: name = "native"; break;
      }
      if (status == <implmntd> || status == <base-dflt> ||
          status == <native>)
        punctuation = "dot+punctuation";
      printf(
        " (%s %s %s %s)", member, name, source ? source : "-", punctuation);
    }
  printf(")\n");
}

/* Cache the selected declaration, not a transaction-owned binding identity. */
static List _resolve_member(
  Compiler c, Type participant, String member_name) {
  List key = $("protocol-member", participant, member_name), selected = NULL;
  $memo(c.proto_cache, key, selected) {
    List protocols = _ordered_occurrences(c);
    List ancestry = _ancestry(c, participant);
    /* A generated member is selected before a direct base alias. */
    selected = _generated_member(c, ancestry, member_name);
    if (!selected)
      selected = _base_alias(c, protocols, ancestry, member_name);
    if (!selected)
      selected = _adopted_member(c, protocols, ancestry, member_name);
  }
  return selected;
}

static List _generated_member(
  Compiler c, List ancestry, String member) {
  foreach (Type current in ancestry) {
    List decision = _generated_owner(c, current, member);
    if (decision ~= %(owner ? ? ?signature ?)) {
      String source = _member_spelling(current, member);
      return $(source, signature);
    }
  }
  return NULL;
}

static List _base_alias(
  Compiler c, List protocols, List ancestry, String member) {
  foreach (List entry in protocols) {
    (Type base, List occurrence) = entry;
    if (!(base in ancestry)) continue;
    String base_name = _base_name(base);
    if (!base_name) continue;
    List record = occurrence.car();
    List declared = record.last().list().cdr();
    if (!_declares_member(declared, member)) continue;
    String source = %"$(base_name)_$member";
    Type signature = c.sym.get($(source));
    if (!signature || !signature.is_function()) continue;
    return $(source, signature);
  }
  return NULL;
}

static int _declares_member(List rows, String member) {
  foreach (List row in rows) if (row.car() == member) return 1;
  return 0;
}

static List _adopted_member(
  Compiler c, List protocols, List ancestry, String member) {
  foreach (Type current in ancestry) {
    List row = _member_row(c, protocols, current, member);
    if (!row) continue;
    if (row ~= %(? ?(Symbol status) ?(String source) ?(Type signature) ? ?)) {
      if (status == <implmntd>) return $(source, signature);
      if (status == <native>)
        return $(_member_spelling(current, member), signature);
    }
    return %();
  }
  return %();
}

/* Select the sole generated owner across all adopted protocols. */
module List _generated_owner(
  Compiler c, Type participant, String member) {
  List key = $("protocol-generated-owner", participant, member), owner = NULL;
  $memo(c.proto_cache, key, owner) {
    owner = _generated_decision(c, participant, member);
  }
  return owner;
}

static List _generated_decision(
  Compiler c, Type participant, String member) {
  GeneratedOwners owners = {
    .participant = participant, .member = member, .candidates = []};
  Type base = NULL;
  List rows = NULL;
  $adopted_rows(c, _ordered_occurrences(c), participant, base, rows) {
    foreach (List row in rows)
      if (_consider(owners, c, base, row)) return _decision(owners);
  }
  return _decision(owners);
}

static int _consider(
  GeneratedOwners &g, Compiler c, Type base, List row) {
  if (row ~= %(?(String member) base-dflt ?(String source)
               ?(Type expected) ordinary ?) && member == g.member) {
    Symbol storage = _visibility(c, base, g.participant);
    List owner = %(owner $base $source $expected $storage);
    g.candidates.push(owner);
    if (storage == <mixed>) {
      g.result = %(linkage $owner $owner);
      return 1;
    }
    if (!g.first_linkage) {
      g.first_linkage = owner;
      g.first_storage = storage;
    }
    else if (g.first_storage != storage) {
      g.result = %(linkage $(g.first_linkage) $owner);
      return 1;
    }
  }
  return 0;
}

static List _decision(GeneratedOwners &owners) {
  List rows = owners.candidates.list_free();
  if (owners.result) return owners.result;
  match (rows) {
    case %(?only): return only;
    case %(?first ?second *rest):
      return %(conflict $first $second @rest);
  }
  return NULL;
}
