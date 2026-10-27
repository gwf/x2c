/*  macrovalue.x -- macros as values that build and recognize code

    Copyright (c) 2025 Gary William Flake

    A `Macro` is the canonical `macrodef` record of a definition. `$name`
    selects one and `macro Kind(...) => ...` creates one. Applying it returns
    a pending invocation the compiler expands and binds at the insertion
    site; naming it in a `case` derives a Match pattern from the same body.
    Generated code calls these operations by name, so the module is part of
    the prelude.
*/

#pragma once

#include "common.x"
#include "match/match.x"

/** Records fixed-local slots for distinct-identity checks and Name slots
    for member-spelling comparisons during recognition.
*/
typedef struct MacroFixedSlots {
  int count, slots[MACHINE_BINDER_MAX];
  int names, name_slots[MACHINE_BINDER_MAX];
} MacroFixedSlots;

/** Records where each of a `case`'s binders reads its capture: the slot
    of its internal binder in the pattern that captured, and its own slot
    in the `case`, which need not share the parameters' order.
*/
typedef struct MacroPublishing {
  int from[MACHINE_BINDER_MAX], fallback[MACHINE_BINDER_MAX];
  int to[MACHINE_BINDER_MAX];
  int count, binders, complete;
  unsigned long definite;
} MacroPublishing;

/** Holds one macro-valued `case` site's prepared recognition for the
    process: the plan Match keeps, the slots of the macro's fixed locals, and
    where each binder reads its capture. The compiler emits one
    zero-initialized static site per `case`.
*/
typedef struct MacroCaseSite {
  MatchCaptureSite match;
  MacroFixedSlots policy;
  MacroPublishing route;
  int ready;
} MacroCaseSite;

#include "array/array.x"
#include "atom.x"
#include "list/list.x"
#include "meta.x"
#include "string/string.x"
#include "var/var.x"
#include <math.h>

/** Starts a macro-valued `case` without `Macro_case_root` when `code` is
    its own view. `head`, the Symbol heading the derived pattern, is not a
    source wrapper or `seq`. Returns 2 after storing `code` in `cursor`
    for a subject headed by `head`, 0 for an empty subject or one headed by
    another Symbol than a wrapper, `expr`, or `seq`, which cannot match,
    and -1 when `Macro_case_root` must decide.
*/
inline int Macro_case_start(List code, Symbol head, List &cursor) {
  if (!code) return 0;
  Symbol first = Macro_case_symbol(code.car);
  if (first == head && (head != <expr> || Macro_case_own(code.caddr()))) {
    cursor = code;
    return 2;
  }
  return first && first != <at> && first != <src> && first != <expr> &&
    first != <seq> ? 0 : -1;
}

/** Whether an `expr` node whose content is `content` is its own view: the
    content is not a List headed by an Atom, as a retained invocation's is,
    or by the `expr` a template shell holds.
*/
inline int Macro_case_own(Var content) {
  List node = content.list_payload();
  if (!node) return 1;
  Symbol head = Macro_case_symbol(node.car);
  return head && head != <expr>;
}

/** The short Symbol `value` holds, or 0 for any other value. */
inline Symbol Macro_case_symbol(Var value) {
  Symbol symbol = value.u64 - VAR_SYMBOL_OFFSET;
  return symbol < 1ul << 51 ? symbol : 0;
}

/** Stores in `cursor` the List a macro-valued `case` examines for
    `value`, beneath its source wrappers, and returns whether there is
    one. A List headed by another Symbol than a wrapper or `expr` is its
    own view.
*/
inline int Macro_case_enter(Var value, List &cursor) {
  List node = value.list_payload();
  Symbol head = node ? Macro_case_symbol(node.car) : 0;
  if (!head || head == <at> || head == <src> || head == <expr>)
    return Macro_case_view(value, cursor);
  cursor = node;
  return 1;
}

/** Retains a macro and hole patterns for repeated recognition. A pattern
    independent of subject bindings is derived once; contextual references
    are resolved against each subject. The caller keeps the source values
    alive as long as this record. Match plans use the active Match cache.
*/
typedef struct MacroMatcher {
  Macro shape;
  List holes, pattern;
} MacroMatcher;

module {
  "construction.x",
  "patterns.x",
  "recognition.x",
}
