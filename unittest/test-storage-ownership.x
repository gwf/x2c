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

static void storage_arrays_acquire_owned_contents_lazily(void) {
  $test.scoped();
  Scope allocation_owner = *Scope.top();
  size_t scopes = Scope.stats().live_scopes;
  Array array = [];
  Array copy = array.copy(), slice = array[0:0];
  EXPECT_NULL(array.lifetime);
  EXPECT_NULL(copy.lifetime);
  EXPECT_NULL(slice.lifetime);
  EXPECT_INT_EQ(Scope.stats().live_scopes, scopes);
  Scope unrelated = Scope.new();
  Scope.push(&unrelated);
  Scope owner = array;
  Scope.pop();
  EXPECT_NOT_NULL(owner);
  EXPECT_PTR_EQ(array.scope(), owner);
  EXPECT_PTR_EQ(Scope.owner(array), allocation_owner);
  EXPECT_PTR_EQ(owner.parent(), allocation_owner);
  EXPECT_NULL(copy.lifetime);
  EXPECT_NULL(slice.lifetime);
  unrelated.destroy();
  Scope destination = Scope.new();
  array.move_to(&destination);
  for (int i = 0; i < 128; i++) array.push(i);
  EXPECT_PTR_EQ(Scope.owner(array), destination);
  EXPECT_PTR_EQ(owner.parent(), destination);
  EXPECT_PTR_EQ(Scope.owner((unsigned char *) array.bytes - sizeof(Block)),
    destination);
  EXPECT_INT_EQ(array[127].int(), 127);
  destination.destroy();
}

static void storage_maps_grow_under_their_record_owner(void) {
  $test.scoped();
  size_t scopes = Scope.stats().live_scopes;
  Map map = {};
  MapIntInt typed = MapIntInt.new();
  EXPECT_NULL(map.scope);
  EXPECT_NULL(typed.scope);
  EXPECT_INT_EQ(Scope.stats().live_scopes, scopes);
  Scope owner = map, destination = Scope.new();
  map.move_to(&destination);
  typed.move_to(&destination);
  Scope temporary = Scope.new();
  Scope.push(&temporary);
  for (int i = 0; i < 128; i++) {
    map[i] = i + 1;
    typed[i] = i + 2;
  }
  Scope.pop();
  temporary.destroy();
  EXPECT_PTR_EQ(Scope.owner(map), destination);
  EXPECT_PTR_EQ(Scope.owner(map.hashes.block()), destination);
  EXPECT_PTR_EQ(Scope.owner(map.entries.block()), destination);
  EXPECT_PTR_EQ(Scope.owner(typed), destination);
  EXPECT_PTR_EQ(Scope.owner(typed.entries.block()), destination);
  EXPECT_NULL(typed.scope);
  EXPECT_INT_EQ(map[127].int(), 128);
  EXPECT_INT_EQ(typed[127], 129);
  EXPECT_PTR_EQ(owner.parent(), destination);
  destination.destroy();
}

static void storage_adoption_destroys_cycles_once(void) {
  $test.scoped();
  Map parent = {}, child = {}, independent = {};
  Array links = [];
  Scope parent_scope = parent, child_scope = child, links_scope = links;
  child.move_to(&parent_scope);
  links.move_to(&child_scope);
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
  child.move_to(&parent_scope);
  links.move_to(&child_scope);
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
  Scope parent_scope = parent;
  storage_drops = 0;
  Scope.malloc_finalized_in(&owner, 1, _storage_drop);
  Scope.malloc_finalized_in(&table_owner, 1, _storage_drop);
  values.move_to(&parent_scope);
  table.move_to(&parent_scope);
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
    parent_scope);
  parent.cleanup();
  EXPECT_INT_EQ(storage_drops, 2);
}

static void storage_failed_export_can_retry_adopted_graph(void) {
  $test.scoped();
  Context context = Context.open_isolated();
  Map parent = {}, child = {};
  Scope parent_scope = parent, child_scope = child;
  child.move_to(&parent_scope);
  String key = String.printf("private-retry-key-%d", 706);
  String text = String.printf("private-retry-value-%d", 707);
  EXPECT_FALSE(Pool.is_permanent(key));
  EXPECT_FALSE(Pool.is_permanent(text));
  parent["child"] = child;
  child[key] = text;
  child["bad"] = xmalloc(4);
  int caught = 0;
  try context.export(parent);
  catch %(bad-types *): caught = 1;
  EXPECT_TRUE(caught);
  EXPECT_TRUE(context.owns(parent));
  EXPECT_TRUE(context.owns(child));
  EXPECT_PTR_EQ(child_scope.parent(), parent_scope);
  child["bad"] = 1;
  context.export(parent);
  context.close();
  String lookup = String.printf("private-retry-key-%d", 706);
  EXPECT_STR_EQ(child[lookup].str(), "private-retry-value-707");
  EXPECT_PTR_EQ(child_scope.parent(), parent_scope);
}

