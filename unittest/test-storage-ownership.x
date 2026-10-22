/*  test-storage-ownership.x -- explicit container storage lifetimes */

#include "typed-array.x"
#include "typed-map.x"
#include "test-support.x"
#include "test-macros.x"

static int storage_drops;

static void _storage_drop(void *value) {
  (void) value;
  __atomic_fetch_add(&storage_drops, 1, __ATOMIC_SEQ_CST);
}

static void storage_scope_transfer_preserves_allocations(void) {
  ScopeStats before = Scope.stats();
  Scope source = Scope.new(), destination = Scope.new();
  Scope.push(&source);
  Scope child = Scope.child();
  Scope.pop();
  char *text = Scope.memdup_in(&child, "owned", 6);
  EXPECT_PTR_EQ(child.parent(), source);
  EXPECT_TRUE(source.contains(child));
  child.transfer(destination);
  child.transfer(destination);
  source.destroy();
  EXPECT_PTR_EQ(child.parent(), destination);
  EXPECT_PTR_EQ(Scope.owner(text), child);
  EXPECT_STR_EQ(text, "owned");
  destination.destroy();
  EXPECT_INT_EQ(Scope.stats().live_allocations, before.live_allocations);
  EXPECT_INT_EQ(Scope.stats().live_scopes, before.live_scopes);
}

static void storage_empty_arrays_have_private_scopes(void) {
  $test.scoped();
  Array array = [];
  Array copy = array.copy(), slice = array[0:0];
  Scope owner = array;
  EXPECT_NOT_NULL(owner);
  EXPECT_PTR_EQ(Scope.owner(array), owner);
  EXPECT_PTR_EQ(owner.parent(), *Scope.top());
  EXPECT_TRUE(copy.scope() != owner);
  EXPECT_TRUE(slice.scope() != owner);
  Scope destination = Scope.new();
  owner.transfer(destination);
  for (int i = 0; i < 128; i++) array.push(i);
  EXPECT_PTR_EQ(Scope.owner(array), owner);
  EXPECT_PTR_EQ(Scope.owner((unsigned char *) array.bytes - sizeof(Block)),
    owner);
  EXPECT_INT_EQ(array[127].int(), 127);
  destination.destroy();
}

static void storage_maps_grow_under_their_storage_scope(void) {
  $test.scoped();
  Map map = {};
  Scope owner = map, destination = Scope.new();
  owner.transfer(destination);
  for (int i = 0; i < 128; i++) map[i] = i + 1;
  EXPECT_PTR_EQ(Scope.owner(map), owner);
  EXPECT_PTR_EQ(Scope.owner(map.hashes.block()), owner);
  EXPECT_PTR_EQ(Scope.owner(map.entries.block()), owner);
  EXPECT_INT_EQ(map[127].int(), 128);
  EXPECT_PTR_EQ(owner.parent(), destination);
  destination.destroy();
}

static void storage_adoption_destroys_cycles_once(void) {
  $test.scoped();
  Map parent = {}, child = {}, independent = {};
  Array links = [];
  Scope parent_scope = parent, child_scope = child, links_scope = links;
  child_scope.transfer(parent_scope);
  links_scope.transfer(child_scope);
  parent["child"] = child;
  child["links"] = links;
  child["independent"] = independent;
  links.push(parent);
  storage_drops = 0;
  Scope.malloc_finalized_in(&parent_scope, 1, _storage_drop);
  Scope.malloc_finalized_in(&child_scope, 1, _storage_drop);
  Scope.malloc_finalized_in(&links_scope, 1, _storage_drop);
  parent.cleanup();
  EXPECT_INT_EQ(storage_drops, 3);
  independent["alive"] = 1;
  EXPECT_INT_EQ(independent["alive"].int(), 1);
}

