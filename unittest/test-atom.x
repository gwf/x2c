/*  test-atom.x -- canonical exact-name tests */

#include "test-support.x"

#include <stdint.h>

static Var _atom_read_lisp(String source, Symbol *status) {
  Lisp lisp = Lisp.new_bare();
  unsigned cursor = 0;
  Var value = void;
  *status = Lisp.read(lisp, source, &cursor, &value);
  Lisp.destroy(lisp);
  return value;
}


static void atom_compact_and_long_representations(void) {
  Atom compact = Atom.intern(%"alpha");
  Atom compact_exact = Atom.intern(%"va_arg");
  Atom long_name = Atom.intern(%"VeryLongIdentifierName");
  EXPECT_TRUE(compact.is_atom());
  EXPECT_TRUE(compact is <symbol>);
  EXPECT_STR_EQ(compact.str(), "alpha");
  EXPECT_TRUE(compact_exact is <symbol>);
  EXPECT_STR_EQ(compact_exact.str(), "va_arg");
  EXPECT_TRUE(long_name.is_atom());
  EXPECT_TRUE(long_name is <lsym>);
  EXPECT_STR_EQ(long_name.str(), "VeryLongIdentifierName");
  EXPECT_TRUE(long_name.first() == 'V');
}


static void atom_preserves_exact_spelling(void) {
  Atom mixed = Atom.intern(%"Mixed_Case_Identifier");
  Atom lower = Atom.intern(%"mixed_case_identifier");
  EXPECT_STR_EQ(mixed.str(), "Mixed_Case_Identifier");
  EXPECT_STR_EQ(lower.str(), "mixed_case_identifier");
  EXPECT_FALSE(mixed.equal(lower));
}


static void atom_long_identity_and_prefixes(void) {
  Atom alpha = Atom.intern(%"common-prefix-long-name-alpha");
  Atom again = Atom.intern(String.new("common-prefix-long-name-alpha"));
  Atom beta = Atom.intern(%"common-prefix-long-name-beta");
  EXPECT_TRUE(alpha.u64 == again.u64);
  EXPECT_TRUE(alpha.same(again));
  EXPECT_FALSE(alpha.equal(beta));
  EXPECT_TRUE(alpha.u64 != beta.u64);
  EXPECT_TRUE(alpha.pointer() == again.pointer());
}


static void atom_hash_and_string_alignment(void) {
  String spelling = %"LongAtomHashAndAlignment";
  Atom atom = Atom.intern(spelling);
  EXPECT_TRUE(atom.hash() == spelling.hash());
  EXPECT_TRUE(((uintptr_t) atom.pointer() & 0x7) == 0);
  EXPECT_TRUE(atom.pointer() == spelling);
}


static void atom_rejects_empty_spelling(void) {
  int caught = 0;
  try Atom.intern(NULL);
  catch %(bad-arg *): caught++;
  try Atom.intern(String.new(""));
  catch %(bad-arg *): caught++;
  EXPECT_INT_EQ(caught, 2);
}


static void atom_repr_round_trips_lisp_reader(void) {
  String spellings[] = {
    %"Very Long Atom",
    %"1234567890123",
    %"+123456789012",
    %"comment//looking-long",
    %"comment/*looking-long",
    %"angle<atom>long",
    %"paren(atom)long",
    %"backslash\\atom-long",
    %"line\nbreak-long"
  };
  for (int i = 0; i < sizeof spellings / sizeof spellings[0]; i++) {
    Atom expected = Atom.intern(spellings[i]);
    Symbol status;
    Var actual = _atom_read_lisp(expected.repr(), &status);
    EXPECT_TRUE(status == <value>);
    EXPECT_TRUE(actual.u64 == expected.u64);
  }
}


static void atom_list_literals_are_exact(void) {
  Symbol truncated = Symbol.new("VeryLongIdentifierName");
  List values = %(
    VeryLongIdentifierName
    Mixed_Case_Identifier
    escaped\ atom
    <
    \x31
    \x31numeric-looking-long
    comment\x2F/looking-long
    $truncated
  );
  EXPECT_STR_EQ(values.getindex(0).str(), "VeryLongIdentifierName");
  EXPECT_STR_EQ(values.getindex(1).str(), "Mixed_Case_Identifier");
  EXPECT_STR_EQ(values.getindex(2).str(), "escaped atom");
  EXPECT_STR_EQ(values.getindex(3).str(), "<");
  EXPECT_STR_EQ(values.getindex(4).str(), "1");
  EXPECT_STR_EQ(values.getindex(5).str(), "1numeric-looking-long");
  EXPECT_STR_EQ(values.getindex(6).str(), "comment//looking-long");
  EXPECT_TRUE(values.getindex(0) is <lsym>);
  EXPECT_TRUE(values.getindex(4) is <symbol>);
  EXPECT_TRUE(values.getindex(7) is <symbol>);
  EXPECT_STR_EQ(values.getindex(7).str(), "verylongid");
}


