// SYNTAX TEST "source.x2c" "current x2c grammar"

in item;
// <- keyword.control.x2c
// <- keyword.control.in.x2c
try work();
// <- keyword.control.x2c
// <- keyword.control.try.x2c
catch (Exception error) {}
// <- keyword.control.x2c
// <- keyword.control.catch.x2c
finally cleanup();
// <- keyword.control.x2c
// <- keyword.control.finally.x2c
defer cleanup();
// <- keyword.control.x2c
// <- keyword.control.defer.x2c
raise error;
// <- keyword.control.x2c
// <- keyword.control.raise.x2c
match (value) {}
// <- keyword.control.x2c
// <- keyword.control.match.x2c
void nested_x2c_syntax(void) {
  foreach (Var item, items)
//^^^^^^^ keyword.control.foreach.x2c
    consume(item);
  match (item) {
//^^^^^ keyword.control.match.x2c
    raise %(bad-item);
//  ^^^^^ keyword.control.raise.x2c
  }
  catch %(bad-item): recover();
//^^^^^ keyword.control.catch.x2c
  consume(%!(int value) => value);
//                      ^^ keyword.operator.arrow.x2c
}
int macro = 0;
//  ^^^^^ - keyword.declaration.macro.x2c
int using = 0;
//  ^^^^^ - keyword.other.macro.using.x2c

protocol Reading(T) {
// <-------- keyword.declaration.protocol.x2c
  associated Value = Var;
//^^^^^^^^^^ keyword.declaration.protocol.x2c
}
protocol Var(Row) as List;
//                ^^ keyword.declaration.protocol.x2c
//                   ^^^^ support.type.prelude.x2c
protocol Var(ArrayString) tag <arraystr>;
//                        ^^^ keyword.declaration.protocol.x2c
static protocol Prepared(LocalPlan);
//     ^^^^^^^^ keyword.declaration.protocol.x2c
meta protocol Iter(List);
// <- storage.modifier.meta.x2c
//   ^^^^^^^^ keyword.declaration.protocol.x2c
meta static protocol Prepared(Plan);
// <- storage.modifier.meta.x2c
//          ^^^^^^^^ keyword.declaration.protocol.x2c
meta static int compile_only(void);
// <- storage.modifier.meta.x2c
meta native int runtime_only(void) { return 0; }
// <- storage.modifier.meta.x2c
//   ^^^^^^ storage.modifier.native.x2c
meta native static int local_runtime(void) { return 0; }
//   ^^^^^^ storage.modifier.native.x2c
int native = 0;
//  ^^^^^^ - storage.modifier.native.x2c
native();
// <- - storage.modifier.native.x2c
int meta = 0;
//  ^^^^ - storage.modifier.meta.x2c
typedef int meta;
meta value;
// <- - storage.modifier.meta.x2c
meta();
// <- - storage.modifier.meta.x2c
meta = 1;
// <- - storage.modifier.meta.x2c

  delegate Reader reader;
//^^^^^^^^ storage.modifier.x2c
//^^^^^^^^ storage.modifier.delegate.x2c
  threaded int depth;
//^^^^^^^^ storage.modifier.x2c
//^^^^^^^^ storage.modifier.threaded.x2c
  thread_local int local_depth;
//^^^^^^^^^^^^ storage.modifier.x2c
//^^^^^^^^^^^^ - storage.modifier.thread_local.x2c
  _Thread_local int c_depth;
//^^^^^^^^^^^^^ storage.modifier.x2c
//^^^^^^^^^^^^^ - storage.modifier._Thread_local.x2c
Self List.cdr(Self values);
// <--- storage.type.self.x2c
//            ^^^^ storage.type.self.x2c
int Self = 0;
//  ^^^^ - storage.type.self.x2c

