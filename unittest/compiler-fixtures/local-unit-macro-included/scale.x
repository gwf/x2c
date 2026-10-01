macro Unit $scale(Type $type, Name $method, Name $label, Expr $factor) {
  $type $type.$method($type value) { return value * $factor; }
  String $label($type value) { return %"$value"; }
}

$scale(int, twice, twice_label, 2);
