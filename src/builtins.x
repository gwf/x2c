/*  builtins.x -- the built-in macros' compile-time algorithms

    Copyright (c) 2026 Gary William Flake.

    The built-in macros expand through these functions, which run as native
    code inside the compiler. `Compiler.builtin_targets` names each as its
    callers do: the prototypes `etc/compiler-prelude.x` and
    `lib/compiler-meta.x` declare, and the recipes and quotation slots the
    compiler writes.
*/
#pragma once
#include "x2c.x"
#include "meta.x"
#include "grammar.x"
#include "lisp/lisp.x"
#include "macros/macros.x"
#include "transform/transform.x"

// $scope

static List _scope_expand(List body, List destinations) {
  if (destinations.len() > 1)
    x2c_diagnostic_fail("$scope accepts zero or one destination", %());
  List enter = destinations ? $!( Scope_push(@destinations) )
                            : $!( Scope_retain() );
  List leave = destinations ? $!( Scope_pop() ) : $!( Scope_release() );
  return $!{ { $enter; { defer $leave; $body } } };
}

// with

/* `with (place = value, ...)` nests one block per assignment around the
   body, the first outermost. Each block captures its place's address once,
   saves the value there, defers restoring it, and assigns. Each quotation
   application declares its own private `address` and `previous`. */
static List _with_expand(List body, List assignments) {
  if (!assignments)
    x2c_diagnostic_fail("with requires at least one assignment", %());
  foreach (List assignment in assignments.reverse())
    body = _with_assignment(assignment, body);
  return body;
}

static List _with_assignment(List assignment, List body) {
  List place = NULL, value = NULL;
  match (assignment)
    case %(expr ? (op = ?target ?source)): place = target, value = source;
  if (!place)
    x2c_diagnostic_fail(
      "with requires 'destination = expression' entries",
      %("parenthesize a comma expression inside an entry"));
  Type type = ((Code) place).type();
  return $!{ {
    $type *address = &$place;
    $type previous = *address;
    defer *address = previous;
    *address = $value;
    $body
  } };
}

// $auto

/* Preserve the acquired value after its declaration's checks. */
static macro Stmt $auto_release(Decl $local, Expr $binding) using $acquired {
  @_x2c_auto_release($local, $binding, $acquired)
}

/* `$auto(value)` returns `value` and places the release after the
   declarator it initializes. The declaration checks that the result is its
   complete initializer before it binds the release, so a partial use
   reports that first. */
static List _auto_expand(List value) {
  Code local = x2c_enclosing(<declarator>);
  if (!local || !x2c_enclosing(<function>))
    _auto_fail(
      <parse>,
      "managed initializer requires a complete block-local initializer", %());
  _auto_reject_managed(value);
  match (local) case %(declare ? (bindings (bind ?binding ?))): {
    Compiler c = Compiler.expanding();
    c.sym.put(c.semantic_binding_facts(), %(managed $binding), 1);
    Macro release = $auto_release;
    x2c_place(
      %(after-statement), x2c_template_call(release, %($local $binding)));
  }
  return value;
}

/* A local that an earlier `$auto` manages is released once at block exit;
   managing it again would release it twice. */
static void _auto_reject_managed(List value) {
  match (value) {
    case %(expr ? ${$grouped(?inner)}): _auto_reject_managed(inner);
    case %(expr ? ${$source_identifier_content(%(?binding))}): {
      Compiler c = Compiler.expanding();
      if (%(managed $binding) in c.semantic_binding_facts())
        _auto_fail(
          <parse>, "managed initializer cannot manage an already managed local",
          %("local: ${Ast.binding_spelling(binding)}"));
    }
  }
}

/* Automatic locals release through Cleanup when their type participates. */
static List _auto_release(Code local, List binding, List acquired) {
  Type base = local.cadr();
  if (base.is_static() || base.is_extern() || base.is_threaded())
    _auto_fail(
      <parse>, "managed initializer requires automatic local storage", %());
  Type type = local.type();
  if (!type.protocol_member("cleanup")) return %(seq);
  return $!{
    const $type $acquired = $binding;
    defer $acquired.cleanup();
  };
}

// Reports at the block item that holds the managed declaration.
static void _auto_fail(Symbol category, String message, List notes) {
  x2c_diagnostic_fail_at(
    x2c_enclosing(<statement>), category, message, notes);
}

/* foreach

   A collection whose owner declares a matching `try_next` runs a cursor
   loop that calls it directly; any other iterable runs through an Iter. */

/* One `foreach` expansion: its declaration, collection, and body, the
   expressions the declaration binds, the collection's type, and the fresh
   names the macro supplies for the loop's own variables. */
