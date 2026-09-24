/* broken.x -- a unit that does not parse still gets its token findings. */
int broken(int value {
  return !(value is <list>);
}
