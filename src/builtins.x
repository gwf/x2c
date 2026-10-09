/*  builtins.x -- the built-in macros' compile-time algorithms

    Copyright (c) 2026 Gary William Flake.

    The built-in macros expand through these functions, which run as native
    code inside the compiler. The compile-time Lisp in
    `etc/builtin-core.xlisp` and `etc/lisp-bindings.xlisp` calls them by
    name, and `builtin_targets` binds each into the shared session.
*/
#pragma once
#include "x2c.x"
#include "meta.x"
#include "grammar.x"
#include "lisp.x"
#include "macros.x"
#include "transform.x"

/* The `lib/meta.x` builder that reaches the compiler runs here as the copy
   `src/linked-meta.x` links. */
// lint: allow src-forward-declaration FI-6: linked native copy
List x2c_param_make(List type, Var name);

// $scope

static List _scope_expand(List body, List destinations) {
  if (destinations.len() > 1)
    x2c_diagnostic_fail("$scope accepts zero or one destination", %());
  List enter = destinations ? $!( Scope_push(@destinations) )
                            : $!( Scope_retain() );
  List leave = destinations ? $!( Scope_pop() ) : $!( Scope_release() );
  return $!{ { $enter; { defer $leave; $body } } };
}

// $auto

/* The release placed after a managed declarator: its checks, then the
   deferred cleanup of the declared binding. */
static macro Stmt $auto_release(Decl $local, Expr $binding) {
  @(auto.release $local)
  defer $binding.cleanup();
}

/* `$auto(value)` returns `value` and places the release after the
   declarator it initializes. The declaration checks that the result is its
   complete initializer before it binds the release, so a partial use
   reports that first. */
static List _auto_expand(List value) {
  Code local = x2c_enclosing(<declarator>);
  if (!local || !x2c_enclosing(<function>))
    _auto_fail(<parse>,
      "managed initializer requires a complete block-local initializer",
      %());
  match (local) case %(declare ? (bindings (bind ?binding ?))): {
    Macro release = $auto_release;
    x2c_place(%(after-statement),
      x2c_template_call(release, %($local $binding)));
  }
  return value;
}

/* A managed declaration has automatic storage and a type that participates
   in Cleanup. */
static List _auto_release(Code local) {
  Type base = local.cadr();
  if (base.is_static() || base.is_extern() || base.is_threaded())
    _auto_fail(<parse>,
      "managed initializer requires automatic local storage", %());
  Type type = local.type();
  if (!type.protocol_member("cleanup"))
    _auto_fail(<protocol>,
      "managed initializer requires Cleanup participation",
      %("type: ${type.repr()}"));
  return NULL;
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
  collection = builtin_foreach_collection(collection);
  List targets = builtin_foreach_bindings(declaration);
  List type = x2c_syntax_type(collection);
  int direct = type == %("Iter");
  List converter = direct ? %() : _converter(type);
  List spec = direct ? %() : _cursor_spec(type);
  if (targets.len() != 1 && targets.len() != 2)
    x2c_diagnostic_fail(
      "foreach requires one binding or a two-name destructuring declaration",
      %());
  if (!direct && !converter) {
    Var printable = type;
    x2c_diagnostic_fail(
      "type " + printable.repr() + " is not iterable",
      %("declare an Iter protocol adoption or iterate an Iter directly"));
  }
  Foreach f = {
    .declaration = declaration, .collection = collection, .body = body,
    .targets = targets, .type = type, .iterator = iterator, .item = item,
    .pair = pair, .object = object, .cursor = cursor};
  if (spec && (targets.len() == 1 || List.len(spec[2]) >= 2))
    return f.with_cursor(spec);
  return f.with_iter(converter);
}

/* The function that makes an Iter of a `type` value. */
static List _converter(List type) =>
  type == %("Var") ? builtin_foreach_reference("Var_iter")
                    : x2c_protocol_member(type, %("Iter"), "iter");

/* The cursor loop's `(function cursor-type output-types)` for a
   collection whose owner declares `int T_try_next(T, C *, O *...)` with an
   integral cursor or one of the collection's own type, or else an empty
   List. */