static void atom_list_angles_only_quote_spelling(void) {
  List bare = %(foo \x31);
  List angled = %(<foo> <1>);
  List numeric = %(1);
  List empty = %(<"">);
  EXPECT_TRUE(bare == angled);
  EXPECT_TRUE(angled.getindex(0) is <symbol>);
  EXPECT_TRUE(angled.getindex(1) is <symbol>);
  EXPECT_TRUE(angled.getindex(1).symbol() == <"1">);
  EXPECT_TRUE(numeric.getindex(0) is <i32>);
  EXPECT_TRUE(empty.getindex(0) is <symbol>);
  EXPECT_TRUE(empty.getindex(0).symbol() == 0);
}


static void atom_list_and_lisp_readers_canonicalize(void) {
  List first = %(
    VeryLongIdentifierName
    Mixed_Case_Identifier
    escaped\ atom
    <
    \x31
    \x31numeric-looking-long
    comment\x2F/looking-long
  );
  List second = %(
    VeryLongIdentifierName
    Mixed_Case_Identifier
    escaped\ atom
    <
    \x31
    \x31numeric-looking-long
    comment\x2F/looking-long
  );
  EXPECT_TRUE(first == second);
  Symbol status;
  Var read = _atom_read_lisp(first.repr(), &status);
  EXPECT_TRUE(status == <value>);
  EXPECT_TRUE(read is <list>);
  EXPECT_TRUE(read.pointer() == first);
}


static void atom_list_promotion_preserves_long_payload(void) {
  String.pool_retain_named("test-atom-promotion-values");
  String spelling = String.printf("pool-owned-long-atom-%d", 314159);
  Atom atom = Atom.intern(spelling);
  List result = cons(atom, NULL);
  EXPECT_TRUE(atom is <lsym>);
  EXPECT_TRUE(atom.pointer() == spelling);
  EXPECT_TRUE(List.promote(result) == result);
  String.pool_release();

  EXPECT_STR_EQ(atom.str(), "pool-owned-long-atom-314159");
  EXPECT_TRUE(result.car().u64 == atom.u64);
  Atom again = Atom.intern(String.new("pool-owned-long-atom-314159"));
  EXPECT_TRUE(again.u64 == atom.u64);
}


static void atom_bare_spelling_owns_writer_contract(void) {
  EXPECT_TRUE(Atom.bare_spelling(%"foo"));
  EXPECT_TRUE(Atom.bare_spelling(%"*"));
  EXPECT_TRUE(Atom.bare_spelling(%"set!"));
  EXPECT_TRUE(Atom.bare_spelling(%"+"));
  EXPECT_FALSE(Atom.bare_spelling(NULL));
  EXPECT_FALSE(Atom.bare_spelling(%""));
  EXPECT_FALSE(Atom.bare_spelling(%"1x"));
  EXPECT_FALSE(Atom.bare_spelling(%"+1"));
  EXPECT_FALSE(Atom.bare_spelling(%"]x"));
  EXPECT_FALSE(Atom.bare_spelling(%"}x"));
  EXPECT_FALSE(Atom.bare_spelling(%"<x"));
  EXPECT_FALSE(Atom.bare_spelling(%"\\x"));
  EXPECT_FALSE(Atom.bare_spelling(%"a b"));
  EXPECT_FALSE(Atom.bare_spelling(%"a\"b"));
  EXPECT_FALSE(Atom.bare_spelling(%"a//b"));
}

$(import "test-macros.xmacro")

void atom_suite(void) {
  $test.run(atom_compact_and_long_representations);
  $test.run(atom_bare_spelling_owns_writer_contract);
  $test.run(atom_preserves_exact_spelling);
  $test.run(atom_long_identity_and_prefixes);
  $test.run(atom_hash_and_string_alignment);
  $test.run(atom_rejects_empty_spelling);
  $test.run(atom_repr_round_trips_lisp_reader);
  $test.run(atom_list_literals_are_exact);
  $test.run(atom_list_angles_only_quote_spelling);
  $test.run(atom_list_and_lisp_readers_canonicalize);
  $test.run(atom_list_promotion_preserves_long_payload);
}
