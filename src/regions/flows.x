/*  flows.x -- value escapes and diagnostic findings */

static macro Stmt $report.region.use_ended(
  Expr $f, Expr $subject, Expr $region) =>
  _warn(
    (*$f.w), <region>, $f.w.origin,
    %"${$subject} is used after the region that allocated it ended",
    _opened((*$f.w), $region));

static macro Stmt $report.region.local_escape(
  Expr $f, Expr $subject, Expr $exit) {
  String message =
    %"${$subject} can outlive the local storage it points into when ${$exit}";
  _warn(
    (*$f.w), <region>, $f.w.origin, message,
    %("local storage ends when the function returns"));
}

static macro Stmt $report.region.escape(
  Expr $f, Expr $subject, Expr $exit, Expr $region) =>
  _warn(
    (*$f.w), <region>, $f.w.origin,
    %"${$subject} can outlive the region it was allocated in when ${$exit}",
    _opened((*$f.w), $region));

static macro Expression $region.reason.returned() => "returned";
static macro Expression $region.reason.static_store() => "stored into a static";
static macro Expression $region.reason.local() =>
  "assigned to a local declared outside the region";
static macro Expression $region.reason.pointer() =>
  "stored through an unknown pointer";
static macro Expression $region.reason.parameter() => "stored through a parameter";
static macro Expression $region.reason.other() =>
  "stored into an object of another region";
static macro Expression $region.reason.outer() =>
  "stored into an object of an outer region";

// flows

/* One value on its way to a sink: what the walk knows about it as `fact`,
   and the local it names as `named`. */
static typedef struct Flow {
  Walk *w;
  Var value;
  Type type;
  Symbol sink;
  Fact fact;
  List named;
} Flow;

/* `value` reaches `sink` through a destination of `type`: <return>,
   <static>, <local> for the local `target`, or <heap> for the storage
   `target` reaches, or an unknown pointer when `target` is NULL. A canonical
   destination copies. A parameter adds the sink to this function's summary;
   any other value reports when either possible owner can end first.
   Returns whether it reported. */
module int _flow(Walk &w, Var value, Type type, Symbol sink, Fact target) {
  if (_number(w, type, value)) return 0;
  match (_unwrap(value))
    case $source_operator_content(%((!quote ?) ? ?yes ?no)):
      return _flow(w, yes, type, sink, target) ||
             _flow(w, no, type, sink, target);
  List named = NULL;
  Fact fact = _value_fact(w, value, named);
  if (!fact) fact = _returned_argument(w, value, named);
  int born = 0;
  Region other = NULL;
  Acquired acquired = fact ? fact.acquired : NULL;
  Region region = fact ? fact.region
                       : _birth(w, value, NULL, born, other, acquired);
  if (!fact && !born) return 0;
  if (fact && fact.param >= 0) {
    _sink_parameter(w, fact, sink, target);
    return 0;
  }
  if (fact) {
    born = fact.born;
    other = fact.other;
  }
  Flow flow = {&w, value, type, sink, fact, named};
  return _owners(flow, target, region, other, born) ||
         (_cleanup(acquired) &&
          _check(flow, target, acquired.cleanup, 1, 1));
}

static void _sink_parameter(Walk &w, Fact fact, Symbol sink, Fact target) {
  Var row = sink;
  if (sink == <heap>) {
    if (!target) row = <unknown>;
    else if (target.param >= 0) row = %(param ${target.param});
    else row = target.born ? <result>
           : (target.region || target.other) ? void : <return>;
  }
  if (sink != <local> && row is not void)
    w.sinks[%(${fact.param} $row)] = 1;
}

static int _owners(
  Flow &f, Fact target, Region region, Region other, int born) {
  int reported = 0;
  for (int choice = 0; choice < (born == 3 ? 2 : 1); choice++) {
    Region owner = choice ? other : region;
    int kind = born;
    if (born == 3) kind = choice ? 2 : 1;
    if (owner && target && target.born == 3 && f.sink == <heap>) {
      struct Fact pooled = *target;
      pooled.region = target.other;
      pooled.born = 2;
      reported |= _check(f, target, owner, kind, !reported);
      reported |= _check(f, &pooled, owner, kind, !reported);
    }
    else
      reported |= _check(f, target, owner, kind, !reported);
  }
  return reported;
}

static int _check(
  Flow &f, Fact target, Region region, int born, int report) {
  if (_copies((*f.w), f.type, f.value) && !(born & 2) &&
      (!region || region.kind != <pool>))
    return 0;
  if (!region) {
    if (f.sink == <return>) f.w.fresh |= born;
    return 0;
  }
  Region cleanup = _cleanup(region.acquired);
  if (cleanup && _check(f, target, cleanup, 1, report)) return 1;
  String subject = _subject((*f.w), f.value, f.named, f.fact);
  if (region.closed) {
    if (report)
      $report.region.use_ended(f, subject, region);
    return 1;
  }
  if (region.kind == <local>) return 0;
  String exit = _exit_reason(f, target, region);
  if (!exit) return 0;
  if (report) {
    // lint: allow one-statement-braces ST-1: macro emits declaration and call
    if (region == f.w.frame) {
      $report.region.local_escape(f, subject, exit);
    }
    else
      $report.region.escape(f, subject, exit, region);
  }
  return 1;
}

static String _exit_reason(Flow &f, Fact target, Region region) {
  switch (f.sink) {
    case <return>: return $region.reason.returned();
    case <static>: return $region.reason.static_store();
    case <local>:
      return target.depth < region.depth
        ? $region.reason.local() : NULL;
    default:
      if (!target) return $region.reason.pointer();
      if (target.param >= 0) return $region.reason.parameter();
      if (target.region == region) return NULL;
      if (_cleanup(target.acquired) == region ||
          (target.region && _cleanup(target.region.acquired) == region))
        return NULL;
      /* Every region a function opens ends before its own storage. */
      if (target.region)
        return region == f.w.frame ? NULL
          : $region.reason.other();
      return $region.reason.outer();
  }
}

// warnings

module void _warn(
  Walk &w, Symbol code, int origin, String message, List notes) {
  w.warnings.push(
    w.audit ? %(${w.function} $code $origin $message $notes)
            : %($code $origin $message $notes));
}

static List _opened(Walk &w, Region region) {
  List location = w.c.origin_location(region.origin);
  return %("region opened at line ${location.assoc(<line>).int()}");
}

/* How a warning names the value that leaves: a local by its name, and an
   address by the local it borrows from. A callee may hand back the address
   it was given or one inside it. */
module String _subject(Walk &w, Var value, List named, Fact fact) {
  match (source_expression(value)) case $source_any_lambda():
    return "a closure";
  if (!named) return "a fresh allocation";
  String name = %"'${Ast.binding_spelling(named)}'";
  Var own = w.facts[named];
  if (own is not void && own.pointer() == fact) return name;
  List arguments = NULL;
  if (_callee_of(value, arguments)) return %"an address from $name";
  match (fact ? fact.place : NULL)
    case $source_identifier_content(%(*fields)):
    return %"the address of $name";
  return %"an address inside $name";
}
