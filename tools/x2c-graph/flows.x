/*  flows.x -- exact producer-to-consumer value-flow queries

    The analysis keeps compiler bindings only while one parsed unit is alive.
    Its project records use paths, emitted names, parameter positions, and
    source locations.  A path is reported only through value-preserving forms;
    every other boundary remains explicit and unresolved.
*/

#pragma once

#include "compiler.x"
#include "targets.x"

List Flow_analyze_unit(Compiler compiler, List ast, String path);
List Flow_finish(List functions, String producer, String consumer);

#pragma private

#include <string.h>

static List _flow_producer_target;
static Map _flow_public_index, _flow_tainted_parameters;
static Map _flow_tainted_returns;

static List _flow_location(Compiler compiler, String path, int origin) {
  List location = compiler.origin_location(origin);
  if (!location) return %(location $path 0 0);
  Var file = location.assoc(<file>);
  String source = file is <string>
                ? compiler.display_path(file.str()) : path;
  return %(
    location $source ${location.assoc(<line>).integer()}
    ${location.assoc(<column>).integer()}
  );
}

static List _flow_target(
  Compiler compiler, Map definitions, Var value, String *name) {
  return project_call_target(compiler, definitions, value, name);
}

static List _flow_summary(
  Compiler compiler, Var value, Map parameters, Map locals) {
  if (value is not <list>) return %(value);
  List node = value;
  match (node) {
    case %(expr ? ?inner):
      return _flow_summary(compiler, inner, parameters, locals);
    case %(parens ?inner):
      return _flow_summary(compiler, inner, parameters, locals);
    case %(at ? ?inner):
      return _flow_summary(compiler, inner, parameters, locals);
    case %(ident (!set ?binding (binding ? ?spelling))): {
      Var position;
      if (parameters.try_get(binding, &position)) return position.list();
      if (locals.contains(binding)) return %(local $spelling);
      String name = compiler.emitted_binding_name(binding);
      return %(identifier ${name ? name : spelling.str()});
    }
    case %(call ?callee (args *)): {
      String name = NULL;
      _flow_target(compiler, %{}, node, &name);
      return %(call ${name ? name : %"computed"});
    }
    case %(literal ? ?spelling *): return %(literal $spelling);
    case %(cons *): return %(list);
    case %(map *): return %(map);
    case %(array *): return %(array);
    case %(op . ? (?member)): return %(field $member);
    case %(op (!quote ->) ? (?member)): return %(field $member);
  }
  return %(value);
}

static List _flow_source(
  Compiler compiler, Var value, String path, int origin, Map definitions,
  Map parameters, Map locals);

static List _flow_arguments(
  Compiler compiler, List values, String path, int origin, Map definitions,
  Map parameters, Map locals) {
  Array arguments = %[];
  int position = 0;
  foreach (Var value, values) {
    arguments.push(%(
      argument $position
      ${_flow_summary(compiler, value, parameters, locals)}
      ${_flow_source(
        compiler, value, path, origin, definitions, parameters, locals
      )}
    ));
    position++;
  }
  return arguments.list_free();
}

static List _flow_source(
  Compiler compiler, Var value, String path, int origin, Map definitions,
  Map parameters, Map locals) {
  if (value is not <list>)
    return %(
      unknown "value" ${_flow_location(compiler, path, origin)}
    );
  List node = value;
  match (node) {
    case %(at ?next_origin ?inner):
      return _flow_source(
        compiler, inner, path, next_origin.integer(), definitions,
        parameters, locals
      );
    case %(expr ? ?inner):
      return _flow_source(
        compiler, inner, path, origin, definitions, parameters, locals
      );
    case %(parens ?inner):
      return _flow_source(
        compiler, inner, path, origin, definitions, parameters, locals
      );
    case %(cast ? ?inner):
      return _flow_source(
        compiler, inner, path, origin, definitions, parameters, locals
      );
    case %(op = ? ?right):
      return _flow_source(
        compiler, right, path, origin, definitions, parameters, locals
      );
    case %(ident (!set ?binding (binding ? ?spelling))): {
      Var position;
      if (parameters.try_get(binding, &position)) return position.list();
      if (locals.contains(binding)) return locals[binding].list();
      return %(value ${_flow_summary(compiler, node, parameters, locals)});
    }
    case %(call ? (args *arguments)): {
      String name = NULL;
      List target = _flow_target(compiler, definitions, node, &name);
      if (name && name == %"List_var" && arguments && !arguments.cdr())
        return %(
          wrapper $name ${_flow_location(compiler, path, origin)}
          ${_flow_source(
            compiler, arguments.car(), path, origin, definitions,
            parameters, locals
          )}
        );
      return %(
        call ${target ? target : %(computed)}
        ${name ? name : %"computed"}
        ${_flow_location(compiler, path, origin)}
        (arguments
          @{_flow_arguments(
            compiler, arguments, path, origin, definitions,
            parameters, locals
          )})
      );
    }
    case %(op ? ? ?ontrue ?onfalse):
      return %(
        choice ${_flow_location(compiler, path, origin)}
        ${_flow_source(
          compiler, ontrue, path, origin, definitions, parameters, locals
        )}
        ${_flow_source(
          compiler, onfalse, path, origin, definitions, parameters, locals
        )}
      );
    case %(op . ? (?)):
      return %(unknown "field-read" ${_flow_location(compiler, path, origin)});
    case %(op (!quote ->) ? (?)):
      return %(unknown "field-read" ${_flow_location(compiler, path, origin)});
  }
  return %(
    value ${_flow_summary(compiler, node, parameters, locals)}
  );
}

