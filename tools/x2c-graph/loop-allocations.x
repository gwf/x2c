/*  loop-allocations.x -- ranked allocation expressions inside loops */

#pragma once

#include "lifetime.x"
#include "targets.x"

typedef struct LoopAllocations *LoopAllocations;

enum { LOOP_ALLOCATION_LIMIT = 25 };

List LoopAllocations.analyze_unit(Compiler compiler, List ast, String path);
List LoopAllocations.finish(List units, int limit);

#pragma private

static void _loop_increment(Map counts, List key, int amount) {
  Var prior;
  int count = counts.try_get(key, &prior) ? prior.int() : 0;
  counts[key] = count + amount;
}

static int _loop_count(Map counts, List key) {
  Var value;
  return counts.try_get(key, &value) ? value.int() : 0;
}

static List _loop_location(Compiler compiler, String path, int origin) {
  List location = compiler.origin_location(origin);
  if (!location) return %(location $path 0 0);
  Var file = location.assoc(<file>);
  String source = file is <string>
                ? compiler.display_path(file.str()) : path;
  int line = location.assoc(<line>).integer();
  int column = location.assoc(<column>).integer();
  return %(location $source $line $column);
}

static void _loop_collect(
  Compiler compiler, Map definitions, Var value, String path, String function,
  Symbol visibility, int origin, int loop_depth, Symbol use, Array direct,
  Array pending) {
  if (value is not <list>) return;
  List node = value;
  String operation = NULL;
  Symbol direct_kind = 0;
  if (loop_depth) {
    direct_kind = Lifetime.loop_allocation_kind(
      compiler, node, &operation
    );
    if (direct_kind)
      direct.push(%(
        direct-allocation $path $function $visibility
        $direct_kind $operation $use
        ${_loop_location(compiler, path, origin)} $loop_depth
      ));
  }
  match (node) {
    case %(function *): return;
    case %(at ?next_origin ?inner): {
      _loop_collect(
        compiler, definitions, inner, path, function, visibility,
        next_origin.integer(), loop_depth, use, direct, pending
      );
      return;
    }
    case %(while ?condition ?body): {
      _loop_collect(
        compiler, definitions, condition, path, function, visibility,
        origin, loop_depth + 1, <condition>, direct, pending
      );
      _loop_collect(
        compiler, definitions, body, path, function, visibility,
        origin, loop_depth + 1, <nested>, direct, pending
      );
      return;
    }
    case %(do ?body ?condition): {
      _loop_collect(
        compiler, definitions, body, path, function, visibility,
        origin, loop_depth + 1, <nested>, direct, pending
      );
      _loop_collect(
        compiler, definitions, condition, path, function, visibility,
        origin, loop_depth + 1, <condition>, direct, pending
      );
      return;
    }
    case %(for ?initial ?condition ?increment ?body): {
      _loop_collect(
        compiler, definitions, initial, path, function, visibility,
        origin, loop_depth, <nested>, direct, pending
      );
      _loop_collect(
        compiler, definitions, condition, path, function, visibility,
        origin, loop_depth + 1, <condition>, direct, pending
      );
      _loop_collect(
        compiler, definitions, increment, path, function, visibility,
        origin, loop_depth + 1, <nested>, direct, pending
      );
      _loop_collect(
        compiler, definitions, body, path, function, visibility,
        origin, loop_depth + 1, <nested>, direct, pending
      );
      return;
    }
    case %(return ? ?expression): {
      _loop_collect(
        compiler, definitions, expression, path, function, visibility,
        origin, loop_depth, <returned>, direct, pending
      );
      return;
    }
    case %(stmnt ?expression): {
      _loop_collect(
        compiler, definitions, expression, path, function, visibility,
        origin, loop_depth, <discarded>, direct, pending
      );
      return;
    }
    case %(expr ? ?inner): {
      _loop_collect(
        compiler, definitions, inner, path, function, visibility,
        origin, loop_depth, use, direct, pending
      );
      return;
    }
    case %(parens ?inner): {
      _loop_collect(
        compiler, definitions, inner, path, function, visibility,
        origin, loop_depth, use, direct, pending
      );
      return;
    }
    case %(cast ?declaration ?expression): {
      _loop_collect(
        compiler, definitions, declaration, path, function, visibility,
        origin, loop_depth, <nested>, direct, pending
      );
      _loop_collect(
        compiler, definitions, expression, path, function, visibility,
        origin, loop_depth, use, direct, pending
      );
      return;
    }
    case %(op = ?left ?right): {
      _loop_collect(
        compiler, definitions, left, path, function, visibility,
        origin, loop_depth, <nested>, direct, pending
      );
      _loop_collect(
        compiler, definitions, right, path, function, visibility,
        origin, loop_depth, <assigned>, direct, pending
      );
      return;
    }
    case %(call ?callee (!set ?arguments (args *))): {
      if (loop_depth && !direct_kind) {
        String name;
        List target = project_call_target(
          compiler, definitions, node, &name
        );
        if (target && !List.equal(target, %(computed)))
          pending.push(%(
            allocation-return $target $path $function $visibility
            $name $use ${_loop_location(compiler, path, origin)}
            $loop_depth
          ));
      }
      _loop_collect(
        compiler, definitions, callee, path, function, visibility,
        origin, loop_depth, <nested>, direct, pending
      );
      foreach (Var argument, cdr(arguments))
        _loop_collect(
          compiler, definitions, argument, path, function, visibility,
          origin, loop_depth, <argument>, direct, pending
        );
      return;
    }
  }
  foreach (Var child, node)
    _loop_collect(
      compiler, definitions, child, path, function, visibility,
      origin, loop_depth, <nested>, direct, pending
    );
}

