/*  component-printf.x -- Var values in printf-family formats

    A printf-family call whose format is a static literal passes each Var
    value the format consumes as the C type its conversion reads: a numeric
    conversion converts the value through `Var.convert`, `%c` and a `*`
    width or precision read an int, and `%s` displays it through `Var.str`.
    The format is read once, left to right, into steps that the call's
    arguments then follow in order. A Var value that no conversion consumes,
    or one at a conversion with no native reading, is an error. Each family
    member is one call pattern, keyed by its callee.

    Each definition precedes the definitions that call it: the compiler
    settles whether a linked copy reaches a compile-time operation when the
    copy binds.
*/
#pragma once
#include "rewrite.x"

// format steps

/* Adds `(error MESSAGE)`, the last step of a format that cannot be read. */
meta static int _printf_stop(Array steps, String message) {
  steps.push(%(error $message));
  return 0;
}

/* Whether the conversion at `cursor` names its argument, as `N$` does. */
meta static int _printf_positional(String format, int cursor) {
  while (isdigit(format[cursor])) cursor++;
  return format[cursor] == '$';
}

/* Steps over a width or precision, adding `(star)` for a `*`, which reads
   an argument. */
meta static int _printf_count(String format, int &cursor, Array steps) {
  if (format[cursor] != '*') {
    while (isdigit(format[cursor])) cursor++;
    return 1;
  }
  if (_printf_positional(format, ++cursor))
    return _printf_stop(
      steps, "positional formats cannot infer Var argument types");
  steps.push(%(star));
  return 1;
}

/* Consumes the length modifier at the cursor: `hh`, `h`, `ll`, `l`, `j`,
   `z`, `t`, `L`, or none. */
meta static String _printf_length(String format, int &cursor) {
  int start = cursor, letter = format[cursor];
  if (!letter || !strchr("hljztL", letter)) return "";
  if (format[++cursor] == letter && (letter == 'h' || letter == 'l'))
    cursor++;
  return format[start:cursor];
}

meta static int _printf_valid(String length, int conversion) {
  if (strchr("diouxXn", conversion)) return length != "L";
  if (strchr("fFeEgGaA", conversion))
    return length == "" || length == "l" || length == "L";
  if (conversion == 'c' || conversion == 's')
    return length == "" || length == "l";
  return conversion == 'p' && length == "";
}

/* Adds the steps of the conversion after the `%` at `cursor`: a `(star)`
   for each `*` width or precision, then `(value LENGTH CONVERSION)`. */
meta static int _printf_conversion(String format, int &cursor, Array steps) {
  int end = format.len() - 1;
  if (_printf_positional(format, cursor))
    return _printf_stop(
      steps, "positional formats cannot infer Var argument types");
  while (cursor < end && strchr("-+ #0", format[cursor])) cursor++;
  if (!_printf_count(format, cursor, steps)) return 0;
  if (format[cursor] == '.') {
    cursor++;
    if (!_printf_count(format, cursor, steps)) return 0;
  }
  String length = _printf_length(format, cursor);
  if (cursor >= end)
    return _printf_stop(steps, "incomplete format conversion");
  int conversion = format[cursor++];
  if (!_printf_valid(length, conversion))
    return _printf_stop(
      steps,
      "unsupported or malformed format conversion %%%c".printf(conversion));
  steps.push(%(value $length $conversion));
  return 1;
}

/* The steps of the C spelling `format`, stepping over escape sequences and
   `%%`, up to the first one that cannot be read. */
meta static List _printf_steps(String format) {
  Array steps = [];
  int cursor = 1, end = format.len() - 1, read = 1;
  while (read && cursor < end) {
    int ch = format[cursor++];
    if (ch == '\\') cursor++;
    else if (ch != '%') continue;
    else if (cursor >= end)
      read = _printf_stop(steps, "incomplete format conversion");
    else if (format[cursor] == '%') cursor++;
    else read = _printf_conversion(format, cursor, steps);
  }
  return steps.list_free();
}

// reading values

meta static int _printf_is_var(Code value) => value.type().is_named("Var");

/* The C type a Var value has where `conversion` with `length` reads it, or
   NULL when no native reading applies. */
meta static Type _printf_type(String length, int conversion) {
  if (strchr("fFeEgGaA", conversion))
    return length == "L" ? %(long double) : %(double);
  if (conversion == 'c') return length == "" ? %(int) : NULL;
  if (!strchr("diouxX", conversion)) return NULL;
  int is_signed = conversion == 'd' || conversion == 'i';
  if (length == "hh" || length == "h") return %(int);
  if (length == "") return is_signed ? %(int) : %(unsigned);
  if (length == "l") return is_signed ? %(long) : %(unsigned long);
  if (length == "ll")
    return is_signed ? %(long long) : %(unsigned long long);
  return NULL;
}

