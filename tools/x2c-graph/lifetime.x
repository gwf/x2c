/*  lifetime.x -- definite escapes from explicit x2c allocation regions */

#pragma once

#include "compiler.x"
#include "targets.x"

typedef struct Lifetime *Lifetime;

Symbol Lifetime.loop_allocation_kind(
  Compiler compiler, List node, String *operation);
List Lifetime.analyze_unit(
  Compiler compiler, List ast, String path, Map definitions);
List Lifetime.finish(List units);
List Lifetime.allocation_returns(List units, String wanted);
List Lifetime.resolve_allocation_returns(List units, List pending);

#pragma private

#include <string.h>

struct Lifetime {
  Compiler compiler;
  String path, function;
  List target;
  Map definitions, bindings, return_bindings, regions, allocations;
  Map allocation_unresolved, uncertain_allocations;
  Array return_facts, allocation_returns, findings, unresolved;
  Array pending_allocations, pending_returns;
  int next_region, next_allocation, direct_allocations;
  int origin, transfers, summary_unresolved;
};

static String _lifetime_callee(Lifetime lifetime, Var value, List *arguments) {
  *arguments = NULL;
  if (value is not <list>) return NULL;
  List node = value;
  match (node) {
    case %(expr ? ?inner):
      return _lifetime_callee(lifetime, inner, arguments);
    case %(stmnt ?inner):
      return _lifetime_callee(lifetime, inner, arguments);
    case %(parens ?inner):
      return _lifetime_callee(lifetime, inner, arguments);
    case %(at ? ?inner):
      return _lifetime_callee(lifetime, inner, arguments);
    case %(call
           (expr ?
             (ident (!set ?binding (binding ? ?spelling))))
           (!set ?call_arguments (args *))): {
      *arguments = call_arguments;
      if (lifetime.compiler.semantic_binding_facts().contains(
            %(automatic $binding)
          ))
        return %"computed";
      String name = lifetime.compiler.emitted_binding_name(binding);
      if (name && strlen(name)) return name;
      return spelling.str();
    }
    case %(call ? (!set ?call_arguments (args *))): {
      *arguments = call_arguments;
      return %"computed";
    }
  }
  return NULL;
}

static List _lifetime_binding(Var value) {
  if (value is not <list>) return NULL;
  List node = value;
  match (node) {
    case %(expr ? ?inner): return _lifetime_binding(inner);
    case %(parens ?inner): return _lifetime_binding(inner);
    case %(at ? ?inner): return _lifetime_binding(inner);
    case %(ident (!set ?binding (binding ? ?))): return binding;
  }
  return NULL;
}

static Type _lifetime_expression_type(Var value) {
  if (value is not <list>) return NULL;
  List node = value;
  match (node) {
    case %(expr ?type ?): return type;
    case %(parens ?inner): return _lifetime_expression_type(inner);
    case %(at ? ?inner): return _lifetime_expression_type(inner);
  }
  return NULL;
}

static Type _lifetime_binding_type(Lifetime lifetime, List binding) {
  Var stored;
  return lifetime.compiler.semantic_binding_facts().try_get(
           %(type $binding), &stored
         ) && stored is <list>
       ? stored.list().type() : NULL;
}

static int _lifetime_preserves_value(
  Lifetime lifetime, Type source, Type target) {
  if (!source || !target) return 0;
  source = source.canonicalize();
  target = target.canonicalize();
  if (List.equal(source, target)) return 1;
  if (source.is_bare_typedef_name() && target.is_bare_typedef_name())
    return 0;
  source = lifetime.compiler.sym.resolve_key(source);
  target = lifetime.compiler.sym.resolve_key(target);
  return source.is_pointer() && target.is_pointer();
}

static int _lifetime_candidate_type(Type type) {
  if (!type) return 0;
  type = type.canonicalize();
  return type.is_pointer() || type.is_bare_typedef_name();
}

static List _lifetime_location(Lifetime lifetime) {
  List location = lifetime.compiler.origin_location(lifetime.origin);
  if (!location) return %(location ${lifetime.path} 0 0);
  Var file = location.assoc(<file>);
  String source = file is <string>
                ? lifetime.compiler.display_path(file.str())
                : lifetime.path;
  int line = location.assoc(<line>).integer();
  int column = location.assoc(<column>).integer();
  return %(location $source $line $column);
}