static typedef struct Foreach {
  List declaration, collection, body, targets, type;
  Var iterator, item, pair, object, cursor;
} Foreach;

static List _foreach_expand(
  List declaration, List collection, List body, Var iterator, Var item,
  Var pair, Var object, Var cursor) {
  collection = ((Code) collection).promoted();
  List targets = Code.declared_bindings(declaration);
  Type type = ((Code) collection).type();
  int direct = type == %("Iter");
  List converter = direct ? %() : _converter(type);
  if (targets.len() != 1 && targets.len() != 2)
    x2c_diagnostic_fail(
      "foreach requires one binding or a two-name destructuring declaration",
      %());
  List spec = direct ? %() : _typed_cursor_spec(type, targets);
  if (!direct && !spec) spec = _cursor_spec(type, type, targets.len());
  if (!direct && !converter && !spec) {
    Var printable = type;
    x2c_diagnostic_fail(
      "type " + printable.repr() + " is not iterable",
      %("declare a matching try_next cursor or an Iter protocol adoption"));
  }
  Foreach f = {
    .declaration = declaration, .collection = collection, .body = body,
    .targets = targets, .type = type, .iterator = iterator, .item = item,
    .pair = pair, .object = object, .cursor = cursor};
  if (spec) return _with_cursor(f, spec);
  return _with_iter(f, converter);
}

/* The function that makes an Iter of a `type` value. */
static List _converter(Type type) =>
  type == %("Var") ? MetaContext.function_reference("Var_iter")
                    : type.protocol_member("iter");

/* A source or element owner can supply `int try_next(Source, C *, O *...)`.
   Return its cursor and output types when the source and arity match. */
static List _cursor_spec(Type collection_type, Type owner, int arity) {
  if (!_atom_type(collection_type) || !_atom_type(owner)) return %();
  Code function = _method(owner, "try_next");
  if (!function) return %();
  Type type = function.type();
  List parameters = type.parameters();
  List rest = parameters.cdr();
  Type cursor_parameter = rest ? rest.car() : %();
  List outputs = rest ? rest.cdr() : %();
  if (type.return_type() != %(int) ||
      (owner == collection_type
        ? parameters.car() != collection_type
        : Type.resolve(parameters.car()) != collection_type.resolve()) ||
      !cursor_parameter.canonicalize().is_pointer()) return %();
  Type cursor_type = cursor_parameter.element();
  if (!cursor_type.is_integral() &&
      cursor_type.resolve() != collection_type.resolve())
    return %();
  if (!outputs || (arity == 2 && outputs.len() < 2)) return %();
  if (!_valid_outputs(outputs)) return %();
  List output_types = outputs.map(%!(Type output) => output.element());
  /* A fourth element marks reference parameters. */
  if (cursor_parameter.car() == <*>)
    return %($function $cursor_type $output_types);
  return %($function $cursor_type $output_types reference);
}

/* A requested element can supply a native cursor for this source. Match
   its output exactly before considering the collection's default cursor. */
static List _typed_cursor_spec(Type collection_type, List targets) {
  if (!targets) return %();
  Type requested = Code.type(targets.last());
  List spec = _cursor_spec(collection_type, requested, targets.len());
  if (!spec) return %();
  List outputs = spec[2];
  Type output = targets.len() == 1 ? outputs.last() : outputs[1];
  return output.resolve() == requested.resolve() ? spec : %();
}

/* Whether `type` is named by one String or Symbol. */
static int _atom_type(Var type) {
  if (type is not <list>) return 0;
  List items = type;
  if (items.len() != 1) return 0;
  Var name = items.car();
  return name is <string> || name.kind() == <symbol>;
}

/* Whether each output parameter points to a named type. */
static int _valid_outputs(List outputs) {
  foreach (Type output in outputs)
    if (!output.canonicalize().is_pointer() || !_atom_type(output.element()))
      return 0;
  return 1;
}

/* A cursor loop calls `try_next` with the collection, the cursor, and one
   output per value. A reference parameter takes the object itself; a
   pointer takes its address. */
