/*  definitions.x -- build and print authored definition rows */

// definition rows

/** Returns one row for each function, foreign alias, and typedef that the
    lowered unit `ast` defines, in source order:
    `(function NAME DISPLAY TYPE PARAMETERS LINE DOC STATIC ORIGIN DECLARATOR
    SPAN)` or `(typedef NAME BASE MODIFIERS SPAN)`. `ORIGIN` is `<source>`,
    `<macro>` for a Unit macro or generated body, or `<alias>`. `DECLARATOR`
    is the token range of an authored function's declarator, and `SPAN` the
    token range and privacy of the top-level form that produced the
    definition; either is empty when the compiler made the definition.
    `LINE` is 1 and `DOC` empty for a definition without authored source.
*/
List Compiler.definition_rows(Compiler c, List ast) {
  Array rows = [];
  // Prototypes and imported units have no local function node.
  foreach (List node in ast) match (node) {
    case %(function ?type (bind ?binding ?modifiers) ?): {
      List row = _function_row(c, type, binding, modifiers, 0);
      if (row) rows.push(row);
    }
    case %(falias
           (declare ?type (bindings (bind ?binding ?modifiers))) ?): {
      List row = _function_row(c, type, binding, modifiers, 1);
      if (row) rows.push(row);
    }
    case %(typedef ?base (bindings *declarators)):
      foreach (List declarator in declarators)
        if (declarator ~= %(bind ?binding ?modifiers))
          rows.push(
            %(typedef $(Ast.binding_spelling(binding)) $base $modifiers
              $(_span(c, node))));
  }
  return rows.list_free();
}

/* The row of a function or foreign alias, or NULL when its binding has no
   spelling. */
static List _function_row(
  Compiler c, List type, List binding, List modifiers, int alias) {
  String name = Ast.binding_spelling(binding);
  if (!name) return NULL;
  Type signature =
    %(declare $type (bindings (bind $binding $modifiers))).type_from_ast();
  int line = 1, Var doc = "", List declarator = NULL, span = _span(c, binding);
  if (c.semantic_binding_facts()[%(api-definition $binding)] ~=
      %(?(int recorded) ?text ?range)) {
    line = recorded;
    if (text is <string>) doc = text;
    declarator = range;
  }
  /* Authored prose precedes the whole form, before any decorator. */
  if (span ~= %(?(int start) *) && (declarator || alias)) {
    Token first = c.tokenizer.tokens;
    first += start;
    if (alias) line = first.line;
    String written = c.definition_doc(first);
    doc = written ? written : "";
  }
  Symbol origin = declarator ? <source> : <macro>;
  if (alias) origin = <alias>;
  return %(function $name $(_display(c, binding, name)) $signature
           $(_parameter_names(c, modifiers)) $line $doc
           $(type.type().is_static()) $origin $declarator $span);
}

/* A method displays as `Owner.member`. */
static String _display(Compiler c, List binding, String name) {
  if (c.semantic_binding_facts()[%(method $binding)] ~=
      %(?(String owner) ?(String member))) return %"$owner.$member";
  return c.unprefixed(name);
}

static List _span(Compiler c, List key) =>
  c.fact(%(definition-span $key));

static List _parameter_names(Compiler c, List modifiers) {
  Array names = [];
  if (modifiers ~= %((fnmod (params *parameters)) *))
    foreach (List parameter in parameters)
      if (parameter ~= %(param ? (bind ?binding ?)))
        names.push(_parameter_name(c, binding));
  return names.list_free();
}

/* A parameter's source spelling, or "" for an unnamed parameter. */
static String _parameter_name(Compiler c, List binding) {
  String name = Ast.binding_spelling(binding);
  Var spelling;
  Map facts = c.semantic_binding_facts();
  if (facts.try_get(%(source-spelling $binding), spelling)) name = spelling;
  return name ? name : "";
}

// definition dump

