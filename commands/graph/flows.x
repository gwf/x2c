/*  flows.x -- exact producer-to-consumer value-flow queries

    The analysis keeps compiler bindings only while one parsed unit is alive.
    Its project records use paths, emitted names, parameter positions, and
    source locations.  A path is reported only through value-preserving forms;
    every other boundary remains explicit and unresolved.
*/

#pragma once

#include "compiler/compiler.x"
#include "targets.x"


#include <string.h>

/* One function's value-flow walk: the unit facts its calls resolve
   against, its parameters, and the returns, calls, and unresolved stores
   it finds. Locals vary by branch and travel beside the walk. */
typedef struct FlowUnit FlowUnit;
static struct FlowUnit {
  Compiler compiler;
  String path;
  Map definitions, parameters;
  Array returns, calls, unresolved;
};

static List _flow_location(FlowUnit &unit, int origin) =>
  project_location(unit.compiler, unit.path, origin);

static List _flow_summary(FlowUnit &unit, Var value, Map locals) {
  Var node = project_peel(value);
  match (node) {
    case %(ident (!set ?binding (binding ? ?spelling))): {
      Var position;
      if (unit.parameters.try_get(binding, position)) return position;
      if (locals.contains(binding)) return %(local $spelling);
      return %(identifier ${unit.compiler.emitted_binding_name(binding)});
    }
    case %(call ?callee (args *)): {
      String name;
      project_call_target(unit.compiler, {}, node, name, NULL);
      return %(call $name);
    }
    case %(literal ? ?spelling *): return %(literal $spelling);
    case %(cons *): return %(list);
    case %(map *): return %(map);
    case %(array *): return %(array);
    case %(op (!or (!quote .) (!quote ->)) ? (?member)):
      return %(field $member);
  }
  return %(value);
}

static List _flow_arguments(
  FlowUnit &unit, List values, int origin, Map locals) {
  Array arguments = [];
  int position = 0;
  foreach (Var value, values) {
    arguments.push(
      %(argument $position ${_flow_summary(unit, value, locals)}
        ${_flow_source(unit, value, origin, locals)}));
    position++;
  }
  return arguments.list_free();
}

static List _flow_source(FlowUnit &unit, Var value, int origin, Map locals) {
  if (value is not <list>)
    return %(unknown "value" ${_flow_location(unit, origin)});
  List node = value;
  match (node) {
    case %(at ?next_origin ?inner):
      return _flow_source(unit, inner, next_origin.integer(), locals);
    case %(expr ? ?inner): return _flow_source(unit, inner, origin, locals);
    case %(parens ?inner): return _flow_source(unit, inner, origin, locals);
    case %(cast ? ?inner): return _flow_source(unit, inner, origin, locals);
    case %(op = ? ?right): return _flow_source(unit, right, origin, locals);
    case %(ident (!set ?binding (binding ? ?spelling))): {
      Var position;
      if (unit.parameters.try_get(binding, position)) return position;
      if (locals.contains(binding)) return locals[binding];
      return %(value ${_flow_summary(unit, node, locals)});
    }
    case %(call ? (args *arguments)): {
      String name = NULL;
      List target = project_call_target(
        unit.compiler, unit.definitions, node, name, NULL);
      if (name == "List_var" && arguments && !arguments.cdr())
        return %(
          wrapper $name ${_flow_location(unit, origin)}
          ${_flow_source(unit, arguments.car(), origin, locals)}
        );
      return %(
        call $target $name ${_flow_location(unit, origin)}
        (arguments @{_flow_arguments(unit, arguments, origin, locals)})
      );
    }
    case %(op ? ? ?ontrue ?onfalse):
      return %(
        choice ${_flow_location(unit, origin)}
        ${_flow_source(unit, ontrue, origin, locals)}
        ${_flow_source(unit, onfalse, origin, locals)}
      );
    case %(op (!or (!quote .) (!quote ->)) ? (?)):
      return %(unknown "field-read" ${_flow_location(unit, origin)});
  }
  return %(value ${_flow_summary(unit, node, locals)});
}