static void storage_exports_raw_typed_block_views(void) {
  $test.scoped();
  Context context = Context.open_isolated();
  ArrayInt numbers = (ArrayInt) Block.new(sizeof(int));
  ArrayString strings = (ArrayString) Block.new(sizeof(String));
  numbers.push(37);
  strings.push(String.printf("raw-typed-private-%d", 708));
  EXPECT_FALSE(Pool.is_permanent(strings[0]));
  Var exported_numbers = context.export(numbers);
  Var exported_strings = context.export(strings);
  context.close();
  EXPECT_PTR_EQ(exported_numbers.arrayint(), numbers);
  EXPECT_PTR_EQ(exported_strings.arraystring(), strings);
  EXPECT_INT_EQ(numbers[0], 37);
  EXPECT_STR_EQ(strings[0], "raw-typed-private-708");
  EXPECT_NULL(numbers.lifetime);
  EXPECT_NULL(strings.lifetime);
  numbers.free();
  strings.free();
}

static void storage_detached_subtree_survives_and_reattaches(void) {
  ScopeStats before = Scope.stats();
  Scope source = Scope.new(), destination = Scope.new();
  Scope transit = Scope.new();
  Scope.push(&source);
  Map map = {};
  Array child = [];
  Scope owner = map, nested = child;
  child.move_to(&owner);
  map[0] = child;
  child.push(42);
  storage_drops = 0;
  Scope.malloc_finalized_in(&owner, 1, _storage_drop);
  Scope.malloc_finalized_in(&nested, 1, _storage_drop);
  Scope.pop();
  map.move_to(&transit);
  transit.transfer(NULL);
  EXPECT_NULL(transit.parent());
  EXPECT_FALSE(source.contains(transit));
  source.destroy();
  EXPECT_INT_EQ(storage_drops, 0);
  EXPECT_PTR_EQ(Scope.owner(map), transit);
  EXPECT_PTR_EQ(Scope.owner(child), owner);
  EXPECT_PTR_EQ(owner.parent(), transit);
  EXPECT_PTR_EQ(nested.parent(), owner);
  EXPECT_TRUE(owner.contains(nested));
  EXPECT_PTR_EQ(map[0].array(), child);
  EXPECT_INT_EQ(child[0].int(), 42);
  for (int i = 1; i < 128; i++) {
    map[i] = i;
    child.push(i);
  }
  EXPECT_PTR_EQ(Scope.owner(map.entries.block()), transit);
  EXPECT_PTR_EQ(Scope.owner((unsigned char *) child.bytes - sizeof(Block)),
    owner);
  map.move_to(&destination);
  transit.destroy();
  EXPECT_PTR_EQ(owner.parent(), destination);
  EXPECT_PTR_EQ(Scope.owner(map), destination);
  EXPECT_PTR_EQ(nested.parent(), owner);
  EXPECT_INT_EQ(map[127].int(), 127);
  EXPECT_INT_EQ(child[127].int(), 127);
  destination.destroy();
  EXPECT_INT_EQ(storage_drops, 2);
  EXPECT_INT_EQ(Scope.stats().live_allocations, before.live_allocations);
  EXPECT_INT_EQ(Scope.stats().live_scopes, before.live_scopes);
}

