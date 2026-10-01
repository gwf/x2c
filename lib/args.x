/*  args.x -- parse program arguments against a declarative spec

    Copyright (c) 2026 Gary William Flake

    Args owns the reading of a command line against a spec: an ordinary
    `List` with one row per option or operand. The result is a `Map` from
    each row's name to its value, words stay `String`s, and bad input raises
    `<bad-arg>` so the caller decides whether to print `Args.usage` and which
    status to return.
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
   every spelling for the usage text. `owner` is the first row with the
   same name, and its `collected` holds that name's repeated values. */
typedef struct Option {
  String spelling, spellings, name, value, help;
  Var fallback;
  Array collected;
  struct Option *owner;
  int operand, defaulted, required, repeated, given;
} Option;

typedef struct Spec {
  Option *options;
  int count;
  Map index;
} Spec;

// parsing

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
  Spec parsed = _read_spec(spec);
  defer parsed._free();
  Map result = {}, complete = NULL;
  defer if ((void *) complete == 0) result.cleanup();
  for (int i = 0; i < parsed.count; i++)
    result[parsed.options[i].name] = parsed.options[i].fallback;
  Array operands = $auto([]);
  int options_ended = 0;
  for (List rest = args; rest; rest = rest.cdr()) {
    String word = rest.car().str();
    if (options_ended || word.len() < 2 || word[0] != '-')
      operands.push(word);
    else if (word == "--") options_ended = 1;
    else if (word[1] == '-') parsed._parse_long(result, rest, word);
    else parsed._parse_short(result, rest, word);
  }
  List remaining = operands;
  parsed._assign_operands(result, remaining);
  for (int i = 0; i < parsed.count; i++) {
    Option *option = &parsed.options[i];
    if (option.collected) {
      List collected = option.collected;
      result[option.name] = collected;
    }
    if (!option.required || option.given) continue;
    String name = option.name, spelling = option.spelling;
    if (option.operand) _bad_operand("missing operand", name);
    _bad_option("missing option", spelling);
  }
  return complete = result;
}

// spec rows

static Spec _read_spec(List spec) {
  Spec result = { .count = spec.len(), .index = {} };
  int complete = 0;
  defer if (!complete) result._free();
  result.options = Scope.calloc(result.count, sizeof(Option));
  int position = 0;
  foreach (List row, spec) {
    Option *option = &result.options[position];
    option._read_row(row, result.index, position);
    Var earlier;
    option.owner = result.index.try_get(option.name, earlier)
      ? result.options[earlier.integer()].owner : option;
    result.index[option.name] = position;
    position++;
  }
  complete = 1;
  return result;
}

/* The first word names an operand unless it begins with a dash; every
   dashed word is a spelling of the same option. */
static void Option._read_row(
  Option *option, List row, Map index, int position) {
  String first = row.car().str();
  option.operand = !first.startswith("-");
  foreach (Var word, row) {
    if (word is List) {
      option._read_property(word);
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

static void Option._read_property(Option *option, List property) {
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

static void Spec._free(Spec *spec) {
  if (spec.options)
    for (int i = 0; i < spec.count; i++) spec.options[i].collected.free();
  Scope.free(spec.options);
  spec.index.cleanup();
}

// words

static void Spec._parse_long(
  Spec *spec, Map result, List &rest, String word) {
  int equals = word.find("=");
  String spelling = equals < 0 ? word : word[:equals];
  Option *option = spec._find(spelling);
  if (!option.value) {
    if (equals >= 0) _bad_option("unexpected value", spelling);
    option._store(result, 1);
  }
  else if (equals >= 0) option._store(result, word[equals + 1:]);
  else option._store(result, _next_value(rest, spelling));
}

/* Short flags may share one word, as in `-vq`; the first short option that
   takes a value consumes the rest of the word, or else the next word. */
static void Spec._parse_short(
  Spec *spec, Map result, List &rest, String word) {
  for (int at = 1; at < word.len(); at++) {
    String spelling = %"-${word[at:at + 1]}";
    Option *option = spec._find(spelling);
    if (!option.value) {
      option._store(result, 1);
      continue;
    }
    String value = at + 1 < word.len()
      ? word[at + 1:] : _next_value(rest, spelling);
    option._store(result, value);
    return;
  }
}

static Option *Spec._find(Spec *spec, String spelling) {
  Var position;
  if (!spec.index.try_get(spelling, position))
    _bad_option("unknown option", spelling);
  return &spec.options[position.integer()];
}

static String _next_value(List &rest, String spelling) {
  if (!rest.cdr()) _bad_option("missing value", spelling);
  rest = rest.cdr();
  return rest.car().str();
}

/* A repeated row collects every value in order, starting afresh at its
   first occurrence or after another row replaced the value; a flag counts
   its occurrences; any other value replaces an earlier one. */
static void Option._store(Option *option, Map result, Var value) {
  Option *owner = option.owner;
  if (!option.repeated || !option.given) {
    owner.collected.free();
    owner.collected = NULL;
  }
  if (option.repeated) {
    if (!owner.collected) owner.collected = [];
    owner.collected.push(value);
  }
  else if (option.value || option.operand) result[option.name] = value;
  else result[option.name] = option.given + 1;
  option.given++;
}

static void Spec._assign_operands(Spec *spec, Map result, List operands) {
  for (int i = 0; i < spec.count; i++) {
    Option *option = &spec.options[i];
    if (!option.operand) continue;
    while (operands) {
      option._store(result, operands.car());
      operands = operands.cdr();
      if (!option.repeated) break;
    }
  }
  if (operands) _bad_operand("unexpected operand", operands.car().str());
}

// errors

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

// usage text

/** Returns usage text for `spec` as `Args.parse` reads it: a synopsis
    for `program`, then each option, then each operand that has help, in
    spec order. Help text starts at column 30, as in `x2c help`.
*/
String Args.usage(String program, List spec) {
  Spec parsed = _read_spec(spec);
  defer parsed._free();
  Buffer synopsis = $auto(Buffer.new(0)), options = $auto(Buffer.new(0));
  Buffer operands = $auto(Buffer.new(0)), out = $auto(Buffer.new(0));
  for (int i = 0; i < parsed.count; i++) {
    Option *option = &parsed.options[i];
    String label = option._label();
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

static String Option._label(Option *option) {
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

/** Returns the program arguments that follow `argv[0]` as `String`s. */
List Args.from_argv(int argc, char **argv) {
  List result = NULL;
  for (int i = argc - 1; i > 0; i--)
    result = %(${String.new(argv[i])} @result);
  return result;
}