static void _flow_collect_parameters(
  List modifiers, Map parameters, Array records) {
  match (modifiers)
    case %((fnmod (params *values)) *): {
      int position = 0;
      foreach (Var value, values) {
        match (value)
          case %(
            param ?type
            (bind (!set ?binding (binding ? ?spelling)) ?)
          ):
            parameters[binding] = %(
              parameter $position $spelling $type
            );
        match (value)
          case %(param ?type (bind (binding ? ?spelling) ?)):
            records.push(%(parameter $position $spelling $type));
        position++;
      }
    }
}

static void _flow_collect_calls(
  Compiler compiler, Var value, String path, int origin, Map definitions,
  Map parameters, Map locals, Array calls) {
  if (value is not <list>) return;
  List node = value;
  match (node) {
    case %(function *): return;
    case %(at ?next_origin ?inner): {
      _flow_collect_calls(
        compiler, inner, path, next_origin.integer(), definitions,
        parameters, locals, calls
      );
      return;
    }
    case %(call ? (args *arguments)):
      calls.push(_flow_source(
        compiler, node, path, origin, definitions, parameters, locals
      ));
  }
  foreach (Var child, node)
    _flow_collect_calls(
      compiler, child, path, origin, definitions, parameters, locals,
      calls
    );
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
  Compiler compiler, Var value, String path, int origin, Map locals) {
  if (value is not <list>) return;
  List node = value;
  match (node) {
    case %(function *): return;
    case %(at ?next_origin ?inner): {
      _flow_invalidate_addressed(
        compiler, inner, path, next_origin.integer(), locals
      );
      return;
    }
    case %(op & ?inner): {
      List binding = _flow_local_binding(inner);
      if (binding && locals.contains(binding)) {
        List prior = locals[binding];
        locals[binding] = %(
          unknown "address-mutation"
          ${_flow_location(compiler, path, origin)} $prior
        );
      }
      return;
    }
  }
  foreach (Var child, node)
    _flow_invalidate_addressed(compiler, child, path, origin, locals);
}

static void _flow_collect_effects(
  Compiler compiler, Var value, String path, int origin, Map definitions,
  Map parameters, Map locals, Array calls) {
  _flow_collect_calls(
    compiler, value, path, origin, definitions, parameters, locals,
    calls
  );
  _flow_invalidate_addressed(compiler, value, path, origin, locals);
}

static void _flow_merge_locals(
  Compiler compiler, String path, int origin, Map locals, Map first,
  Map second) {
  foreach (Var (binding_value, source_value), locals) {
    List binding = binding_value;
    List first_source = first[binding];
    List second_source = second[binding];
    if (List.equal(first_source, second_source)) {
      locals[binding] = first_source;
      continue;
    }
    locals[binding] = %(
      unknown "alias-merge" ${_flow_location(compiler, path, origin)}
      $first_source $second_source
    );
  }
}

static void _flow_set_local(
  Compiler compiler, List binding, String spelling, Var value, Symbol kind,
  String path, int origin, Map definitions, Map parameters, Map locals) {
  locals[binding] = %(
    $kind $spelling ${_flow_location(compiler, path, origin)}
    ${_flow_source(
      compiler, value, path, origin, definitions, parameters, locals
    )}
  );
}