Symbol Lifetime.loop_allocation_kind(
  Compiler compiler, List node, String *operation) {
  match (node) {
    case %(array *): {
      *operation = %"Array literal";
      return <scoped>;
    }
    case %(map *): {
      *operation = %"Map literal";
      return <scoped>;
    }
    case %(cons *): {
      *operation = %"cons";
      return <pooled>;
    }
    case %(append *): {
      *operation = %"List.append";
      return <pooled>;
    }
    case %(call
           (expr ?
             (ident (!set ?callee (binding ? ?))))
           (args *)): {
      String name = compiler.emitted_binding_name(callee);
      if (name == %"Array_new" || name == %"Map_new") {
        *operation = name;
        return <scoped>;
      }
      if (name == %"cons" || name == %"List_append" ||
          name == %"String_concat" || name == %"String_join" ||
          name == %"String_new") {
        *operation = name;
        return <pooled>;
      }
    }
  }
  return 0;
}

static Symbol _lifetime_named_allocation_kind(String name) {
  if (name == %"Scope_malloc" || name == %"Scope_calloc" ||
      name == %"Scope_memdup" || name == %"Array_new" ||
      name == %"Map_new" || name == %"Block_new" ||
      name == %"Buffer_new")
    return <scoped>;
  if (name == %"cons" || name == %"List_append" ||
      name == %"String_concat" || name == %"String_join" ||
      name == %"String_new" || name == %"String_new_len" ||
      name == %"String_new_fill" || name == %"Atom_intern" ||
      name == %"Array_list_free")
    return <pooled>;
  return 0;
}

static Symbol _lifetime_region_allocation_kind(
  Lifetime lifetime, Var value, String *operation) {
  if (value is not <list>) return 0;
  List node = value;
  match (node) {
    case %(expr ? ?inner):
      return _lifetime_region_allocation_kind(lifetime, inner, operation);
    case %(parens ?inner):
      return _lifetime_region_allocation_kind(lifetime, inner, operation);
    case %(at ? ?inner):
      return _lifetime_region_allocation_kind(lifetime, inner, operation);
    case %(segments *): {
      *operation = %"String interpolation";
      return <pooled>;
    }
  }
  Symbol kind = Lifetime.loop_allocation_kind(
    lifetime.compiler, node, operation
  );
  if (kind) return kind;
  List arguments;
  String name = _lifetime_callee(lifetime, node, &arguments);
  if (!name) return 0;
  kind = _lifetime_named_allocation_kind(name);
  if (kind) *operation = name;
  return kind;
}

static int _lifetime_region(Lifetime lifetime, Symbol allocation_kind) {
  for (int id = lifetime.next_region; id; id--) {
    if (!lifetime.regions.contains(id)) continue;
    List row = lifetime.regions[id];
    match (row)
      case %(region ? ?kind ?isolated ?alive ? ? ?):
        if (alive.integer() &&
            (allocation_kind == <scoped> ||
             (kind == <context> && isolated.integer())))
          return id;
  }
  return 0;
}

static int _lifetime_context_region(Lifetime lifetime, List owner) {
  for (int id = lifetime.next_region; id; id--) {
    if (!lifetime.regions.contains(id)) continue;
    List row = lifetime.regions[id];
    match (row)
      case %(region ? context ? ?alive ? ?binding ?):
        if (alive.integer() && binding is <list> &&
            List.equal(binding.list(), owner))
          return id;
  }
  return 0;
}

static int _lifetime_scope_region(Lifetime lifetime) {
  for (int id = lifetime.next_region; id; id--) {
    if (!lifetime.regions.contains(id)) continue;
    List row = lifetime.regions[id];
    match (row)
      case %(region ? scope ? ?alive ? ? ?):
        if (alive.integer()) return id;
  }
  return 0;
}

static void _lifetime_end_region(Lifetime lifetime, int id, int deferred) {
  if (!id || !lifetime.regions.contains(id)) return;
  List row = lifetime.regions[id];
  match (row)
    case %(region ?identity ?kind ?isolated ?alive ? ?owner ?):
      if (alive.integer())
        lifetime.regions[id] = %(
          region $identity $kind $isolated ${deferred ? 1 : 0}
          $deferred $owner ${_lifetime_location(lifetime)}
        );
}

static int _lifetime_allocation_id(Lifetime lifetime, Var value) {
  List binding = _lifetime_binding(value);
  if (!binding || !lifetime.bindings.contains(binding)) return 0;
  return lifetime.bindings[binding].integer();
}

static int _lifetime_transparent(String name) {
  return name == %"Var_map" || name == %"Var_array" ||
         name == %"Var_list" || name == %"Var_string" ||
         name == %"Map_var" || name == %"Array_var" ||
         name == %"List_var" || name == %"String_var";
}

