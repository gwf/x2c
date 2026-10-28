module {
  "member.x",
  "other.x",
  "types.x"
}
int module_target(void) => 1;
int module_caller(void) => member_bridge();
