/*  survey.x -- classify the declarations a C header adds to a unit

    Copyright (c) 2026 Gary William Flake.

    A survey reads the rows that host-preprocessor collection adds when a
    unit includes the header, beyond the rows of an empty unit. Both units
    stay open while the survey is used, because the rows and the emitter
    belong to them. README.md states the naming and pairing rules.
*/

#pragma once
#include "frontend.x"

/** One header's declarations, classified for a package's raw tier.
    `handles` maps each opaque C typedef name to its x2c handle name, and
    `releases` maps a handle's C typedef name to its release method.
    `methods` holds `(c-type method function type)` rows in output order.
    `raw` names functions without a handle receiver, and `skipped` holds
    `(function reason)` rows for functions a method cannot forward.
*/
typedef struct Survey {
  Compiler compiler;
  String prefix;
  Map handles, releases;
  List methods, raw, skipped, enums;
  int constants;
} *Survey;

// lifetime verbs

/* Each acquisition verb with a release verb that ends its lifetime. */
static List lifetime_pairs = %(
  ("open" "close") ("new" "free") ("new" "delete") ("new" "destroy")
  ("create" "destroy") ("create" "free") ("alloc" "free")
  ("prepare" "finalize"));

/* Method names that runtime protocols or x2c conversions already use; a
   function that would take one keeps its C name. */
static List reserved_methods =
  %("cleanup" "var" "iter" "str" "len" "truth" "getindex" "setindex");

/** Surveys the rows `header` adds to `base`. `prefix` is the library prefix
    that method names lose; NULL selects the longest prefix ending in `_`
    that the header's functions share.
*/
Survey Survey.new(ParsedUnit &base, ParsedUnit &header, String prefix) {
  Survey s = xcalloc(1, sizeof(struct Survey));
  s.compiler = header.compiler;
  Map rows = {};
  foreach (Var (key, value) in header.globals)
    if (!(key in base.globals)) rows[key] = value;
  Map preprocessed = _identifiers(header.preprocessor_output);
  Array functions = [], enums = [];
  foreach (Var (key, value) in rows) {
    if (key ~= %(?name) && name is <string> && name in preprocessed &&
        Survey.signature(value, NULL, NULL))
      functions.push(name);
    else if (key ~= %(enum ?name "enumerators") && name is <string>)
      enums.push(name);
    else if (key ~= %(?) && value ~= %(enum *)) s.constants++;
  }
  functions.sort();
  s.enums = enums.sort();
  s.prefix = prefix ? prefix : _common_prefix(functions);
  s.handles = _handles(rows, base.globals, functions);
  _methods(s, rows, functions);
  s.releases = _releases(s, _acquisitions(s, rows, functions));
  return s;
}

/** Returns whether `type` is a function type. Stores its parameter types,
    NULL for `(void)`, and its result type when asked. Qualifiers stay as
    declared, which `Type.function_parts` does not preserve.
*/
int Survey.signature(Var type, List &?parameters, List &?result) {
  if (type is not <list>) return 0;
  match (type)
    case %((func (*types)) ?head *tail): {
      if (parameters) parameters = types ~= %((void)) ? NULL : types;
      if (result) result = $(head, @tail);
      return 1;
    }
  return 0;
}

/** Returns the C spelling of `type` declaring `name`, with no semicolon.
    `name` may be a method name such as `Sqlite3.close`; `parameters` names
    the function parameters in order.
*/
String Survey.declaration(Survey s, Type type, String name, List parameters) {
  Compiler c = s.compiler;
  List declaration = _named(type.declaration_ast($(name)), parameters);
  String text = c.code_text(c.emit($(declaration), NULL));
  // Pointer declarators bind to the name, as x2c source spells them.
  while ("* *" in text) text = text.replace("* *", "**");
  return text.replace("* ", "*").remove_suffix(";");
}

/** Returns `type` with each non-`const` `T *` whose `T` is a handle's C
    typedef spelled as that handle. Function types inside `type` keep their
    C spelling.
*/
List Survey.through_handles(Survey s, List type) {
  if (type ~= %((!quote *) ?name) && name in s.handles)
    return $(s.handles[name]);
  if (!type || type.car() is <list>) return type;
  return cons(type.car(), s.through_handles(type.cdr()));
}

// handles

/* Opaque struct typedefs that some function takes first, each named by
   joining the capitalized words of its C name. */
static Map _handles(Map rows, Map base, Array functions) {
  Map handles = {}, taken = {};
  foreach (String function in functions) {
    String c_type = _receiver(rows[$(function)]);
    if (!c_type || c_type in handles || !_opaque(rows, c_type)) continue;
    String name = _camel(c_type);
    if ($(name) in base || $(name) in rows || name in taken)
      name = %"$(name)Handle";
    handles[c_type] = name;
    taken[name] = 1;
  }
  return handles;
}

/* The typedef name a function's first parameter points to, or NULL. */
static String _receiver(Type type) {
  List parameters = NULL;
  if (!Survey.signature(type, parameters, NULL) || !parameters) return NULL;
  List first = parameters.car();
  if (first ~= %((!quote *) ?name) && name is <string>) return name;
  if (first ~= %((!quote *) const ?name) && name is <string>) return name;
  return NULL;
}

/* A typedef of a struct or union tag that the header never completes. */
static int _opaque(Map rows, String c_type) {
  Var target = rows[%(typedef $c_type)];
  return target ~= %((!or struct union) ?) && !(target.list() in rows);
}