Array prelude_array;
// <--- support.type.prelude.x2c
Atom prelude_atom;
// <-- support.type.prelude.x2c
Block prelude_block;
// <--- support.type.prelude.x2c
Buffer prelude_buffer;
// <---- support.type.prelude.x2c
Bytes prelude_bytes;
// <--- support.type.prelude.x2c
Context prelude_context;
// <----- support.type.prelude.x2c
Error prelude_error;
// <--- support.type.prelude.x2c
ErrorHandler prelude_error_handler;
// <---------- support.type.prelude.x2c
File prelude_file;
// <-- support.type.prelude.x2c
Func prelude_func;
// <-- support.type.prelude.x2c
Iter prelude_iter;
// <-- support.type.prelude.x2c
Lambda prelude_lambda;
// <---- support.type.prelude.x2c
Lisp prelude_lisp;
// <-- support.type.prelude.x2c
List prelude_list;
// <-- support.type.prelude.x2c
Logger prelude_logger;
// <---- support.type.prelude.x2c
LogSink prelude_log_sink;
// <----- support.type.prelude.x2c
Map prelude_map;
// <- support.type.prelude.x2c
Mutex prelude_mutex;
// <--- support.type.prelude.x2c
Pool prelude_pool;
// <-- support.type.prelude.x2c
Scope prelude_scope;
// <--- support.type.prelude.x2c
Split prelude_split;
// <--- support.type.prelude.x2c
String prelude_string;
// <---- support.type.prelude.x2c
Symbol prelude_symbol;
// <---- support.type.prelude.x2c
SymbolSet prelude_symbol_set;
// <------- support.type.prelude.x2c
Thread prelude_thread;
// <---- support.type.prelude.x2c
Token prelude_token;
// <--- support.type.prelude.x2c
Tokenizer prelude_tokenizer;
// <------- support.type.prelude.x2c
Var prelude_var;
// <- support.type.prelude.x2c
DisjointSet user_type;
// <--------- - support.type.prelude.x2c
IterNextFn callback_type;
// <-------- - support.type.prelude.x2c
MapState implementation_record;
// <------ - support.type.prelude.x2c
// Array List Map Iter are not types inside comments.
// ^^^^^ - support.type.prelude.x2c
const char *type_names = "Array List Map Iter";
//                         ^^^^^ - support.type.prelude.x2c

keyword swap $project.swap;
// <----- keyword.declaration.macro.x2c
//      ^^^^ entity.name.function.macro-alias.x2c
//           ^ punctuation.definition.macro.sigil.x2c
//            ^^^^^^^^^^^^ entity.name.function.macro.x2c
keyword exchange $swap;
// <----- keyword.declaration.macro.x2c
//               ^ punctuation.definition.macro.sigil.x2c
keyword List $project.list;
//      ^^^^ entity.name.function.macro-alias.x2c
//      ^^^^ - support.type.prelude.x2c
static keyword hidden_swap $swap;
// <- storage.modifier.x2c
//     ^^^^^^^ keyword.declaration.macro.x2c
//             ^^^^^^^^^^^ entity.name.function.macro-alias.x2c
//                         ^ punctuation.definition.macro.sigil.x2c
//                          ^^^^ entity.name.function.macro.x2c
int keyword = 0;
//  ^^^^^^^ - keyword.declaration.macro.x2c

import "pcre2" with Regexp, RegexpMatch;
// <------ keyword.control.import.x2c
//             ^^^^ keyword.control.import.x2c
import "geo" as g with Vec as V;
// <------ keyword.control.import.x2c
//           ^^ keyword.control.import.x2c
//                ^^^^ keyword.control.import.x2c
//                         ^^ keyword.control.import.x2c

with (point.x = 1, point.y = 2) {
// <---- keyword.control.with.x2c
  point.x = 3;
}
if (ready) with (mode = quiet) {
//         ^^^^ keyword.control.with.x2c
}
else with (depth = depth + 1) {
//   ^^^^ keyword.control.with.x2c
}
$lock(mutex) with (scale = 2) {
//           ^^^^ keyword.control.with.x2c
}
int with = 0;
//  ^^^^ - keyword.control.with.x2c
int with(int value) { return value; }
//  ^^^^ - keyword.control.with.x2c
value = with(3);
//      ^^^^ - keyword.control.with.x2c
alias point.settings as settings;
// <----- keyword.declaration.alias.x2c
//                   ^^ keyword.declaration.alias.x2c
static alias origin as home;
//     ^^^^^ keyword.declaration.alias.x2c
//                  ^^ keyword.declaration.alias.x2c
alias point as local {
// <----- keyword.declaration.alias.x2c
//          ^^ keyword.declaration.alias.x2c
  local.x = 1;
}
if (ready) alias point {
//         ^^^^^ keyword.declaration.alias.x2c
  _.x = 2;
}
alias point.x as px:
// <----- keyword.declaration.alias.x2c
//            ^^ keyword.declaration.alias.x2c
int alias = 3;
//  ^^^^^ - keyword.declaration.alias.x2c
alias += 1;
// <----- - keyword.declaration.alias.x2c
printf("%d\n", alias);
//             ^^^^^ - keyword.declaration.alias.x2c
alias(value);
// <----- - keyword.declaration.alias.x2c
unalias settings;
// <------- keyword.declaration.alias.x2c
int unalias = 1;
//  ^^^^^^^ - keyword.declaration.alias.x2c
unalias += 1;
// <------- - keyword.declaration.alias.x2c

  Var (first, second) = values;
