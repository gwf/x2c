/*  test-symbolset.x -- runtime tests for SymbolSet literals */

#include "test-support.x"
$(import "test-macros.xmacro")

static const SymbolSet colors = %<<red green blue violet>>;
static const SymbolSet empty_set = %<<>>;

/* Quoted entries spell Symbols a bare entry cannot: reader punctuation is
   ordinary text and `>>` inside the quotes does not close the literal. */
static const SymbolSet operators = %<<"|=" "<<=" ">>=" ">>">>;
static const SymbolSet mixed = %<<plain "a\"b" tail "a\tb">>;

static void symbolset_len_and_index_cover_every_member(void) {
  Symbol members[] = { <red>, <green>, <blue>, <violet> };
  int count = sizeof(members) / sizeof(members[0]);

  EXPECT_INT_EQ(colors.len(), count);
  for (int i = 0; i < count; i++) {
    EXPECT_INT_EQ(colors.index(members[i]), i);
    EXPECT_TRUE(colors.contains(members[i]));
  }
  EXPECT_INT_EQ(colors.index(<orange>), -1);
  EXPECT_FALSE(colors.contains(<orange>));
}

static void symbolset_getindex_normalizes_and_bounds(void) {
  EXPECT_TRUE(colors.getindex(0) == <red>);
  EXPECT_TRUE(colors.getindex(3) == <violet>);
  EXPECT_TRUE(colors.getindex(-1) == <violet>);
  EXPECT_TRUE(colors.getindex(-4) == <red>);
  EXPECT_TRUE(colors.getindex(4) == 0);
  EXPECT_TRUE(colors.getindex(-5) == 0);
}

static void symbolset_iteration_yields_source_order(void) {
  Symbol expected[] = { <red>, <green>, <blue>, <violet> };
  int position = 0;

  foreach(Symbol member, colors) {
    EXPECT_TRUE(position < 4);
    if (position < 4) EXPECT_TRUE(member == expected[position]);
    position++;
  }
  EXPECT_INT_EQ(position, 4);
}

static void symbolset_empty_set_has_no_members(void) {
  EXPECT_INT_EQ(empty_set.len(), 0);
  EXPECT_INT_EQ(empty_set.index(<red>), -1);
  EXPECT_FALSE(empty_set.contains(<red>));
  EXPECT_TRUE(empty_set.getindex(0) == 0);
  EXPECT_TRUE(empty_set.getindex(-1) == 0);
  int visited = 0;
  foreach(Symbol member, empty_set) {
    (void) member;
    visited++;
  }
  EXPECT_INT_EQ(visited, 0);
}

static void symbolset_quoted_entries_own_reader_punctuation(void) {
  Symbol members[] = { <"|=">, <"<<=">, <">>=">, <">>"> };
  int count = sizeof(members) / sizeof(members[0]);

  EXPECT_INT_EQ(operators.len(), count);
  for (int i = 0; i < count; i++) {
    EXPECT_INT_EQ(operators.index(members[i]), i);
    EXPECT_TRUE(operators.contains(members[i]));
  }
  // The quotes delimit the entry; they are not part of the Symbol.
  EXPECT_FALSE(operators.contains(<"\"|=\"">));
  EXPECT_FALSE(operators.contains(<"|">));
}

static void symbolset_mixed_entries_keep_source_order(void) {
  Symbol expected[] = { <plain>, <"a\"b">, <tail>, <"a\tb"> };
  int position = 0;

  EXPECT_INT_EQ(mixed.len(), 4);
  foreach(Symbol member, mixed) {
    EXPECT_TRUE(position < 4);
    if (position < 4) EXPECT_TRUE(member == expected[position]);
    position++;
  }
  EXPECT_INT_EQ(position, 4);
  for (int i = 0; i < 4; i++) EXPECT_INT_EQ(mixed.index(expected[i]), i);
  EXPECT_FALSE(mixed.contains(<"a\\tb">));
}

void symbolset_suite(void) {
  $test.run(symbolset_len_and_index_cover_every_member);
  $test.run(symbolset_getindex_normalizes_and_bounds);
  $test.run(symbolset_iteration_yields_source_order);
  $test.run(symbolset_empty_set_has_no_members);
  $test.run(symbolset_quoted_entries_own_reader_punctuation);
  $test.run(symbolset_mixed_entries_keep_source_order);
}