static List _lifetime_summary_fact(Lifetime lifetime, Var value) {
  List binding = _lifetime_binding(value);
  if (binding)
    return lifetime.return_bindings.contains(binding)
         ? lifetime.return_bindings[binding].list() : %(other);
  if (value is not <list>) return %(other);
  List node = value, arguments;
  match (node) {
    case %(expr ? ?inner):
      return _lifetime_summary_fact(lifetime, inner);
    case %(parens ?inner):
      return _lifetime_summary_fact(lifetime, inner);
    case %(at ? ?inner):
      return _lifetime_summary_fact(lifetime, inner);
    case %(cast *): return %(unresolved);
  }
  String operation = NULL;
  Symbol kind = _lifetime_region_allocation_kind(
    lifetime, node, &operation
  );
  if (kind) return %(kind $kind);
  String name = _lifetime_callee(lifetime, node, &arguments);
  if (!name) return %(other);
  if (_lifetime_transparent(name) && arguments && arguments.len() > 1)
    return _lifetime_summary_fact(lifetime, arguments[1]);
  if (name == %"Context_export") return %(other);
  List target = project_call_target(
    lifetime.compiler, lifetime.definitions, node, &name
  );
  return target && !List.equal(target, %(computed))
       ? %(call $target) : %(unresolved);
}

static List _lifetime_typed_summary_fact(
  Lifetime lifetime, Var value, Type target) {
  List fact = _lifetime_summary_fact(lifetime, value);
  match (fact)
    case %((!or kind call) *): {
      Type source = _lifetime_expression_type(value);
      if (!_lifetime_preserves_value(lifetime, source, target))
        return %(unresolved);
    }
  return fact;
}

static int _lifetime_always_returns(Var value) {
  if (value is not <list>) return 0;
  List node = value;
  match (node) {
    case %(at ? ?inner): return _lifetime_always_returns(inner);
    case %(return *): return 1;
    case %(block *statements): {
      foreach (Var statement, statements)
        if (_lifetime_always_returns(statement)) return 1;
      return 0;
    }
    case %(if ? ?ontrue ?onfalse):
      return _lifetime_always_returns(ontrue) &&
             _lifetime_always_returns(onfalse);
    case %(function *): return 0;
  }
  return 0;
}

static int _lifetime_wrapped_allocation(Lifetime lifetime, Var value) {
  int id = _lifetime_allocation_id(lifetime, value);
  if (id || value is not <list>) return id;
  List node = value, arguments;
  match (node) {
    case %(expr ? ?inner):
      return _lifetime_wrapped_allocation(lifetime, inner);
    case %(parens ?inner):
      return _lifetime_wrapped_allocation(lifetime, inner);
  }
  String name = _lifetime_callee(lifetime, node, &arguments);
  return name && _lifetime_transparent(name) && arguments &&
         arguments.len() > 1
       ? _lifetime_wrapped_allocation(lifetime, arguments[1]) : 0;
}

static int _lifetime_export_result(Lifetime lifetime, Var value) {
  if (value is not <list>) return 0;
  List node = value, arguments;
  match (node) {
    case %(expr ? ?inner): return _lifetime_export_result(lifetime, inner);
    case %(parens ?inner): return _lifetime_export_result(lifetime, inner);
  }
  String name = _lifetime_callee(lifetime, node, &arguments);
  if (!name) return 0;
  if (_lifetime_transparent(name) && arguments && arguments.len() > 1)
    return _lifetime_export_result(lifetime, arguments[1]);
  if (name != %"Context_export") return 0;
  lifetime.transfers++;
  return 1;
}

static int _lifetime_known_call(String name) {
  return name && (
    name == %"Scope_retain" || name == %"Scope_release" ||
    name == %"Scope_move" || name == %"Context_open" ||
    name == %"Context_open_named" ||
    name == %"Context_open_isolated" ||
    name == %"Context_open_isolated_named" ||
    name == %"Context_close" || name == %"Context_export" ||
    _lifetime_named_allocation_kind(name) || _lifetime_transparent(name)
  );
}

static void _lifetime_unresolve(Lifetime lifetime, int id, List cause) {
  if (!id || !lifetime.allocations.contains(id)) return;
  lifetime.uncertain_allocations[id] = 1;
  List row = lifetime.allocations[id];
  match (row) {
    case %(allocation ?identity ?region ?operation known ?location):
      lifetime.allocations[id] = %(
        allocation $identity $region $operation unresolved $location
      );
    case %(
      pending-allocation ?identity ?target ?name ?scope ?pool
      known ?location
    ):
      lifetime.allocations[id] = %(
        pending-allocation $identity $target $name $scope $pool
        unresolved $location
      );
  }
  if (cause) {
    List causes = lifetime.allocation_unresolved.contains(id)
                ? lifetime.allocation_unresolved[id].list() : NULL;
    if (!causes.contains(cause))
      lifetime.allocation_unresolved[id] = cons(cause, causes);
  }
}