//    ^ punctuation.section.parens.begin.destructuring.x2c
//     ^^^^^ variable.other.readwrite.destructuring.x2c
//          ^ punctuation.separator.destructuring.x2c
//            ^^^^^^ variable.other.readwrite.destructuring.x2c
//                  ^ punctuation.section.parens.end.destructuring.x2c
  (int index, const String label) = values;
//^ punctuation.section.parens.begin.destructuring.x2c
//     ^^^^^ variable.other.readwrite.destructuring.x2c
//          ^ punctuation.separator.destructuring.x2c
//                         ^^^^^ variable.other.readwrite.destructuring.x2c
//                              ^ punctuation.section.parens.end.destructuring.x2c
  (first, second) = values;
//^ punctuation.section.parens.begin.destructuring.x2c
// ^^^^^ variable.other.readwrite.destructuring.x2c
//      ^ punctuation.separator.destructuring.x2c
//        ^^^^^^ variable.other.readwrite.destructuring.x2c
//              ^ punctuation.section.parens.end.destructuring.x2c
  Values copy = (first) = values;
//              ^ punctuation.section.parens.begin.destructuring.x2c
//               ^^^^^ variable.other.readwrite.destructuring.x2c
//                    ^ punctuation.section.parens.end.destructuring.x2c
  return (first, second) = values;
//       ^ punctuation.section.parens.begin.destructuring.x2c
  call((first, second) = values);
//     ^ punctuation.section.parens.begin.destructuring.x2c
foreach(Var (key, value), map) {
// <------ keyword.control.foreach.x2c
//      ^^^ support.type.prelude.x2c
//          ^ punctuation.section.parens.begin.destructuring.x2c
//           ^^^ variable.other.readwrite.destructuring.x2c
//              ^ punctuation.separator.destructuring.x2c
//                ^^^^^ variable.other.readwrite.destructuring.x2c
//                     ^ punctuation.section.parens.end.destructuring.x2c
}
  int (*callback)(int) = handler;
//     ^ - punctuation.section.parens.begin.destructuring.x2c
  Var (single) = value;
//    ^ - punctuation.section.parens.begin.destructuring.x2c
  (record.field) = value;
//^ - punctuation.section.parens.begin.destructuring.x2c
  (array[index]) = value;
//^ - punctuation.section.parens.begin.destructuring.x2c
  (*pointer) = value;
//^ - punctuation.section.parens.begin.destructuring.x2c

int tagged = value is <string>;
//                 ^^ keyword.operator.is.x2c
int untagged = value is not <string>;
//                   ^^^^^^ keyword.operator.is.x2c

