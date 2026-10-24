/*  loop-allocations.x -- ranked allocation expressions inside loops */

#pragma once

#include "lifetime.x"
#include "targets.x"

typedef struct LoopAllocations *LoopAllocations;

enum { LOOP_ALLOCATION_LIMIT = 25 };


/* One unit's loop-allocation walk: the function being walked and the
   direct allocations and helper calls found in its loops. */
typedef struct LoopWalk LoopWalk;
static struct LoopWalk {
  Compiler compiler;
  Map definitions;
  String path, function;
  Symbol visibility;
  Array direct, pending;
};

static void _loop_collect(
  LoopWalk &walk, Var value, int origin, int loop_depth, Symbol use) {
  if (value is not <list>) return;
  List node = value;
  String operation = NULL;
  Symbol direct_kind = 0;
  if (loop_depth) {
    direct_kind = Lifetime.loop_allocation_kind(
      walk.compiler, node, operation);
    if (direct_kind)
      walk.direct.push(
        %(direct $direct_kind ${walk.path} ${walk.function}
          ${walk.visibility} $operation $use
          ${project_location(walk.compiler, walk.path, origin)} $loop_depth));
  }
  match (node) {
    case %(function *): return;
    case %(at ?next_origin ?inner): {
      _loop_collect(walk, inner, next_origin.integer(), loop_depth, use);
      return;
    }
    case %(while ?condition ?body): {
      _loop_collect(walk, condition, origin, loop_depth + 1, <condition>);
      _loop_collect(walk, body, origin, loop_depth + 1, <nested>);
      return;
    }
    case %(do ?body ?condition): {
      _loop_collect(walk, body, origin, loop_depth + 1, <nested>);
      _loop_collect(walk, condition, origin, loop_depth + 1, <condition>);
      return;
    }
    case %(for ?initial ?condition ?increment ?body): {
      _loop_collect(walk, initial, origin, loop_depth, <nested>);
      _loop_collect(walk, condition, origin, loop_depth + 1, <condition>);
      _loop_collect(walk, increment, origin, loop_depth + 1, <nested>);
      _loop_collect(walk, body, origin, loop_depth + 1, <nested>);
      return;
    }
    case %(return ? ?expression): {
      _loop_collect(walk, expression, origin, loop_depth, <returned>);
      return;
    }
    case %(stmnt ?expression): {
      _loop_collect(walk, expression, origin, loop_depth, <discarded>);
      return;
    }
    case %(expr ? ?inner): {
      _loop_collect(walk, inner, origin, loop_depth, use);
      return;
    }
    case %(parens ?inner): {
      _loop_collect(walk, inner, origin, loop_depth, use);
      return;
    }
    case %(cast ?declaration ?expression): {
      _loop_collect(walk, declaration, origin, loop_depth, <nested>);
      _loop_collect(walk, expression, origin, loop_depth, use);
      return;
    }
    case %(op = ?left ?right): {
      _loop_collect(walk, left, origin, loop_depth, <nested>);
      _loop_collect(walk, right, origin, loop_depth, <assigned>);
      return;
    }
    case %(call ?callee (!set ?arguments (args *))): {
      if (loop_depth && !direct_kind) {
        String name;
        List target = project_call_target(
          walk.compiler, walk.definitions, node, name, NULL);
        if (target && !List.equal(target, %(computed)))
          walk.pending.push(
            %(allocation-return $target ${walk.path} ${walk.function}
              ${walk.visibility} $name $use
              ${project_location(walk.compiler, walk.path, origin)}
              $loop_depth));
      }
      _loop_collect(walk, callee, origin, loop_depth, <nested>);
      foreach (Var argument, cdr(arguments))
        _loop_collect(walk, argument, origin, loop_depth, <argument>);
      return;
    }
  }
  foreach (Var child, node)
    _loop_collect(walk, child, origin, loop_depth, <nested>);
}

List LoopAllocations.analyze_unit(Compiler compiler, List ast, String path) {
  LoopWalk walk = {
    .compiler = compiler,
    .definitions = project_function_targets(compiler, ast, path),
    .path = path, .direct = [], .pending = []
  };
  foreach (List node, ast)
    match (node)
      case %(function ?type
             (bind (!set ?binding (binding ? ?)) ?)
             ?body): {
        walk.function = compiler.emitted_binding_name(binding);
        walk.visibility = project_visibility(compiler, type, binding);
        _loop_collect(walk, body, 0, 0, <nested>);
      }
  walk.direct.sort();
  walk.pending.sort();
  return %(
    loop-allocation-unit
    (lifetime ${
      Lifetime.analyze_unit(compiler, ast, path, walk.definitions)})
    (direct @{walk.direct.list_free()})
    (pending @{walk.pending.list_free()})
  );
}

/* Groups a direct allocation or a resolved helper call by its site. Both
   events list kind, unit, function, visibility, operation, use, location,
   and loop depth. */
