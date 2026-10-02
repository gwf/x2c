#include "x2c.x"
macro Unit $install_declaration() {
  $(list '(macrodef
      (name built_declare) (kind block-item)
      (target) (targetp ())
      (parameters
        ((macro-param (binder ?n) (kind name) (sequence 0))
         (macro-param (binder ?v) (kind expr) (sequence 0))))
      (fresh ()) (captures ())
      (pattern
        (args
          (capture (!and (source ?n) (source ?))
            (value ?__macro_value_n) (expression ?) (splice *))
          (capture (!and (source ?v) (source ?))
            (value ?) (expression ?__macro_expression_v) (splice *))))
      (template
        (seq (declare (int)
          (bindings (op = (bind ?__macro_value_n ())
            (expr (macro-expr) ?__macro_expression_v))))))
      (local 0)))...
}
$install_declaration();
macro Statement $outer_built(Name $out) {
  $built_declare(v, 4);
  $out = v;
}
int main(void) {
  int v = 7000, result = 0;
  $outer_built(result);
  printf("%d %d\n", result, v);
  return result != 4 || v != 7000;
}