static void _flow_collect_calls(
  FlowUnit &unit, Var value, int origin, Map locals) {
  if (value is not <list>) return;
  List node = value;
  match (node) {
    case %(function *): return;
    case %(at ?next_origin ?inner): {
      _flow_collect_calls(unit, inner, next_origin.integer(), locals);
      return;
    }
    case %(call ? (args *arguments)):
      unit.calls.push(_flow_source(unit, node, origin, locals));
  }
  foreach (Var child, node) _flow_collect_calls(unit, child, origin, locals);
}

static List _flow_local_binding(Var value) {
  if (value is not <list>) return NULL;
  List node = value;
  match (node) {
    case %(bind (!set ?binding (binding ? ?)) ?): return binding;
    case %(ident (!set ?binding (binding ? ?))): return binding;
    case %(op = ?left ?): return _flow_local_binding(left);
    case %(expr ? ?inner): return _flow_local_binding(inner);
    case %(parens ?inner): return _flow_local_binding(inner);
  }
  return NULL;
}

static void _flow_invalidate_addressed(
  FlowUnit &unit, Var value, int origin, Map locals) {
  if (value is not <list>) return;
  List node = value;
  match (node) {
    case %(function *): return;
    case %(at ?next_origin ?inner): {
      _flow_invalidate_addressed(unit, inner, next_origin.integer(), locals);
      return;
    }
    case %(op & ?inner): {
      List binding = _flow_local_binding(inner);
      if (binding && locals.contains(binding)) {
        List prior = locals[binding];
        locals[binding] = %(
          unknown "address-mutation" ${_flow_location(unit, origin)} $prior
        );
      }
      return;
    }
  }
  foreach (Var child, node)
    _flow_invalidate_addressed(unit, child, origin, locals);
}

static void _flow_collect_effects(
  FlowUnit &unit, Var value, int origin, Map locals) {
  _flow_collect_calls(unit, value, origin, locals);
  _flow_invalidate_addressed(unit, value, origin, locals);
}

static void _flow_merge_locals(
  FlowUnit &unit, int origin, Map locals, Map first, Map second) {
  foreach (Var (binding_value, source_value), locals) {
    List binding = binding_value;
    List first_source = first[binding];
    List second_source = second[binding];
    if (List.equal(first_source, second_source)) {
      locals[binding] = first_source;
      continue;
    }
    locals[binding] = %(
      unknown "alias-merge" ${_flow_location(unit, origin)}
      $first_source $second_source
    );
  }
}

static void _flow_set_local(
  FlowUnit &unit, List binding, Var value, Symbol kind, int origin,
  Map locals) {
  locals[binding] = %(
    $kind ${Ast.binding_spelling(binding)} ${_flow_location(unit, origin)}
    ${_flow_source(unit, value, origin, locals)}
  );
}

/* Walks `branch` from a copy of `locals` and merges the result back. */
static void _flow_branch(FlowUnit &unit, Var branch, int origin, Map locals) {
  Map prior = locals.copy(), branch_locals = prior.copy();
  _flow_statement(unit, branch, origin, branch_locals);
  _flow_merge_locals(unit, origin, locals, prior, branch_locals);
}

