/*  component-printf.x -- Var values in printf-family formats

    A printf-family call whose format is a static literal passes each Var
    value the format consumes as the C type its conversion reads: a numeric
    conversion converts the value through `Var.convert`, `%c` and a `*`
    width or precision read an int, and `%s` displays it through `Var.str`.
    The format is read once, left to right. A Var value that no conversion
    consumes, or one at a conversion with no native reading, is an error.
    Each family member is one call pattern, keyed by its callee.

    Each definition precedes the definitions that call it: the compiler
    settles whether a linked copy reaches a compile-time operation when the
    copy binds.
*/
#pragma once
#include "rewrite.x"

// reading values

meta static int _printf_is_var(Code value) => value.type().is_named("Var");

/* Reports `message` about the printf-family call `call`. */
meta static void _printf_fail(Code call, String message) {
  match (call) case %(expr ? (call ?callee *)):
    x2c_diagnostic_fail_at(
      call, <xform>, message,
      %("printf-family call: ${x2c_binding_spelling(callee)}"));
}

meta static int _printf_valid(String length, int conversion) {
  if (strchr("diouxXn", conversion)) return length != "L";
  if (strchr("fFeEgGaA", conversion))
    return length == "" || length == "l" || length == "L";
  if (conversion == 'c' || conversion == 's')
    return length == "" || length == "l";
  return conversion == 'p' && length == "";
}

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

/* `value` as `conversion` with `length` reads it, or NULL for a Var that no
   native reading takes. A native value keeps C's calling semantics. */
meta static Code _printf_read(Code value, String length, int conversion) {
  if (!_printf_is_var(value)) return value;
  if (conversion == 's' && length == "")
    return %(expr ("String") (call "Var_str" (args $value)));
  Type type = _printf_type(length, conversion);
  return type ? value.convert(type) : NULL;
}

// the format walk

/* Reports a conversion at `at` that names its argument, as `N$` does. */
meta static void _printf_position(Code call, const char *at) {
  while (isdigit(*at)) at++;
  if (*at == '$')
    _printf_fail(call, "positional formats cannot infer Var argument types");
}

/* Steps over a width or precision at `at`. A `*` reads the next argument
   as an int. */
meta static void _printf_count(
  Code call, const char *&at, Array arguments, int &next) {
  if (*at != '*') {
    while (isdigit(*at)) at++;
    return;
  }
  _printf_position(call, ++at);
  if (next >= arguments.len())
    _printf_fail(call, "format consumes a missing '*' argument");
  Code value = arguments[next];
  if (_printf_is_var(value)) arguments[next] = value.convert(%(int));
  next++;
}

/* Consumes the length modifier at `at`: `hh`, `h`, `ll`, `l`, `j`, `z`,
   `t`, `L`, or none. */
meta static String _printf_length(const char *&at) {
  const char *start = at;
  if (*at && strchr("hljztL", *at))
    at += (*at == 'h' || *at == 'l') && at[1] == *at ? 2 : 1;
  return String.new_len(start, (int) (at - start));
}

/* Reads the conversion after a `%` at `at`, with the arguments its
   position, flags, width, precision, length, and letter read. */
meta static void _printf_conversion(
  Code call, const char *&at, Array arguments, int &next) {
  _printf_position(call, at);
  while (*at && strchr("-+ #0", *at)) at++;
  _printf_count(call, at, arguments, next);
  if (*at == '.') {
    at++;
    _printf_count(call, at, arguments, next);
  }
  String length = _printf_length(at);
  if (!*at) _printf_fail(call, "incomplete format conversion");
  int conversion = *at++;
  if (!_printf_valid(length, conversion))
    _printf_fail(
      call, "unsupported or malformed format conversion %%%c"
        .printf(conversion));
  if (next >= arguments.len())
    _printf_fail(
      call, "format conversion %%%c consumes a missing argument"
        .printf(conversion));
  Code read = _printf_read(arguments[next], length, conversion);
  if (!read)
    _printf_fail(call, "%s%c%s".printf(
      "cannot infer a native argument for Var at %", conversion,
      "; use an explicit converter for this format conversion"));
  arguments[next++] = read;
}

/* Reads each conversion of the format text `at` in order, stepping over
   escape sequences and `%%`. */
meta static void _printf_scan(
  Code call, const char *at, Array arguments, int &next) {
  while (*at) {
    int ch = *at++;
    if (ch == '\\' && *at) at++;
    if (ch != '%') continue;
    if (!*at) _printf_fail(call, "incomplete format conversion");
    if (*at == '%') at++;
    else _printf_conversion(call, at, arguments, next);
  }
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
  match (code) case %(expr ?type (call ?callee (args *given))): {
    Array arguments = given;
    int next = given.len() - values.len();
    _printf_scan(code, spelling[1:spelling.len() - 1], arguments, next);
    for (; next < arguments.len(); next++)
      if (_printf_is_var(arguments[next]))
        _printf_fail(
          code, "Var argument has no corresponding format conversion");
    return %(expr $type (call $callee (args @{arguments.list_free()})));
  }
  return code;
}

/* A C library member names only a function no declaration resolves. */
meta static Code _printf_library(Code code, Code format, List values) {
  match (code) case %(expr ? (call (expr () ?) ?)):
    return _printf_lowered(code, format, values);
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
$rewrite($string_printf_format)
$rewrite($file_printf_format)
$rewrite($buffer_printf_format)
/** Reads the Var values a printf-family call's static format consumes. */
meta Code printf_values(Code code) {
  match (code) {
    case $printf_format(?f, *v): return _printf_library(code, f, v);
    case $fprintf_format(?, ?f, *v): return _printf_library(code, f, v);
    case $sprintf_format(?, ?f, *v): return _printf_library(code, f, v);
    case $snprintf_format(?, ?, ?f, *v): return _printf_library(code, f, v);
    case $string_printf_format(?f, *v): return _printf_lowered(code, f, v);
    case $file_printf_format(?, ?f, *v): return _printf_lowered(code, f, v);
    case $buffer_printf_format(?, ?f, *v): return _printf_lowered(code, f, v);
  }
  return code;
}