/* `value` as `conversion` with `length` reads it, or NULL for a Var with
   no native reading. A native value keeps C's calling semantics. */
meta static Code _printf_read(Code value, String length, int conversion) {
  if (!_printf_is_var(value)) return value;
  if (conversion == 's' && length == "")
    return %(expr ("String") (call "Var_str" (args $value)));
  Type type = _printf_type(length, conversion);
  return type ? value.convert(type) : NULL;
}

/* Reports `message` about the call `call`. */
meta static void _printf_fail(Code call, String message) {
  match (call) case %(expr ? (call ?callee *)):
    x2c_diagnostic_fail_at(
      call, <xform>, message,
      %("printf-family call: ${x2c_binding_spelling(callee)}"));
}

/* The arguments of `call` with each value its `steps` read from `first`
   on read as the C type its conversion selects. */
meta static List _printf_arguments(
  Code call, List arguments, int first, List steps) {
  Array read = [];
  foreach (Var argument, arguments) read.push(argument);
  int next = first;
  foreach (List step, steps) {
    match (step) {
      case %(error ?message): _printf_fail(call, message);
      case %(star): {
        if (next >= read.len())
          _printf_fail(call, "format consumes a missing '*' argument");
        Code value = read[next];
        if (_printf_is_var(value)) read[next] = value.convert(%(int));
      }
      case %(value ?length ?(int conversion)): {
        if (next >= read.len())
          _printf_fail(
            call, "format conversion %%%c consumes a missing argument"
              .printf(conversion));
        Code value = _printf_read(read[next], length, conversion);
        if (!value)
          _printf_fail(call, "%s%c%s".printf(
            "cannot infer a native argument for Var at %", conversion,
            "; use an explicit converter for this format conversion"));
        read[next] = value;
      }
    }
    next++;
  }
  for (; next < read.len(); next++)
    if (_printf_is_var(read[next]))
      _printf_fail(call, "Var argument has no corresponding format conversion");
  return read.list_free();
}

/* The call `code` with each Var value its static `format` consumes read as
   the C type the conversion selects. `values` are the arguments the format
   may consume; a call with no Var among them is left alone. */
meta static Code _printf_lowered(Code code, Code format, List values) {
  int has_var = 0;
  foreach (Code value, values) has_var |= _printf_is_var(value);
  if (!has_var) return code;
  String spelling = format.format();
  if (!spelling)
    _printf_fail(code, "Var arguments require a single static format literal");
  match (code) case %(expr ?type (call ?callee (args *arguments))): {
    List read = _printf_arguments(
      code, arguments, arguments.len() - values.len(),
      _printf_steps(spelling));
    return %(expr $type (call $callee (args @read)));
  }
  return code;
}

// the family

macro Expression $printf_format(Expr $format, Expr @values) =>
  printf($format, @values);
macro Expression $fprintf_format(Expr $stream, Expr $format, Expr @values) =>
  fprintf($stream, $format, @values);
macro Expression $sprintf_format(Expr $text, Expr $format, Expr @values) =>
  sprintf($text, $format, @values);
macro Expression $snprintf_format(
    Expr $text, Expr $size, Expr $format, Expr @values) =>
  snprintf($text, $size, $format, @values);
macro Expression $string_printf_format(Expr $format, Expr @values) =>
  String_printf($format, @values);
macro Expression $file_printf_format(Expr $file, Expr $format, Expr @values) =>
  File_printf($file, $format, @values);
macro Expression $buffer_printf_format(
    Expr $buffer, Expr $format, Expr @values) =>
  Buffer_printf($buffer, $format, @values);

$rewrite($printf_format)
$rewrite($fprintf_format)
$rewrite($sprintf_format)
$rewrite($snprintf_format)
/** Reads the Var values of a C library printf-family call. A function the
    unit declares with one of these names is not that call. */
meta Code printf_library(Code code) {
  match (code) {
    case %(expr ? (call (expr (? *) ?) ?)): return code;
    case $printf_format(?format, *values):
      return _printf_lowered(code, format, values);
    case $fprintf_format(?, ?format, *values):
      return _printf_lowered(code, format, values);
    case $sprintf_format(?, ?format, *values):
      return _printf_lowered(code, format, values);
    case $snprintf_format(?, ?, ?format, *values):
      return _printf_lowered(code, format, values);
  }
  return code;
}

$rewrite($string_printf_format)
$rewrite($file_printf_format)
$rewrite($buffer_printf_format)
/** Reads the Var values of a runtime printf-family call. */
meta Code printf_runtime(Code code) {
  match (code) {
    case $string_printf_format(?format, *values):
      return _printf_lowered(code, format, values);
    case $file_printf_format(?, ?format, *values):
      return _printf_lowered(code, format, values);
    case $buffer_printf_format(?, ?format, *values):
      return _printf_lowered(code, format, values);
  }
  return code;
}