static void _flow_statement(
  Compiler compiler, Var value, String path, int origin, Map definitions,
  Map parameters, Map locals, Array returns, Array calls, Array unresolved) {
  if (value is not <list>) return;
  List node = value;
  match (node) {
    case %(function *): return;
    case %(at ?next_origin ?inner): {
      _flow_statement(
        compiler, inner, path, next_origin.integer(), definitions,
        parameters, locals, returns, calls, unresolved
      );
      return;
    }
    case %(block *statements): {
      foreach (Var statement, statements)
        _flow_statement(
          compiler, statement, path, origin, definitions, parameters,
          locals, returns, calls, unresolved
        );
      return;
    }
    case %(declare ? (bindings *bindings)): {
      foreach (Var entry, bindings) {
        List binding = _flow_local_binding(entry);
        if (!binding) continue;
        String spelling = %"local";
        match (binding) case %(binding ? ?name): spelling = name.str();
        match (entry) {
          case %(op = ? ?initial):
            _flow_set_local(
              compiler, binding, spelling, initial, <local>, path,
              origin, definitions, parameters, locals
            );
          default:
            locals[binding] = %(
              unknown "uninitialized"
              ${_flow_location(compiler, path, origin)}
            );
        }
      }
      _flow_collect_effects(
        compiler, node, path, origin, definitions, parameters, locals,
        calls
      );
      return;
    }
    case %(stmnt (expr ? (op = ?left ?right))): {
      List binding = _flow_local_binding(left);
      if (binding) {
        String spelling = %"local";
        match (binding) case %(binding ? ?name): spelling = name.str();
        _flow_set_local(
          compiler, binding, spelling, right, <assignment>, path,
          origin, definitions, parameters, locals
        );
      }
      else
        unresolved.push(%(
          unresolved "field-storage"
          ${_flow_location(compiler, path, origin)}
          ${_flow_source(
            compiler, right, path, origin, definitions, parameters,
            locals
          )}
        ));
      _flow_collect_effects(
        compiler, right, path, origin, definitions, parameters, locals,
        calls
      );
      return;
    }
    case %(stmnt (expr ? (op ?operator ?left ?right))): {
      List binding = _flow_local_binding(left);
      if (binding && operator != <=>) {
        String spelling = %"local";
        match (binding) case %(binding ? ?name): spelling = name.str();
        List prior = locals.contains(binding)
                   ? locals[binding].list()
                   : %(
                       unknown "prior"
                       ${_flow_location(compiler, path, origin)}
                     );
        locals[binding] = %(
          unknown "mutation" ${_flow_location(compiler, path, origin)}
          $prior
        );
      }
      _flow_collect_effects(
        compiler, node, path, origin, definitions, parameters, locals,
        calls
      );
      return;
    }
    case %(return ? ?expression): {
      returns.push(%(
        return ${_flow_location(compiler, path, origin)}
        ${_flow_source(
          compiler, expression, path, origin, definitions, parameters,
          locals
        )}
      ));
      _flow_collect_effects(
        compiler, expression, path, origin, definitions, parameters,
        locals, calls
      );
      return;
    }
    case %(if ?condition ?ontrue): {
      _flow_collect_effects(
        compiler, condition, path, origin, definitions, parameters,
        locals, calls
      );
      Map prior = locals.copy(), branch = prior.copy();
      _flow_statement(
        compiler, ontrue, path, origin, definitions, parameters,
        branch, returns, calls, unresolved
      );
      _flow_merge_locals(
        compiler, path, origin, locals, prior, branch
      );
      return;
    }
    case %(if ?condition ?ontrue ?onfalse): {
      _flow_collect_effects(
        compiler, condition, path, origin, definitions, parameters,
        locals, calls
      );
      Map prior = locals.copy();
      Map true_locals = prior.copy(), false_locals = prior.copy();
      _flow_statement(
        compiler, ontrue, path, origin, definitions, parameters,
        true_locals, returns, calls, unresolved
      );
      _flow_statement(
        compiler, onfalse, path, origin, definitions, parameters,
        false_locals, returns, calls, unresolved
      );
      _flow_merge_locals(
        compiler, path, origin, locals, true_locals, false_locals
      );
      return;
    }
    case %(while ?condition ?body): {
      _flow_collect_effects(
        compiler, condition, path, origin, definitions, parameters,
        locals, calls
      );
      Map prior = locals.copy(), branch = prior.copy();
      _flow_statement(
        compiler, body, path, origin, definitions, parameters, branch,
        returns, calls, unresolved
      );
      _flow_merge_locals(
        compiler, path, origin, locals, prior, branch
      );
      return;
    }
    case %(do ?body ?condition): {
      Map prior = locals.copy(), branch = prior.copy();
      _flow_statement(
        compiler, body, path, origin, definitions, parameters, branch,
        returns, calls, unresolved
      );
      _flow_collect_effects(
        compiler, condition, path, origin, definitions, parameters,
        branch, calls
      );
      _flow_merge_locals(
        compiler, path, origin, locals, prior, branch
      );
      return;
    }
    case %(for ?initial ?condition ?increment ?body): {
      Map prior = locals.copy(), branch = prior.copy();
      _flow_statement(
        compiler, initial, path, origin, definitions, parameters,
        branch, returns, calls, unresolved
      );
      _flow_collect_effects(
        compiler, condition, path, origin, definitions, parameters,
        branch, calls
      );
      _flow_statement(
        compiler, body, path, origin, definitions, parameters, branch,
        returns, calls, unresolved
      );
      _flow_collect_effects(
        compiler, increment, path, origin, definitions, parameters,
        branch, calls
      );
      _flow_merge_locals(
        compiler, path, origin, locals, prior, branch
      );
      return;
    }
    case %(switch ?expression ?body): {
      _flow_collect_effects(
        compiler, expression, path, origin, definitions, parameters,
        locals, calls
      );
      Map prior = locals.copy(), branch = prior.copy();
      _flow_statement(
        compiler, body, path, origin, definitions, parameters, branch,
        returns, calls, unresolved
      );
      _flow_merge_locals(
        compiler, path, origin, locals, prior, branch
      );
      return;
    }
    case %(catchcases ?arms): {
      Map prior = locals.copy();
      foreach (List arm, arms.list())
        match (arm)
          case %(? ?body): {
            Map branch = prior.copy();
            _flow_statement(
              compiler, body, path, origin, definitions, parameters,
              branch, returns, calls, unresolved
            );
            Map accumulated = locals.copy();
            _flow_merge_locals(
              compiler, path, origin, locals, accumulated, branch
            );
          }
      return;
    }
    case %(try ?body ?catches ?cleanup): {
      Map prior = locals.copy();
      Map body_locals = prior.copy(), catch_locals = prior.copy();
      _flow_statement(
        compiler, body, path, origin, definitions, parameters,
        body_locals, returns, calls, unresolved
      );
      if (catches is <list>)
        _flow_statement(
          compiler, catches, path, origin, definitions, parameters,
          catch_locals, returns, calls, unresolved
        );
      _flow_merge_locals(
        compiler, path, origin, locals, body_locals,
        catches is <list> ? catch_locals : body_locals
      );
      if (cleanup is <list>)
        _flow_statement(
          compiler, cleanup, path, origin, definitions, parameters,
          locals, returns, calls, unresolved
        );
      return;
    }
  }
  _flow_collect_effects(
    compiler, node, path, origin, definitions, parameters, locals, calls
  );
}

