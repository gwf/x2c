/*  construction.x -- macro value construction */

// application

/** Records the Macro values an anonymous macro captured where it was
   created, so applying it later applies the same children.
*/
Macro Macro_close(Macro value, List captures) =>
  value.append(%((env $captures)));

/** Applies a macro value to code values. The result is a pending
   invocation; inserting it into a program expands and binds it there.
*/
List Macro_apply(Macro t, List values) =>
  $("x2c.template", t, _group(t, values));

// typed quotations

/** Returns the name a typed quotation declares with a Name hole whose local
    holds `value`: the name form of an `x2c_ident` spelling or a String,
    or a binding as it is.
*/
Var Macro.declared(Var value) {
  Var spelling = _spelling(value);
  return spelling is <string> ? $(spelling).var() : value;
}

/** Returns the items a typed quotation splices for an expression sequence
    hole whose local holds `values`: each number, String, or Symbol becomes
    its literal, as a spliced data List's items do.
*/
List Macro.inserted_items(List values) => _expr_values(values);

/** Returns what a typed quotation builds when its code is one hole whose
    local holds `value`: the inserted expression with the type `type`. A
    String typed `String` is a String literal.
*/
List Macro.typed(List type, Var value) {
  if (value is <list> && value.list_payload().car().is_match_op())
    return %(expr $type $value);
  if (value is <string> && List.compare(type, %("String")) == 0)
    value = %(expr ("String") (segments
      (segexp (expr ("String") (literal ("String") $value)))));
  List expression = Macro.inserted(value, 1, 1);
  return %(expr $type @(expression.cddr()));
}



/** Returns what a typed quotation inserts for one use of a hole whose
    local holds `value`, as a rebuild inserts it. An expression hole
    (`lifts`) takes a number, String, or Symbol as its literal. Where the
    code takes an expression (`expression`), a binding, an `x2c_ident`
    spelling, or a Name hole's String becomes an identifier expression;
    in a Name hole's member position, an `x2c_ident` spelling is its
    String.
*/
Var Macro.inserted(Var value, int lifts, int expression) {
  match (value) case %(expr *): return value;
  if (lifts) value = _expr_value(value);
  if (!expression && lifts) return value;
  Var spelling = _spelling(value);
  if (!expression) return spelling;
  if (spelling is <string>) return %(expr () (ident $spelling));
  if (value ~= %(binding ? ?)) return %(expr () (ident $value));
  return value;
}

static Var _spelling(Var value) {
  if (value is not <list>) return value;
  List syntax = value;
  if (syntax.car() is not <string>) return value;
  match (syntax) case %("x2c.ident" ?(String name)): return name;
  return value;
}

/** Whether an ordinary expression hole still needs placement's expression
    shell. Scalars are lifted by insertion; complete expressions, staged
    code, and identifier values already have their insertion forms. Other
    Lists keep the existing projection path without changing their syntax.
*/
int Macro.needs_shell(Var value) {
  if (value is not <list>)
    return !(value.is_integer() || value.is_floating() ||
             value is <string> || value is <symbol>);
  match (value) {
    case %(!or (expr ? *) (code-value ? ? ?) ("x2c.ident" ?) (binding ? ?)):
      return 0;
  }
  return 1;
}

// number literals

/** Returns the C type of a number's Var family, or NULL when `value` is not
    a number. An untyped integer is an `int` when it fits one.
*/
List Macro.number_type(Var value) {
  switch (value.tag()) {
    case <i8>: return %(signed char);
    case <u8>: return %(unsigned char);
    case <i16>: return %(short);
    case <u16>: return %(unsigned short);
    case <i32>: return %(int);
    case <u32>: return %(unsigned);
    case <long>: return %(long);
    case <ulong>: return %(unsigned long);
    case <llong>: return %(long long);
    case <ullong>: return %(unsigned long long);
    case <f32>: return %(float);
    case <ldouble>: return %(long double);
  }
  if (value.is_floating()) return %(double);
  if (value.is_integer()) {
    long n = value.integer();
    return n == (int) n ? %(int) : %(long long);
  }
  return NULL;
}

