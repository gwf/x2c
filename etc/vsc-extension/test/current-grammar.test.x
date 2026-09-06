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

with point as local {
// <--- keyword.control.with.x2c
//         ^^ keyword.control.with.x2c
  local.x = 1;
}
if (ready) with point {
//         ^^^^ keyword.control.with.x2c
  _.x = 2;
}
with
// <--- keyword.control.with.x2c
  point as local {
//      ^^ keyword.control.with.x2c
  _.x = 3;
}
else with point {
//   ^^^^ keyword.control.with.x2c
  _.x = 4;
}
int with = 0;
//  ^^^^ - keyword.control.with.x2c
int with(int value) { return value; }
//  ^^^^ - keyword.control.with.x2c

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

macro expression $project.make(expr $value, type $kind) => ($value)
// <---- keyword.declaration.macro.x2c
//    ^^^^^^^^^^ storage.type.macro.result.x2c
//               ^ punctuation.definition.macro.sigil.x2c
//                ^^^^^^^^^^^^ entity.name.function.macro.x2c
//                             ^^^^ storage.type.macro.hole.x2c
//                                  ^ punctuation.definition.macro.sigil.x2c
//                                          ^^^^ storage.type.macro.hole.x2c
//                                               ^ punctuation.definition.macro.sigil.x2c
static int local_macro_grammar(void) {
  macro Expression local_value(Expr $value) => ($value)
//^^^^^ keyword.declaration.macro.x2c
//      ^^^^^^^^^^ storage.type.macro.result.x2c
//                 ^^^^^^^^^^^ entity.name.function.macro.x2c
}
macro Statement $holes(
  Expr $a, Type $b, Decl $c, Function $d, Name $e, Literal $f,
//^^^^ storage.type.macro.hole.x2c
//         ^^^^ storage.type.macro.hole.x2c
//                  ^^^^ storage.type.macro.hole.x2c
//                           ^^^^^^^^ storage.type.macro.hole.x2c
//                                        ^^^^ storage.type.macro.hole.x2c
//                                                 ^^^^^^^ storage.type.macro.hole.x2c
  Param $g, Statement $h, Block $i, Field $j, Entry $row,
//^^^^^ storage.type.macro.hole.x2c
//          ^^^^^^^^^ storage.type.macro.hole.x2c
//                        ^^^^^ storage.type.macro.hole.x2c
//                                  ^^^^^ storage.type.macro.hole.x2c
//                                            ^^^^^ storage.type.macro.hole.x2c
//                        ^^^^^ - support.type.prelude.x2c
  Enumerator $enum, Unit $k...
//^^^^^^^^^^ storage.type.macro.hole.x2c
//                  ^^^^ storage.type.macro.hole.x2c
) using $temporary => {
//^^^^^ keyword.other.macro.using.x2c
//      ^ punctuation.definition.macro.sigil.x2c
//       ^^^^^^^^^ variable.other.macro.hole.x2c
//                 ^^ keyword.operator.arrow.x2c
  $k...
//  ^^^ punctuation.definition.macro.splice.x2c
}

macro Block $block() => {}
//    ^^^^^ storage.type.macro.result.x2c
//    ^^^^^ - support.type.prelude.x2c
macro Field $field() => {}
//    ^^^^^ storage.type.macro.result.x2c
macro Entry $entry() => {}
//    ^^^^^ storage.type.macro.result.x2c
macro Enumerator $enumerator() => {}
//    ^^^^^^^^^^ storage.type.macro.result.x2c
macro Unit $unit() => {}
//    ^^^^ storage.type.macro.result.x2c
macro Decorator $decorator(Expr $target) => ($target)
//    ^^^^^^^^^ storage.type.macro.result.x2c

List list = %(root (child 42) [1 2] {key $value} "$value ${call()}"
//          ^^ punctuation.definition.literal.list.begin.x2c
//                 ^ punctuation.definition.literal.list.nested.begin.x2c
//                            ^ punctuation.definition.literal.array.nested.begin.x2c
//                                  ^ punctuation.definition.literal.map.nested.begin.x2c
//                                       ^ punctuation.definition.interpolation.x2c
//                                                ^ punctuation.definition.interpolation.x2c
//                                                       ^^ punctuation.definition.interpolation.expression.begin.x2c
  $value ${call()} @values @{make_values()} ?optional *rest);
//^ punctuation.definition.interpolation.x2c
//       ^^ punctuation.definition.interpolation.expression.begin.x2c
//                 ^ punctuation.definition.interpolation.list.x2c
//                         ^^ punctuation.definition.interpolation.list.expression.begin.x2c
//                                          ^^^^^^^^^ variable.other.pattern.optional.x2c
//                                                    ^^^^^ variable.other.pattern.variadic.x2c