List Flow_analyze_unit(Compiler compiler, List ast, String path) {
  Map definitions = project_function_targets(compiler, ast, path);
  Array functions = %[];
  foreach (List node, ast)
    match (node)
      case %(function ?type
             (bind (!set ?binding (binding ? ?)) ?modifiers)
             ?body): {
        Map parameters = %{}, locals = %{};
        Array parameter_records = %[], returns = %[], calls = %[];
        Array unresolved = %[];
        _flow_collect_parameters(
          modifiers, parameters, parameter_records
        );
        _flow_statement(
          compiler, body, path, 0, definitions, parameters, locals,
          returns, calls, unresolved
        );
        parameter_records.sort();
        returns.sort();
        calls.sort();
        unresolved.sort();
        Symbol visibility = ((Type) type).is_static()
                          ? <static> : <public>;
        functions.push(%(
          function ${definitions[binding]}
          ${compiler.emitted_binding_name(binding)}
          $visibility
          (parameters @{parameter_records.list_free()})
          (returns @{returns.list_free()})
          (calls @{calls.list_free()})
          (unresolved @{unresolved.list_free()})
        ));
      }
  functions.sort();
  return functions.list_free();
}

static void _flow_indexes(
  List functions, Map by_target, Map publics, Map by_name) {
  foreach (List function, functions)
    match (function)
      case %(
        function (!set ?target (target ? ?name)) ? ?visibility
        (parameters *) (returns *) (calls *) (unresolved *)
      ): {
        by_target[target] = function;
        List named = by_name.contains(name) ? by_name[name].list() : NULL;
        by_name[name] = cons(target, named);
        if (visibility == <public>) {
          List values = publics.contains(name)
                      ? publics[name].list() : NULL;
          publics[name] = cons(target, values);
        }
      }
}

