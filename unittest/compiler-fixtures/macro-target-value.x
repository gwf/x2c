meta static List identity(List target) { return target; }
macro Decorator $keep(Macro $target) => $identity($target);

$keep() 17;
