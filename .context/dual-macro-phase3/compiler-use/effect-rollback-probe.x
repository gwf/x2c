void Compiler.prototype_effect_rollback(Compiler c) {
  SymScope *base = _semantic_scope(c.sym, c.sym.base_scopes - 1);
  Map saved_global_bindings = base.bindings.copy();
  int early = c.early_decls.len(), init = c.inits.len();
  int origin = c.origin, exception = c.needs_exception;
  Var key = Atom.intern("prototype-effect");
  c.sym.push_new_scope();
  SymTxn transaction = c.begin_semantic_transaction();
  int binding_count = c.names.next_binding;
  String generated = c.fresh_name("effect_probe");
  (void) c.sym.introduce(generated);
  c.add_early(%(prototype-declaration));
  c.add_init(<early>, %(prototype-init));
  c.names.adapters[key] = %(prototype-adapter);
  List global = c.sym.reference_global(%("__prototype_global"));
  c.origin = origin + 1;
  c.needs_exception = !exception;
  transaction.rollback();
  fprintf(stderr,
    "effects rollback: binding=%d fresh=%d early=%d init=%d memo=%d global=%d origin=%d exception=%d\n",
    c.names.next_binding == binding_count,
    c.fresh_name("effect_probe") == generated,
    c.early_decls.len() == early, c.inits.len() == init,
    !(key in c.names.adapters),
    c.sym.resolve_global(%("__prototype_global"), NULL) != global,
    c.origin == origin, c.needs_exception == exception);
  c.sym.pop_scope();
  base = _semantic_scope(c.sym, c.sym.base_scopes - 1);
  base.bindings = saved_global_bindings;
  c.early_decls.resize(early);
  c.inits.resize(init);
  c.names.adapters.del(key);
  c.origin = origin;
  c.needs_exception = exception;
}