static void storage_context_exports_adopted_private_values(void) {
  $test.scoped();
  Context context = Context.open_isolated_named("adopted private values");
  String key = String.new("private adopted map key");
  String text = String.new("private adopted array text");
  EXPECT_FALSE(Pool.is_permanent(key));
  EXPECT_FALSE(Pool.is_permanent(text));
  Map parent = {}, child = {};
  Array links = [];
  Scope parent_scope = parent, child_scope = child, links_scope = links;
  child_scope.transfer(parent_scope);
  links_scope.transfer(child_scope);
  parent["child"] = child;
  child[key] = text;
  child["links"] = links;
  links.push(text);
  links.push(parent);
  Var exported = context.export(parent);
  context.close();
  EXPECT_PTR_EQ(exported.map(), parent);
  EXPECT_PTR_EQ(child_scope.parent(), parent_scope);
  EXPECT_PTR_EQ(links_scope.parent(), child_scope);
  EXPECT_PTR_EQ(parent["child"].map(), child);
  String lookup = String.new("private adopted map key");
  EXPECT_STR_EQ(child[lookup].str(),
    "private adopted array text");
  EXPECT_STR_EQ(links[0].str(), "private adopted array text");
  EXPECT_PTR_EQ(links[1].map(), parent);
  EXPECT_TRUE(Pool.is_permanent(links[0]));
}

static void storage_context_exports_adopted_string_array(void) {
  $test.scoped();
  Context context = Context.open_isolated();
  Map parent = {};
  ArrayString values = ArrayString.new();
  MapStringString table = MapStringString.new();
  values.push(String.new("private typed adopted text"));
  String key = String.new("private typed adopted key");
  EXPECT_FALSE(Pool.is_permanent(key));
  EXPECT_FALSE(Pool.is_permanent(values[0]));
  table[key] = values[0];
  Scope owner = values;
  Scope table_owner = table;
  storage_drops = 0;
  Scope.malloc_finalized_in(&owner, 1, _storage_drop);
  Scope.malloc_finalized_in(&table_owner, 1, _storage_drop);
  owner.transfer(parent);
  table_owner.transfer(parent);
  parent["values"] = values;
  parent["table"] = table;
  context.export(parent);
  context.close();
  EXPECT_PTR_EQ(owner.parent(), parent.scope());
  EXPECT_PTR_EQ(table_owner.parent(), parent.scope());
  EXPECT_STR_EQ(values[0], "private typed adopted text");
  String lookup = String.new("private typed adopted key");
  EXPECT_STR_EQ(table[lookup],
    "private typed adopted text");
  EXPECT_PTR_EQ(Scope.owner((unsigned char *) values.bytes - sizeof(Block)),
    owner);
  parent.cleanup();
  EXPECT_INT_EQ(storage_drops, 2);
}

static Var _storage_transfer_worker(Var input) {
  Scope destination = input;
  for (int i = 0; i < 128; i++) {
    Map map = {};
    Scope owner = map;
    owner.transfer(destination);
    Scope.malloc_finalized_in(&owner, 1, _storage_drop);
    map[i] = i;
    map.cleanup();
  }
  return void;
}

static void storage_concurrent_adoption_and_destruction(void) {
  $test.scoped();
  Scope destination = Scope.new();
  Array workers = $auto([]);
  storage_drops = 0;
  defer Thread.finish_all(workers);
  for (int i = 0; i < 4; i++)
    workers.push(Thread.start(_storage_transfer_worker, destination));
  Thread.finish_all(workers);
  EXPECT_INT_EQ(storage_drops, 512);
  destination.destroy();
  EXPECT_INT_EQ(storage_drops, 512);
}

void storage_ownership_suite(void) {
  $test.run(storage_scope_transfer_preserves_allocations);
  $test.run(storage_empty_arrays_have_private_scopes);
  $test.run(storage_maps_grow_under_their_storage_scope);
  $test.run(storage_adoption_destroys_cycles_once);
  $test.run(storage_context_exports_adopted_private_values);
  $test.run(storage_context_exports_adopted_string_array);
  $test.run(storage_concurrent_adoption_and_destruction);
}
