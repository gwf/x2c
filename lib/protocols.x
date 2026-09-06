/*  protocols.x -- built-in runtime protocol declarations

    Copyright (c) 2026 Gary William Flake

    Declares `Block` storage views, `Iter` traversal, and `Var` boxing for
    built-in
    runtime types. Each declaration generates its static adapters and
    dynamic descriptor rows.
 */

#pragma once
#include "common.x"

protocol Block(T) {
  void   T.clear(T);
  size_t T.len(T);
  size_t T.capacity(T);
  int    T.truth(T);
  void   T.pop(T);
  void   T.free(T);
  void   T.truncate(T, size_t length);
}

protocol Iter(T) {
  Iter T.iter(T, Iter dest);
}

/* Participation is explicit. The Var forward converters, Iter methods, and
   Block storage-view converters below are declared in common.x and resolve
   within this unit. Adoptions whose converters are defined elsewhere remain
   beside those converters in tokenizer.x, file.x, and string.x. */

protocol Block(Array);  protocol Block(Bytes);
protocol Iter(Array);  protocol Iter(File);  protocol Iter(List);
protocol Iter(Map);    protocol Iter(String);

protocol Var(Array);   protocol Var(Block);  protocol Var(Buffer);
protocol Var(Bytes);   protocol Var(File);   protocol Var(Iter);
protocol Var(List);    protocol Var(Map);    protocol Var(String);
protocol Var(Symbol);  protocol Var(uchar);  protocol Var(uint);
protocol Var(ulong);   protocol Var(ushort);

protocol Var(T) {
  associated Key = Var;
  associated Value = Var;
  associated Needle = Var;

  String T.str(T);
  String T.repr(T);
  Buffer T.write_str(T, Buffer);
  Buffer T.write_repr(T, Buffer);
  unsigned T.hash(T);
  int T.equal(T, T);
  int T.compare(T, T);
  int T.truth(T);
  Iter T.iter(T, Iter dest);
  int T.contains(T, Needle);
  T T.add(T, T);
  T T.sub(T, T);
  T T.mul(T, T);
  T T.div(T, T);
  T T.mod(T, T);
  T T.neg(T);
  Value T.getindex(T, Key);
  Value T.setindex(T, Key, Value);
  Value T.updateindex(T, Key, Symbol, Value);
  Value T.postfixindex(T, Key, Symbol);
  T T.export_context(T, Context source);
}