static List _with_cursor(Foreach &f, List spec) {
  List function = spec[0], cursor_type = spec[1], types = spec[2];
  int by_reference = spec.len() > 3;
  List outputs = types.map(
    %!(Var type) => %($type ${MetaContext.fresh_binding("cursor_output")}));
  List values = outputs.map(%!(List record) => _expr(record[0], record[1]));
  List addresses = by_reference ? values : values.map(
    %!(List value) => _address(value));
  List declarations = outputs.map(
    %!(List record) => _declare(record[0], record[1], %()));
  List object_expression = _expr(f.type, f.object);
  List cursor_expression = _expr(cursor_type, f.cursor);
  List cursor_argument = by_reference ? cursor_expression
    : _address(cursor_expression);
  List condition =
    $!( $function($object_expression, $cursor_argument, @addresses) );
  List loop_body =
    $!{ { @{_cursor_assignments(f.targets, values)} ${f.body} } };
  List initial = Type.resolve(cursor_type) == Type.resolve(f.type)
    ? object_expression : $!( 0 );
  List setup = %(
    ${_declare(f.type, f.object, f.collection)}
    ${_declare(cursor_type, f.cursor, initial)}
    @declarations);
  return _loop(f, condition, loop_body, setup);
}

static List _cursor_assignments(List targets, List outputs) {
  if (targets.len() == 1) return %(${_assign(targets[0], outputs.last())});
  return %(${_assign(targets[0], outputs[0])}
           ${_assign(targets[1], outputs[1])});
}

/* `Iter_try_next` reads each item into a Var; a pair of names takes the
   item's first two elements. */
static List _with_iter(Foreach &f, List converter) {
  List constructor = _iter_constructor(f, converter);
  List item_expression = _expr(%("Var"), f.item);
  List initializer = _x2c_complete_iterator(
    constructor ? _iter_call(constructor, f.collection) : f.collection);
  Code next = MetaContext.function_reference("Iter_try_next");
  List output = next.type().parameters()[1];
  List item_argument = output.car() == <*>
    ? _address(item_expression) : item_expression;
  List condition =
    $!( $next(${_expr(%("Iter"), f.iterator)}, $item_argument) );
  List assignments = f.targets.len() == 1
    ? %(${_assign(f.targets[0], item_expression)})
    : _pair_assignments(f.targets, item_expression, f.pair);
  List loop_body = $!{ { @assignments ${f.body} } };
  List setup = %(
    ${_declare(%("Iter"), f.iterator, initializer)}
    ${_declare(%("Var"), f.item, %())});
  return _loop(f, condition, loop_body, setup);
}

static List _loop(
  Foreach &f, List condition, List body, List setup) {
  return $!{ { ${f.declaration} @setup while ($condition) $body } };
}

/* The function that makes the loop's Iter: the owner's `enumerate` for a
   pair of names, or else the collection's converter. */
static List _iter_constructor(Foreach &f, List converter) {
  List type = f.type;
  int atom = _atom_type(type);
  String owner = atom ? type.car().str() : "";
  List enumerate = %();
  if (f.targets.len() == 2 && atom && type != %("Iter"))
    enumerate = MetaContext.function_reference(owner + "_enumerate");
  return enumerate ? enumerate : converter;
}

static List _iter_call(List function, List collection) =>
  $!Iter{ $function($collection) };

static List _pair_assignments(List targets, List item, Var pair) {
  List first = targets[0], second = targets[1];
  List assignments = $!{
    List $pair = $item;
    $first = $pair[0];
    $second = $pair[1];
  };
  return %($assignments);
}

static List _expr(List type, Var binding) => $!($type){ $binding };

static List _address(List value) => $!( &$value );

static List _declare(Type type, Var binding, List initializer) =>
  initializer ? $!{ $type $binding = $initializer; } : $!{ $type $binding; };

static List _assign(List target, List value) => $!{ $target = $value; };

// foreign aliases and callback adapters

static List _foreign_alias(List declaration, List native) =>
  %((falias $declaration $native));

static List _callback_adapt(List target, List source) =>
  %(expr () (tadapt $target $source));

/* class declarations

   A class declaration receives defaults for the operations it does not
   define: a constructor, heap storage and cleanup, and a Var boxing with
   equality, hashing, and writers. */

static List _class_expand(List capture) {
  String owner = capture[1];
  Type type = capture[2];
  if (!type) return %($capture);
  if (!type.canonicalize().is_pointer() && type.car() == <enum>)
    x2c_diagnostic_fail(
      %"class $owner cannot take an enum value " +
      "representation: Var has no fixed tag for an enum",
      %("give the enum a typedef and name that typedef instead"));
  return %($capture (declaration-recipe class.defaults
    ($owner $type ${MetaContext.invocation_location()})));
}

/* One class declaration: its name `owner`, its declared `type`, and where
   it stands. A heap class is a pointer to its `pointee`, an alias names
   one other type, an aggregate is a struct or union, and a positional
   class is a struct whose fields all have Var forms. The defaults share
   one `value` parameter and Var tag. */
static typedef struct Shape {
  String owner, List type, location, pointee, representation, named;
  int heap, alias, aggregate, positional;
  List parameter, Symbol tag;
} Shape;

