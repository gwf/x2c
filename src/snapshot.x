/*  snapshot.x -- deterministic Lisp data writer for unit interfaces

    Copyright (c) 2026 Gary William Flake.

    Serializes interface rows as Lisp that the shared bare reader restores.
    `src/collect.x` writes each unit's `.xi` interface through this grammar.
*/

#pragma once

/* Values use part of the Lisp reader grammar: proper Lists, bare Symbols
   and Atoms, Strings, integers, and floating-point values. The outer form
   and rows are data; a loader never evaluates them.
*/
/** Writes one value in the restricted Lisp grammar.
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
    if (Atom.bare_spelling(text)) output.puts(text);
    else if (value is <symbol>) output.puts(value.repr());  // `<"<<">`
    else return 0;
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