macro expression $project.make(expr $value, type $kind) => ($value) + 1;
// <---- keyword.declaration.macro.x2c
//    ^^^^^^^^^^ storage.type.macro.result.x2c
//               ^ punctuation.definition.macro.sigil.x2c
//                ^^^^^^^^^^^^ entity.name.function.macro.x2c
//                             ^^^^ storage.type.macro.hole.x2c
//                                  ^ punctuation.definition.macro.sigil.x2c
//                                          ^^^^ storage.type.macro.hole.x2c
//                                               ^ punctuation.definition.macro.sigil.x2c
//                                                      ^^ keyword.operator.arrow.x2c
List type_code = $!Type{ int * };
//               ^^ punctuation.definition.macro.sigil.x2c
//                 ^^^^ storage.type.macro.result.x2c
List param_code = $!Param{ int $name };
//                ^^ punctuation.definition.macro.sigil.x2c
//                  ^^^^^ storage.type.macro.result.x2c
List unit_code = $!Unit{ int $name; };
//               ^^ punctuation.definition.macro.sigil.x2c
//                 ^^^^ storage.type.macro.result.x2c
List typed_code = $!int{ $value };
//                ^^ punctuation.definition.macro.sigil.x2c
List paren_code = $!(int){ $value };
//                ^^ punctuation.definition.macro.sigil.x2c
List expr_code = $!( $value + 1 );
//               ^^ punctuation.definition.macro.sigil.x2c
List stmt_code = $!{ return $value; };
//               ^^ punctuation.definition.macro.sigil.x2c
static int local_macro_grammar(void) {
  macro Expression local_value(Expr $value) => $value;
//^^^^^ keyword.declaration.macro.x2c
//      ^^^^^^^^^^ storage.type.macro.result.x2c
//                 ^^^^^^^^^^^ entity.name.function.macro.x2c
}
macro Stmt $holes(
  Expr $a, Type $b, Decl $c, Function $d, Name $e, Literal $f,
//^^^^ storage.type.macro.hole.x2c
//         ^^^^ storage.type.macro.hole.x2c
//                  ^^^^ storage.type.macro.hole.x2c
//                           ^^^^^^^^ storage.type.macro.hole.x2c
//                                        ^^^^ storage.type.macro.hole.x2c
//                                                 ^^^^^^^ storage.type.macro.hole.x2c
  Param $g, Stmt $h, Catch $i, Field $j, Entry $row,
//^^^^^ storage.type.macro.hole.x2c
//          ^^^^ storage.type.macro.hole.x2c
//                   ^^^^^ storage.type.macro.hole.x2c
//                             ^^^^^ storage.type.macro.hole.x2c
//                                       ^^^^^ storage.type.macro.hole.x2c
  Enumerator $enum, Unit @k
//                       ^ punctuation.definition.macro.splice.x2c
//                        ^ variable.parameter.macro.x2c
//^^^^^^^^^^ storage.type.macro.hole.x2c
//                  ^^^^ storage.type.macro.hole.x2c
) {
  using $temporary, $cursor;
//^^^^^ keyword.other.macro.using.x2c
//      ^ punctuation.definition.macro.sigil.x2c
//       ^^^^^^^^^ variable.parameter.macro.x2c
//                  ^ punctuation.definition.macro.sigil.x2c
//                   ^^^^^^ variable.parameter.macro.x2c
  @k
//^ punctuation.definition.macro.splice.x2c
// ^ variable.other.macro.hole.x2c
}

macro Stmt $stmt() {}
//    ^^^^ storage.type.macro.result.x2c
macro Field $field() {}
//    ^^^^^ storage.type.macro.result.x2c
macro Entry $entry() {}
//    ^^^^^ storage.type.macro.result.x2c
macro Enumerator $enumerator() {}
//    ^^^^^^^^^^ storage.type.macro.result.x2c
macro Unit $unit() {}
//    ^^^^ storage.type.macro.result.x2c
macro Decorator $decorator(Expr $target) => $target;
//    ^^^^^^^^^ storage.type.macro.result.x2c

macro Stmt $legacy_using() using $temporary => {}
//                         ^^^^^ keyword.other.macro.using.x2c
//                               ^ punctuation.definition.macro.sigil.x2c
//                                ^^^^^^^^^ variable.other.macro.hole.x2c
//                                          ^^ keyword.operator.arrow.x2c
macro Expression $legacy_expression(Expr $value) => ($value)
//                                               ^^ keyword.operator.arrow.x2c

List list = %(root (child 42) [1 2] {key $value} "$value $(call())"
//          ^^ punctuation.definition.literal.list.begin.x2c
//                 ^ punctuation.definition.literal.list.nested.begin.x2c
//                            ^ punctuation.definition.literal.array.nested.begin.x2c
//                                  ^ punctuation.definition.literal.map.nested.begin.x2c
//                                       ^ punctuation.definition.interpolation.x2c
//                                                ^ punctuation.definition.interpolation.x2c
//                                                       ^^ punctuation.definition.interpolation.expression.begin.x2c
  $value $(call()) @values @(make_values()) ?optional *rest);
//^ punctuation.definition.interpolation.x2c
//       ^^ punctuation.definition.interpolation.expression.begin.x2c
//                 ^ punctuation.definition.interpolation.list.x2c
//                         ^^ punctuation.definition.interpolation.list.expression.begin.x2c
//                                          ^^^^^^^^^ variable.other.pattern.optional.x2c
//                                                    ^^^^^ variable.other.pattern.variadic.x2c