Array array = %[ready, "text", [nested, $value], {kind: widget}, ${call()}];
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
Map map = %{key: 42, runtime: $value, computed: ${call()}};
//        ^^ punctuation.definition.literal.map.begin.x2c
//          ^^^ constant.other.atom.x2c
//             ^ punctuation.separator.literal.collection.x2c
//                   ^^^^^^^ constant.other.atom.x2c
//                            ^ punctuation.definition.interpolation.x2c
//                                    ^^^^^^^^ constant.other.atom.x2c
//                                              ^^ punctuation.definition.interpolation.expression.begin.x2c
String string = %"value $name ${compute()}";
//              ^^ punctuation.definition.literal.string.begin.x2c
//                      ^ punctuation.definition.interpolation.x2c
//                            ^^ punctuation.definition.interpolation.expression.begin.x2c
SymbolSet symbols = %<<alpha beta>>;
//                  ^^^ punctuation.definition.literal.symbol-set.begin.x2c
Lambda lambda = %!(int value) => value + 1;
//              ^^ punctuation.definition.literal.lambda.x2c
//                            ^^ keyword.operator.arrow.x2c

int value = $project.make(42);
//          ^ punctuation.definition.macro.sigil.x2c
//           ^^^^^^^^^^^^ entity.name.function.macro.x2c
$logged()
// <- punctuation.definition.macro.sigil.x2c
$validated()
// <- punctuation.definition.macro.sigil.x2c
int answer(void) { return 42; }
int truth = $nonzero() value + 1;
//          ^ punctuation.definition.macro.sigil.x2c

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

Var form = $(outer (inner "a ) string" /* ) */
//         ^^ punctuation.definition.embedded.lisp.begin.x2c
//                 ^ punctuation.section.list.begin.lisp.x2c
  '`(template ,value ,@values '$hole <1>)));
//^ punctuation.definition.quote.lisp.x2c
// ^ punctuation.definition.quasiquote.lisp.x2c
//            ^ punctuation.definition.unquote.lisp.x2c
//                   ^^ punctuation.definition.unquote-splicing.lisp.x2c
//                            ^ punctuation.definition.quote.lisp.x2c
//                             ^ punctuation.definition.macro.sigil.x2c
//                                   ^^^ constant.other.symbol.lisp.x2c
$(import "helpers.xmacro")
// <- punctuation.definition.embedded.lisp.begin.x2c
//^^^^^^ variable.other.lisp.x2c
//       ^^^^^^^^^^^^^^^^ string.quoted.double.lisp.x2c
$(def lisp.native.target.rows '(
  (Var_car ((func (("Var"))) "Var"))
  (Var_cons ((func (("Var") ("List"))) "List"))
  (List_sort ((func (("List"))) "List"))
))
// <- punctuation.section.list.end.lisp.x2c
// <~- punctuation.definition.embedded.lisp.end.x2c
macro Expression $after.embedded.lisp() => (0)
// <---- keyword.declaration.macro.x2c
//               ^ punctuation.definition.macro.sigil.x2c
Var sequence = $(list $items...);
//                          ^^^ punctuation.definition.macro.splice.x2c

int modulo = left % right;
//                  ^ - punctuation.definition.literal.list.begin.x2c
int grouped_modulo = left % (right);
//                         ^^ - punctuation.definition.literal.list.begin.x2c
int shifted = left << right;
//                   ^^ - punctuation.definition.literal.symbol.begin.x2c
int compared = left < right;
//                    ^ - punctuation.definition.literal.symbol.begin.x2c
const char *plain = "$(not_lisp) $name";
//                   ^ string.quoted.double - punctuation.definition.embedded.lisp.begin.x2c
call(value);
//  ^ - punctuation.definition.literal.list.begin.x2c
List braced = %(${old} @{values});
//              ^^ punctuation.definition.interpolation.expression.begin.x2c
//                   ^ punctuation.definition.interpolation.expression.end.x2c
//                     ^^ punctuation.definition.interpolation.list.expression.begin.x2c
//                             ^ punctuation.definition.interpolation.list.expression.end.x2c
String braced_text = %"${old} @{old}";
//                     ^^ punctuation.definition.interpolation.expression.begin.x2c
//                          ^ punctuation.definition.interpolation.expression.end.x2c
//                            ^^ - punctuation.definition.interpolation.list.expression.begin.x2c
List rejected_parenthesized = %($(old) @(values));
//                              ^^ - punctuation.definition.interpolation.expression.begin.x2c
//                                     ^^ - punctuation.definition.interpolation.list.expression.begin.x2c
String rejected_parenthesized_text = %"$(old)";
//                                     ^^ - punctuation.definition.interpolation.expression.begin.x2c
List nested_text = %("value ${old}");
//                          ^^ punctuation.definition.interpolation.expression.begin.x2c
String escaped = %"\${old}";
//                   ^^ - punctuation.definition.interpolation.expression.begin.x2c
List nested_x2c = %([${$(* 20 2)}] {answer: ${$(* 20 2)}});
//                   ^^ punctuation.definition.interpolation.expression.begin.x2c
//                     ^^ punctuation.definition.embedded.lisp.begin.x2c
//                                          ^^ punctuation.definition.interpolation.expression.begin.x2c
//                                            ^^ punctuation.definition.embedded.lisp.begin.x2c
Var ordinary = %{old};
//             ^ - punctuation.definition.embedded.lisp.begin.x2c
Var old_splice = @{old};
//               ^ - punctuation.definition.interpolation.list.x2c