static void _flow_statement(
  FlowUnit &unit, Var value, int origin, Map locals) {
  if (value is not <list>) return;
  List node = value;
  match (node) {
    case %(function *): return;
    case %(at ?next_origin ?inner): {
      _flow_statement(unit, inner, next_origin.integer(), locals);
      return;
    }
    case %(block *statements): {
      foreach (Var statement, statements)
        _flow_statement(unit, statement, origin, locals);
      return;
    }
    case %(declare ? (bindings *bindings)): {
      foreach (Var entry, bindings) {
        List binding = _flow_local_binding(entry);
        if (!binding) continue;
        match (entry) {
          case %(op = ? ?initial):
            _flow_set_local(unit, binding, initial, <local>, origin, locals);
          default:
            locals[binding] = %(
              unknown "uninitialized" ${_flow_location(unit, origin)}
            );
        }
      }
      _flow_collect_effects(unit, node, origin, locals);
      return;
    }
    case %(stmnt (expr ? (op = ?left ?right))): {
      List binding = _flow_local_binding(left);
      if (binding)
        _flow_set_local(unit, binding, right, <assignment>, origin, locals);
      else
        unit.unresolved.push(
          %(unresolved "field-storage" ${_flow_location(unit, origin)}
            ${_flow_source(unit, right, origin, locals)}));
      _flow_collect_effects(unit, right, origin, locals);
      return;
    }
    case %(stmnt (expr ? (op ?operator ?left ?right))): {
      List binding = _flow_local_binding(left);
      if (binding && operator != <=>) {
        List prior = locals.contains(binding)
                   ? locals[binding].list()
                   : %(unknown "prior" ${_flow_location(unit, origin)});
        locals[binding] = %(
          unknown "mutation" ${_flow_location(unit, origin)} $prior
        );
      }
      _flow_collect_effects(unit, node, origin, locals);
      return;
    }
    case %(return ? ?expression): {
      unit.returns.push(
        %(return ${_flow_location(unit, origin)}
          ${_flow_source(unit, expression, origin, locals)}));
      _flow_collect_effects(unit, expression, origin, locals);
      return;
    }
    case %(if ?condition ?ontrue): {
      _flow_collect_effects(unit, condition, origin, locals);
      _flow_branch(unit, ontrue, origin, locals);
      return;
    }
    case %(if ?condition ?ontrue ?onfalse): {
      _flow_collect_effects(unit, condition, origin, locals);
      Map prior = locals.copy();
      Map true_locals = prior.copy(), false_locals = prior.copy();
      _flow_statement(unit, ontrue, origin, true_locals);
      _flow_statement(unit, onfalse, origin, false_locals);
      _flow_merge_locals(unit, origin, locals, true_locals, false_locals);
      return;
    }
    case %(while ?condition ?body): {
      _flow_collect_effects(unit, condition, origin, locals);
      _flow_branch(unit, body, origin, locals);
      return;
    }
    case %(do ?body ?condition): {
      Map prior = locals.copy(), branch = prior.copy();
      _flow_statement(unit, body, origin, branch);
      _flow_collect_effects(unit, condition, origin, branch);
      _flow_merge_locals(unit, origin, locals, prior, branch);
      return;
    }
    case %(for ?initial ?condition ?increment ?body): {
      Map prior = locals.copy(), branch = prior.copy();
      _flow_statement(unit, initial, origin, branch);
      _flow_collect_effects(unit, condition, origin, branch);
      _flow_statement(unit, body, origin, branch);
      _flow_collect_effects(unit, increment, origin, branch);
      _flow_merge_locals(unit, origin, locals, prior, branch);
      return;
    }
    case %(switch ?expression ?body): {
      _flow_collect_effects(unit, expression, origin, locals);
      _flow_branch(unit, body, origin, locals);
      return;
    }
    case %(catchcases ?arms): {
      Map prior = locals.copy();
      foreach (List arm, arms.list())
        match (arm)
          case %(? ?body): {
            Map branch = prior.copy();
            _flow_statement(unit, body, origin, branch);
            Map accumulated = locals.copy();
            _flow_merge_locals(unit, origin, locals, accumulated, branch);
          }
      return;
    }
    case %(try ?body ?catches ?cleanup): {
      Map prior = locals.copy();
      Map body_locals = prior.copy(), catch_locals = prior.copy();
      _flow_statement(unit, body, origin, body_locals);
      if (catches is <list>)
        _flow_statement(unit, catches, origin, catch_locals);
      _flow_merge_locals(
        unit, origin, locals, body_locals,
        catches is <list> ? catch_locals : body_locals);
      if (cleanup is <list>) _flow_statement(unit, cleanup, origin, locals);
      return;
    }
  }
  _flow_collect_effects(unit, node, origin, locals);
}

List _x2c_flow_analyze_unit(Compiler compiler, List ast, String path) {
  Map definitions = project_function_targets(compiler, ast, path);
  Array functions = [];
  foreach (List node, ast)
    match (node)
      case %(function ?type
             (bind (!set ?binding (binding ? ?)) ?modifiers)
             ?body): {
        FlowUnit unit = {
          .compiler = compiler, .path = path, .definitions = definitions,
          .parameters = {}, .returns = [], .calls = [], .unresolved = []
        };
        Array parameter_records = [];
        foreach (List parameter, project_parameters(modifiers))
          match (parameter)
            case %(parameter ?position
                   (!set ?parameter_binding (binding ? ?spelling))
                   ?parameter_type): {
              List record = %(
                parameter $position $spelling $parameter_type
              );
              unit.parameters[parameter_binding] = record;
              parameter_records.push(record);
            }
        _flow_statement(unit, body, 0, {});
        parameter_records.sort();
        unit.returns.sort();
        unit.calls.sort();
        unit.unresolved.sort();
        functions.push(
          %(function ${definitions[binding]}
            ${compiler.emitted_binding_name(binding)}
            ${project_visibility(type)}
            (parameters @{parameter_records.list_free()})
            (returns @{unit.returns.list_free()})
            (calls @{unit.calls.list_free()})
            (unresolved @{unit.unresolved.list_free()})));
      }
  functions.sort();
  return functions.list_free();
}