Array array = %[ready, "text", [nested, $value], {kind: widget}, $(call())];
//            ^^ punctuation.definition.literal.array.begin.x2c
//              ^^^^^ constant.other.atom.x2c
//                      ^^^^ string.quoted.double.x2c
//                              ^^^^^^ constant.other.atom.x2c
//                                      ^ punctuation.definition.interpolation.x2c
//                                                ^^^^ constant.other.atom.x2c
//                                                      ^^^^^^ constant.other.atom.x2c
//                                                               ^^ punctuation.definition.interpolation.expression.begin.x2c
return %(ok);
// <------ keyword.control.x2c
//     ^^ punctuation.definition.literal.list.begin.x2c
Map map = %{key: 42, runtime: $value, computed: $(call())};
//        ^^ punctuation.definition.literal.map.begin.x2c
//          ^^^ constant.other.atom.x2c
//             ^ punctuation.separator.literal.collection.x2c
//                   ^^^^^^^ constant.other.atom.x2c
//                            ^ punctuation.definition.interpolation.x2c
//                                    ^^^^^^^^ constant.other.atom.x2c
//                                              ^^ punctuation.definition.interpolation.expression.begin.x2c
String string = %"value $name $(compute())";
//              ^^ punctuation.definition.literal.string.begin.x2c
//                      ^ punctuation.definition.interpolation.x2c
//                            ^^ punctuation.definition.interpolation.expression.begin.x2c
SymbolSet symbols = %<<alpha beta>>;
//                  ^^^ punctuation.definition.literal.symbol-set.begin.x2c
SymbolSet shifts = %<<"<<=" ">>=">>;
//                          ^^^^^ constant.other.symbol.quoted.x2c.symbol-set
//                               ^^ punctuation.definition.literal.symbol-set.end.x2c
Lambda lambda = %!(int value) => value + 1;
//              ^^ punctuation.definition.literal.lambda.x2c
//                            ^^ keyword.operator.arrow.x2c
Lambda shared = %!() using &captured => captured;
//                   ^^^^^ keyword.control.capture.x2c
//                                   ^^ keyword.operator.arrow.x2c

int value = $project.make(42);
//          ^ punctuation.definition.macro.sigil.x2c
//           ^^^^^^^^^^^^ entity.name.function.macro.x2c
$logged()
// <- punctuation.definition.macro.sigil.x2c
$validated()
// <- punctuation.definition.macro.sigil.x2c
int answer(void) { return 42; }
int truth = $nonzero() value + 1;
int managed = $auto(make_value());
//             ^^^^ support.function.macro.builtin.x2c
$scope(&arena) { int scoped = make_value(); }
//^ support.function.macro.builtin.x2c

Var missing = void;
//            ^^^^ constant.language.void.x2c
static Var return_void(void) {
  return void;
//       ^^^^ constant.language.void.x2c
}
int empty = void is void;
//          ^^^^ constant.language.void.x2c
//                  ^^^^ constant.language.void.x2c
Map values = %{missing: void};
//                      ^^^^ constant.language.void.x2c

void consume(void) {}
// <- storage.type.built-in.primitive.x2c
//           ^^^^ storage.type.built-in.primitive.x2c
int casted = ((void) value, 0);
//             ^^^^ storage.type.built-in.primitive.x2c

