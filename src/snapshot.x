/*  snapshot.x -- deterministic compiler symbol snapshot I/O

    Copyright (c) 2026 Gary William Flake.

    Serializes the compiler's invariant runtime symbol `Map` as Lisp data and
    restores it through the shared Lisp reader. Source-specific declarations
    overlay the restored `Map` in the ordinary shallow-parse path. Writing
    sorts
    entries before emitting the versioned artifact; loading validates the
    complete reader shape before publishing a `Map`.
*/

#pragma once

/* Snapshot values use part of the Lisp reader grammar: proper Lists, bare
   Symbols and Atoms, Strings, integers, and floating-point values. The outer form and
   rows are data; the loader never evaluates them.
*/
/** Writes one value in the snapshot's restricted Lisp grammar.
    `List`s are written recursively. An atom that requires quoting or an
    unsupported value returns zero; otherwise the result is one. A successful
    result establishes representability, not stream health, so the caller must
    inspect `output.error()` separately. The stream remains open.
*/
int snapshot_write_var(File output, Var value) {
  if (value is <list>) {
    List list = value;
    output.putc('(');
    for (List p = list; p; p = p.cdr()) {
      if (p != list) output.putc(' ');
      if (!snapshot_write_var(output, p.car())) return 0;
    }
    output.putc(')');
    return 1;
  }
  if (value.is_atom()) {
    // lib/atom.x owns bare spelling and the reader's Symbol/Atom choice.
    String text = value.str();
    if (!Atom.bare_spelling(text)) return 0;
    output.puts(text);
    return 1;
  }
  if (value is <string>) {
    output.puts(value.repr());
    return 1;
  }
  if (value.is_integer()) {
    output.printf("%ld", value);
    return 1;
  }
  if (value.is_floating()) {
    output.printf("%.17g", value);
    return 1;
  }
  return 0;
}

static int _function_type(List type) {
  if (!type) return 0;
  Var first = type.car();
  if (first == <func> || first == <inline>) return 1;
  return first is <list> ? _function_type(first) : 0;
}

/** Writes a deterministic version-3 symbol snapshot to `output`.
    Rows are sorted before emission. Function rows whose spelling occurs in
    `fn_defs` carry a `definition` marker. Returns zero for an unrepresentable
    value or stream error and one on success; failure may leave partial output.
    The input `Map`s are unchanged and the stream remains open.
*/
int symbol_snapshot_write(Map symbols, Map fn_defs, File output) {
  Array entries = %[];
  foreach (Var (key, value), symbols) {
    List symbol_type = value is <list> ? value.list() : NULL, int defined = 0;
    match (key)
      case %(?(String spelling)):
        defined = symbol_type && _function_type(symbol_type) &&
                  fn_defs.contains(spelling);
    entries.push(defined ? %($key $value definition) : %($key $value));
  }
  entries.sort();
  output.puts("(snapshot 3 (\n");
  foreach (Var entry, entries) {
    output.puts("  ");
    if (!snapshot_write_var(output, entry)) return 0;
    output.putc('\n');
  }
  output.puts("))\n");
  entries.free();
  return !output.error();
}

static int _gensym(Var value) {
  if (value is not <list>) return 0;
  List list = value, int maximum = 0;
  match (list)
    case %(gensym ?id): if (id.is_integer()) maximum = Var.integer(id);
  foreach (Var item, list) {
    int found = _gensym(item);
    if (found > maximum) maximum = found;
  }
  return maximum;
}

/** Loads exactly one version-3 symbol snapshot from `path`.
    Returns a `Scope`-owned symbol `Map`. On success, optional `fn_defs`
    receives a
    `Scope`-owned `Map` of rows marked `definition`, and optional `gensym`
    receives
    the greatest nonnegative `(gensym N)` identifier found recursively. After
    the file and bare Lisp session are constructed, every read and validation
    path releases both.

    Raises: `<not-found>` or `<io-fail>` while reading, `<incomplete>` for a
    truncated Lisp form, or `<malformed>` for invalid Lisp syntax, an invalid
    snapshot shape, or trailing input.
*/
Map symbol_snapshot_load(String path, Map *fn_defs, int *gensym) {
  if (fn_defs) *fn_defs = NULL;
  if (gensym) *gensym = 0;
  File input = path.open("r"), Lisp lisp = Lisp.new_bare(), Map symbols = NULL;
  try {
    String source = input.string();
    unsigned cursor = 0;
    Var document = void, trailing = void;
    Symbol status = Lisp.read(lisp, source, &cursor, &document);
    if (status != <value> || document is not <list>)
      raise %(malformed (path $path) (why "invalid snapshot header"));
    List form = document;
    List entries = NULL;
    match (form) {
      case %(snapshot 3 (!set ?captured (!is type list))):
        entries = captured;
      default:
        raise %(malformed (path $path) (why "invalid snapshot header"));
    }
    status = Lisp.read(lisp, source, &cursor, &trailing);
    if (status != <eof>)
      raise %(malformed (path $path) (why "trailing snapshot form"));
    Map imported = %{};
    symbols = %{};
    foreach (Var entry, entries) {
      List row = entry is <list> ? entry.list() : NULL;
      if (!row || (row.len() != 2 && row.len() != 3))
        raise %(malformed (path $path) (why "invalid snapshot entry"));
      Var (key, value, marker) = row;
      int defined = row.len() == 3 && marker == <definition>;
      if ((!defined && row.len() != 2) || key is not <list> ||
          value is not <list>)
        raise %(malformed (path $path) (why "invalid snapshot entry"));
      symbols[key] = value;
      if (defined)
        match (key)
          case %(?(String spelling)): imported[spelling] = 1;
      int found = _gensym(entry);
      if (gensym && found > *gensym) *gensym = found;
    }
    if (fn_defs) *fn_defs = imported;
  }
  finally {
    input.close();
    Lisp.destroy(lisp);
  }
  return symbols;
}