static List _cursor_spec(List collection_type) {
  if (!_atom_type(collection_type)) return %();
  String owner = collection_type.car().str();
  List function = builtin_foreach_reference(owner + "_try_next");
  if (!function) return %();
  List type = x2c_syntax_type(function);
  List parameters = x2c_type_parameters(type);
  List rest = parameters.cdr();
  List cursor_parameter = rest ? rest.car() : %();
  List outputs = rest ? rest.cdr() : %();
  if (x2c_type_return(type) != %(int) ||
      parameters.car() != collection_type ||
      !x2c_type_is_pointer(cursor_parameter)) return %();
  List cursor_type = x2c_type_element(cursor_parameter);
  if (!x2c_type_is_integral(cursor_type) &&
      cursor_type != collection_type) return %();
  if (!outputs) return %();
  if (!_valid_outputs(outputs)) return %();
  List output_types = outputs.map(%!(Var output) => x2c_type_element(output));
  /* A fourth element marks reference parameters. */
  if (cursor_parameter.car() == <*>)
    return %($function $cursor_type $output_types);
  return %($function $cursor_type $output_types reference);
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
  foreach (List output, outputs)
    if (!x2c_type_is_pointer(output) ||
        !_atom_type(x2c_type_element(output))) return 0;
  return 1;
}

/* A cursor loop calls `try_next` with the collection, the cursor, and one
   output per value. A reference parameter takes the object itself; a
   pointer takes its address. */
static List Foreach.with_cursor(Foreach &f, List spec) {
  List function = spec[0], cursor_type = spec[1], types = spec[2];
  int by_reference = spec.len() > 3;
  List outputs = types.map(
    %!(Var type) => %($type ${builtin_foreach_unique("cursor_output")}));
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
  List initial = cursor_type == f.type ? object_expression : $!( 0 );
  List setup = %(
    ${_declare(f.type, f.object, f.collection)}
    ${_declare(cursor_type, f.cursor, initial)}
    @declarations);
  return f.loop(condition, loop_body, setup);
}

static List _cursor_assignments(List targets, List outputs) {
  if (targets.len() == 1) return %(${_assign(targets[0], outputs.last())});
  return %(${_assign(targets[0], outputs[0])}
           ${_assign(targets[1], outputs[1])});
}

/* `Iter_try_next` reads each item into a Var; a pair of names takes the
   item's first two elements. */
static List Foreach.with_iter(Foreach &f, List converter) {
  List constructor = f.constructor(converter);
  List item_expression = _expr(%("Var"), f.item);
  List initializer = builtin_foreach_complete(
    constructor ? _iter_call(constructor, f.collection) : f.collection);
  List next = builtin_foreach_reference("Iter_try_next");
  List output = x2c_type_parameters(x2c_syntax_type(next))[1];
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
  return f.loop(condition, loop_body, setup);
}

static List Foreach.loop(
  Foreach &f, List condition, List body, List setup) {
  return $!{ { ${f.declaration} @setup while ($condition) $body } };
}

/* The function that makes the loop's Iter: the owner's `enumerate` for a
   pair of names, or else the collection's converter. */
