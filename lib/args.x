/*  args.x -- parse program arguments against a declarative spec

    Copyright (c) 2026 Gary William Flake

    A spec is an ordinary `List` with one row per option or operand, and the
    parse result is a `Map` from each row's name to its value, so a script
    describes its command line as data and reads the answer by name. Words
    are `String`s throughout; converting a value to a number is the caller's
    choice. Bad input raises `<bad-arg>` instead of exiting, so the caller
    decides whether to print `Args.usage` and which status to return.
*/

#pragma once
#include "x2c.x"

/** The receiverless owner of `Args.parse` and the other argument
    operations.
*/
typedef enum Args {
  ARGS_NAMESPACE
} Args;

#pragma private

/* One spec row after its properties are read. An option is named by its
   first long spelling, or else its short one, without the dashes; `value`
   is the placeholder of an option that takes one, and `spellings` joins
   every spelling for the usage text. */
typedef struct _Option {
  String spelling, spellings, name, value, help;
  Var fallback;
  int operand, defaulted, required, repeated, given;
} _Option;

typedef struct _Spec {
  _Option *options;
  int count;
  Map index;
} _Spec;

static void _bad_option(String why, String option) {
  raise %(bad-arg (operation "Args.parse") (why $why) (option $option));
}

static void _bad_operand(String why, String operand) {
  raise %(bad-arg (operation "Args.parse") (why $why)
          (operand $operand));
}

static void _bad_spec(String why, Var entry) {
  raise %(bad-arg (operation "Args.parse") (why $why) (spec $entry));
}

static void _read_property(_Option *option, List property) {
  Symbol key = 0;
  if (property.car() is Symbol) key = property.car();
  switch (key) {
    case <value>:
      option.value = property.cadr().str();
      break;
    case <default>:
      option.fallback = property.cadr();
      option.defaulted = 1;
      break;
    case <help>:
      option.help = property.cadr().str();
      break;
    default:
      _bad_spec("unknown spec property", property);
  }
}

/* The first word names an operand unless it begins with a dash; every
   dashed word is a spelling of the same option. */
static void _read_row(_Option *option, List row, Map index, int position) {
  String first = row.car().str();
  option.operand = !first.startswith("-");
  foreach (Var word, row) {
    if (word is List) {
      _read_property(option, word);
      continue;
    }
    String text = word.str();
    if (text.startswith("-")) {
      if (!option.spelling ||
          (text.startswith("--") && !option.spelling.startswith("--")))
        option.spelling = text;
      option.spellings =
        option.spellings ? %"${option.spellings}, $text" : text;
      index[text] = position;
    }
    else if (text == "required") option.required = 1;
    else if (text == "repeated") option.repeated = 1;
    else if (text != first) _bad_spec("unknown spec word", text);
  }
  if (option.operand) option.name = first;
  else {
    int dashes = option.spelling.startswith("--") ? 2 : 1;
    option.name = option.spelling[dashes:];
  }
  if (option.defaulted) return;
  if (option.repeated) option.fallback = (List) NULL;
  else if (option.value || option.operand)
    option.fallback = (String) NULL;
  else option.fallback = 0;
}

static _Spec _read_spec(List spec) {
  _Spec result = { .count = spec.len(), .index = {} };
  result.options = Scope.calloc(result.count, sizeof(_Option));
  int position = 0;
  foreach (List row, spec) {
    _read_row(&result.options[position], row, result.index, position);
    position++;
  }
  return result;
}

static _Option *_find(_Spec *spec, String spelling) {
  Var position;
  if (!spec.index.try_get(spelling, &position))
    _bad_option("unknown option", spelling);
  return &spec.options[position.integer()];
}

/* A repeated row collects every value in order, replacing its default at
   the first occurrence; a flag counts its occurrences; any other value
   replaces an earlier one. */
static void _store(_Option *option, Map result, Var value) {
  if (option.repeated) {
    List earlier = NULL;
    if (option.given) earlier = result[option.name];
    result[option.name] = earlier.append(%($value));
  }
  else if (option.value || option.operand) result[option.name] = value;
  else result[option.name] = option.given + 1;
  option.given++;
}

static String _next_value(List &rest, String spelling) {
  if (!rest.cdr()) _bad_option("missing value", spelling);
  rest = rest.cdr();
  return rest.car().str();
}

static void _parse_long(_Spec *spec, Map result, List &rest, String word) {
  int equals = word.find("=");
  String spelling = equals < 0 ? word : word[:equals];
  _Option *option = _find(spec, spelling);
  if (!option.value) {
    if (equals >= 0) _bad_option("unexpected value", spelling);
    _store(option, result, 1);
  }
  else if (equals >= 0) _store(option, result, word[equals + 1:]);
  else _store(option, result, _next_value(rest, spelling));
}

/* Short flags may share one word, as in `-vq`; the first short option that
   takes a value consumes the rest of the word, or else the next word. */
static void _parse_short(_Spec *spec, Map result, List &rest, String word) {
  for (int at = 1; at < word.len(); at++) {
    String spelling = %"-${word[at:at + 1]}";
    _Option *option = _find(spec, spelling);
    if (!option.value) {
      _store(option, result, 1);
      continue;
    }
    String value = at + 1 < word.len()
      ? word[at + 1:] : _next_value(rest, spelling);
    _store(option, result, value);
    return;
  }
}