static void _lifetime_replace_return_fact(
  Lifetime lifetime, Var value, List replacement) {
  List binding = _lifetime_binding(value);
  if (binding && lifetime.return_bindings.contains(binding)) {
    List fact = lifetime.return_bindings[binding];
    match (fact)
      case %((!or kind call) *): lifetime.summary_unresolved = 1;
    lifetime.return_bindings[binding] = replacement;
    return;
  }
  if (value is not <list>) return;
  List node = value, arguments;
  String name = _lifetime_callee(lifetime, node, &arguments);
  if (name && _lifetime_transparent(name) && arguments &&
      arguments.len() > 1)
    _lifetime_replace_return_fact(
      lifetime, arguments[1], replacement
    );
}

static void _lifetime_scan_calls(Lifetime lifetime, Var value) {
  if (value is not <list>) return;
  List node = value, arguments;
  match (node) {
    case %(function *): return;
    case %(at ?origin ?inner): {
      int saved = lifetime.origin;
      lifetime.origin = origin.integer();
      _lifetime_scan_calls(lifetime, inner);
      lifetime.origin = saved;
      return;
    }
    case %(cast *): return;
  }
  String name = _lifetime_callee(lifetime, node, &arguments);
  if (arguments) {
    if (!_lifetime_known_call(name))
      foreach (Var argument, cdr(arguments)) {
        int id = _lifetime_wrapped_allocation(lifetime, argument);
        List cause = %(
          call ${lifetime.path} ${lifetime.function}
          ${name ? name : %"computed"} ${_lifetime_location(lifetime)}
        );
        if (id) {
          _lifetime_unresolve(lifetime, id, cause);
        }
        _lifetime_replace_return_fact(lifetime, argument, %(unresolved));
      }
    foreach (Var argument, cdr(arguments))
      _lifetime_scan_calls(lifetime, argument);
    return;
  }
  foreach (Var child, node) _lifetime_scan_calls(lifetime, child);
}

static int _lifetime_expression(Lifetime lifetime, Var value) {
  if (_lifetime_export_result(lifetime, value)) return 0;
  int id = _lifetime_allocation_id(lifetime, value);
  if (id) return id;
  String operation = NULL;
  Symbol allocation_kind = _lifetime_region_allocation_kind(
    lifetime, value, &operation
  );
  int region = allocation_kind
             ? _lifetime_region(lifetime, allocation_kind) : 0;
  if (region) {
    id = ++lifetime.next_allocation;
    lifetime.direct_allocations++;
    lifetime.allocations[id] = %(
      allocation $id $region $operation known
      ${_lifetime_location(lifetime)}
    );
    return id;
  }
  List arguments;
  String name = _lifetime_callee(lifetime, value, &arguments);
  if (name && _lifetime_transparent(name) && arguments &&
      arguments.len() > 1)
    return _lifetime_expression(lifetime, arguments[1]);
  if (arguments && !_lifetime_known_call(name)) {
    List target = project_call_target(
      lifetime.compiler, lifetime.definitions, value, &name
    );
    Type result_type = _lifetime_expression_type(value);
    int scope_region = _lifetime_region(lifetime, <scoped>);
    int pool_region = _lifetime_region(lifetime, <pooled>);
    if (target && _lifetime_candidate_type(result_type) &&
        (scope_region || pool_region)) {
      id = ++lifetime.next_allocation;
      lifetime.allocations[id] = %(
        pending-allocation $id $target $name
        $scope_region $pool_region known ${_lifetime_location(lifetime)}
      );
      lifetime.pending_allocations.push(%(
        pending-allocation $target $scope_region $pool_region
      ));
      return id;
    }
  }
  _lifetime_scan_calls(lifetime, value);
  return 0;
}

static int _lifetime_context_open(
  Lifetime lifetime, Var value, int *isolated) {
  List arguments;
  String name = _lifetime_callee(lifetime, value, &arguments);
  if (!name) return 0;
  *isolated = name == %"Context_open_isolated" ||
              name == %"Context_open_isolated_named";
  return *isolated || name == %"Context_open" ||
         name == %"Context_open_named";
}

static void _lifetime_bind(Lifetime lifetime, List binding, Var expression) {
  Type target = _lifetime_binding_type(lifetime, binding);
  List return_fact = _lifetime_typed_summary_fact(
    lifetime, expression, target
  );
  if (lifetime.return_bindings.contains(binding)) {
    List previous = lifetime.return_bindings[binding];
    if (!List.equal(previous, return_fact)) {
      match (previous)
        case %((!or kind call) *): lifetime.summary_unresolved = 1;
    }
  }
  lifetime.return_bindings[binding] = return_fact;
  int previous_allocation = lifetime.bindings.contains(binding)
                          ? lifetime.bindings[binding].integer() : 0;
  int isolated = 0;
  if (_lifetime_context_open(lifetime, expression, &isolated)) {
    int id = ++lifetime.next_region;
    lifetime.regions[id] = %(
      region $id context $isolated 1 0 $binding none
    );
    lifetime.bindings.del(binding);
    return;
  }
  int id = _lifetime_expression(lifetime, expression);
  if (previous_allocation && previous_allocation != id)
    lifetime.uncertain_allocations[previous_allocation] = 1;
  Type source = _lifetime_expression_type(expression);
  if (id && _lifetime_preserves_value(lifetime, source, target))
    lifetime.bindings[binding] = id;
  else lifetime.bindings.del(binding);
}

