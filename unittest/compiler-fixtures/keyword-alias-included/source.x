macro Decorator $fixture.identity(Function $target) => {
  $(x2c.function.body $target)...
}

keyword identity $fixture.identity;

identity List included_values(void) {
  return %[];
}
