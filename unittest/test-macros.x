#pragma once

macro Stmt $test.scoped() {
  Scope.retain();
  defer Scope.release();
}

macro Stmt $test.run(Name $function) {
  TestHarness_run($(Code.binding_spelling $function), $function);
}

macro Stmt $test.suite(Name $suite) {
  if (TestSuite_begin($(Code.binding_spelling $suite))) $suite();
}

macro Expression $test.incrementing_lambda(Name $binding) =>
  %!() using &$binding => ++$binding;

macro Expression $test.block_lambda(Expr $bias) =>
  %!(int value) => {
    int result = value + $bias;
    if (result) return result;
    return;
  };