static void _flow_indexes(
  List functions, Map by_target, Map publics, Map by_name) {
  foreach (List function, functions)
    match (function)
      case %(
        function (!set ?target (target ? ?)) ? ?visibility
        (parameters *) (returns *) (calls *) (unresolved *)
      ): {
        by_target[target] = function;
        project_add_public(by_name, target);
        if (visibility == <public>) project_add_public(publics, target);
      }
}

static String _flow_unresolved_call(List raw, Map publics) {
  if (List.equal(raw, %(computed))) return "computed-call";
  match (raw)
    case %(public ?name): {
      if (!publics.contains(name)) return "missing-call";
      List targets = publics[name];
      if (targets && targets.cdr()) return "ambiguous-call";
    }
  return "unresolved-call";
}

static List _flow_argument(List arguments, int position) {
  foreach (List argument, arguments)
    match (argument)
      case %(argument ?index ? ?source):
        if (index.integer() == position) return source;
  return NULL;
}

static List _flow_other_arguments(List arguments, int consumed) {
  Array others = [];
  foreach (List argument, arguments)
    match (argument)
      case %(argument ?index ?summary ?):
        if (index.integer() != consumed)
          others.push(%(argument $index $summary));
  others.sort();
  return others.list_free();
}

/* One producer-to-consumer query over the project's function records:
   the resolved producer, the taint facts that reach it, the functions on
   the current trace path, and the paths and unresolved chains found. */
typedef struct FlowTrace FlowTrace;
static struct FlowTrace {
  List producer, functions;
  Map by_target, publics, tainted_parameters, tainted_returns, active;
  Array paths, unresolved;
};

static int _flow_is_tainted(FlowTrace &trace, List source, List current) {
  if (!source) return 0;
  match (source) {
    case %((!or local assignment return wrapper unknown) *parts):
      foreach (Var part, parts)
        if (part is <list> && _flow_is_tainted(trace, part, current))
          return 1;
    case %(choice ? ?ontrue ?onfalse):
      return _flow_is_tainted(trace, ontrue, current) ||
             _flow_is_tainted(trace, onfalse, current);
    case %(parameter ?position ? ?):
      return trace.tainted_parameters.contains(
        %(parameter $current $position));
    case %(call ?raw ? ? (arguments *)): {
      List target = resolve_project_target(raw, trace.publics);
      if (target &&
          (List.equal(target, trace.producer) ||
           trace.tainted_returns.contains(target)))
        return 1;
    }
  }
  return 0;
}

static int _flow_carries_taint(
  FlowTrace &trace, List source, List current) {
  if (_flow_is_tainted(trace, source, current)) return 1;
  match (source)
    case %(call ? ? ? (arguments *arguments)):
      foreach (List argument, arguments)
        match (argument)
          case %(argument ? ? ?argument_source):
            if (_flow_carries_taint(trace, argument_source, current))
              return 1;
  return 0;
}

static void _flow_build_taint(FlowTrace &trace) {
  int changed;
  do {
    changed = 0;
    foreach (List function, trace.functions)
      match (function)
        case %(
          function ?target ? ? (parameters *) (returns *returns)
          (calls *calls) (unresolved *)
        ): {
          if (!trace.tainted_returns.contains(target))
            foreach (List returned, returns)
              if (_flow_is_tainted(trace, returned, target)) {
                trace.tainted_returns[target] = 1;
                changed = 1;
                break;
              }
          foreach (List call, calls)
            match (call)
              case %(call ?raw ? ? (arguments *arguments)): {
                List callee = resolve_project_target(raw, trace.publics);
                if (!callee) continue;
                foreach (List argument, arguments)
                  match (argument)
                    case %(argument ?position ? ?source): {
                      List key = %(parameter $callee $position);
                      if (!trace.tainted_parameters.contains(key) &&
                          _flow_is_tainted(trace, source, target)) {
                        trace.tainted_parameters[key] = 1;
                        changed = 1;
                      }
                    }
              }
        }
  } while (changed);
}