static void _storage_export_order(int child_first) {
  $scope() {
    Context work = Context.open_isolated();
    Map parent = {}, child = {};
    ArrayString strings = ArrayString.new();
    MapStringString table = MapStringString.new();
    Scope owner = parent, child_owner = child;
    Scope strings_owner = strings, table_owner = table;
    child.move_to(&owner);
    strings.move_to(&owner);
    table.move_to(&owner);
    String key = String.printf("ordered-key-%d", child_first);
    String text = String.printf("ordered-text-%d", child_first);
    EXPECT_FALSE(Pool.is_permanent(key));
    EXPECT_FALSE(Pool.is_permanent(text));
    child[key] = text;
    strings.push(text);
    table[key] = text;
    Scope.push(&owner);
    Block block = Block.new(sizeof(int));
    int number = 37;
    block.push(&number);
    Buffer buffer = Buffer.new(0);
    buffer.write("ordered buffer");
    ContextProbe probe = xmalloc(sizeof(struct ContextProbe));
    *probe = (struct ContextProbe) {.value = text};
    Var object = Var.new(<ctxprobe>, probe);
    Var wide = Var.box_long(0x123456789L), clone = wide.clone_wide();
    Scope.pop();
    parent["child"] = child;
    parent["strings"] = strings;
    parent["table"] = table;
    parent["block"] = block;
    parent["buffer"] = buffer;
    parent["probe"] = object;
    parent["wide"] = wide;
    parent["clone"] = clone;
    Array root = [];
    if (!child_first) root.push(parent);
    root.push(child);
    root.push(strings);
    root.push(table);
    root.push(block);
    root.push(buffer);
    root.push(object);
    root.push(wide);
    root.push(clone);
    if (child_first) root.push(parent);
    work.export(root);
    work.close();
    EXPECT_PTR_EQ(child_owner.parent(), owner);
    EXPECT_PTR_EQ(strings_owner.parent(), owner);
    EXPECT_PTR_EQ(table_owner.parent(), owner);
    EXPECT_PTR_EQ(Scope.owner(block), owner);
    EXPECT_PTR_EQ(Scope.owner(buffer), owner);
    EXPECT_PTR_EQ(Scope.owner(buffer.content), owner);
    EXPECT_PTR_EQ(Scope.owner(buffer.indents), owner);
    EXPECT_PTR_EQ(Scope.owner(probe), owner);
    EXPECT_PTR_EQ(wide.wide_owner(), owner);
    EXPECT_PTR_EQ(clone.wide_owner(), owner);
    EXPECT_FALSE(wide.same(clone));
    EXPECT_INT_EQ(wide.long_value(), 0x123456789L);
    EXPECT_INT_EQ(clone.long_value(), 0x123456789L);
    EXPECT_INT_EQ(*((int *) block.bytes), 37);
    EXPECT_STR_EQ(buffer.str(), "ordered buffer");
    String lookup = String.printf("ordered-key-%d", child_first);
    String expected = String.printf("ordered-text-%d", child_first);
    EXPECT_STR_EQ(child[lookup].str(), expected);
    EXPECT_STR_EQ(strings[0], expected);
    EXPECT_STR_EQ(table[lookup], expected);
    EXPECT_STR_EQ(probe.value.str(), expected);
    parent.cleanup();
    root.free();
  }
}

static void storage_exports_child_before_parent(void) {
  _storage_export_order(1);
}

static void storage_exports_parent_before_child(void) {
  _storage_export_order(0);
}

static void storage_exports_child_independently(void) {
  $test.scoped();
  Context work = Context.open_isolated();
  Map parent = {}, child = {};
  Scope owner = parent, nested = child;
  child.move_to(&owner);
  child["value"] = String.printf("independent-child-%d", 709);
  work.export(child);
  work.close();
  EXPECT_TRUE(nested.parent() != owner);
  EXPECT_STR_EQ(child["value"].str(), "independent-child-709");
  child.cleanup();
}

static void storage_exports_distinct_equal_wide_boxes(void) {
  $test.scoped();
  Scope destination = *Scope.top();
  Context work = Context.open_isolated();
  Var wide = Var.box_long(0x123456789L), clone = wide.clone_wide();
  Array root = [wide, clone];
  work.export(root);
  EXPECT_PTR_EQ(wide.wide_owner(), destination);
  EXPECT_PTR_EQ(clone.wide_owner(), destination);
  EXPECT_FALSE(wide.same(clone));
  work.close();
  EXPECT_INT_EQ(wide.long_value(), 0x123456789L);
  EXPECT_INT_EQ(clone.long_value(), 0x123456789L);
  EXPECT_TRUE(root[0].same(wide));
  EXPECT_TRUE(root[1].same(clone));
}

void storage_ownership_suite(void) {
  $test.run(storage_scope_transfer_preserves_allocations);
  $test.run(storage_arrays_acquire_owned_contents_lazily);
  $test.run(storage_maps_grow_under_their_record_owner);
  $test.run(storage_adoption_destroys_cycles_once);
  $test.run(storage_context_exports_adopted_private_values);
  $test.run(storage_context_exports_adopted_string_array);
  $test.run(storage_failed_export_can_retry_adopted_graph);
  $test.run(storage_exports_raw_typed_block_views);
  $test.run(storage_detached_subtree_survives_and_reattaches);
  $test.run(storage_exports_child_before_parent);
  $test.run(storage_exports_parent_before_child);
  $test.run(storage_exports_child_independently);
  $test.run(storage_exports_distinct_equal_wide_boxes);
}