/** Returns the literal expression of type `result` that holds `value`, a
    number of the scalar type `type`. An `int` value is its decimal
    literal; another number is its exact bits cast to `type`.
*/
List Macro.number_literal(List result, List type, Var value) {
  if (value.tag() == <i32>) return _int_literal(result, value);
  List literal = _bits_literal(value);
  return %(expr $result (parens (expr $result (cast $type $literal))));
}

/* Groups positional arguments by the definition's parameters: a sequence
   parameter takes every remaining argument as one List. */
static List _group(Macro t, List values) {
  Array grouped = [];
  foreach (List hole in t.assoc(<parameters>).list()) {
    int sequence = hole.assoc(<sequence>);
    /* One List of syntax or of numbers and Strings passes the whole
       sequence, as `call(f, items)`; the compiler lifts each scalar. */
    if (sequence && values && !values.cdr() && values.car() is <list> &&
        _items(values.car()))
      values = values.car();
    grouped.push(sequence ? values.var() : values.car());
    values = sequence ? NULL : values.cdr();
  }
  return grouped.list_free();
}

/* Whether `items` is a List of arguments rather than one: empty, or led by
   syntax, a number, or a String other than an identifier's or pending
   code's tag. A Symbol leads one syntax node. */
static int _items(List items) {
  if (!items) return 1;
  if (items ~= %((!or "x2c.ident" "x2c.quoted" "x2c.template") *)) return 0;
  Var first = items.car();
  return first is <list> || first is <string> || first.is_integer() ||
         first.is_floating();
}

/* An expression parameter takes code, so a number, String, or Symbol
   argument becomes the literal expression that holds it, as the compiler
   lifts a compile-time value. */
module Var _expr_value(Var value) {
  if (value is <string>)
    return %(expr (* char) (literal (* char) $(value.repr())));
  if (value is <symbol>)
    return %(expr ("Symbol") (literal ("Symbol") $(value.str()) $value));
  Type type = Macro.number_type(value);
  return type ? Macro.number_literal(type, type, value) : value;
}

/* C reads a negative literal as a negation, so it takes parentheses, and
   INT_MIN's magnitude does not fit an int, so its literal is cast back. */
static List _int_literal(Type result, Var value) {
  long n = value.integer();
  List literal = %(expr $result (literal (int) $(value.str())));
  if (n == INT_MIN)
    return %(expr $result (parens (expr $result (cast (int) $literal))));
  return n < 0 ? %(expr $result (parens $literal)) : literal;
}

/* The exact bits of a number that is not an int, as a long double or an
   unsigned long long literal that the caller casts to the number's type. */
static List _bits_literal(Var value) {
  X2CVarNumeric number;
  value.numeric_decode(number);
  Type literal_type = number.floating ? %(long double) : %(unsigned long long);
  String text = number.floating ? _float_text(number.floating_value)
                                : "%lluULL".printf(number.raw);
  return %(expr $literal_type (literal $literal_type $text));
}

/* NaN and the infinities have no literal, so they spell builtin calls. */
static String _float_text(long double n) {
  if (isnan(n)) return "__builtin_nanl(\"\")";
  if (isinf(n)) return n < 0 ? "(-__builtin_infl())" : "__builtin_infl()";
  return _hex_float(n);
}

/* Spells finite `n` exactly as a normalized hex literal. Printf's %La
   layout depends on the host's long double. */
static String _hex_float(long double n) {
  const char *sign = signbit(n) ? "-" : "";
  if (n == 0) return "%s0x0p+0L".printf(sign);
  int exponent;
  long double fraction = frexpl(fabsl(n), &exponent) * 2 - 1;
  char digits[32];
  int count = 0;
  for (; fraction != 0; count++) {
    fraction *= 16;
    int digit = (int) fraction;
    fraction -= digit;
    digits[count] = "0123456789abcdef"[digit];
  }
  digits[count] = 0;
  return "%s0x1%s%sp%+dL".printf(sign, count ? "." : "", digits, exponent - 1);
}

module List _expr_values(List values) {
  Array lifted = [];
  foreach (Var item in values) lifted.push(_expr_value(item));
  return lifted.list_free();
}