static List _class_defaults(String owner, List type, List location) {
  Shape s = _shape(owner, type, location);
  List body = _class_constructor(s);
  if (s.alias) return %(seq @body);
  List release = _release(s);
  if (s.heap && s.aggregate) body = body.append(%(${_alloc(s)}));
  if (s.heap) body = body.append(_cleanup(s, release));
  if (s.aggregate || s.heap) body = body.append(_boxed(s));
  else body = body.append(_scalar(s));
  return %(seq @body);
}

static Shape _shape(String owner, Type type, List location) {
  int heap = type.canonicalize().is_pointer();
  int alias = type.len() == 1 && type.car() is <string>;
  Type pointee = heap ? type.element() : type;
  Type representation = pointee.is_value() ? pointee : pointee.resolve();
  int aggregate = representation.car() == <struct> ||
                  representation.car() == <union>;
  List fields = aggregate ? representation.layout() : %();
  List named = _named(fields);
  int positional = aggregate && representation.car() == <struct> &&
                   _positional(fields);
  Shape s = {
    .owner = owner, .type = type, .location = location, .pointee = pointee,
    .representation = representation, .named = named, .heap = heap,
    .alias = alias, .aggregate = aggregate, .positional = positional};
  s.parameter = _param(%($owner), "value");
  s.tag = Type.tag_name(owner);
  return s;
}

/* The fields a layout names. */
static List _named(List fields) {
  Array named = [];
  foreach (List field in fields)
    if (field.car() is <string> && field.car().str().len() > 0)
      named.push(field);
  return named.list_free();
}

static int _positional(List fields) {
  foreach (List field in fields) if (!Type.is_value(field[1])) return 0;
  return 1;
}

/* The default `new`, unless the class defines one. An aggregate other
   than an alias takes the extra parameters of its own `init`, and an
   alias forwards `new` to the class it names. */
static List _class_constructor(Shape &s) {
  String owner = s.owner;
  if (_own_method(owner, "new")) return %();
  List extras = %();
  List initialize = _own_method(owner, "init");
  if (s.aggregate && !s.alias && initialize) {
    List function = ((Code) initialize).type().car();
    List declared = function[1];
    extras = declared.cdr();
  }
  if (s.heap && !s.aggregate && !((Type) s.pointee).is_value())
    x2c_diagnostic_fail(
      %"class $owner requires an explicit constructor", %());
  List constructor = _new(
    owner, s.representation, s.heap, s.named,
    s.positional && !initialize, extras);
  if (s.alias)
    return %((default-forward ($owner) ${s.type} "new"
      ${constructor[1]}));
  return %($constructor);
}

/* What `free` runs: the class's own `drop` on a set value, then the
   release of the value's storage. */
static List _release(Shape &s) {
  List drop = _own_method(s.owner, "drop");
  List release = drop
    ? $!{
        if (value) ${x2c_ident(((Code) drop).binding_spelling())}(value);
        Scope_free((void *) value);
      }
    : $!{ Scope_free((void *) value); };
  return %($release);
}

/* Zeroed heap storage belongs to the active scope. */
static List _alloc(Shape &s) {
  Type type = %(${s.owner});
  List body = $!{
    $type value = Scope_calloc(1, sizeof(*value));
    return value;
  };
  return _default(s.owner, "alloc", type, %(), %($body));
}

/* Pairs heap release methods with their protocol adoption. */
static List _cleanup(Shape &s, List release) {
  String owner = s.owner;
  List parameter = s.parameter;
  List free_method = _default(
    owner, "free", %(void), %($parameter), release);
  List freed = $!{ value.free(); };
  List cleanup_method = _default(
    owner, "cleanup", %(void), %($parameter), %($freed));
  return %($free_method $cleanup_method
    (adopt ("Cleanup") ($owner) external ${s.location}));
}

/* A heap or aggregate class boxes by its tag, with equality, hashing, and
   writers. */
static List _boxed(Shape &s) {
  List body = _boxing(s);
  body = body.append(_comparison(s));
  body = body.append(_writers(s));
  return body.append(
    %((adopt ("Var") (${s.owner}) external
        (tag ${$!Symbol{ ${s.tag} }}) ${s.location})));
}

/* `var`, and the conversion back: the pointer a heap class boxed, or a
   copy of an aggregate's boxed record. */