static void _flow_record_result(
  FlowTrace &trace, String blocked, List steps) {
  if (blocked)
    trace.unresolved.push(%(unresolved $blocked (chain @steps)));
  else
    trace.paths.push(%(path @steps));
}

static void _flow_trace_call_arguments(
  FlowTrace &trace, List arguments, List current, Map environment,
  List suffix, String reason) {
  foreach (List argument, arguments)
    match (argument)
      case %(argument ? ? ?source):
        if (_flow_carries_taint(trace, source, current))
          _flow_trace(trace, source, current, environment, suffix, reason);
}

/* Follows `source` back toward the producer. `current` is the function
   whose record holds `source`, `environment` maps its parameter positions
   to the caller's argument sources, and `suffix` holds the steps already
   taken toward the consumer. */
static void _flow_trace(
  FlowTrace &trace, List source, List current, Map environment,
  List suffix, String blocked) {
  if (!source) return;
  match (source) {
    case %(wrapper ?name ?location ?inner):
      _flow_trace(
        trace, inner, current, environment,
        cons(%(step wrapper $name $location), suffix), blocked);
    case %(choice ?location ?ontrue ?onfalse): {
      _flow_trace(
        trace, ontrue, current, environment,
        cons(%(step choice $location), suffix), blocked);
      _flow_trace(
        trace, onfalse, current, environment,
        cons(%(step choice $location), suffix), blocked);
    }
    case %((!or local assignment) ?spelling ?location ?inner):
      _flow_trace(
        trace, inner, current, environment,
        cons(%(step ${source.car()} $spelling $location), suffix), blocked);
    case %(return ?location ?inner):
      _flow_trace(
        trace, inner, current, environment,
        cons(%(step return $location), suffix), blocked);
    case %(unknown ?reason ?location *inners):
      foreach (List inner, inners)
        _flow_trace(
          trace, inner, current, environment, suffix,
          blocked ? blocked : reason.str());
    case %(parameter ?position ?spelling ?type): {
      Var replacement;
      if (environment.try_get(position.integer(), replacement)) {
        _flow_trace(
          trace, replacement, current, {},
          cons(%(step parameter $position $spelling $type), suffix),
          blocked);
        return;
      }
      foreach (List caller, trace.functions)
        match (caller)
          case %(
            function ?caller_target ? ? (parameters *) (returns *)
            (calls *calls) (unresolved *)
          ):
            foreach (List call, calls)
              match (call)
                case %(
                  call ?raw ?name ?location
                  (arguments *arguments)
                ): {
                  List target = resolve_project_target(raw, trace.publics);
                  if (!target || !List.equal(target, current)) continue;
                  if (trace.active.contains(caller_target)) continue;
                  List argument = _flow_argument(
                    arguments, position.integer());
                  if (argument &&
                      _flow_carries_taint(trace, argument, caller_target)) {
                    trace.active[caller_target] = 1;
                    _flow_trace(
                      trace, argument, caller_target, {},
                      cons(%(step call $name $location), suffix), blocked);
                    trace.active.del(caller_target);
                  }
                }
    }
    case %(
      call ?raw ?name ?location (arguments *arguments)
    ): {
      List target = resolve_project_target(raw, trace.publics);
      if (target && List.equal(target, trace.producer)) {
        _flow_record_result(
          trace, blocked,
          cons(%(step producer $target $location), suffix));
        return;
      }
      String reason = !target ? _flow_unresolved_call(raw, trace.publics)
                    : trace.active.contains(target) ? "recursive-call"
                    : !trace.by_target.contains(target) ? "external-call"
                    : NULL;
      if (reason) {
        _flow_trace_call_arguments(
          trace, arguments, current, environment, suffix,
          blocked ? blocked : reason);
        return;
      }
      List function = trace.by_target[target];
      Map next_environment = {};
      foreach (List argument, arguments)
        match (argument)
          case %(argument ?position ? ?argument_source):
            next_environment[position.integer()] = argument_source;
      int returned = 0;
      trace.active[target] = 1;
      match (function)
        case %(
          function ? ? ? (parameters *) (returns *returns)
          (calls *) (unresolved *)
        ):
          foreach (List returned_source, returns) {
            if (!_flow_carries_taint(trace, returned_source, target))
              continue;
            returned = 1;
            _flow_trace(
              trace, returned_source, target, next_environment,
              cons(%(step call $name $location), suffix), blocked);
          }
      trace.active.del(target);
      if (!returned)
        _flow_trace_call_arguments(
          trace, arguments, current, environment, suffix,
          blocked ? blocked : "no-return-flow");
    }
  }
}