static List _flow_exact_target(Map by_name, String name) {
  if (!by_name.contains(name)) return NULL;
  List values = by_name[name];
  return values && !values.cdr() ? values.car().list() : NULL;
}

static List _flow_resolve(List raw, Map publics) {
  return resolve_project_target(raw, publics);
}

static String _flow_unresolved_call(List raw, Map publics) {
  if (List.equal(raw, %(computed))) return %"computed-call";
  match (raw)
    case %(public ?name): {
      if (!publics.contains(name)) return %"missing-call";
      List targets = publics[name];
      if (targets && targets.cdr()) return %"ambiguous-call";
    }
  return %"unresolved-call";
}

static List _flow_argument(List arguments, int position) {
  foreach (List argument, arguments)
    match (argument)
      case %(argument ?index ? ?source):
        if (index.integer() == position) return source;
  return NULL;
}

static List _flow_other_arguments(List arguments, int consumed) {
  Array others = %[];
  foreach (List argument, arguments)
    match (argument)
      case %(argument ?index ?summary ?):
        if (index.integer() != consumed)
          others.push(%(argument $index $summary));
  others.sort();
  return others.list_free();
}

static int _flow_is_tainted(List source, List current) {
  if (!source) return 0;
  match (source) {
    case %((!or local assignment return wrapper unknown) *parts):
      foreach (Var part, parts)
        if (part is <list> && _flow_is_tainted(part.list(), current))
          return 1;
    case %(choice ? ?ontrue ?onfalse):
      return _flow_is_tainted(ontrue, current) ||
             _flow_is_tainted(onfalse, current);
    case %(parameter ?position ? ?):
      return _flow_tainted_parameters.contains(%(
        parameter $current $position
      ));
    case %(call ?raw ? ? (arguments *)): {
      List target = _flow_resolve(raw, _flow_public_index);
      if (target &&
          (List.equal(target, _flow_producer_target) ||
           _flow_tainted_returns.contains(target)))
        return 1;
    }
  }
  return 0;
}

static int _flow_carries_taint(List source, List current) {
  if (_flow_is_tainted(source, current)) return 1;
  match (source)
    case %(call ? ? ? (arguments *arguments)):
      foreach (List argument, arguments)
        match (argument)
          case %(argument ? ? ?argument_source):
            if (_flow_carries_taint(argument_source, current)) return 1;
  return 0;
}

static void _flow_build_taint(List functions) {
  int changed;
  do {
    changed = 0;
    foreach (List function, functions)
      match (function)
        case %(
          function ?target ? ? (parameters *) (returns *returns)
          (calls *calls) (unresolved *)
        ): {
          if (!_flow_tainted_returns.contains(target))
            foreach (List returned, returns)
              if (_flow_is_tainted(returned, target)) {
                _flow_tainted_returns[target] = 1;
                changed = 1;
                break;
              }
          foreach (List call, calls)
            match (call)
              case %(call ?raw ? ? (arguments *arguments)): {
                List callee = _flow_resolve(raw, _flow_public_index);
                if (!callee) continue;
                foreach (List argument, arguments)
                  match (argument)
                    case %(argument ?position ? ?source): {
                      List key = %(parameter $callee $position);
                      if (!_flow_tainted_parameters.contains(key) &&
                          _flow_is_tainted(source, target)) {
                        _flow_tainted_parameters[key] = 1;
                        changed = 1;
                      }
                    }
              }
        }
  } while (changed);
}

static List _flow_prepend(List step, List suffix) {
  return cons(step, suffix);
}

static void _flow_record_result(
  Array paths, Array unresolved, String blocked, List steps) {
  if (blocked)
    unresolved.push(%(unresolved $blocked (chain @steps)));
  else
    paths.push(%(path @steps));
}