static List _boxing(Shape &s) {
  String owner = s.owner;
  Type type = %($owner), pointer = %(* $owner);
  List unboxed = s.heap ? $!( ($type)Var_pointer(value) )
                        : $!( *($pointer)Var_pointer(value) );
  List returned = $!{ return ${_box(s.tag, s.heap)}; };
  List var_method = _default(
    owner, "var", %("Var"), %(${s.parameter}), %($returned));
  return %($var_method ${_unbox(owner, unboxed)});
}

/* `equal` and `hash` of a heap or positional class; a value class of
   another shape must define compatible ones. */
static List _comparison(Shape &s) {
  String owner = s.owner;
  if (s.heap || s.positional)
    return %(${_equal(owner, s.heap, s.named)}
             ${_hash(owner, s.heap, s.named)});
  if (!_method(%($owner), "equal") ||
      !_method(%($owner), "hash"))
    x2c_diagnostic_fail(
      %"value class $owner requires compatible equal " +
      "and hash methods", %());
  return %();
}

/* Supplies missing `str` and `repr` methods. */
static List _writers(Shape &s) {
  String owner = s.owner;
  Array writers = [];
  foreach (String member in %("str" "repr")) {
    List selected = _own_method(owner, member);
    List writer = _own_method(owner, %"write_${member}");
    if (!writer)
      writers.push(_writer(owner, s.heap, s.named, member, selected));
    if (!selected) writers.push(_string_method(owner, member));
  }
  return writers.list_free();
}

/* Boxing uses the underlying representation. */
static List _scalar(Shape &s) {
  String owner = s.owner;
  Type type = %($owner), representation = s.representation;
  List boxed = $!{ return (Var)($representation)value; };
  List unboxed = $!( ($type)($representation)value );
  List var_method = _default(
    owner, "var", %("Var"), %(${s.parameter}), %($boxed));
  return %($var_method ${_unbox(owner, unboxed)}
    (adopt ("Var") ($owner) external $representation ${s.location}));
}

// class constructors

/* The default `new`. A positional struct takes its fields, another
   aggregate takes the extra parameters of its `init`, which a deferred
   initializer calls, and a scalar takes its initial value. */
static List _new(
  String owner, List representation, int heap, List named, int positional,
  List extras) {
  int aggregate = representation.car() == <struct> ||
                  representation.car() == <union>;
  if (!aggregate) return _scalar_new(owner, representation, heap);
  if (positional) return _positional_new(owner, representation, heap, named);
  return _initialized_new(owner, heap, extras);
}

static List _scalar_new(String owner, Type representation, int heap) {
  List parameters = %(${_param(representation, "initial")});
  List value = x2c_ident("value");
  List declaration = $!{ $representation $value = initial; };
  return _finish_new(owner, %($owner), parameters, %($declaration), heap);
}

static List _positional_new(
  String owner, Type representation, int heap, List named) {
  Array parameters = [], arguments = [];
  foreach (List field in named) {
    String name = %"field_${field[0]}";
    parameters.push(_param(_value_type(field[1]), name));
    arguments.push($!( ${x2c_ident(name)} ));
  }
  List value = x2c_ident("value");
  List declaration =
    $!{ $representation $value = { @{arguments.list_free()} }; };
  return _finish_new(
    owner, %($owner), parameters.list_free(), %($declaration), heap);
}

/* Another aggregate starts zeroed, or from `alloc` for a heap class, and
   the deferred initializer calls its `init`. */
static List _initialized_new(
  String owner, int heap, List extras) {
  Type type = %($owner);
  Array parameters = [];
  foreach (List extra in extras)
    parameters.push(_param(extra, %"argument_${parameters.len()}"));
  List value = x2c_ident("value");
  List declaration =
    heap ? $!{ $type $value = ${x2c_ident(%"${owner}_alloc")}(); }
         : $!{ $type $value = { 0 }; };
  Var heap_value = %();
  if (heap) heap_value = <true>;
  List body =
    %($declaration (syntax-recipe class.initializer ($owner $heap_value)));
  return _finish_new(owner, type, parameters.list_free(), body, 0);
}

/* `new` runs `body` and returns the value, or with `copy`, a copy of the
   value in the active scope. */
static List _finish_new(
  String owner, List type, List parameters, List body, int copy) {
  List returned = copy ? $!{ return Scope_memdup(&value, sizeof(value)); }
                       : $!{ return value; };
  return _default(owner, "new", type, parameters, body.append(%($returned)));
}

/* The deferred initializer calls the class's `init` on the value and the
   constructor's arguments. A heap class's `init` may return an int, and
   a zero frees the value and fails `new`. */