static int _lifetime_owner_ended(List owner) {
  match (owner)
    case %(region ? ? ? ?alive ?deferred ? ?):
      return !alive.integer() || deferred.integer();
  return 0;
}

static List _lifetime_owner(Lifetime lifetime, int id) {
  return id && lifetime.regions.contains(id)
       ? lifetime.regions[id].list() : %(none);
}

static void _lifetime_emit_unresolved(Lifetime lifetime, int id) {
  if (!lifetime.allocation_unresolved.contains(id)) return;
  foreach (List cause, lifetime.allocation_unresolved[id].list())
    if (!lifetime.unresolved.contains(cause))
      lifetime.unresolved.push(cause);
}

static void _lifetime_return(Lifetime lifetime, Type target, Var expression) {
  lifetime.return_facts.push(
    _lifetime_typed_summary_fact(lifetime, expression, target)
  );
  String operation = NULL;
  Symbol direct = _lifetime_region_allocation_kind(
    lifetime, expression, &operation
  );
  if (direct)
    lifetime.allocation_returns.push(%(
      return ${lifetime.path} ${lifetime.function} $direct $operation
      ${_lifetime_location(lifetime)}
    ));
  Type source = _lifetime_expression_type(expression);
  if (!_lifetime_preserves_value(lifetime, source, target)) return;
  int id = _lifetime_expression(lifetime, expression);
  if (!id || !lifetime.allocations.contains(id)) return;
  List allocation = lifetime.allocations[id];
  match (allocation) {
    case %(allocation ? ?region ?operation known ?allocated): {
      if (!lifetime.regions.contains(region)) return;
      List owner = lifetime.regions[region];
      match (owner) {
        case %(region ? ?kind ? ? ? ? ?ended): {
          if (!_lifetime_owner_ended(owner)) return;
          if (lifetime.uncertain_allocations.contains(id)) {
            _lifetime_emit_unresolved(lifetime, id);
            return;
          }
          lifetime.findings.push(%(
            finding dangling-return ${lifetime.path}
            ${lifetime.function} $kind $operation
            (allocated $allocated) (ended $ended)
            (returned ${_lifetime_location(lifetime)})
          ));
        }
      }
      return;
    }
    case %(allocation ? ?region ? unresolved ?): {
      if (lifetime.regions.contains(region) &&
          _lifetime_owner_ended(lifetime.regions[region].list()))
        _lifetime_emit_unresolved(lifetime, id);
      return;
    }
    case %(
      pending-allocation ? ?target ?name ?scope ?pool
      ?status ?allocated
    ): {
      List causes = lifetime.allocation_unresolved.contains(id)
                  ? lifetime.allocation_unresolved[id].list() : NULL;
      Symbol final_status = lifetime.uncertain_allocations.contains(id)
                          ? <unresolved> : status.symbol();
      lifetime.pending_returns.push(%(
        pending-return ${lifetime.path} ${lifetime.function}
        $target $name $final_status
        (scope ${_lifetime_owner(lifetime, scope.integer())})
        (pool ${_lifetime_owner(lifetime, pool.integer())})
        (allocated $allocated)
        (returned ${_lifetime_location(lifetime)})
        (causes @causes)
      ));
      return;
    }
  }
}

static void _lifetime_transfer(Lifetime lifetime, int id) {
  if (!id || !lifetime.allocations.contains(id)) return;
  List allocation = lifetime.allocations[id];
  match (allocation) {
    case %(allocation ?identity ?region ?operation ? ?location):
      lifetime.allocations[id] = %(
        allocation $identity $region $operation transferred $location
      );
    case %(
      pending-allocation ?identity ?target ?name ?scope ?pool ? ?location
    ):
      lifetime.allocations[id] = %(
        pending-allocation $identity $target $name $scope $pool
        moved $location
      );
  }
}

static void _lifetime_statement(Lifetime lifetime, Var value, int nested);