/** Prints the `--dump-definitions` projection of the lowered unit `ast`:
    `(unit PATH)`, the module comment as `(module TEXT)` when the file opens
    with one, then one row per `Compiler.definition_rows` entry. The
    command-line reference in the book describes the fields.
*/
void Compiler.dump_definitions(Compiler c, List ast) {
  printf("%s\n", %(unit $(c.filename)).repr());
  Token tokens = c.tokenizer.tokens, first = tokens;
  while (first.type == <space> || first.type == <preproc>) first++;
  if (first.type == <comment>) printf("%s\n", %(module $(first.text)).repr());
  foreach (List row in c.definition_rows(ast)) match (row) {
    case %(function *): _print_function(c, tokens, row);
    case %(typedef *): _print_type(c, tokens, row);
  }
}

static void _print_function(Compiler c, Token tokens, List row) {
  if (row ~= %(function ?name ?display ?type ?names ?line ?doc ?is_static
              ?origin ?declarator ?span)) {
    String text = "";
    if (declarator ~= %(?(int start) ?(int body)))
      text = _source_text(tokens + start, tokens + body);
    List location = _location(tokens, span);
    printf(
      "%s\n",
      %(function (name $name) (display $display) (line $line)
        $(_definition_source(
          c, tokens, declarator ? declarator : span, line.integer()))
        $(location.cadr()) (static $is_static) (origin $origin)
        (doc $doc) (text $text) (type $type) (params $names)).repr());
  }
}

/* A typedef with a source span prints its text without the closing `;`,
   its kind, its doc, and its privacy. */
static void _print_type(Compiler c, Token tokens, List row) {
  if (row ~= %(typedef ?name ?base ?modifiers ?span)) {
    Var doc = "", text = "", kind = <alias>;
    List location = _location(tokens, span), privacy = NULL;
    if (span ~= %(?(int start) ?(int end) ?private)) {
      Token last = tokens + end, final = last - 1;
      if (final.type == <;>) last = final;
      text = _source_text(tokens + start, last);
      kind = _type_kind(tokens + start, base, modifiers);
      String written = c.definition_doc(tokens + start);
      if (written) doc = written;
      privacy = %((private $(!c.publishes_typedef(name))));
    }
    printf(
      "%s\n",
      %(type (name $name) (kind $kind) @location
        $(_definition_source(c, tokens, span, 0)) @privacy (doc $doc)
        (text $text)).repr());
  }
}

/* Resolve an authored range or invocation line through source markers. */
static List _definition_source(
  Compiler c, Token tokens, List range, int line) {
  Token first = tokens;
  if (range) first += range.car().integer();
  else {
    if (line <= 1) return %(source);
    while (first.type != <eof> && first.line < line) first++;
  }
  line = first.line;
  String path = c.token_source(first, line);
  return %(source $path $line);
}

/* Source text between two tokens with comments removed and each run of
   whitespace written as one space. */
static String _source_text(Token first, Token last) {
  Buffer output = auto Buffer.new(0);
  int gap = 0;
  for (Token token = first; token < last; token++) {
    if (token.type == <space> || token.type == <comment>) gap = 1;
    else if (token.len) {
      if (gap && output.len()) output.write_char(' ');
      output.write(token.text);
      gap = 0;
    }
  }
  return output;
}

/* The one-based line and byte range of a token range. */
static List _location(Token tokens, List range) {
  if (range ~= %(?(int start) ?(int end) *)) {
    Token first = tokens + start, last = tokens + end - 1;
    return %((line $(first.line))
             (span $(first.pos) $(last.pos + last.len)));
  }
  return %((line 0) (span));
}

static Symbol _type_kind(Token first, List base, List modifiers) {
  if (first.text == "class") return <class>;
  if (modifiers ~= %(?pointer (fnmod *) *))
    if (pointer == <*>) return <callback>;
  if (base ~= %((!or ?kind struct union enum) *)) return kind;
  return <alias>;
}
