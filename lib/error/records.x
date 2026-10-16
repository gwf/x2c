/*  records.x -- error records */

/* records

   A record's entry has the shape of a Diagnostics entry,
   `((code C) (detail D) (location L))`, so a handler can match on it. Its
   detail is copied into the record's own region. */

static void _record(const X2CErrorSite *site, Symbol code, List detail) {
  if (Error.count() >= Error.bound())
    _floor(code, "error stack exceeded its bound");
  ErrorThreadState state = _thread();
  state.floor_only++;
  ErrorRecord record = { .region = _region_new() };
  detail = _copy_value(&(record.region), detail);
  record.entry = _entry(&(record.region), site, code, detail);
  state.stack.push(&record);
  state.floor_only--;
}

static void _record_n(
  const X2CErrorSite *site, Symbol code, unsigned pair_count, va_list args) {
  if (Error.count() >= Error.bound())
    _floor(code, "error stack exceeded its bound");
  ErrorThreadState state = _thread();
  state.floor_only++;
  ErrorRecord record = { .region = _region_new() };
  List detail = _counted_detail(&(record.region), code, pair_count, args);
  record.entry = _entry(&(record.region), site, code, detail);
  state.stack.push(&record);
  state.floor_only--;
}

static typedef struct ErrorPair { Var key, value; } ErrorPair;

/* Copies `count` key-value arguments into `region` as a detail List in
   argument order. The pairs wait in a Block because the List is built from
   its end. */
static List _counted_detail(
  ErrorRegion *region, Symbol code, unsigned count, va_list args) {
  int pushed = _scope_push(
    code, "could not enter error scope for counted detail");
  Block pairs = Block.new(sizeof(ErrorPair));
  for (unsigned i = 0; i < count; i++) {
    ErrorPair pair = { .key = _copy_value(region, va_arg(args, Var)) };
    pair.value = _copy_value(region, va_arg(args, Var));
    pairs.push(&pair);
  }
  ErrorPair *items = pairs.bytes;
  List detail = NULL;
  for (int i = (int) count - 1; i >= 0; i--)
    detail = _field(region, items[i].key, items[i].value, detail);
  pairs.free();
  if (pushed) Scope.pop();
  return detail;
}

static List _entry(
  ErrorRegion *region, const X2CErrorSite *site, Symbol code, List detail) {
  List location = _location(region, site), entry = NULL;
  entry = _field(region, <location>, location, entry);
  entry = _field(region, <detail>, detail, entry);
  entry = _field(region, <code>, code, entry);
  return entry;
}

static List _location(ErrorRegion *e, const X2CErrorSite *site) {
  if (!site) return NULL;
  String file = _site_text(e, site.file);
  String function = _site_text(e, site.function);
  List location = _field(e, <function>, function, NULL);
  location = _field(e, <line>, site.line, location);
  return _field(e, <file>, file, location);
}

static String _site_text(ErrorRegion *region, const char *text) {
  if (!text) text = "<unknown>";
  return String.new_in(region.pool, text, strlen(text));
}

static List _field(
  ErrorRegion *region, Var key, Var value, List tail) =>
  _cons(region, _pair(region, key, value), tail);

static List _pair(ErrorRegion *region, Var key, Var value) =>
  _cons(region, key, _cons(region, value, NULL));

static List _cons(ErrorRegion *region, Var head, List tail) =>
  List.cons_in(region.pool, head, tail);

static ErrorRecord *_record_at(int index) {
  ErrorRecord *records = _thread().stack.bytes;
  return &records[index];
}

static void _truncate(int mark) {
  if (!Error.ready() || mark < 0) return;
  while (Error.count() > mark) {
    ErrorRecord *record = _record_at(Error.count() - 1);
    _destroy(&(record.region));
    _thread().stack.pop();
  }
}

// admissible values

/* A NULL region requests an ordinary snapshot: construct in the active
   canonical pool, then promote that same object. An explicit region copies
   into its pool instead. Both policies traverse the same immutable shape. */
static Var _copy_value(ErrorRegion *region, Var value) {
  if (value is void)
    _floor(
      <bad-types>, region ? "void is not an admissible error detail"
                          : "void is not an admissible error snapshot");
  if (value.is_null() || value.is_nil() || value is <symbol>) return value;
  if (value.is_wide()) return _copy_wide(region, value);
  if (value.is_integer() || value.is_floating()) return value;
  if (value is <string> || value is <lsym>) return _copy_text(region, value);
  if (value is <list>) return _copy_list(region, value);
  _floor(
    <bad-types>, region ? "error detail contains an identity-bearing value"
                        : "error snapshot contains an identity-bearing value");
}

static Var _copy_wide(ErrorRegion *region, Var value) =>
  region ? _clone_in(&region.values, value) : _snapshot_wide(value);

/* A wide box belongs to the outermost `Scope` of the caller's active slot, so
   a nested release cannot reclaim it. An empty slot has no such `Scope` yet;
   allocate through the slot itself, which then owns the `Scope` the box
   creates. */
static Var _snapshot_wide(Var v) {
  Scope owner = *Scope.top();
  if (!owner) return v.clone_wide();
  while (owner.down) owner = owner.down;
  return _clone_in(&owner, v);
}

static Var _clone_in(Scope *owner, Var v) {
  Scope.push(owner);
  Var copy = v.clone_wide();
  Scope.pop();
  return copy;
}