static List _class_initializer(String owner, Var heap_value) {
  int heap = heap_value != %();
  List type = %($owner);
  List receiver = heap ? type : $!Type{ $type * };
  Code method = _method(type, "init");
  if (method) {
    List signature = method.type();
    List function = signature.car();
    List declared = function[1];
    int reference = !heap && declared.car() == %(& @type);
    if (reference) receiver = declared.car();
    List parameters = cons(receiver, declared.cdr());
    int refusable = heap && signature == %((func $parameters) int);
    if (refusable || signature == %((func $parameters) void)) {
      List init = x2c_ident(method.binding_spelling());
      List arguments = _init_arguments(parameters);
      List call = heap || reference ? $!( $init(value, @arguments) )
                                    : $!( $init(&value, @arguments) );
      return refusable
        ? $!{ if (!$call) { Scope_free((void *) value); return 0; } }
        : $!{ $call; };
    }
  }
  String suffix = heap ? ")" : " &)";
  x2c_diagnostic_fail(
    %"class $owner requires void $owner.init($owner$suffix", %());
  return %();
}

/* One argument for each of `parameters` after the receiver. */
static List _init_arguments(List parameters) {
  Array arguments = [];
  foreach (List parameter in parameters.cdr())
    arguments.push($!( ${x2c_ident(%"argument_${arguments.len()}")} ));
  return arguments.list_free();
}

// class boxing and comparison

static List _box(Symbol tag, int heap) {
  if (heap) return $!( Var_new($tag, value) );
  return $!( Var_box_record($tag, &value, sizeof(value)) );
}

static List _unbox(String owner, List expression) {
  List returned = $!{ return $expression; };
  return %(default ${_function(
    Type.reverse_name("Var", owner), %($owner),
    %(${_param(%("Var"), "value")}), %($returned))});
}

/* A heap class compares addresses; a value class, each named field's Var
   form. */
static List _equal(String owner, int heap, List fields) {
  List same = $!{ return (void *)left == (void *)right; };
  List body = heap ? %($same) : _fields_equal(fields);
  return _default(
    owner, "equal", %(int),
    %(${_param(%($owner), "left")}
      ${_param(%($owner), "right")}), body);
}

static List _fields_equal(List fields) {
  List left = x2c_ident("left"), right = x2c_ident("right");
  Array body = [];
  foreach (List field in fields) {
    body.push(
      $!{
        if (!Var_equal(
          (Var)${_field_on(field, left)}, (Var)${_field_on(field, right)}))
          return 0;
      });
  }
  body.push($!{ return 1; });
  return body.list_free();
}

/* A heap class hashes its address; a value class combines each named
   field's Var hash. */
static List _hash(String owner, int heap, List fields) {
  List hashed = $!{ return x2c_hash_word((unsigned long)value); };
  List body = heap ? %($hashed) : _fields_hash(fields);
  return _default(
    owner, "hash", %(unsigned),
    %(${_param(%($owner), "value")}), body);
}

/* `hash` is an exact name, so the separately built statements share it. */
static List _fields_hash(List fields) {
  List hash = x2c_ident("hash");
  Array body = [$!{ unsigned $hash = 0; }];
  foreach (List field in fields)
    body.push(
      $!{ $hash = x2c_hash_word(
        $hash ^ Var_hash((Var)${_field_value(field)})); });
  body.push($!{ return $hash; });
  return body.list_free();
}

// class writers

/* `write_str` or `write_repr` for `member`. It calls the class's own
   `member` when there is one. For `str`, a heap class writes its address
   and another class its repr; `repr` writes each field. */
static List _writer(
  String owner, int heap, List fields, String member, List selected) {
  List body;
  List parameters = %(${_param(%($owner), "value")}
                      ${_param(%("Buffer"), "out")});
  if (selected) {
    List written = $!{ return out.write(value.$member()); };
    body = %($written);
  }
  else if (member == "str") {
    List shown = heap ? $!{ return ${_pointer_output(owner, $!( value ))}; }
                      : $!{ return value.write_repr(out); };
    body = %($shown);
  }
  else {
    body = heap ? _repr_guard(owner) : %();
    body = body.append(%((syntax-recipe class.write-fields ($owner $fields))));
  }
  return _default(owner, %"write_${member}", %("Buffer"), parameters, body);
}

/* A heap class writes a NULL value, or one the rendering path has already
   entered, as its address. */
static List _repr_guard(String owner) {
  List address = _pointer_output(owner, $!( value ));
  List guard = $!{
    if ((void *)value == (void *)0) return $address;
    RenderPath path;
    if (!path.enter(value)) return $address;
    defer path.leave();
  };
  return %($guard);
}

