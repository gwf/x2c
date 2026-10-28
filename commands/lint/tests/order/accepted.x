/* Shared helpers, recursive groups and independent ties. */
int read_public(void) => read_step();
int write_public(void) => write_step();
static int read_step(void) => shared_value();
static int shared_value(void) => 1;
static int write_step(void) => shared_value();

#define RECURSIVE 1
int cycle_a(int n) => n ? cycle_helper(n - 1) : 0;
int cycle_b(int n) => n ? cycle_a(n - 1) : 0;
static int cycle_helper(int n) => cycle_b(n);

#define PRIVATE_CYCLE 1
static int private_root(int n) => private_a(n);
static int private_b(int n) => n ? private_a(n - 1) : 0;
static int private_a(int n) => n ? private_b(n - 1) : 0;

#define UNRELATED 1
int independent_second(void) => 2;
int independent_first(void) => 1;

#define REMAINING_ROOTS 1
static int left_root(void) => shared_leaf();
static int shared_leaf(void) => 3;
static int right_root(void) => shared_leaf();

#define CROSS_BOUNDARY 1
static int fixed_helper(void) => 4;
#define KEEP_PROVIDER_AVAILABLE 1
int boundary_public(void) => fixed_helper();

#define SHADOWED_BINDING 1
int spelling_only(void) => 1;
int shadowed_pointer(int (*spelling_only)(void)) => spelling_only();

#define SAME_GROUP_SHARED 1
int broad_root(void) => first_consumer() + later_consumer();
static int first_consumer(void) => reused_leaf();
static int reused_leaf(void) => 1;
static int later_consumer(void) => reused_leaf();

#define VARIADIC_PUBLIC 1
int variadic_root(List @args) => variadic_leaf();
int later_variadic_root(void) => variadic_consumer();
static int variadic_leaf(void) => 1;
static int variadic_consumer(void) => variadic_leaf();

#define META_OWNERSHIP 1
meta int known_meta_root(void) => meta_shared_leaf();
int later_meta_consumer_root(void) => later_meta_consumer();
static int meta_shared_leaf(void) => 1;
static int later_meta_consumer(void) => meta_shared_leaf();

#define RECURSIVE_SHARED_READER 1
int recursive_reader(void) => recursive_first(1) + later_recursive();
static int recursive_first(int n) => n ? recursive_second(n - 1) : 0;
static int recursive_second(int n) => n ? recursive_first(n - 1) : 0;
static int later_recursive(void) => recursive_second(1);