static void _assign_operands(_Spec *spec, Map result, List operands) {
  for (int i = 0; i < spec.count; i++) {
    _Option *option = &spec.options[i];
    if (!option.operand) continue;
    while (operands) {
      _store(option, result, operands.car());
      operands = operands.cdr();
      if (!option.repeated) break;
    }
  }
  if (operands) _bad_operand("unexpected operand", operands.car().str());
}

/** Parses `args` against `spec` and returns a `Map` from each row's name
    to its value.

    Each row of `spec` is a `List`. A row that begins with dashed words is
    an option spelled by each of them, such as `-p --prefix`, and named by
    its first long spelling without the dashes, or else by its short one. A
    row that begins with any other word is an operand of that name. The rest
    of a row may hold `(value placeholder)`, which makes an option take a
    value; `(default value)`; `(help "text")` for `Args.usage`; `required`;
    and `repeated`.

    A long option takes its value as `--name value` or `--name=value`, and a
    short option as `-n value` or `-nvalue`; short flags may share one word.
    Operands may appear between options, and `--` makes every later word an
    operand. Operand rows take operands in spec order, and a `repeated`
    operand takes all that remain.

    A flag's value is the number of times it appeared. A `repeated` row's
    value is a `List` of its values. Any other option or operand holds its
    last `String`. A row that was not given holds its default, or else zero
    for a flag, an empty `List` for a `repeated` row, and a NULL `String`
    otherwise, so every name is present and can be tested for truth.

    ```x2c
    ~#include "args.x"
    ~int main(void) {
    List spec = %(
      (-v --verbose)
      (-o --output (value file) (default "a.out"))
      (-I (value dir) repeated)
      (inputs repeated required));
    Map options = Args.parse(%(-vI src -Ilib main.x), spec);
    ~  return options["verbose"] == 1 &&
    ~    options["output"] == "a.out" &&
    ~    options["I"].list().len() == 2 &&
    ~    options["inputs"].list().car().str() == "main.x" ? 0 : 1;
    ~}
    ```

    Raises: `<bad-arg>` with `why` and the offending `option` or `operand`
    for an unknown option, a missing or unexpected value, an unexpected
    operand, or a `required` row that was not given; and with `why` and the
    offending `spec` entry for a property or word it cannot read.
*/
Map Args.parse(List args, List spec) {
  _Spec parsed = _read_spec(spec);
  Map result = {};
  for (int i = 0; i < parsed.count; i++)
    result[parsed.options[i].name] = parsed.options[i].fallback;
  Array operands = [];
  int options_ended = 0;
  for (List rest = args; rest; rest = rest.cdr()) {
    String word = rest.car().str();
    if (options_ended || word.len() < 2 || word[0] != '-')
      operands.push(word);
    else if (word == "--") options_ended = 1;
    else if (word[1] == '-') _parse_long(&parsed, result, rest, word);
    else _parse_short(&parsed, result, rest, word);
  }
  _assign_operands(&parsed, result, operands.list_free());
  for (int i = 0; i < parsed.count; i++) {
    _Option *option = &parsed.options[i];
    if (!option.required || option.given) continue;
    String name = option.name, spelling = option.spelling;
    if (option.operand) _bad_operand("missing operand", name);
    _bad_option("missing option", spelling);
  }
  return result;
}

// usage text

static String _label(_Option *option) {
  if (option.operand) {
    String label = %"<${option.name}>";
    if (option.repeated) label = %"$label...";
    return option.required ? label : %"[$label]";
  }
  String label = option.spellings;
  if (option.value) label = %"$label <${option.value}>";
  return label.startswith("--") ? %"    $label" : label;
}

static void _write_row(Buffer out, String label, String help) {
  const int column = 30;
  if (!help) out.printf("  %s\n", label);
  else if (label.len() + 2 >= column)
    out.printf("  %s\n%*s%s\n", label, column, "", help);
  else out.printf("  %-*s%s\n", column - 2, label, help);
}

/** Returns usage text for `spec` as `Args.parse` reads it: a synopsis
    for `program`, then each option, then each operand that has help, in
    spec order. Help text starts at column 30, as in `x2c help`.
*/
String Args.usage(String program, List spec) {
  _Spec parsed = _read_spec(spec);
  Buffer synopsis = $auto(Buffer.new(0)), options = $auto(Buffer.new(0));
  Buffer operands = $auto(Buffer.new(0)), out = $auto(Buffer.new(0));
  for (int i = 0; i < parsed.count; i++) {
    _Option *option = &parsed.options[i];
    String label = _label(option);
    if (!option.operand) _write_row(options, label, option.help);
    else {
      synopsis.printf(" %s", label);
      if (option.help) _write_row(operands, label, option.help);
    }
  }
  String option_rows = options, operand_rows = operands;
  String words = synopsis;
  out.printf(
    "Usage:\n  %s%s%s\n", program, option_rows ? " [options]" : "",
    words ? words : "");
  if (option_rows) out.printf("\nOptions:\n%s", option_rows);
  if (operand_rows) out.printf("\nOperands:\n%s", operand_rows);
  return out;
}

/** Returns the program arguments that follow `argv[0]` as `String`s. */
List Args.from_argv(int argc, char **argv) {
  List result = NULL;
  for (int i = argc - 1; i > 0; i--)
    result = %(${String.new(argv[i])} @result);
  return result;
}