static List _flow_definition(Map by_target, List target) {
  if (!target || !by_target.contains(target)) return %(unresolved);
  List function = by_target[target];
  match (function)
    case %(function ?target ?name ?visibility *):
      return %(function $target $name $visibility);
  return %(unresolved);
}

static List _flow_sorted_unique(Array values) {
  Map seen = {};
  Array sorted = [];
  foreach (List value, values)
    if (!seen.contains(value)) {
      seen[value] = 1;
      sorted.push(value);
    }
  sorted.sort();
  return sorted.list_free();
}

/* Traces each tainted argument source of one call site in `caller`. */
static void _flow_trace_site(
  FlowTrace &trace, List caller, List source, List terminal,
  String blocked) {
  trace.active = {};
  trace.active[caller] = 1;
  _flow_trace(trace, source, caller, {}, terminal, blocked);
}

List _x2c_flow_finish(
  List functions, String producer_name, String consumer_name) {
  Map by_target = {}, publics = {}, by_name = {};
  _flow_indexes(functions, by_target, publics, by_name);
  List producer = resolve_project_target(
    %(public $producer_name), by_name);
  List consumer = resolve_project_target(
    %(public $consumer_name), by_name);
  FlowTrace trace = {
    .producer = producer, .functions = functions, .by_target = by_target,
    .publics = publics, .tainted_parameters = {}, .tainted_returns = {},
    .paths = [], .unresolved = []
  };
  if (!producer)
    trace.unresolved.push(
      %(unresolved
        ${by_name.contains(producer_name)
          ? "ambiguous-producer" : "missing-producer"}));
  if (!consumer)
    trace.unresolved.push(
      %(unresolved
        ${by_name.contains(consumer_name)
          ? "ambiguous-consumer" : "missing-consumer"}));
  if (producer && consumer) {
    _flow_build_taint(trace);
    foreach (List function, functions)
      match (function)
        case %(
          function ?caller ? ? (parameters *) (returns *)
          (calls *calls) (unresolved *barriers)
        ): {
          foreach (List call, calls)
            match (call)
              case %(
                call ?raw ? ?location (arguments *arguments)
              ): {
                List resolved = resolve_project_target(raw, publics);
                if (List.equal(resolved, consumer)) {
                  int position = 0;
                  foreach (List argument, arguments) {
                    List source = NULL;
                    match (argument)
                      case %(argument ? ? ?value): source = value;
                    if (_flow_carries_taint(trace, source, caller))
                      _flow_trace_site(
                        trace, caller, source,
                        %((consumer $consumer $location
                           (argument $position)
                           (other-arguments
                             @{_flow_other_arguments(arguments, position)}))),
                        NULL);
                    position++;
                  }
                }
                else if (!resolved) {
                  String reason = _flow_unresolved_call(raw, publics);
                  foreach (List argument, arguments)
                    match (argument)
                      case %(argument ? ? ?source):
                        if (_flow_carries_taint(trace, source, caller))
                          _flow_trace_site(
                            trace, caller, source,
                            %((site $location)), reason);
                }
              }
          foreach (List barrier, barriers)
            match (barrier)
              case %(unresolved ?reason ?location ?source):
                if (_flow_carries_taint(trace, source, caller))
                  _flow_trace_site(
                    trace, caller, source, %((site $location)),
                    reason.str());
        }
  }
  return %(
    flows $producer_name $consumer_name
    (definitions
      (producer ${_flow_definition(by_target, producer)})
      (consumer ${_flow_definition(by_target, consumer)}))
    (paths @{_flow_sorted_unique(trace.paths)})
    (unresolved @{_flow_sorted_unique(trace.unresolved)})
  );
}