static Var _copy_text(ErrorRegion *region, Var value) {
  String source = value is <lsym> ? value.str() : value.string();
  if (!region) return _snapshot_text(value, source);
  String owned = String.new_in(region.pool, source, source.len());
  return value is <lsym> ? Var.new(<lsym>, owned) : owned;
}

/* A snapshot promotes its copy, and an Atom's spelling is interned first. */
static Var _snapshot_text(Var value, String source) {
  String owned = String.new_len(source, source.len());
  if (value is not <lsym>) {
    String.try_own(owned);
    return owned;
  }
  Atom atom = Atom.intern(owned);
  if (atom is <lsym>) String.try_own(atom.str());
  return atom;
}

static List _copy_list(ErrorRegion *region, List source) {
  Var head = _copy_value(region, source.car());
  List tail = _copy_value(region, source.cdr());
  if (region) return _cons(region, head, tail);
  List owned = cons(head, tail);
  List.try_own(owned);
  return owned;
}

static ErrorRegion _region_new(void) {
  ErrorRegion region = { 0 };
  region.values = Scope.new_named("Error record values");
  region.pool = Pool.retain_named(NULL, "Error record canonical values");
  return region;
}

/* Release canonical values before their borrowed wide scalar boxes.
   No region value survives this operation. */
static void _destroy(ErrorRegion *region) {
  if (region.pool) region.pool = Pool.release(region.pool);
  if (region.values) {
    Scope.destroy(region.values);
    region.values = NULL;
  }
}

/* accumulated errors

   A handler's view and a catch's bindings are borrowed. A snapshot copies
   errors or values into the caller's owners so they outlive their callback
   or arm. */

/** Returns the number of errors currently accumulated.
    Returns zero before `Error` initialization and after shutdown.
*/
int Error.count(void) => Error.ready() ? (int) _thread().stack.length : 0;

/** Captures the current error-stack position.
    Pass the result to `Error.since` to inspect only later errors.
*/
int Error.mark(void) => Error.count();

/** Returns the accumulated errors at and after `mark`, oldest first.
    Each entry has `code`, `detail`, and `location` fields. An invalid mark or
    an unavailable `Error` runtime returns `nil`. The snapshot enters the
    caller's outermost `Scope` and canonical pools and remains live until
    those owners are released. Failure to materialize it reaches the
    non-reentrant error floor.
*/
List Error.since(int mark) {
  if (!Error.ready() || mark < 0) return NULL;
  ErrorThreadState state = _thread();
  state.floor_only++;
  List out = _view_since(NULL, mark);
  List.try_own(out);
  state.floor_only--;
  return out;
}

/* Copies errors oldest first, using an explicit region or active pools. */
static List _view_since(ErrorRegion *region, int mark) {
  List out = NULL;
  for (int i = Error.count() - 1; i >= mark; i--) {
    ErrorRecord *record = _record_at(i);
    Var entry = _copy_value(region, record.entry);
    out = region ? _cons(region, entry, out) : cons(entry, out);
  }
  return out;
}

/** Copies errors at and after `mark` into explicit owners, oldest first.
    `String`s and `List`s are canonicalized through `pool`'s chain and remain
    live until their actual owning pool is released. Wide scalar boxes enter
    `*values`, whose possibly updated `Scope` head is written back, and remain
    live until that `Scope` is destroyed. An unavailable runtime or negative
    mark returns `nil`. `Null` owners or failures while copying reach the raw
    floor.
*/
List Error.since_in(int mark, Scope *values, Pool pool) {
  if (!Error.ready() || mark < 0) return NULL;
  ErrorRegion region = _owners(values, pool);
  ErrorThreadState state = _thread();
  state.floor_only++;
  List out = _view_since(&region, mark);
  state.floor_only--;
  *values = region.values;
  return out;
}

static ErrorRegion _owners(Scope *values, Pool pool) {
  if (!values || !pool)
    _floor(<bad-arg>, "error snapshot requires explicit owners");
  return (ErrorRegion) { .values = *values, .pool = pool };
}

/** Copies one admissible error value into the caller's ordinary owners.
    Handler slices and filtered-catch bindings are borrowed. Snapshot a value
    that must outlive its callback or selected arm; `String`s and `List`s enter
    the caller's outermost canonical pools and wide scalar boxes enter its
    outermost `Scope`, so nested caller brackets may be released safely.
    Invalid or identity-bearing values and failures while copying reach the raw
    error floor; they never re-enter handler dispatch.
*/
Var Error.snapshot(Var value) {
  ErrorThreadState state = _thread();
  state.floor_only++;
  Var copy = _copy_value(NULL, value);
  state.floor_only--;
  return copy;
}

/** Copies one admissible error value into explicit runtime owners.
    `String`s and `List`s are canonicalized through `pool`'s chain and remain
    live until their actual owning pool is released. Wide scalar boxes enter
    `*values`, whose possibly updated `Scope` head is written back, and remain
    live until that `Scope` is destroyed. `Null` owners, invalid or
    identity-bearing values, and failures while copying reach the raw floor.
*/
Var Error.snapshot_in(Var value, Scope *values, Pool pool) {
  ErrorRegion region = _owners(values, pool);
  ErrorThreadState state = _thread();
  state.floor_only++;
  Var copy = _copy_value(&region, value);
  state.floor_only--;
  *values = region.values;
  return copy;
}