static void _lifetime_block(Lifetime lifetime, List statements, int nested) {
  Map saved_bindings = lifetime.bindings;
  Map saved_return_bindings = lifetime.return_bindings;
  Map saved_regions = lifetime.regions;
  Map saved_allocations = lifetime.allocations;
  if (nested) {
    lifetime.bindings = lifetime.bindings.copy();
    lifetime.return_bindings = lifetime.return_bindings.copy();
    lifetime.regions = lifetime.regions.copy();
    lifetime.allocations = lifetime.allocations.copy();
  }
  foreach (Var statement, statements)
    _lifetime_statement(lifetime, statement, nested + 1);
  if (nested) {
    lifetime.bindings = saved_bindings;
    lifetime.return_bindings = saved_return_bindings;
    lifetime.regions = saved_regions;
    lifetime.allocations = saved_allocations;
  }
}

static void _lifetime_isolated_walk(Lifetime lifetime, List node) {
  Map saved_bindings = lifetime.bindings;
  Map saved_return_bindings = lifetime.return_bindings;
  Map saved_regions = lifetime.regions;
  Map saved_allocations = lifetime.allocations;
  foreach (Var child, cdr(node)) {
    lifetime.bindings = saved_bindings.copy();
    lifetime.return_bindings = saved_return_bindings.copy();
    lifetime.regions = saved_regions.copy();
    lifetime.allocations = saved_allocations.copy();
    _lifetime_statement(lifetime, child, 1);
  }
  lifetime.bindings = saved_bindings;
  lifetime.return_bindings = saved_return_bindings;
  lifetime.regions = saved_regions;
  lifetime.allocations = saved_allocations;
}

static void _lifetime_statement(Lifetime lifetime, Var value, int nested) {
  if (value is not <list>) return;
  List node = value;
  match (node) {
    case %(at ?origin ?inner): {
      int saved = lifetime.origin;
      lifetime.origin = origin.integer();
      _lifetime_statement(lifetime, inner, nested);
      lifetime.origin = saved;
      return;
    }
    case %(block *statements): {
      _lifetime_block(lifetime, statements, nested);
      return;
    }
    case %((!or if switch while do for try) *): {
      _lifetime_isolated_walk(lifetime, node);
      return;
    }
    case %(defer ?cleanup): {
      List arguments;
      String name = _lifetime_callee(lifetime, cleanup, &arguments);
      if (name == %"Scope_release")
        _lifetime_end_region(
          lifetime, _lifetime_scope_region(lifetime), 1
        );
      else if (name == %"Context_close" && arguments &&
               arguments.len() > 1) {
        List binding = _lifetime_binding(arguments[1]);
        if (binding)
          _lifetime_end_region(
            lifetime, _lifetime_context_region(lifetime, binding), 1
          );
      }
      return;
    }
    case %(declare ? (bindings *bindings)): {
      foreach (List item, bindings)
        match (item)
          case %(op = (bind (!set ?binding (binding ? ?)) ?)
                 ?expression):
            _lifetime_bind(lifetime, binding, expression);
      return;
    }
    case %(return ?type ?expression): {
      _lifetime_return(lifetime, type, expression);
      return;
    }
    case %(stmnt (expr ? (op = ?left ?right))): {
      List binding = _lifetime_binding(left);
      if (binding) _lifetime_bind(lifetime, binding, right);
      else {
        _lifetime_expression(lifetime, right);
        int id = _lifetime_allocation_id(lifetime, left);
        _lifetime_unresolve(lifetime, id, NULL);
      }
      return;
    }
    case %(stmnt ?expression): {
      List arguments;
      String name = _lifetime_callee(lifetime, expression, &arguments);
      if (name == %"Scope_retain") {
        int id = ++lifetime.next_region;
        lifetime.regions[id] = %(region $id scope 0 1 0 none none);
        return;
      }
      if (name == %"Scope_release") {
        _lifetime_end_region(
          lifetime, _lifetime_scope_region(lifetime), 0
        );
        return;
      }
      if (name == %"Scope_move" && arguments && arguments.len() > 1) {
        int id = _lifetime_wrapped_allocation(lifetime, arguments[1]);
        _lifetime_transfer(lifetime, id);
        _lifetime_replace_return_fact(lifetime, arguments[1], %(other));
        lifetime.transfers++;
        return;
      }
      if (name == %"Context_close" && arguments &&
          arguments.len() > 1) {
        List binding = _lifetime_binding(arguments[1]);
        if (binding)
          _lifetime_end_region(
            lifetime, _lifetime_context_region(lifetime, binding), 0
          );
        return;
      }
      _lifetime_scan_calls(lifetime, expression);
      return;
    }
    case %((!or goto break continue) *): return;
  }
  _lifetime_isolated_walk(lifetime, node);
}