static List Foreach.constructor(Foreach &f, List converter) {
  List type = f.type;
  int atom = _atom_type(type);
  String owner = atom ? type.car().str() : "";
  List enumerate = %();
  if (f.targets.len() == 2 && atom && type != %("Iter"))
    enumerate = builtin_foreach_reference(owner + "_enumerate");
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

/* class declarations

   A class declaration receives defaults for the operations it does not
   define: a constructor, heap storage and cleanup, and a Var boxing with
   equality, hashing, and writers. */

static List _class_expand(List capture) {
  String owner = capture[1];
  List type = capture[2];
  if (!type) return %($capture);
  if (!x2c_type_is_pointer(type) && type.car() == <enum>)
    x2c_diagnostic_fail(
      %"class $owner cannot take an enum value " +
      "representation: Var has no fixed tag for an enum",
      %("give the enum a typedef and name that typedef instead"));
  return %($capture (declaration-recipe class.defaults
    ($owner $type ${builtin_class_location()})));
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
  List body = s.constructor();
  if (s.alias) return %(seq @body);
  List release = s.release();
  if (s.heap && s.aggregate) body = body.append(%(${s.alloc()}));
  if (s.heap) body = body.append(s.cleanup(release));
  if (s.aggregate || s.heap) body = body.append(s.boxed());
  else body = body.append(s.scalar());
  return %(seq @body);
}

static Shape _shape(String owner, List type, List location) {
  int heap = x2c_type_is_pointer(type);
  int alias = type.len() == 1 && type.car() is <string>;
  List pointee = heap ? x2c_type_element(type) : type;
  List representation = x2c_type_is_value(pointee) ? pointee :
                        x2c_type_resolve(pointee);
  int aggregate = representation.car() == <struct> ||
                  representation.car() == <union>;
  List fields = aggregate ? x2c_type_layout(representation) : %();
  List named = _named(fields);
  int positional = aggregate && representation.car() == <struct> &&
                   _positional(fields);
  Shape s = {
    .owner = owner, .type = type, .location = location, .pointee = pointee,
    .representation = representation, .named = named, .heap = heap,
    .alias = alias, .aggregate = aggregate, .positional = positional};
  s.parameter = x2c_param_make(%($owner), "value");
  s.tag = x2c_type_tag_name(owner);
  return s;
}

/* The fields a layout names. */
static List _named(List fields) {
  Array named = [];
  foreach (List field, fields)
    if (field.car() is <string> && field.car().str().len() > 0)
      named.push(field);
  return named.list_free();
}

static int _positional(List fields) {
  foreach (List field, fields) if (!x2c_type_is_value(field[1])) return 0;
  return 1;
}

/* The default `new`, unless the class defines one. An aggregate other
   than an alias takes the extra parameters of its own `init`, and an
   alias forwards `new` to the class it names. */
static List Shape.constructor(Shape &s) {
  String owner = s.owner;
  if (_own_method(owner, "new")) return %();
  List extras = %();
  List initialize = _own_method(owner, "init");
  if (s.aggregate && !s.alias && initialize) {
    List function = x2c_syntax_type(initialize).car();
    List declared = function[1];
    extras = declared.cdr();
  }
  if (s.heap && !s.aggregate && !x2c_type_is_value(s.pointee))
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
static List Shape.release(Shape &s) {
  List drop = _own_method(s.owner, "drop");
  List release = drop
    ? $!{
        if (value) ${_ref(x2c_binding_spelling(drop))}(value);
        Scope_free(value);
      }
    : $!{ Scope_free(value); };
  return %($release);
}

/* A heap aggregate's `alloc` returns zeroed storage in the active scope. */
static List Shape.alloc(Shape &s) {
  Type type = %(${s.owner});
  List body = $!{
    $type value = Scope_calloc(1, sizeof(*value));
    return value;
  };
  return _default(s.owner, "alloc", type, %(), %($body));
}

/* A heap class's `free` and `cleanup`, and its Cleanup adoption. */
static List Shape.cleanup(Shape &s, List release) {
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
static List Shape.boxed(Shape &s) {
  List body = s.boxing();
  body = body.append(s.comparison());
  body = body.append(s.writers());
  return body.append(
    %((adopt ("Var") (${s.owner}) external
        (tag ${x2c_literal_symbol(s.tag)}) ${s.location})));
}

/* `var`, and the conversion back: the pointer a heap class boxed, or a
   copy of an aggregate's boxed record. */
static List Shape.boxing(Shape &s) {
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
static List Shape.comparison(Shape &s) {
  String owner = s.owner;
  if (s.heap || s.positional)
    return %(${_equal(owner, s.heap, s.named)}
             ${_hash(owner, s.heap, s.named)});
  if (!x2c_method_resolve(%($owner), "equal") ||
      !x2c_method_resolve(%($owner), "hash"))
    x2c_diagnostic_fail(
      %"value class $owner requires compatible equal " +
      "and hash methods", %());
  return %();
}

/* The `str` and `repr` writers and methods the class does not define. */
static List Shape.writers(Shape &s) {
  String owner = s.owner;
  Array writers = [];
  foreach (Var member_value, %("str" "repr")) {
    String member = member_value.str();
    List selected = _own_method(owner, member);
    List writer = _own_method(owner, %"write_${member}");
    if (!writer)
      writers.push(_writer(owner, s.heap, s.named, member, selected));
    if (!selected) writers.push(_string_method(owner, member));
  }
  return writers.list_free();
}

/* A scalar class boxes as its representation. */
static List Shape.scalar(Shape &s) {
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
  List parameters = %(${x2c_param_make(representation, "initial")});
  List value = x2c_ident("value");
  List declaration = $!{ $representation $value = initial; };
  return _finish_new(owner, %($owner), parameters, %($declaration), heap);
}

static List _positional_new(
  String owner, Type representation, int heap, List named) {
  Array parameters = [], arguments = [];
  foreach (List field, named) {
    String name = %"field_${field[0]}";
    parameters.push(x2c_param_make(_value_type(field[1]), name));
    arguments.push(_ref(name));
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
  foreach (List extra, extras)
    parameters.push(x2c_param_make(extra, %"argument_${parameters.len()}"));
  List value = x2c_ident("value");
  List declaration =
    heap ? $!{ $type $value = ${_ref(%"${owner}_alloc")}(); }
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
  List method = x2c_method_resolve(type, "init");
  if (method) {
    List signature = x2c_syntax_type(method);
    List function = signature.car();
    List declared = function[1];
    int reference = !heap && declared.car() == %(& @type);
    if (reference) receiver = declared.car();
    List parameters = cons(receiver, declared.cdr());
    int refusable = heap && signature == %((func $parameters) int);
    if (refusable || signature == %((func $parameters) void)) {
      List init = _ref(x2c_binding_spelling(method));
      List arguments = _init_arguments(parameters);
      List call = heap || reference ? $!( $init(value, @arguments) )
                                    : $!( $init(&value, @arguments) );
      return refusable ? $!{ if (!$call) { Scope_free(value); return 0; } }
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
  foreach (List parameter, parameters.cdr())
    arguments.push(_ref(%"argument_${arguments.len()}"));
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
    x2c_type_reverse_name("Var", owner), %($owner),
    %(${x2c_param_make(%("Var"), "value")}), %($returned))});
}

/* A heap class compares addresses; a value class, each named field's Var
   form. */
static List _equal(String owner, int heap, List fields) {
  List same = $!{ return (void *)left == (void *)right; };
  List body = heap ? %($same) : _fields_equal(fields);
  return _default(
    owner, "equal", %(int),
    %(${x2c_param_make(%($owner), "left")}
      ${x2c_param_make(%($owner), "right")}), body);
}

static List _fields_equal(List fields) {
  List left = _ref("left"), right = _ref("right");
  Array body = [];
  foreach (List field, fields) {
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
    %(${x2c_param_make(%($owner), "value")}), body);
}

/* `hash` is an exact name, so the separately built statements share it. */
static List _fields_hash(List fields) {
  List hash = x2c_ident("hash");
  Array body = [$!{ unsigned $hash = 0; }];
  foreach (List field, fields)
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
  List parameters = %(${x2c_param_make(%($owner), "value")}
                      ${x2c_param_make(%("Buffer"), "out")});
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
  foreach (List field, fields) {
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
  List value = _field_value(field), type = field[1];
  int array = 0;
  match (type) case %((dim *) *): array = 1;
  List writer = %();
  if (!array && !x2c_type_is_pointer(type))
    writer = x2c_method_resolve(type, "write_repr");
  if (writer) return $!{ $value.write_repr(out); };
  if (!array && x2c_type_is_value(type))
    return $!{ ((Var)$value).write_repr(out); };
  if (!array && !x2c_type_is_pointer(x2c_type_resolve(type)))
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
    %(${x2c_param_make(%($owner), "value")}), %($body));
}

static List _pointer_output(String owner, List value) {
  return $!( out.printf(${%"<${owner}: 0x%012lX>"}, (long)$value) );
}

// class syntax

/* The method `member` of `owner` when the class defines it, as opposed
   to one it inherits. */
static List _own_method(String owner, String member) {
  List found = x2c_method_resolve(%($owner), member);
  if (found && x2c_binding_spelling(found) == %"${owner}_${member}")
    return found;
  return %();
}

/* `type` without qualifiers or a bitfield width. */
static List _value_type(List type) {
  Array kept = [];
  foreach (Var item, type) {
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

static List _field_value(List field) => _field_on(field, _ref("value"));

static List _ref(String name) => x2c_expr_ident(%($name));

static List _function(String name, List result, List parameters, List body) {
  List parts = x2c_type_parts(result);
  return %(function ${parts[0]}
    (bind ($name) ((fnmod (params @parameters)) @{parts[1]}))
    (block @body));
}

static List _default(
  String owner, String member, List result, List parameters, List body) =>
  %(default ${_function(%"${owner}_${member}", result, parameters, body)});

/* native Lisp bindings

   `$lisp.bind` records `(group name function type)` rows while a unit
   parses and installs a group's rows as `Lisp_bind` statements. Each
   function here is `_x2c.binding_*` in the compile-time Lisp. */

static List _binding_record(
  Var group, Var name, List function, List all_rows, List sealed) {
  String group_name = x2c_binding_spelling(group);
  String lisp_name = _binding_name(name);
  String function_name = x2c_function_name(function);
  List type = binding_native_type(function);
  List rows = _binding_rows_for(group_name, all_rows);
  foreach (Var installed, sealed)
    if (installed == group_name)
      x2c_diagnostic_fail(
        "native Lisp binding appears after its group was installed",
        %("group: $group_name"));
  foreach (List row, rows)
    if (row[1] == lisp_name)
      x2c_diagnostic_fail(
        "duplicate native Lisp binding name",
        %("group: $group_name" "name: $lisp_name"));
  return %(($group_name $lisp_name $function_name $type) @all_rows);
}

static String _binding_name(Var node) {
  Var value = x2c_literal_value(node);
  if (value is <string>) return value;
  x2c_diagnostic_fail(
    "native Lisp binding name requires a String literal",
    %("value: ${node.repr()}"));
  return NULL;
}

static List _binding_rows_for(String group, List rows) {
  Array selected = [];
  foreach (List row, rows) if (row.car() == group) selected.push(row);
  return selected.list_free();
}

static List _binding_install_rows(String group, List all_rows) {
  List rows = _binding_rows_for(group, all_rows).reverse();
  if (!rows)
    x2c_diagnostic_fail(
      "unknown native Lisp binding group", %("group: $group"));
  return rows;
}

static List _binding_statements(List lisp, List rows) {
  Array statements = [];
  foreach (List row, rows) statements.push(_binding_statement(lisp, row));
  return statements.list_free();
}

static List _binding_statement(List lisp, List row) {
  match (row) case %(?group ?(String name) ?(String function) ?type): {
    List signature = binding_literal_list(type);
    return $!{
      Lisp_bind($lisp, $name, Func_new(${x2c_ident(function)}, $signature));
    };
  }
  return %();
}

static List _binding_call(String name, List arguments) =>
  x2c_expr_call(x2c_expr_ident(x2c_ident(name)), arguments);

static List _binding_targets(List rows) {
  Array arguments = [];
  foreach (List row, rows)
    foreach (Var item, _binding_target_row(row)) arguments.push(item);
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
    %(${x2c_expr_ident(x2c_ident(name))}
      ${binding_literal_list(_binding_name_signature(name))}));
  return %(${_binding_call("String_var", %(${x2c_literal_string(bind_name)}))}
    ${_binding_call("Func_var", %($func))});
}

static List _binding_name_signature(String name) =>
  binding_native_type(builtin_foreach_reference(name));

/* the Lisp names

   Each algorithm is bound into the compile-time Lisp session under the
   name its callers use, as are the slot functions that the try templates
   in `src/transform.x` call. */

static macro Stmt $builtin.row(Expr $rows, Expr $name, Expr $function) {
  $rows[$name] = Func.new(
    $function, $(_x2c.literal.list (_x2c.function.native-type $function)));
}

/** Places the lowered statements that leave a try region after it, with
    the effect that marks the unit as needing exception support. */
List builtin_try_cleanup_placement(Var cleanup) {
  Atom token = Atom.intern("?__try_cleanup");
  match (cleanup)
    case %(code-value ? ?statements ?):
      return %(code-value "lowered" $token ((cleanup $token $statements)));
  x2c_diagnostic_fail("try cleanup must be lowered statements", %());
  return NULL;
}

/** Returns each built-in algorithm by the name compile-time code calls it
    with. */
Map builtin_targets(void) {
  Map rows = {};
  $builtin.row(rows, "builtin_scope_expand", _scope_expand);
  $builtin.row(rows, "x2c_func_call_arguments", x2c_func_call_arguments);
  $builtin.row(rows, "builtin_defer_captures", builtin_defer_captures);
  $builtin.row(rows, "builtin_try_catch_site", builtin_try_catch_site);
  $builtin.row(rows, "builtin_try_landing", builtin_try_landing);
  $builtin.row(rows, "builtin_catch_patterns", builtin_catch_patterns);
  $builtin.row(rows, "builtin_catch_cases", builtin_catch_cases);
  $builtin.row(
    rows, "builtin_try_cleanup_placement", builtin_try_cleanup_placement);
  $builtin.row(rows, "builtin_foreach_expand", _foreach_expand);
  $builtin.row(rows, "builtin_auto_expand", _auto_expand);
  $builtin.row(rows, "builtin_auto_release", _auto_release);
  $builtin.row(rows, "builtin_class_initializer", _class_initializer);
  $builtin.row(rows, "builtin_class_write_fields", _class_write_fields);
  $builtin.row(rows, "builtin_class_expand", _class_expand);
  $builtin.row(rows, "builtin_class_defaults", _class_defaults);
  $builtin.row(rows, "binding_call", _binding_call);
  $builtin.row(rows, "binding_name", _binding_name);
  $builtin.row(rows, "binding_rows_for", _binding_rows_for);
  $builtin.row(rows, "binding_record", _binding_record);
  $builtin.row(rows, "binding_statement", _binding_statement);
  $builtin.row(rows, "binding_install_rows", _binding_install_rows);
  $builtin.row(rows, "binding_statements", _binding_statements);
  $builtin.row(rows, "binding_target", _binding_target);
  $builtin.row(rows, "binding_target_row", _binding_target_row);
  $builtin.row(rows, "binding_targets", _binding_targets);
  return rows;
}
