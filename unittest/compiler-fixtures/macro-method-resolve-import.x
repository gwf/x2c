#pragma once

macro Expression $string_len(Expr $value) =>
  $(let ((method (Type.resolve_member (Code.type $value) "len" 1)))
    `(expr () (call (expr ,(caddr method) (ident ,(cadr method)))
      (args ,$value))));

macro Expression $has_method(Type $type, Name $name) =>
  $(if (Type.resolve_member $type (Code.binding_spelling $name) 1) 1 0);