int modulo = left % right;
//                  ^ - punctuation.definition.literal.list.begin.x2c
int grouped_modulo = left % (right);
//                         ^^ - punctuation.definition.literal.list.begin.x2c
int shifted = left << right;
//                   ^^ - punctuation.definition.literal.symbol.begin.x2c
int compared = left < right;
//                    ^ - punctuation.definition.literal.symbol.begin.x2c
const char *plain = "$(not_lisp) $name";
//                   ^ string.quoted.double - punctuation.definition.macro.sigil.x2c
call(value);
//  ^ - punctuation.definition.literal.list.begin.x2c
List grouped = %($(value) @(values));
//               ^^ punctuation.definition.interpolation.expression.begin.x2c
//                      ^ punctuation.definition.interpolation.expression.end.x2c
//                        ^^ punctuation.definition.interpolation.list.expression.begin.x2c
//                                ^ punctuation.definition.interpolation.list.expression.end.x2c
String grouped_text = %"$(value) @(value)";
//                      ^^ punctuation.definition.interpolation.expression.begin.x2c
//                             ^ punctuation.definition.interpolation.expression.end.x2c
//                               ^^ - punctuation.definition.interpolation.list.expression.begin.x2c
List retired_braced = %(${old} @{values});
//                      ^^ - punctuation.definition.interpolation.expression.begin.x2c
//                             ^^ - punctuation.definition.interpolation.list.expression.begin.x2c
String retired_braced_text = %"${old}";
//                             ^^ - punctuation.definition.interpolation.expression.begin.x2c
List nested_text = %("value $(name)");
//                          ^^ punctuation.definition.interpolation.expression.begin.x2c
String escaped = %"\$(name)";
//                  ^^ - punctuation.definition.interpolation.expression.begin.x2c
List nested_x2c = %([$($twice(20))] {answer: $($twice(20))});
//                   ^^ punctuation.definition.interpolation.expression.begin.x2c
//                     ^ punctuation.definition.macro.sigil.x2c
//                                           ^^ punctuation.definition.interpolation.expression.begin.x2c
//                                             ^ punctuation.definition.macro.sigil.x2c
Var ordinary = %{old};
//             ^^ - punctuation.definition.interpolation.expression.begin.x2c
Var old_splice = @{old};
//               ^ - punctuation.definition.interpolation.list.x2c
List evaluated = $(first, @rest);
//               ^ punctuation.definition.macro.sigil.x2c
//                ^ punctuation.section.macro.hole.begin.x2c

List typed = %(?(String text) ? (String text));
//             ^^ punctuation.definition.pattern.capture.begin.x2c
//               ^^^^^^ support.type.prelude.x2c
//                      ^^^^ meta.pattern.typed-capture.x2c
//                            ^ constant.other.atom.x2c
//                              ^ meta.literal.list.nested.x2c
//                               ^^^^^^ constant.other.atom.x2c

macro Expression $call(Expr $callee, Expr @items) => $callee(@items);
//                                        ^ punctuation.definition.macro.splice.x2c
//                                         ^^^^^ variable.parameter.macro.x2c
call(@fixture.row.values($value));
//   ^ punctuation.definition.macro.splice.x2c
//    ^^^^^^^^^^^^^^^^^^ entity.name.function.macro.x2c
//                       ^ punctuation.definition.macro.sigil.x2c
List quotation = $!{ call(@items, @(parts)); };
//               ^^ punctuation.definition.macro.sigil.x2c
//                        ^ punctuation.definition.macro.splice.x2c
//                         ^^^^^ variable.other.macro.hole.x2c
//                                ^^ meta.macro.hole.expression.x2c
List array_quotation = $!{ return %[$(10), @items, $(40)]; };
//                                         ^ punctuation.definition.macro.splice.x2c
//                                          ^^^^^ variable.other.macro.hole.x2c
List list_data = %(head @items @(values) @{values});
//                      ^^^^^^ meta.interpolation.list.x2c
//                             ^^ meta.interpolation.list.expression.x2c
//                                       ^^ - punctuation.definition.interpolation.list.expression.begin.x2c
void native_variadic(const char *format, ...);
//                                       ^^^ - punctuation.definition.macro.splice.x2c
macro Expression $removed_suffix(Expr $items...) => 0;
//                                          ^^^ - punctuation.definition.macro.splice.x2c
int removed_matrix = left @ right;
//                        ^ - keyword.operator.x2c
int removed_matrix_update = left @= right;
//                               ^ - keyword.operator.assignment.compound.x2c

List operator_data = %(@ @=);
//                     ^ constant.other.atom.x2c
//                       ^^ constant.other.atom.x2c

auto { Array temporary = []; }
// <- storage.modifier.auto.x2c
auto for (int i = 0; i < 2; i++) {}
// <- storage.modifier.auto.x2c
auto (&destination) { work(); }
// <- storage.modifier.auto.x2c
auto ((choose(), &destination)) { work(); }
// <- storage.modifier.auto.x2c
auto static int regional(void) { return 1; }
// <- storage.modifier.auto.x2c

auto Array left = [], right = [];
// <- storage.modifier.auto.x2c
auto Array first = [],
// <- storage.modifier.auto.x2c
  second = [];
