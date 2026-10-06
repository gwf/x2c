/*  adapter-memo.x -- memoized compiler adapter construction
*/

#pragma once

/* Reads `value` from `table` at `key`, or runs `create` to set it and stores
   the result. A null result is stored too, so a miss is computed once. */
macro Decorator $memo(Stmt $create, Expr $table, Expr $key, Expr $value) {
  Var cached;
  if ($table.try_get($key, cached)) $value = cached;
  else {
    $create;
    $table[$key] = $value;
  }
}

macro Decorator $adapter.memo(
  Stmt $create, Expr $compiler, Expr $key, Expr $value) {
  $memo($compiler.names.adapters, $key, $value) $create
}