/* The deferred body of `write_repr`: `Owner { a: ..., b: ... }`. */
static List _class_write_fields(String owner, List fields) {
  Array body = [$!{ out.write(${%"${owner} { "}); }];
  Var final = fields.last();
  foreach (List field in fields) {
    body.push($!{ out.write(${%"${field[0]}: "}); });
    body.push(_field_write(field));
    if (!field.equal(final)) body.push($!{ out.write(", "); });
  }
  body.push($!{ return out.write(" }"); });
  return %(seq @{body.list_free()});
}

/* One field's repr: its type's own `write_repr`, its Var form's repr, or
   else its address. */
static List _field_write(List field) {
  List value = _field_value(field);
  Type type = field[1];
  int array = 0;
  match (type) case %((dim *) *): array = 1;
  List writer = %();
  if (!array && !type.canonicalize().is_pointer())
    writer = _method(type, "write_repr");
  if (writer) return $!{ $value.write_repr(out); };
  if (!array && type.is_value())
    return $!{ ((Var)$value).write_repr(out); };
  if (!array && !type.resolve().canonicalize().is_pointer())
    value = $!( &$value );
  return $!{ ${_pointer_output("opaque", value)}; };
}

/* `str` or `repr` renders `write_str` or `write_repr` into a Buffer. */
static List _string_method(String owner, String member) {
  String writer = %"write_${member}";
  List body = $!{
    Buffer out = Buffer.new(0);
    defer out.free();
    value.$writer(out);
    return out.str();
  };
  return _default(
    owner, member, %("String"),
    %(${_param(%($owner), "value")}), %($body));
}

static List _pointer_output(String owner, List value) {
  return $!( out.printf(${%"<${owner}: 0x%012lX>"}, (long)$value) );
}

// class syntax

/* The callee a member call `name` on a `type` receiver selects, or an empty
   List. Methods that imported packages each provide are an error. */
static List _method(Type type, String name) {
  match (type.resolve_member(name, 1)) {
    case %(method ?binding ?signature):
      return %(expr $signature (ident $binding));
    case %(ambiguous *packages): {
      Array notes = [];
      foreach (String package in packages) notes.push(%"package: '$package'");
      x2c_diagnostic_fail(
        %"method '${type.base_type().car()}.$name' is provided by " +
        "multiple imported packages", notes.list_free());
    }
  }
  return %();
}

/* The method `member` of `owner` when the class defines it, as opposed
   to one it inherits. */
static List _own_method(String owner, String member) {
  Code found = _method(%($owner), member);
  if (found && found.binding_spelling() == %"${owner}_${member}")
    return found;
  return %();
}

/* `type` without qualifiers or a bitfield width. */
static List _value_type(List type) {
  Array kept = [];
  foreach (Var item in type) {
    if (item == <const> || item == <volatile> || item == <restrict>) continue;
    match (item) case %(bitfield *): continue;
    kept.push(item);
  }
  return kept.list_free();
}

/* The field of `receiver`, cast to its value type when it is a bitfield. */
static List _field_on(List field, List receiver) {
  String name = field[0];
  match (field[1]) case %((bitfield *) *): {
    Type type = _value_type(field[1]);
    return $!( ($type)$receiver.$name );
  }
  return $!( $receiver.$name );
}

static List _field_value(List field) => _field_on(field, x2c_ident("value"));

static List _param(Type type, String name) => type.parameter_ast(%($name));

/* A function with no parameters declares `(void)`, so its prototype is not
   an old-style declaration. */
static List _function(String name, Type result, List parameters, List body) {
  List (base, modifiers) = result.parts();
  if (!parameters) parameters = %((param (void) (bind () ())));
  return %(function $base
    (bind ($name) ((fnmod (params @parameters)) @modifiers))
    (block @body));
}

static List _default(
  String owner, String member, List result, List parameters, List body) =>
  %(default ${_function(%"${owner}_${member}", result, parameters, body)});

/* native Lisp bindings

   `$lisp.binding` records `(group name function type)` rows on the
   expanding compiler while a unit parses, and `$lisp.install` seals a
   group and writes its rows as `Lisp_bind` statements, through the
   `_x2c_binding_*` prototypes of `lib/compiler-meta.x`. */

static List _binding_record(Var group, Var name, List function) {
  Compiler c = Compiler.expanding();
  String group_name = Code.binding_spelling(group);
  String lisp_name = _binding_name(name);
  String function_name = Code.name(function);
  List type = Code.native_signature(function);
  if (group_name in c.binding_sealed)
    x2c_diagnostic_fail(
      "native Lisp binding appears after its group was installed",
      %("group: $group_name"));
  foreach (List row in _binding_rows_for(group_name, c.binding_rows))
    if (row[1] == lisp_name)
      x2c_diagnostic_fail(
        "duplicate native Lisp binding name",
        %("group: $group_name" "name: $lisp_name"));
  c.binding_rows =
    %(($group_name $lisp_name $function_name $type) @{c.binding_rows});
  return NULL;
}