static String _camel(String c_name) {
  Array words = [];
  foreach (String word in c_name.split("_"))
    if (word) words.push(word.withindex(0, toupper(word[0])));
  return words.join("");
}

// methods

/* Sorts the header's functions into method rows, raw functions, and
   skipped functions, each in name order. */
static void _methods(Survey s, Map rows, Array functions) {
  Array methods = [], raw = [], skipped = [];
  Map seen = {};
  foreach (String function in functions) {
    Type type = rows[$(function)];
    String c_type = _receiver(type), reason = _unforwardable(type);
    if (!c_type || !(c_type in s.handles)) raw.push(function);
    else if (reason) skipped.push($(function, reason));
    else {
      String method = _method_name(s.prefix, c_type, function);
      if ($(c_type, method) in seen || method in reserved_methods)
        method = function;
      seen[$(c_type, method)] = 1;
      methods.push($(c_type, method, function, type));
    }
  }
  s.methods = methods.sort_by(%!(List row) => %"$(row[0]) $(row[1])");
  s.raw = raw;
  s.skipped = skipped;
}

/* Why a forwarding method cannot pass on its own arguments, or NULL. */
static String _unforwardable(Type type) {
  List parameters = NULL;
  Survey.signature(type, parameters, NULL);
  foreach (List parameter in parameters) {
    if (parameter ~= %(...)) return "variadic";
    if (parameter ~= %((!or "va_list" "__builtin_va_list")))
      return "takes a va_list";
  }
  return NULL;
}

/* Strips `c_type_`, or else the library prefix; keeps the C name when
   stripping leaves no identifier. */
static String _method_name(String prefix, String c_type, String function) {
  String own = %"$(c_type)_";
  String method = function.startswith(own) ? function.remove_prefix(own)
                                           : function.remove_prefix(prefix);
  return method.is_identifier() ? method : function;
}

// releases

/* Maps each handle's C type to the acquisition verbs of the functions that
   return it or fill a pointer to it. */
static Map _acquisitions(Survey s, Map rows, Array functions) {
  Map acquired = {};
  foreach (String function in functions) {
    List words = function.remove_prefix(s.prefix).split("_");
    foreach (String c_type in _yielded(rows[$(function)])) {
      if (!(c_type in acquired)) acquired[c_type] = {};
      Map verbs = acquired[c_type];
      foreach (String word in words) verbs[word] = 1;
    }
  }
  return acquired;
}

/* The C types that `type` returns a pointer to or fills through a `T **`. */
static List _yielded(Type type) {
  List parameters = NULL, result = NULL;
  Survey.signature(type, parameters, result);
  Array yielded = [];
  if (result ~= %((!quote *) ?name) && name is <string>) yielded.push(name);
  foreach (List parameter in parameters)
    if (parameter ~= %((!quote *) (!quote *) ?name) && name is <string>)
      yielded.push(name);
  return yielded;
}

/* For each handle, the one-parameter method whose first word is a release
   verb paired with one of the handle's acquisition verbs. The shorter name
   wins, so `close` is chosen over `close_v2`. */
static Map _releases(Survey s, Map acquired) {
  Map releases = {};
  foreach (List row in s.methods) {
    String c_type = row[0], method = row[1];
    List parameters = NULL;
    Survey.signature(row[3], parameters, NULL);
    String chosen = releases.getdefault(c_type, NULL);
    if (parameters.len() != 1 || (chosen && chosen.len() <= method.len()))
      continue;
    Map verbs = acquired.getdefault(c_type, {});
    String verb = method.split("_").car();
    foreach (List pair in lifetime_pairs)
      if (pair[1] == verb && pair[0] in verbs) releases[c_type] = method;
  }
  return releases;
}

// spelling

/* The identifiers in the host preprocessor's output. Ordinary collection
   also reads the header without evaluating its conditionals, so a function
   in a disabled branch, such as a header-only library's implementation,
   has a row but no identifier here. */
static Map _identifiers(String text) {
  Map words = {};
  int start = -1, length = text.len();
  for (int i = 0; i <= length; i++) {
    int c = i < length ? text[i] : 0;
    if (c == '_' || isalnum(c)) {
      if (start < 0) start = i;
    }
    else if (start >= 0) {
      words[text[start:i]] = 1;
      start = -1;
    }
  }
  return words;
}

/* The longest prefix ending in `_` that every function name shares. */
static String _common_prefix(Array functions) {
  if (!functions.len()) return "";
  String prefix = functions[0];
  foreach (String function in functions)
    while (prefix && !function.startswith(prefix))
      prefix = prefix[:prefix.len() - 1];
  int end = prefix.rfind("_");
  return end < 0 ? "" : prefix[:end + 1];
}

/* Gives the parameters of a function declaration the names in order. */
static List _named(List declaration, List names) {
  match (declaration)
    case %(declare ?base
           (bindings (bind ?name ((fnmod (params *parameters)) *rest)))): {
      Array named = [];
      foreach (List parameter in parameters)
        match (parameter)
          case %(param ?parameter_base (bind ? ?modifiers)): {
            List binding = %(bind $($(names[named.len()])) $modifiers);
            named.push(%(param $parameter_base $binding));
          }
      return %(declare $base
               (bindings (bind $name
                 ((fnmod (params @(named.list()))) @rest))));
    }
  return declaration;
}