static void _loop_add_event(
  Map groups, Map totals, Map functions, List event) {
  match (event)
    case %((!or ?tag direct allocation-return)
           ?kind ?unit ?function ?visibility ?operation ?use ?location
           ?depth): {
      Symbol source = tag == <direct> ? <direct> : <helper>;
      List key = %(site $unit $function $visibility $location);
      groups[key] = cons(
        %($source $kind $operation $use $depth),
        groups.getdefault(key, NULL));
      functions[%($unit $function $visibility)] = 1;
      project_count(totals, %($source $kind), 1);
    }
}

/* The ranked record for the site `key`, `(site UNIT FUNCTION VISIBILITY
   LOCATION)`, and its events. */
static List _loop_candidate(List key, List events) {
  Map counts = {};
  int loop_depth = 0;
  foreach (List event, events)
    match (event)
      case %(?source ?kind ?operation ?use ?depth): {
        project_count(counts, %(allocation $source $kind), 1);
        project_count(counts, %(use $use), 1);
        project_count(counts, %(operation $source $operation $kind), 1);
        if (loop_depth < depth.integer()) loop_depth = depth.integer();
      }

  int direct_pooled = counts.getdefault(%(allocation direct pooled), 0).int();
  int direct_scoped = counts.getdefault(%(allocation direct scoped), 0).int();
  int helper_pooled = counts.getdefault(%(allocation helper pooled), 0).int();
  int helper_scoped = counts.getdefault(%(allocation helper scoped), 0).int();
  int returned = counts.getdefault(%(use returned), 0).int();
  int assigned = counts.getdefault(%(use assigned), 0).int();
  int argument = counts.getdefault(%(use argument), 0).int();
  int discarded = counts.getdefault(%(use discarded), 0).int();
  int condition = counts.getdefault(%(use condition), 0).int();
  int nested = counts.getdefault(%(use nested), 0).int();

  Array operations = [];
  foreach (Var (raw_operation, raw_count), counts) {
    List operation = raw_operation;
    match (operation) {
      case %(operation direct ?name ?):
        operations.push(%(direct $name ${raw_count.int()}));
      case %(operation helper ?name ?kind):
        operations.push(%(helper $name $kind ${raw_count.int()}));
    }
  }
  operations.sort();
  return %(
    @key
    (allocations
      (direct (pooled $direct_pooled) (scoped $direct_scoped))
      (helper-calls (pooled $helper_pooled) (scoped $helper_scoped)))
    (uses (returned $returned) (assigned $assigned)
          (argument $argument) (discarded $discarded)
          (condition $condition) (nested $nested))
    (operations @{operations.list_free()})
    (loop-depth $loop_depth)
  );
}

/* Orders a candidate before another with fewer scoped allocations,
   discarded results, helper calls, allocations, or loop nesting, and
   breaks ties by site. */
static List _loop_candidate_rank(List candidate) {
  match (candidate)
    case %(site ?unit ?function ? (location ?source ?line ?column)
           (allocations (direct (pooled ?direct_pooled) (scoped ?scoped))
                        (helper-calls (pooled ?helper_pooled)
                                      (scoped ?helper_scoped)))
           (uses ? ? ? (discarded ?discarded) ? ?)
           (operations *) (loop-depth ?depth)): {
      int helpers = helper_pooled.int() + helper_scoped.int();
      int direct = direct_pooled.int() + scoped.int();
      return %(
        ${-(scoped.int() + helper_scoped.int())} ${-discarded.int()}
        ${-helpers} ${-(direct + helpers)} ${-depth.int()}
        $unit $function $source $line $column
      );
    }
  return nil;
}

List LoopAllocations.finish(List units, int limit) {
  Array lifetime_units = [], direct = [], pending = [];
  foreach (List unit, units)
    match (unit)
      case %(
        loop-allocation-unit (lifetime ?lifetime)
        (direct *unit_direct) (pending *unit_pending)
      ): {
        lifetime_units.push(lifetime);
        foreach (List event, unit_direct) direct.push(event);
        foreach (List event, unit_pending) pending.push(event);
      }
  List resolved = Lifetime.resolve_allocation_returns(
    lifetime_units.list_free(), pending.list_free());

  Map groups = {}, totals = {}, functions = {};
  foreach (List event, direct)
    _loop_add_event(groups, totals, functions, event);
  foreach (List event, resolved)
    _loop_add_event(groups, totals, functions, event);

  Array candidates = [];
  foreach (Var (raw_key, raw_events), groups)
    candidates.push(_loop_candidate(raw_key, raw_events));
  List ranked = project_ranked_records(
    candidates, %!(List candidate) => _loop_candidate_rank(candidate),
    limit);

  int function_count = functions.len();
  int expression_count = groups.len();
  int direct_pooled = totals.getdefault(%(direct pooled), 0).int();
  int direct_scoped = totals.getdefault(%(direct scoped), 0).int();
  int helper_pooled = totals.getdefault(%(helper pooled), 0).int();
  int helper_scoped = totals.getdefault(%(helper scoped), 0).int();
  int reported = ranked.len();
  return %(
    loop-allocations
    (summary (functions $function_count) (expressions $expression_count)
             (direct (pooled $direct_pooled) (scoped $direct_scoped))
             (helper-calls (pooled $helper_pooled)
                           (scoped $helper_scoped))
             (reported $reported))
    (candidates @ranked)
  );
}