List LoopAllocations.analyze_unit(Compiler compiler, List ast, String path) {
  Map definitions = project_function_targets(compiler, ast, path);
  Array direct = %[], pending = %[];
  foreach (List node, ast)
    match (node)
      case %(function ?type
             (bind (!set ?binding (binding ? ?)) ?)
             ?body): {
        String function = compiler.emitted_binding_name(binding);
        Symbol visibility = ((Type) type).is_static()
                          ? <static> : <public>;
        _loop_collect(
          compiler, definitions, body, path, function, visibility,
          0, 0, <nested>, direct, pending
        );
      }
  direct.sort();
  pending.sort();
  return %(
    loop-allocation-unit
    (lifetime ${Lifetime.analyze_unit(
      compiler, ast, path, definitions
    )})
    (direct @{direct.list_free()})
    (pending @{pending.list_free()})
  );
}

static void _loop_add_event(
  Map groups, Map totals, Map functions, List event) {
  String unit, function, operation;
  Symbol visibility, source, kind, use;
  List location;
  int depth;
  match (event) {
    case %(
      direct-allocation ?event_unit ?event_function ?event_visibility
      ?event_kind ?event_operation ?event_use ?event_location ?event_depth
    ): {
      unit = event_unit, function = event_function;
      visibility = event_visibility, source = <direct>;
      kind = event_kind, operation = event_operation, use = event_use;
      location = event_location, depth = event_depth.integer();
    }
    case %(
      allocation-return ?event_kind ?event_unit ?event_function
      ?event_visibility ?event_operation ?event_use
      ?event_location ?event_depth
    ): {
      unit = event_unit, function = event_function;
      visibility = event_visibility, source = <helper>;
      kind = event_kind, operation = event_operation, use = event_use;
      location = event_location, depth = event_depth.integer();
    }
  }
  List key = %(site $unit $function $visibility $location);
  List events = groups.contains(key) ? groups[key].list() : NULL;
  groups[key] = cons(%($source $kind $operation $use $depth), events);
  functions[%($unit $function $visibility)] = 1;
  _loop_increment(totals, %($source $kind), 1);
}

static List _loop_candidate(List key, List events) {
  String unit, function;
  Symbol visibility;
  List location;
  match (key)
    case %(site ?site_unit ?site_function ?site_visibility ?site_location): {
      unit = site_unit, function = site_function;
      visibility = site_visibility, location = site_location;
    }

  Map counts = %{};
  int loop_depth = 0;
  foreach (List event, events)
    match (event)
      case %(?source ?kind ?operation ?use ?depth): {
        _loop_increment(counts, %(allocation $source $kind), 1);
        _loop_increment(counts, %(use $use), 1);
        _loop_increment(counts, %(operation $source $operation $kind), 1);
        if (loop_depth < depth.integer()) loop_depth = depth.integer();
      }

  int direct_pooled = _loop_count(
    counts, %(allocation direct pooled)
  );
  int direct_scoped = _loop_count(
    counts, %(allocation direct scoped)
  );
  int helper_pooled = _loop_count(
    counts, %(allocation helper pooled)
  );
  int helper_scoped = _loop_count(
    counts, %(allocation helper scoped)
  );
  int returned = _loop_count(counts, %(use returned));
  int assigned = _loop_count(counts, %(use assigned));
  int argument = _loop_count(counts, %(use argument));
  int discarded = _loop_count(counts, %(use discarded));
  int condition = _loop_count(counts, %(use condition));
  int nested = _loop_count(counts, %(use nested));

  Array operations = %[];
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
  List record = %(
    site $unit $function $visibility $location
    (allocations
      (direct (pooled $direct_pooled) (scoped $direct_scoped))
      (helper-calls (pooled $helper_pooled) (scoped $helper_scoped)))
    (uses (returned $returned) (assigned $assigned)
          (argument $argument) (discarded $discarded)
          (condition $condition) (nested $nested))
    (operations @{operations.list_free()})
    (loop-depth $loop_depth)
  );
  return record;
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
  Array lifetime_units = %[], direct = %[], pending = %[];
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
    lifetime_units.list_free(), pending.list_free()
  );

  Map groups = %{}, totals = %{}, functions = %{};
  foreach (List event, direct)
    _loop_add_event(groups, totals, functions, event);
  foreach (List event, resolved)
    _loop_add_event(groups, totals, functions, event);

  Array ranked = %[];
  foreach (Var (raw_key, raw_events), groups)
    ranked.push(
      _loop_candidate(raw_key.list(), raw_events.list())
    );
  ranked.sort_by(%!(List candidate) => _loop_candidate_rank(candidate));
  if (limit && (int) ranked.len() > limit)
    ranked.remslice(limit, ranked.len()).free();

  int function_count = functions.len();
  int expression_count = groups.len();
  int direct_pooled = _loop_count(totals, %(direct pooled));
  int direct_scoped = _loop_count(totals, %(direct scoped));
  int helper_pooled = _loop_count(totals, %(helper pooled));
  int helper_scoped = _loop_count(totals, %(helper scoped));
  int reported = ranked.len();
  return %(
    loop-allocations
    (summary (functions $function_count) (expressions $expression_count)
             (direct (pooled $direct_pooled) (scoped $direct_scoped))
             (helper-calls (pooled $helper_pooled)
                           (scoped $helper_scoped))
             (reported $reported))
    (candidates @{ranked.list_free()})
  );
}