List Lifetime.analyze_unit(
  Compiler compiler, List ast, String path, Map definitions) {
  int regions = 0, allocations = 0, transfers = 0;

  Array functions = %[], allocation_returns = %[];
  Array findings = %[], unresolved = %[];
  Array pending_allocations = %[], pending_returns = %[];
  foreach (List node, ast)
    match (node)
      case %(function ?type
             (bind (!set ?binding (binding ? ?)) ?)
             ?body): {
        Array return_facts = %[];
        struct Lifetime state = {
          .compiler = compiler,
          .path = path,
          .function = compiler.emitted_binding_name(binding),
          .target = definitions[binding],
          .definitions = definitions,
          .bindings = %{},
          .return_bindings = %{},
          .regions = %{},
          .allocations = %{},
          .allocation_unresolved = %{},
          .uncertain_allocations = %{},
          .return_facts = return_facts,
          .allocation_returns = allocation_returns,
          .findings = findings,
          .unresolved = unresolved,
          .pending_allocations = pending_allocations,
          .pending_returns = pending_returns
        };
        _lifetime_statement(&state, body, 0);
        if (!_lifetime_always_returns(body) || !return_facts.len())
          return_facts.push(%(other));
        if (state.summary_unresolved)
          return_facts.push(%(unresolved));
        Symbol visibility = ((Type) type).is_static()
                          ? <static> : <public>;
        functions.push(%(
          function ${state.target} ${state.function} $visibility
          (returns @{return_facts.list_free()})
        ));
        regions += state.next_region;
        allocations += state.direct_allocations;
        transfers += state.transfers;
      }
  functions.sort();
  allocation_returns.sort();
  findings.sort();
  unresolved.sort();
  return %(
    lifetime-unit
    (summary (regions $regions) (allocations $allocations)
             (transfers $transfers))
    (functions @{functions.list_free()})
    (pending-allocations @{pending_allocations.list_free()})
    (pending-returns @{pending_returns.list_free()})
    (allocation-returns @{allocation_returns.list_free()})
    (findings @{findings.list_free()})
    (unresolved @{unresolved.list_free()})
  );
}

static int _lifetime_combine_kind(Symbol *kind, Symbol next) {
  if (*kind && *kind != next) return 0;
  *kind = next;
  return 1;
}

static int _lifetime_resolve_summary(
  List function, Map publics, Map summaries, Symbol *resolved) {
  List self, facts;
  match (function)
    case %(
      function (!set ?target ?) ? ? (returns *return_facts)
    ):
      self = target, facts = return_facts;
  Symbol kind = 0;
  foreach (List fact, facts)
    match (fact) {
      case %(kind ?direct):
        if (!_lifetime_combine_kind(&kind, direct.symbol())) return 0;
      case %((!or other unresolved)): return 0;
    }
  foreach (List fact, facts)
    match (fact)
      case %(call ?raw_target): {
        List target = resolve_project_target(raw_target, publics);
        if (!target) return 0;
        if (List.equal(target, self)) {
          if (!kind) return 0;
          continue;
        }
        if (!summaries.contains(target)) return 0;
        Symbol next = summaries[target].symbol();
        if (!_lifetime_combine_kind(&kind, next)) return 0;
      }
  if (!kind) return 0;
  *resolved = kind;
  return 1;
}

static Map _lifetime_summaries(List functions, Map publics) {
  Map summaries = %{};
  foreach (List function, functions)
    match (function)
      case %(function ?target ?name public (returns *)):
        publics[name] = cons(
          target,
          publics.contains(name) ? publics[name].list() : NULL
        );
  for (int pass = 0; pass < functions.len(); pass++) {
    int changed = 0;
    foreach (List function, functions) {
      List target;
      match (function)
        case %(function (!set ?function_target ?) ? ? (returns *)):
          target = function_target;
      if (summaries.contains(target)) continue;
      Symbol kind;
      if (_lifetime_resolve_summary(
            function, publics, summaries, &kind
          )) {
        summaries[target] = kind;
        changed = 1;
      }
    }
    if (!changed) break;
  }
  return summaries;
}

static Symbol _lifetime_resolved_kind(
  List raw_target, Map publics, Map summaries) {
  List target = resolve_project_target(raw_target, publics);
  return target && summaries.contains(target)
       ? summaries[target].symbol() : 0;
}

static List _lifetime_functions(List units) {
  Array functions = %[];
  foreach (List unit, units)
    match (unit)
      case %(
        lifetime-unit ? (functions *unit_functions) *
      ):
        foreach (List function, unit_functions) functions.push(function);
  functions.sort();
  return functions.list_free();
}

List Lifetime.allocation_returns(List units, String wanted) {
  Array returns = %[];
  foreach (List unit, units)
    match (unit)
      case %(
        lifetime-unit *
        (allocation-returns *unit_returns) *
      ):
        foreach (List row, unit_returns)
          match (row)
            case %(return ? ?function *):
              if (function == wanted) returns.push(row);
  returns.sort();
  int count = returns.len();
  return %(
    allocation-returns $wanted (summary (returns $count))
    (returns @{returns.list_free()})
  );
}

