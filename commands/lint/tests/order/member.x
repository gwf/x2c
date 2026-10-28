/* A member's diagnostics and suppression use physical lines. */
module int member_bridge(void) => module_target();

#define MEMBER_REGION 1
static int member_helper(void) => 2;
module int member_after_private(void) => member_helper();

#define MODULE_ROOT 1
static int other_root(void) => module_shared();
static int module_shared(void) => 3;
module int later_module_root(void) => module_shared();

#define MODULE_INVERSION 1
module int module_leaf(void) => 4;
module int module_later_caller(void) => module_leaf();
