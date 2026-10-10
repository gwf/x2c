macro Decorator $fixture.identity(Function $target) {
  @(Code.body $target)
}

keyword identity $fixture.identity;

identity List included_values(void) {
  return %[];
}
