/*  categories.x -- macro category spellings and result kinds
*/

#pragma once

/* macro categories

   Every syntactic category a definition names, as a hole kind, a result
   kind, or a decorator target, with the kinds each spelling selects.
   Spellings match without regard to case. `named` marks the row whose
   spelling names its hole or result kind in diagnostics. */

static enum { CATEGORY_HOLE_NAME = 1, CATEGORY_RESULT_NAME = 2 };

module typedef struct MacroCategory {
  const char *spelling;
  Symbol hole, result;
  int target, named;
} MacroCategory;

static const MacroCategory macro_categories[] = {
  { "Expr",          <expr>,       <expression>, 1, 1 },
  { "Expression",    <expr>,       <expression>, 1, 2 },
  { "Stmt",          <block>,      <block-item>, 1, 3 },
  { "Field",         <field>,      <field>,      1, 3 },
  { "Entry",         <map-entry>,  <map-entry>,  0, 3 },
  { "Enumerator",    <enumerator>, <enumerator>, 0, 3 },
  { "Unit",          <unit>,       <unit>,       1, 3 },
  { "Declaration",   0,            <decl-unit>,  0, 2 },
  { "Decorator",     0,            <decorator>,  0, 2 },
  { "Function",      <function>,   0,            1, 1 },
  { "NamedType",     <named-type>, 0,            1, 1 },
  { "Type",          <type>,       0,            0, 1 },
  { "Decl",          <decl>,       0,            0, 1 },
  { "DeclaratorRow", <decl-row>,   0,            0, 1 },
  { "Name",          <name>,       0,            0, 1 },
  { "Literal",       <literal>,    0,            0, 1 },
  { "Param",         <param>,      0,            0, 1 },
  { "Catch",         <catch>,      0,            0, 1 },
  { "Captures",      <captures>,   0,            0, 1 },
  { "MatchRow",      <match-row>,  0,            0, 1 }
};

#define MACRO_CATEGORY_COUNT \
  (int) (sizeof(macro_categories) / sizeof(macro_categories[0]))

module const MacroCategory *_category(String spelling) {
  String key = spelling.lower();
  for (int i = 0; i < MACRO_CATEGORY_COUNT; i++)
    if (key == String.new(macro_categories[i].spelling).lower())
      return &macro_categories[i];
  return NULL;
}

module int _decorator_target(Symbol hole) {
  for (int i = 0; i < MACRO_CATEGORY_COUNT; i++)
    if (macro_categories[i].hole == hole) return macro_categories[i].target;
  return 0;
}

module String _kind_spelling(Symbol kind) {
  for (int i = 0; i < MACRO_CATEGORY_COUNT; i++) {
    const MacroCategory *category = &macro_categories[i];
    if ((category.hole == kind && category.named & CATEGORY_HOLE_NAME) ||
        (category.result == kind && category.named & CATEGORY_RESULT_NAME))
      return category.spelling;
  }
  return kind.str().capitalize();
}