List Lifetime.resolve_allocation_returns(List units, List pending) {
  Map publics = %{};
  Map summaries = _lifetime_summaries(
    _lifetime_functions(units), publics
  );
  Array resolved = %[];
  foreach (List row, pending)
    match (row)
      case %(allocation-return ?target *payload): {
        Symbol kind = _lifetime_resolved_kind(
          target, publics, summaries
        );
        if (kind)
          resolved.push(%(allocation-return $kind @payload));
      }
  resolved.sort();
  return resolved.list_free();
}

static List _lifetime_pending_owner(Symbol kind, List scoped, List pooled) {
  List wrapped = kind == <scoped> ? scoped : pooled;
  match (wrapped)
    case %((!or scope pool) ?owner): return owner;
  return %(none);
}

static void _lifetime_finish_return(
  List pending, Map publics, Map summaries, Array findings, Array unresolved) {
  String path, function, name;
  List target, scoped, pooled, allocated, returned, causes;
  Symbol status;
  match (pending)
    case %(
      pending-return ?return_path ?return_function
      ?return_target ?callee ?return_status
      (!set ?scope_owner (scope ?)) (!set ?pool_owner (pool ?))
      (allocated ?allocation_location) (returned ?return_location)
      (causes *return_causes)
    ): {
      path = return_path, function = return_function;
      target = return_target, name = callee;
      status = return_status;
      scoped = scope_owner, pooled = pool_owner;
      allocated = allocation_location, returned = return_location;
      causes = return_causes;
    }
  Symbol allocation_kind = _lifetime_resolved_kind(
    target, publics, summaries
  );
  if (!allocation_kind) {
    List scoped_owner = _lifetime_pending_owner(<scoped>, scoped, pooled);
    List pooled_owner = _lifetime_pending_owner(<pooled>, scoped, pooled);
    if (_lifetime_owner_ended(scoped_owner) ||
        _lifetime_owner_ended(pooled_owner))
      unresolved.push(%(
        call $path $function $name $allocated
      ));
    return;
  }
  List owner = _lifetime_pending_owner(
    allocation_kind, scoped, pooled
  );
  if (!_lifetime_owner_ended(owner) || status == <moved>) return;
  if (status == <unresolved> || causes) {
    foreach (List cause, causes)
      if (!unresolved.contains(cause)) unresolved.push(cause);
    return;
  }
  match (owner)
    case %(region ? ?region_kind ? ? ? ? ?ended):
      findings.push(%(
        finding dangling-return $path $function $region_kind $name
        (allocated $allocated) (ended $ended) (returned $returned)
      ));
}

List Lifetime.finish(List units) {
  int region_count = 0, allocation_count = 0, transfer_count = 0;
  Array functions = %[], pending_allocations = %[];
  Array pending_returns = %[], findings = %[], unresolved = %[];
  foreach (List unit, units)
    match (unit)
      case %(
        lifetime-unit
        (summary (regions ?regions) (allocations ?allocations)
                 (transfers ?transfers))
        (functions *unit_functions)
        (pending-allocations *unit_allocations)
        (pending-returns *unit_returns)
        (allocation-returns *)
        (findings *unit_findings)
        (unresolved *unit_unresolved)
      ): {
        region_count += regions.integer();
        allocation_count += allocations.integer();
        transfer_count += transfers.integer();
        foreach (List function, unit_functions) functions.push(function);
        foreach (List allocation, unit_allocations)
          pending_allocations.push(allocation);
        foreach (List pending, unit_returns) pending_returns.push(pending);
        foreach (List finding, unit_findings) findings.push(finding);
        foreach (List call, unit_unresolved) unresolved.push(call);
      }
  functions.sort();
  Map publics = %{};
  Map summaries = _lifetime_summaries(
    functions.list_free(), publics
  );
  foreach (List allocation, pending_allocations)
    match (allocation)
      case %(pending-allocation ?target ?scope ?pool): {
        Symbol kind = _lifetime_resolved_kind(target, publics, summaries);
        if ((kind == <scoped> && scope.integer()) ||
            (kind == <pooled> && pool.integer()))
          allocation_count++;
      }
  foreach (List pending, pending_returns)
    _lifetime_finish_return(
      pending, publics, summaries, findings, unresolved
    );
  findings.sort();
  unresolved.sort();
  int finding_count = findings.len(), unresolved_count = unresolved.len();
  return %(
    lifetime-escapes
    (summary (regions $region_count) (allocations $allocation_count)
             (transfers $transfer_count) (unresolved $unresolved_count)
             (findings $finding_count))
    (findings @{findings.list_free()})
    (unresolved @{unresolved.list_free()})
  );
}