static void _flow_trace(
  List source, List current, Map environment, List suffix, String blocked,
  List producer, Map by_target, Map publics, List functions, Map active,
  Array paths, Array unresolved);

static void _flow_trace_call_arguments(
  List arguments, List current, Map environment, List suffix, String reason,
  List producer, Map by_target, Map publics, List functions, Map active,
  Array paths, Array unresolved) {
  foreach (List argument, arguments)
    match (argument)
      case %(argument ? ? ?source):
        if (_flow_carries_taint(source, current))
          _flow_trace(
            source, current, environment, suffix, reason, producer,
            by_target, publics, functions, active, paths, unresolved
          );
}

static void _flow_trace(
  List source, List current, Map environment, List suffix, String blocked,
  List producer, Map by_target, Map publics, List functions, Map active,
  Array paths, Array unresolved) {
  if (!source) return;
  match (source) {
    case %(wrapper ?name ?location ?inner):
      _flow_trace(
        inner, current, environment,
        _flow_prepend(%(step wrapper $name $location), suffix), blocked,
        producer, by_target, publics, functions, active, paths,
        unresolved
      );
    case %(choice ?location ?ontrue ?onfalse): {
      _flow_trace(
        ontrue, current, environment,
        _flow_prepend(%(step choice $location), suffix), blocked,
        producer, by_target, publics, functions, active, paths,
        unresolved
      );
      _flow_trace(
        onfalse, current, environment,
        _flow_prepend(%(step choice $location), suffix), blocked,
        producer, by_target, publics, functions, active, paths,
        unresolved
      );
    }
    case %((!or local assignment) ?spelling ?location ?inner):
      _flow_trace(
        inner, current, environment,
        _flow_prepend(%(step ${source.car()} $spelling $location), suffix),
        blocked, producer, by_target, publics, functions, active,
        paths, unresolved
      );
    case %(return ?location ?inner):
      _flow_trace(
        inner, current, environment,
        _flow_prepend(%(step return $location), suffix), blocked,
        producer, by_target, publics, functions, active, paths,
        unresolved
      );
    case %(unknown ?reason ?location *inners):
      foreach (List inner, inners)
        _flow_trace(
          inner, current, environment, suffix,
          blocked ? blocked : reason.str(), producer, by_target,
          publics, functions, active, paths, unresolved
        );
    case %(parameter ?position ?spelling ?type): {
      Var replacement;
      if (environment.try_get(position.integer(), &replacement)) {
        _flow_trace(
          replacement.list(), current, %{},
          _flow_prepend(
            %(step parameter $position $spelling $type), suffix
          ),
          blocked, producer, by_target, publics, functions, active,
          paths, unresolved
        );
        return;
      }
      foreach (List caller, functions)
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
                  List target = _flow_resolve(raw, publics);
                  if (!target || !List.equal(target, current)) continue;
                  if (active.contains(caller_target)) continue;
                  List argument = _flow_argument(
                    arguments, position.integer()
                  );
                  if (argument &&
                      _flow_carries_taint(argument, caller_target)) {
                    Map next_active = active.copy();
                    next_active[caller_target] = 1;
                    _flow_trace(
                      argument, caller_target, %{},
                      _flow_prepend(
                        %(step call $name $location), suffix
                      ), blocked, producer, by_target, publics,
                      functions, next_active, paths, unresolved
                    );
                  }
                }
    }
    case %(
      call ?raw ?name ?location (arguments *arguments)
    ): {
      List target = _flow_resolve(raw, publics);
      if (target && List.equal(target, producer)) {
        _flow_record_result(
          paths, unresolved, blocked,
          _flow_prepend(
            %(step producer $target $location), suffix
          )
        );
        return;
      }
      if (!target) {
        String reason = _flow_unresolved_call(raw, publics);
        _flow_trace_call_arguments(
          arguments, current, environment, suffix,
          blocked ? blocked : reason, producer, by_target, publics,
          functions, active, paths, unresolved
        );
        return;
      }
      if (active.contains(target)) {
        _flow_trace_call_arguments(
          arguments, current, environment, suffix,
          blocked ? blocked : %"recursive-call", producer, by_target,
          publics, functions, active, paths, unresolved
        );
        return;
      }
      if (!by_target.contains(target)) {
        _flow_trace_call_arguments(
          arguments, current, environment, suffix,
          blocked ? blocked : %"external-call", producer, by_target,
          publics, functions, active, paths, unresolved
        );
        return;
      }
      List function = by_target[target];
      Map next_environment = %{}, next_active = active.copy();
      foreach (List argument, arguments)
        match (argument)
          case %(argument ?position ? ?argument_source):
            next_environment[position.integer()] = argument_source;
      next_active[target] = 1;
      int returned = 0;
      match (function)
        case %(
          function ? ? ? (parameters *) (returns *returns)
          (calls *) (unresolved *)
        ):
          foreach (List returned_source, returns) {
            if (!_flow_carries_taint(returned_source, target)) continue;
            returned = 1;
            _flow_trace(
              returned_source, target, next_environment,
              _flow_prepend(%(step call $name $location), suffix),
              blocked, producer, by_target, publics, functions,
              next_active, paths, unresolved
            );
          }
      if (!returned)
        _flow_trace_call_arguments(
          arguments, current, environment, suffix,
          blocked ? blocked : %"no-return-flow", producer, by_target,
          publics, functions, active, paths, unresolved
        );
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
  Map seen = %{};
  Array sorted = %[];
  foreach (List value, values)
    if (!seen.contains(value)) {
      seen[value] = 1;
      sorted.push(value);
    }
  sorted.sort();
  return sorted.list_free();
}

List Flow_finish(List functions, String producer_name, String consumer_name) {
  Map by_target = %{}, publics = %{}, by_name = %{};
  _flow_indexes(functions, by_target, publics, by_name);
  List producer = _flow_exact_target(by_name, producer_name);
  List consumer = _flow_exact_target(by_name, consumer_name);
  Array paths = %[], unresolved = %[];
  if (!producer)
    unresolved.push(%(
      unresolved
      ${by_name.contains(producer_name)
        ? %"ambiguous-producer" : %"missing-producer"}
    ));
  if (!consumer)
    unresolved.push(%(
      unresolved
      ${by_name.contains(consumer_name)
        ? %"ambiguous-consumer" : %"missing-consumer"}
    ));
  if (producer && consumer) {
    _flow_producer_target = producer;
    _flow_public_index = publics;
    _flow_tainted_parameters = %{};
    _flow_tainted_returns = %{};
    _flow_build_taint(functions);
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
                List resolved = _flow_resolve(raw, publics);
                if (List.equal(resolved, consumer)) {
                  int position = 0;
                  foreach (List argument, arguments) {
                    List source = NULL;
                    match (argument)
                      case %(argument ? ? ?value): source = value;
                    if (!_flow_carries_taint(source, caller)) {
                      position++;
                      continue;
                    }
                    Map active = %{};
                    active[caller] = 1;
                    List terminal = cons(%(
                      consumer $consumer $location
                      (argument $position)
                      (other-arguments
                        @{_flow_other_arguments(arguments, position)})
                    ), NULL);
                    _flow_trace(
                      source, caller, %{},
                      terminal, NULL, producer, by_target, publics,
                      functions, active, paths, unresolved
                    );
                    position++;
                  }
                }
                else if (!resolved) {
                  String reason = _flow_unresolved_call(raw, publics);
                  Map active = %{};
                  active[caller] = 1;
                  foreach (List argument, arguments)
                    match (argument)
                      case %(argument ? ? ?source):
                        if (_flow_carries_taint(source, caller)) {
                          _flow_trace(
                            source, caller, %{},
                            cons(%(site $location), NULL), reason,
                            producer, by_target, publics, functions,
                            active, paths, unresolved
                          );
                        }
                }
              }
          foreach (List barrier, barriers)
            match (barrier)
              case %(unresolved ?reason ?location ?source): {
                if (!_flow_carries_taint(source, caller))
                  continue;
                Map active = %{};
                active[caller] = 1;
                List terminal = cons(%(site $location), NULL);
                _flow_trace(
                  source, caller, %{},
                  terminal, reason.str(), producer,
                  by_target, publics, functions, active, paths,
                  unresolved
                );
              }
        }
  }
  return %(
    flows $producer_name $consumer_name
    (definitions
      (producer ${_flow_definition(by_target, producer)})
      (consumer ${_flow_definition(by_target, consumer)}))
    (paths @{_flow_sorted_unique(paths)})
    (unresolved @{_flow_sorted_unique(unresolved)})
  );
}