static String _binding_name(Var node) {
  Var value = Code.value(node);
  if (value is <string>) return value;
  x2c_diagnostic_fail(
    "native Lisp binding name requires a String literal",
    %("value: ${node.repr()}"));
  return NULL;
}

static List _binding_rows_for(String group, List rows) {
  Array selected = [];
  foreach (List row in rows) if (row.car() == group) selected.push(row);
  return selected.list_free();
}

static List _binding_install(List lisp, Var group) {
  Compiler c = Compiler.expanding();
  String group_name = Code.binding_spelling(group);
  List rows = _binding_rows_for(group_name, c.binding_rows).reverse();
  if (!rows)
    x2c_diagnostic_fail(
      "unknown native Lisp binding group", %("group: $group_name"));
  if (!(group_name in c.binding_sealed))
    c.binding_sealed = cons(group_name, c.binding_sealed);
  Array statements = [];
  foreach (List row in rows) statements.push(_binding_statement(lisp, row));
  return statements.list_free();
}

static List _binding_statement(List lisp, List row) {
  match (row) case %(?group ?(String name) ?(String function) ?type): {
    List signature = MetaContext.literal_list(type);
    return $!{
      Lisp_bind($lisp, $name, Func_new(${x2c_ident(function)}, $signature));
    };
  }
  return %();
}

static List _binding_call(String name, List arguments) =>
  %(expr () (call ${_binding_ident(name)} (args @arguments)));

static List _binding_ident(String name) =>
  %(expr () (ident ${x2c_ident(name)}));

static List _binding_targets(List rows) {
  Array arguments = [];
  foreach (List row in rows)
    foreach (Var item in _binding_target_row(row)) arguments.push(item);
  return $!(
    Map_update_n(Map_new(), ${rows.len()}, @{arguments.list_free()}) );
}

static List _binding_target_row(List row) {
  match (row) {
    case %(?name (as ?bind)):
      return _binding_target(bind.str(), name.str(), "Func_new");
    case %(?name): return _binding_target(name.str(), name.str(), "Func_new");
    case %(?name ?marker):
      return _binding_target(name.str(), name.str(), "Func_new_rest");
  }
  return %();
}

static List _binding_target(String bind_name, String name, String maker) {
  List func = _binding_call(
    maker,
    %(${_binding_ident(name)}
      ${MetaContext.literal_list(_binding_name_signature(name))}));
  return %(${_binding_call("String_var", %(${$!String{ $bind_name }}))}
    ${_binding_call("Func_var", %($func))});
}

static List _binding_name_signature(String name) =>
  Code.native_signature(MetaContext.function_reference(name));

/* the built-in names

   Each algorithm is reachable by the name its callers use, as are the slot
   functions that compiler quotations call. */

static macro Stmt $builtin.row(Expr $rows, Expr $name, Expr $function) {
  $rows[$name] = (Func) $function;
}

/** Returns a fresh Map of built-in algorithms by their compile-time names.
    The Map borrows shared Func handles that live for the program. */
Map Compiler.builtin_targets(void) {
  Map rows = {};
  $builtin.row(rows, "_x2c_scope_expand", _scope_expand);
  $builtin.row(rows, "_x2c_with_expand", _with_expand);
  $builtin.row(rows, "_x2c_foreach_expand", _foreach_expand);
  $builtin.row(rows, "_x2c_auto_expand", _auto_expand);
  $builtin.row(rows, "_x2c_class_expand", _class_expand);
  $builtin.row(rows, "_x2c_foreign_alias", _foreign_alias);
  $builtin.row(rows, "_x2c_callback_adapt", _callback_adapt);
  $builtin.row(rows, "_x2c_func_call_arguments", _x2c_func_call_arguments);
  $builtin.row(rows, "Ast_defer_captures", Ast.defer_captures);
  $builtin.row(rows, "class.initializer", _class_initializer);
  $builtin.row(rows, "class.write-fields", _class_write_fields);
  $builtin.row(rows, "class.defaults", _class_defaults);
  $builtin.row(rows, "_x2c_auto_release", _auto_release);
  $builtin.row(rows, "_x2c_binding_record", _binding_record);
  $builtin.row(rows, "_x2c_binding_install", _binding_install);
  $builtin.row(rows, "_x2c_target_map", _binding_targets);
  Compiler.add_sdk_targets(rows);
  return rows;
}
