/*  x2c-graph.x -- deterministic source-level call graph for x2c

    The tool consumes the real compiler parser but retains only compact graph
    records.  It never guesses a target for an indirect or ambiguous call.
*/

#include "frontend.x"
#include "flows.x"
#include "lifetime.x"
#include "loop-allocations.x"
#include "targets.x"

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static void _increment(Map counts, List key, int amount) {
  Var prior;
  int count = counts.try_get(key, &prior) ? prior.int() : 0;
  counts[key] = count + amount;
}

static void _record_call(Compiler compiler, List callee, Map calls) {
  match (callee) {
    case %(expr ?
           (ident (!set ?binding (binding ?identity ?spelling)))): {
      String name = compiler.emitted_binding_name(binding);
      if (compiler.semantic_binding_facts().contains(%(automatic $binding)))
        _increment(calls, %(indirect $spelling), 1);
      else
        _increment(calls, %(direct $identity $name), 1);
      return;
    }
  }
  _increment(calls, %(indirect "computed"), 1);
}

static void _collect_calls(Compiler compiler, Var value, Map calls) {
  if (value is not <list>) return;
  List node = value;
  match (node) {
    case %(function *): return;
    case %(expr ? (call ?callee (args *))):
      _record_call(compiler, callee, calls);
  }
  foreach (Var child, node) _collect_calls(compiler, child, calls);
}

static List _call_records(Map calls) {
  Array records = %[];
  foreach (Var (key, count), calls) {
    List call = key;
    match (call) {
      case %(direct ?identity ?name):
        records.push(%(call direct $identity $name ${count.int()}));
      case %(indirect ?name):
        records.push(%(call indirect $name ${count.int()}));
    }
  }
  records.sort();
  return records.list_free();
}

static String _source_function_name(Compiler compiler, List binding) {
  Var stored;
  if (compiler.semantic_binding_facts().try_get(
        %(method $binding), &stored)) {
    List method = stored;
    match (method)
      case %((!is ?owner type string) (!is ?member type string)):
        return %"$owner.$member";
  }
  return binding_identity_spelling(binding);
}

static List _analyze_unit(Compiler compiler, List ast) {
  Array functions = %[];
  Map top_level_calls = %{};
  int source_order = 0;
  foreach (List node, ast) {
    match (node) {
      case %(function ?type
             (bind (!set ?binding (binding ?identity ?)) ?)
             ?body): {
        Map calls = %{};
        _collect_calls(compiler, body, calls);
        String name = compiler.emitted_binding_name(binding);
        String source_name = _source_function_name(compiler, binding);
        Symbol visibility = ((Type) type).is_static()
                          ? <static> : <public>;
        source_order++;
        functions.push(%(
          function $identity $name $visibility
          (source $source_name $source_order)
          (calls @{_call_records(calls)})
        ));
        continue;
      }
    }
    _collect_calls(compiler, node, top_level_calls);
  }
  if (top_level_calls.len())
    functions.push(%(
      function 0 "<top-level>" static
      (source "<top-level>" 0)
      (calls @{_call_records(top_level_calls)})
    ));
  functions.sort();
  return functions.list_free();
}

static int _field_access_parts(
  Var type, Var member, String receiver_name, String field_name) {
  return type is <list> && member is <string> &&
         List.equal(type.list(), %($receiver_name)) &&
         member.str() == field_name;
}

static int _field_access_matches(
  List node, String receiver_name, String field_name) {
  match (node) {
    case %(op . (expr ?type ?) (?member)):
      return _field_access_parts(
        type, member, receiver_name, field_name
      );
    case %(op (!quote ->) (expr ?type ?) (?member)):
      return _field_access_parts(
        type, member, receiver_name, field_name
      );
  }
  return 0;
}

static List _walk_stable_root(Var value, Var type) {
  if (value is not <list>) return NULL;
  List node = value;
  match (node) {
    case %(ident (!set ?binding (binding ? ?))):
      return type.is_void() ? NULL : %(root $binding $type (path));
    case %(expr ?argument_type ?inner): {
      Var root_type = type.is_void() ? argument_type : type;
      return _walk_stable_root(inner, root_type);
    }
    case %(parens ?inner): return _walk_stable_root(inner, type);
    case %(at ? ?inner): return _walk_stable_root(inner, type);
    case %(op ?operator ?receiver (?member)): {
      if ((operator != <.> && operator != <"->">) ||
          member is not <string>)
        return NULL;
      List root = _walk_stable_root(receiver, type);
      match (root)
        case %(root ?binding ?root_type (path *path)):
          return %(
            root $binding $root_type
            (path @path (member $operator $member))
          );
    }
  }
  return NULL;
}

static String _walk_root_spelling(String root, List path) {
  Array parts = %[];
  parts.push(root);
  foreach (List step, path)
    match (step)
      case %(member ? ?name): {
        parts.push(%".");
        parts.push(name);
      }
  return %"".join(parts.list_free());
}

static int _walk_candidate_type(Var type) {
  if (type is not <list>) return 0;
  List value = type;
  return List.equal(value, %("Array")) ||
         List.equal(value, %("Ast")) ||
         List.equal(value, %("List")) ||
         List.equal(value, %("Map")) ||
         List.equal(value, %("Type")) ||
         List.equal(value, %("Var"));
}

static List _source_location(Compiler compiler, String path, int origin) {
  List location = compiler.origin_location(origin);
  if (!location) return %(location $path 0 0);
  Var file = location.assoc(<file>);
  String source = file is <string>
                ? compiler.display_path(file.str()) : path;
  int line = location.assoc(<line>).integer();
  int column = location.assoc(<column>).integer();
  return %(location $source $line $column);
}

static void _collect_tail_calls(
  Compiler compiler, Var value, List self, String path, int origin, int tail,
  Map counts, Map blockers, Array sites) {
  if (value is not <list>) return;
  List node = value;
  match (node) {
    case %(function *): return;
    case %(at ?next_origin ?inner): {
      _collect_tail_calls(
        compiler, inner, self, path, next_origin.integer(), tail,
        counts, blockers, sites
      );
      return;
    }
    case %(return ? ?expression): {
      _collect_tail_calls(
        compiler, expression, self, path, origin, 1,
        counts, blockers, sites
      );
      return;
    }
    case %(expr ? ?inner): {
      _collect_tail_calls(
        compiler, inner, self, path, origin, tail,
        counts, blockers, sites
      );
      return;
    }
    case %(parens ?inner): {
      _collect_tail_calls(
        compiler, inner, self, path, origin, tail,
        counts, blockers, sites
      );
      return;
    }
    case %(op (!quote ?) ?condition ?ontrue ?onfalse): {
      _collect_tail_calls(
        compiler, condition, self, path, origin, 0,
        counts, blockers, sites
      );
      foreach (Var arm, %($ontrue $onfalse))
        _collect_tail_calls(
          compiler, arm, self, path, origin, tail,
          counts, blockers, sites
        );
      return;
    }
    case %(defer *): blockers[<cleanup>] = 1;
    case %(try *): blockers[<cleanup>] = 1;
    case %(call
           (expr ?
             (ident (!set ?callee (binding ? ?))))
           (args *)): {
      if (List.equal(callee, self)) {
        Symbol kind = tail ? <tail> : <non-tail>;
        _increment(counts, %(kind $kind), 1);
        sites.push(%(
          site $kind ${_source_location(compiler, path, origin)}
        ));
      }
    }
  }
  foreach (Var child, node)
    _collect_tail_calls(
      compiler, child, self, path, origin, 0,
      counts, blockers, sites
    );
}

static int _kind_count(Map counts, Symbol kind) {
  Var count;
  return counts.try_get(%(kind $kind), &count) ? count.int() : 0;
}

static List _analyze_tail_unit(Compiler compiler, List ast, String path) {
  Array functions = %[];
  foreach (List node, ast)
    match (node)
      case %(function ?type
             (bind (!set ?binding (binding ? ?)) ?)
             ?body): {
        Map counts = %{}, blockers = %{};
        Array sites = %[];
        _collect_tail_calls(
          compiler, body, binding, path, 0, 0,
          counts, blockers, sites
        );
        int tail = _kind_count(counts, <tail>);
        int non_tail = _kind_count(counts, <non-tail>);
        if (!tail) continue;
        Array blocker_rows = %[];
        foreach (Var (blocker, present), blockers)
          blocker_rows.push(blocker);
        blocker_rows.sort();
        sites.sort();
        Symbol visibility = ((Type) type).is_static()
                          ? <static> : <public>;
        functions.push(%(
          function ${compiler.emitted_binding_name(binding)} $visibility
          (calls (tail $tail) (non-tail $non_tail))
          (blockers @{blocker_rows.list_free()})
          (sites @{sites.list_free()})
        ));
      }
  functions.sort();
  return functions.list_free();
}

static void _collect_walk_calls(
  Compiler compiler, Var value, String path, int origin, Map definitions,
  Array calls) {
  if (value is not <list>) return;
  List node = value;
  match (node) {
    case %(function *): return;
    case %(at ?next_origin ?inner): {
      _collect_walk_calls(
        compiler, inner, path, next_origin.integer(), definitions, calls
      );
      return;
    }
    case %(expr ?
           (call
             (expr ?
               (ident
                 (!set ?callee (binding ?callee_identity ?))))
             (args *arguments))): {
      Array direct_arguments = %[];
      int position = 0;
      foreach (Var argument, arguments) {
        List root = _walk_stable_root(argument, void);
        match (root)
          case %(
            root (binding ?identity ?spelling) ?type (path *root_path)
          ): {
            String display = _walk_root_spelling(
              spelling.str(), root_path
            );
            direct_arguments.push(%(
              argument $position
              (root $identity $spelling $type
                (path @root_path) $display)
            ));
          }
        position++;
      }
      List target = definitions.contains(callee)
                  ? definitions[callee].list()
                  : %(public ${compiler.emitted_binding_name(callee)});
      calls.push(%(
        call $target ${compiler.emitted_binding_name(callee)}
        ${_source_location(compiler, path, origin)}
        (arguments @{direct_arguments.list_free()})
      ));
    }
  }
  foreach (Var child, node)
    _collect_walk_calls(
      compiler, child, path, origin, definitions, calls
    );
}

static void _walk_collect_parameters(
  List modifiers, Map parameters, Array records) {
  match (modifiers)
    case %((fnmod (params *values)) *): {
      int position = 0;
      foreach (Var value, values) {
        match (value)
          case %(
            param ?type
            (bind (binding (!set ?identity) ?spelling) ?)
          ): {
            parameters[identity] = position;
            records.push(%(
              parameter $position $identity $type $spelling
            ));
          }
        position++;
      }
    }
}

static int _walk_root_parameter(List root, Map parameters) {
  match (root)
    case %(root ?binding ? ? (path *) ?): {
      Var position;
      if (parameters.try_get(binding, &position)) return position.integer();
    }
  return -1;
}

static int _walk_add_summary(Map summaries, List target, List summary) {
  List values = summaries.contains(target)
              ? summaries[target].list() : NULL;
  if (values.contains(summary)) return 0;
  summaries[target] = cons(summary, values);
  return 1;
}

static void _walk_mark_root(
  List root, List location, Map parameters, Map direct) {
  int position = _walk_root_parameter(root, parameters);
  if (position < 0) return;
  match (root)
    case %(root ? ? ?type (path *path) ?display):
      if (type is <list> && List.equal(type.list(), %("List")))
        direct[%(
          walk $position $type (path @path) $display linear $location
        )] = 1;
}

static int _walk_has_exit(Var value) {
  if (value is not <list>) return 0;
  List node = value;
  match (node) {
    case %(function *): return 0;
    case %((!or return break goto) *): return 1;
  }
  foreach (Var child, node)
    if (_walk_has_exit(child)) return 1;
  return 0;
}

static int _walk_loop_has_exit(Var value) {
  if (value is not <list>) return 0;
  List node = value;
  match (node) {
    case %(function *): return 0;
    case %((!or while for) *parts): {
      Var body = parts.last();
      if (_walk_has_exit(body)) return 1;
    }
  }
  foreach (Var child, node)
    if (_walk_loop_has_exit(child)) return 1;
  return 0;
}

static List _walk_direct_parameters(
  Var body, List self, List parameter_records, List calls) {
  Map parameters = %{}, direct = %{};
  foreach (List parameter, parameter_records)
    match (parameter)
      case %(parameter ?position ?binding ? ?):
        parameters[binding] = position;

  int recursive = 0, iterates = 0;
  List recursive_location = %(location "" 0 0);
  foreach (List call, calls)
    match (call)
      case %(
        call ?target ?name (!set ?location (location ? ? ?))
        (arguments *arguments)
      ): {
        if (List.equal(target, self)) {
          recursive = 1;
          recursive_location = location;
        }
        if (name is <string> && name.string() == %"Iter_try_next")
          foreach (List argument, arguments)
            match (argument)
              case %(
                argument 0 (root ? ?spelling ? (path) ?)
              ):
                if (spelling.str().startswith(
                      "_x2c_macro_iterator_"
                    )) iterates = 1;
      }

  if (recursive)
    foreach (List parameter, parameter_records)
      match (parameter)
        case %(parameter ?position ? ?type ?spelling):
          if (_walk_candidate_type(type))
            direct[%(
              walk $position $type (path) $spelling recursive
              $recursive_location
            )] = 1;

  if (iterates && !_walk_loop_has_exit(body))
    foreach (List call, calls)
      match (call)
        case %(
          call ? ?name (!set ?location (location ? ? ?))
          (arguments *arguments)
        ):
          if (name is <string> && name.string() == %"List_iter")
            foreach (List argument, arguments)
              match (argument)
                case %(argument 0 ?root):
                  _walk_mark_root(
                    root, location, parameters, direct
                  );

  match (self)
    case %(target ? "List_len"):
      foreach (List parameter, parameter_records)
        match (parameter)
          case %(parameter 0 ? ?type ?spelling):
            direct[%(
              walk 0 $type (path) $spelling linear
              (location "" 0 0)
            )] = 1;
  Array summaries = %[];
  foreach (Var (summary, present), direct) summaries.push(summary);
  summaries.sort();
  return summaries.list_free();
}

static List _analyze_walk_unit(Compiler compiler, List ast, String path) {
  Map definitions = %{};
  foreach (List node, ast)
    match (node)
      case %(function ?type
             (bind (!set ?binding (binding ?identity ?)) ?)
             ?):
        definitions[binding] = %(
          target $path ${compiler.emitted_binding_name(binding)}
        );

  Array functions = %[];
  foreach (List node, ast)
    match (node)
      case %(function ?type
             (bind (!set ?binding (binding ? ?)) ?modifiers)
             ?body): {
        List target = definitions[binding].list();
        Map parameters = %{};
        Array parameter_records = %[];
        _walk_collect_parameters(
          modifiers, parameters, parameter_records
        );
        List parameter_list = parameter_records.list_free();
        Array calls = %[];
        _collect_walk_calls(
          compiler, body, path, 0, definitions, calls
        );
        calls.sort();
        List call_list = calls.list_free();
        Symbol visibility = ((Type) type).is_static()
                          ? <static> : <public>;
        functions.push(%(
          function $target ${compiler.emitted_binding_name(binding)}
          $visibility (parameters @parameter_list) (calls @call_list)
          (direct
            @{_walk_direct_parameters(
              body, target, parameter_list, call_list
            )})
        ));
      }
  functions.sort();
  return functions.list_free();
}

static List _walk_call_argument(List arguments, int position) {
  foreach (List argument, arguments)
    match (argument)
      case %(argument ?argument_position ?root):
        if (argument_position.integer() == position) return root;
  return NULL;
}

static List _walk_candidates(List functions) {
  Map publics = %{}, walked = %{};
  foreach (List function, functions)
    match (function)
      case %(
        function (!set ?target (target ? ?name)) ? public
        (parameters *) (calls *) (direct *)
      ): {
        List targets = publics.contains(name) ? publics[name].list() : NULL;
        publics[name] = cons(target, targets);
      }

  foreach (List function, functions)
    match (function)
      case %(
        function ?target ? ? (parameters *) (calls *)
        (direct *summaries)
      ):
        foreach (List summary, summaries)
          match (summary)
            case %(
              walk ?position ?type ?path ?display ?kind
              (location ? ? ?)
            ):
              _walk_add_summary(
                walked, target,
                %(walk $position $type $path $display $kind)
              );

  int changed;
  do {
    changed = 0;
    foreach (List function, functions)
      match (function)
        case %(
          function ?caller ? ? (parameters *parameters)
          (calls *calls) (direct *)
        ): {
          Map parameter_map = %{};
          foreach (List parameter, parameters)
            match (parameter)
              case %(parameter ?position ?binding ? ?):
                parameter_map[binding] = position;
          foreach (List call, calls)
            match (call)
              case %(
                call ?raw_target ? (location ? ? ?)
                (arguments *arguments)
              ): {
                List target = resolve_project_target(raw_target, publics);
                if (!target || !walked.contains(target)) continue;
                foreach (List summary, walked[target].list()) {
                  int position = -1;
                  Var type = void;
                  List path = NULL;
                  match (summary)
                    case %(
                      walk ?next_position ?next_type
                      (path *next_path) ? linear
                    ): {
                      position = next_position.integer();
                      type = next_type;
                      path = next_path;
                    }
                  if (position < 0 || path) continue;
                  List root = _walk_call_argument(
                    arguments, position
                  );
                  if (!root) continue;
                  int caller_position = _walk_root_parameter(
                    root, parameter_map
                  );
                  match (root)
                    case %(root ? ? ?root_type (path *root_path) ?display):
                      if (caller_position >= 0 && !root_path &&
                          Var.equal(type, root_type))
                        changed |= _walk_add_summary(
                          walked, caller,
                          %(
                            walk $caller_position $type
                            (path) $display linear
                          )
                        );
                }
              }
        }
  } while (changed);

  Map groups = %{};
  foreach (List function, functions)
    match (function)
      case %(
        function (!set ?caller (target ?path ?))
        ?caller_name ?visibility (parameters *parameters)
        (calls *calls) (direct *direct)
      ): {
        foreach (List summary, direct)
          match (summary)
            case %(
              walk ?position ?type ?root_path ?display linear
              (!set ?location (location ? ? ?))
            ): {
              foreach (List parameter, parameters)
                match (parameter)
                  case %(
                    parameter ?parameter_position ?binding ? ?spelling
                  ):
                    if (position == parameter_position) {
                      List key = %(
                        group $caller $path $caller_name $visibility
                        $binding $spelling $type $root_path $display
                      );
                      List sites = groups.contains(key)
                                 ? groups[key].list() : NULL;
                      groups[key] = cons(
                        %(site "<inline>" $location), sites
                      );
                    }
            }
        foreach (List call, calls)
          match (call)
            case %(
              call ?raw_target ?callee_name
              (!set ?location (location ? ? ?))
              (arguments *arguments)
            ): {
              List target = resolve_project_target(raw_target, publics);
              Map matched_groups = %{};
              if (target && !List.equal(target, caller) &&
                  walked.contains(target))
                foreach (List summary, walked[target].list()) {
                  int position = -1;
                  Var terminal_type = void;
                  List suffix = NULL;
                  match (summary)
                    case %(
                      walk ?next_position ?type
                      (path *next_suffix) ? ?
                    ): {
                      position = next_position.integer();
                      terminal_type = type;
                      suffix = next_suffix;
                    }
                  if (position < 0) continue;
                  List root = _walk_call_argument(
                    arguments, position
                  );
                  match (root)
                    case %(
                      root ?argument_identity ?spelling ?
                      (path *prefix) ?
                    ): {
                      Array path_parts = %[];
                      foreach (Var step, prefix) path_parts.push(step);
                      foreach (Var step, suffix) path_parts.push(step);
                      List combined = path_parts.list_free();
                      String display = _walk_root_spelling(
                        spelling.str(), combined
                      );
                      List key = %(
                        group $caller $path $caller_name $visibility
                        $argument_identity $spelling $terminal_type
                        (path @combined) $display
                      );
                      if (matched_groups.contains(key)) continue;
                      matched_groups[key] = 1;
                      List sites = groups.contains(key)
                                 ? groups[key].list() : NULL;
                      groups[key] = cons(
                        %(site $callee_name $location), sites
                      );
                    }
                }
            }
      }

  Map by_unit = %{};
  foreach (Var (key_value, sites_value), groups) {
    List sites = sites_value;
    if (!sites.cdr()) continue;
    Map seen_walkers = %{};
    Array sorted_walkers = %[], sorted_sites = %[];
    foreach (List site, sites) {
      sorted_sites.push(site);
      match (site)
        case %(site (!set ?walker) (location ? ? ?)):
          if (!seen_walkers.contains(walker)) {
            seen_walkers[walker] = 1;
            sorted_walkers.push(walker);
          }
    }
    sorted_walkers.sort();
    sorted_sites.sort();
    List key = key_value;
    match (key)
      case %(
        group ? ?path ?caller_name ?visibility
        ? ? ?type ? ?display
      ): {
        List candidates = by_unit.contains(path)
                        ? by_unit[path].list() : NULL;
        by_unit[path] = cons(%(
          candidate $caller_name $visibility
          (argument $type $display)
          (walkers @{sorted_walkers.list_free()})
          (sites @{sorted_sites.list_free()})
        ), candidates);
      }
  }
  Array units = %[];
  foreach (Var (path, values), by_unit) {
    Array candidates = %[];
    foreach (List candidate, values.list()) candidates.push(candidate);
    candidates.sort();
    units.push(%(
      unit $path (candidates @{candidates.list_free()})
    ));
  }
  units.sort();
  return %(walks (units @{units.list_free()}));
}

static String _site_direct_callee(Compiler compiler, List callee) {
  match (callee)
    case %(expr ?
           (ident (!set ?binding (binding ? ?)))): {
      if (compiler.semantic_binding_facts().contains(%(automatic $binding)))
        return NULL;
      return compiler.emitted_binding_name(binding);
    }
  return NULL;
}

static void _site_add_prior_write(
  Map prior_writes, List binding, List summary) {
  List prior = prior_writes.contains(binding)
             ? prior_writes[binding].list() : NULL;
  if (!prior.contains(summary)) prior_writes[binding] = cons(summary, prior);
}

static List _site_value_summary(
  Compiler compiler, Var value, Map parameters, Map prior_writes) {
  if (value is not <list>) return %(form);
  List node = value;
  if (!node) return %(form);
  match (node) {
    case %(expr ? ?inner):
      return _site_value_summary(
        compiler, inner, parameters, prior_writes
      );
    case %(parens ?inner):
      return _site_value_summary(
        compiler, inner, parameters, prior_writes
      );
    case %(at ? ?inner):
      return _site_value_summary(
        compiler, inner, parameters, prior_writes
      );
    case %(ident (!set ?binding (binding ? ?spelling))): {
      if (parameters.contains(binding)) return %(parameter $spelling);
      if (prior_writes.contains(binding)) {
        Array writes = %[];
        foreach (List write, prior_writes[binding].list())
          writes.push(write);
        writes.sort();
        return %(
          local $spelling (prior-writes @{writes.list_free()})
        );
      }
      if (compiler.semantic_binding_facts().contains(%(automatic $binding)))
        return %(local $spelling);
      String name = compiler.emitted_binding_name(binding);
      return %(global ${name ? name : spelling.str()});
    }
    case %(op . (expr ?type ?) (?member)):
      return %(field $type $member);
    case %(op (!quote ->) (expr ?type ?) (?member)):
      return %(field $type $member);
    case %(call ?callee (args *)): {
      String name = _site_direct_callee(compiler, callee);
      return name ? %(call $name) : %(call computed);
    }
    case %((!or index getindex) ?target ?):
      return %(
        index ${_site_value_summary(
          compiler, target, parameters, prior_writes
        )}
      );
    case %(literal ? ?spelling *): return %(literal $spelling);
    case %(cons *): return %(list);
    case %(map *): return %(map);
    case %(array *): return %(array);
    case %(cast ? ?inner):
      return %(
        cast ${_site_value_summary(
          compiler, inner, parameters, prior_writes
        )}
      );
    case %(op ?operator *): return %(operator $operator);
    case %(cache ?): return %(constant);
  }
  Var tag = node.car();
  return tag is <symbol> ? %(form ${tag.symbol()}) : %(form);
}

static List _site_argument_summary(
  Compiler compiler, Var argument, Map parameters, Map prior_writes) {
  match (argument)
    case %(expr ?type ?): {
      List summary = _site_value_summary(
        compiler, argument, parameters, prior_writes
      );
      if (type is <list> && List.equal(type.list(), %("List")) &&
          List.equal(summary, %(constant)))
        summary = %(list);
      return %(
        argument $type $summary
      );
    }
  return %(
    argument ()
    ${_site_value_summary(compiler, argument, parameters, prior_writes)}
  );
}

static void _site_collect_parameters(List modifiers, Map parameters) {
  match (modifiers)
    case %((fnmod (params *values)) *):
      foreach (Var value, values)
        match (value)
          case %(param ? (bind (!set ?binding (binding ? ?)) ?)):
            parameters[binding] = 1;
}

static List _site_direct_binding(Var value) {
  if (value is not <list>) return NULL;
  List node = value;
  match (node) {
    case %(ident (!set ?binding (binding ? ?))): return binding;
    case %(expr ? ?inner): return _site_direct_binding(inner);
    case %(parens ?inner): return _site_direct_binding(inner);
    case %(at ? ?inner): return _site_direct_binding(inner);
  }
  return NULL;
}

static void _collect_sites(
  Compiler compiler, Var value, String path, String caller, Symbol visibility,
  String wanted, Map parameters, Map prior_writes, Map sites) {
  if (value is not <list>) return;
  List node = value;
  match (node) {
    case %(function *): return;
    case %(op = (bind (!set ?binding (binding ? ?)) ?) ?right): {
      _collect_sites(
        compiler, right, path, caller, visibility, wanted,
        parameters, prior_writes, sites
      );
      _site_add_prior_write(
        prior_writes, binding,
        _site_value_summary(compiler, right, %{}, %{})
      );
      return;
    }
    case %(op ?operator ?left *right):
      if (operator is <symbol> &&
          ast_changes_left_operand(operator.symbol())) {
        _collect_sites(
          compiler, left, path, caller, visibility, wanted,
          parameters, prior_writes, sites
        );
        foreach (Var child, right)
          _collect_sites(
            compiler, child, path, caller, visibility, wanted,
            parameters, prior_writes, sites
          );
        List binding = _site_direct_binding(left);
        if (binding) {
          List summary = operator == <=> && right
                       ? _site_value_summary(
                           compiler, right.car(), %{}, %{}
                         )
                       : %(operator $operator);
          _site_add_prior_write(prior_writes, binding, summary);
        }
        return;
      }
    case %(postfix ?operator ?target): {
      _collect_sites(
        compiler, target, path, caller, visibility, wanted,
        parameters, prior_writes, sites
      );
      List binding = _site_direct_binding(target);
      if (binding)
        _site_add_prior_write(
          prior_writes, binding, %(operator $operator)
        );
      return;
    }
    case %(expr ? (call ?callee (args *arguments))): {
      String name = _site_direct_callee(compiler, callee);
      if (name == wanted) {
        Array summaries = %[];
        foreach (Var argument, arguments)
          summaries.push(_site_argument_summary(
            compiler, argument, parameters, prior_writes
          ));
        _increment(
          sites,
          %(
            call $path $caller $visibility
            (args @{summaries.list_free()})
          ),
          1
        );
      }
    }
  }
  foreach (Var child, node)
    _collect_sites(
      compiler, child, path, caller, visibility, wanted,
      parameters, prior_writes, sites
    );
}

static List _site_records(Map sites) {
  Array records = %[];
  foreach (Var (key, count), sites) {
    List call = key;
    match (call)
      case %(call ?path ?caller ?visibility (args *arguments)):
        records.push(%(
          call $path $caller $visibility ${count.int()}
          (args @arguments)
        ));
  }
  records.sort();
  return records.list_free();
}

static List _analyze_sites_unit(
  Compiler compiler, List ast, String path, String wanted) {
  Map sites = %{}, top_level_writes = %{};
  foreach (List node, ast) {
    match (node)
      case %(function ?type
             (bind (!set ?binding (binding ? ?)) ?modifiers)
             ?body): {
        Map parameters = %{}, prior_writes = %{};
        _site_collect_parameters(modifiers, parameters);
        String caller = compiler.emitted_binding_name(binding);
        Symbol visibility = ((Type) type).is_static()
                          ? <static> : <public>;
        _collect_sites(
          compiler, body, path, caller, visibility, wanted,
          parameters, prior_writes, sites
        );
        continue;
      }
    _collect_sites(
      compiler, node, path, "<top-level>", <static>, wanted,
      %{}, top_level_writes, sites
    );
  }
  return _site_records(sites);
}

static int _field_whole_target(
  Var value, String receiver_name, String field_name) {
  if (value is not <list>) return 0;
  List node = value;
  if (_field_access_matches(node, receiver_name, field_name)) return 1;
  match (node) {
    case %(expr ? ?inner):
      return _field_whole_target(inner, receiver_name, field_name);
    case %(parens ?inner):
      return _field_whole_target(inner, receiver_name, field_name);
    case %(at ? ?inner):
      return _field_whole_target(inner, receiver_name, field_name);
  }
  return 0;
}

static Var _field_site_value_type(Var value) {
  if (value is not <list>) return %();
  List node = value;
  match (node) {
    case %(expr ?type ?): return type;
    case %(parens ?inner): return _field_site_value_type(inner);
    case %(at ? ?inner): return _field_site_value_type(inner);
  }
  return %();
}

static void _collect_field_sites(
  Compiler compiler, Var value, String path, String caller, Symbol visibility,
  String receiver_name, String field_name, Map parameters, Symbol access,
  Var replacement, int origin, Map sites) {
  if (value is not <list>) return;
  List node = value;
  if (_field_access_matches(node, receiver_name, field_name)) {
    List detail;
    if (access == <replace>) {
      Var type = _field_site_value_type(replacement);
      List summary = _site_value_summary(
        compiler, replacement, parameters, %{}
      );
      detail = %(access replace (value $type $summary));
    }
    else detail = %(access $access);
    _increment(
      sites,
      %(
        site $path $caller $visibility
        ${_source_location(compiler, path, origin)}
        $detail
      ),
      1
    );
    return;
  }
  match (node) {
    case %(at ?next_origin ?inner): {
      _collect_field_sites(
        compiler, inner, path, caller, visibility,
        receiver_name, field_name, parameters, access, replacement,
        next_origin.integer(), sites
      );
      return;
    }
    case %(expr ? ?inner): {
      _collect_field_sites(
        compiler, inner, path, caller, visibility,
        receiver_name, field_name, parameters, access, replacement,
        origin, sites
      );
      return;
    }
    case %(parens ?inner): {
      _collect_field_sites(
        compiler, inner, path, caller, visibility,
        receiver_name, field_name, parameters, access, replacement,
        origin, sites
      );
      return;
    }
    case %(op = ?left ?right): {
      Symbol left_access = _field_whole_target(
        left, receiver_name, field_name
      ) ? <replace> : <mutate>;
      _collect_field_sites(
        compiler, left, path, caller, visibility,
        receiver_name, field_name, parameters, left_access, right,
        origin, sites
      );
      _collect_field_sites(
        compiler, right, path, caller, visibility,
        receiver_name, field_name, parameters, <read>, void,
        origin, sites
      );
      return;
    }
    case %(op ?operator ?left *right):
      if (operator is <symbol> &&
          ast_changes_left_operand(operator.symbol())) {
        _collect_field_sites(
          compiler, left, path, caller, visibility,
          receiver_name, field_name, parameters, <mutate>, void,
          origin, sites
        );
        foreach (Var child, right)
          _collect_field_sites(
            compiler, child, path, caller, visibility,
            receiver_name, field_name, parameters, <read>, void,
            origin, sites
          );
        return;
      }
    case %(postfix ? ?target): {
      _collect_field_sites(
        compiler, target, path, caller, visibility,
        receiver_name, field_name, parameters, <mutate>, void,
        origin, sites
      );
      return;
    }
    case %((!or vcompound vpostfix) ?target *rest): {
      _collect_field_sites(
        compiler, target, path, caller, visibility,
        receiver_name, field_name, parameters, <mutate>, void,
        origin, sites
      );
      foreach (Var child, rest)
        _collect_field_sites(
          compiler, child, path, caller, visibility,
          receiver_name, field_name, parameters, <read>, void,
          origin, sites
        );
      return;
    }
    case %((!or index getindex) ?target ?selector): {
      _collect_field_sites(
        compiler, target, path, caller, visibility,
        receiver_name, field_name, parameters,
        access == <read> ? <read> : <mutate>, void, origin, sites
      );
      _collect_field_sites(
        compiler, selector, path, caller, visibility,
        receiver_name, field_name, parameters, <read>, void,
        origin, sites
      );
      return;
    }
    case %(function *): return;
  }
  foreach (Var child, node)
    _collect_field_sites(
      compiler, child, path, caller, visibility,
      receiver_name, field_name, parameters, access, replacement,
      origin, sites
    );
}

static List _field_site_records(Map sites) {
  Array records = %[];
  foreach (Var (key, count), sites) {
    List site = key;
    match (site)
      case %(site ?path ?caller ?visibility ?location ?access):
        records.push(%(
          site $path $caller $visibility $location $access
          (count ${count.int()})
        ));
  }
  records.sort();
  return records.list_free();
}

static List _analyze_field_sites_unit(
  Compiler compiler, List ast, String path, String receiver_name,
  String field_name) {
  Map sites = %{};
  foreach (List node, ast) {
    match (node)
      case %(function ?type
             (bind (!set ?binding (binding ? ?)) ?modifiers)
             ?body): {
        Map parameters = %{};
        _site_collect_parameters(modifiers, parameters);
        _collect_field_sites(
          compiler, body, path, compiler.emitted_binding_name(binding),
          ((Type) type).is_static() ? <static> : <public>,
          receiver_name, field_name, parameters, <read>, void, 0, sites
        );
        continue;
      }
    _collect_field_sites(
      compiler, node, path, "<top-level>", <static>,
      receiver_name, field_name, %{}, <read>, void, 0, sites
    );
  }
  return _field_site_records(sites);
}

static List _field_functions_from_sites(List sites) {
  Map reads = %{}, lvalues = %{};
  foreach (List site, sites)
    match (site)
      case %(site ? ?caller ?visibility ? ?access (count ?count)):
        if (caller != "<top-level>") {
          List key = %(function $caller $visibility);
          match (access) {
            case %(access read): _increment(reads, key, count.integer());
            case %(access *): _increment(lvalues, key, count.integer());
          }
        }
  Map functions = %{};
  foreach (Var (key, count), reads) functions[key] = count;
  foreach (Var (key, count), lvalues)
    if (!functions.contains(key)) functions[key] = 0;
  Array records = %[];
  foreach (Var (key_value, read_count), functions) {
    List key = key_value;
    match (key)
      case %(function ?caller ?visibility): {
        int reads_count = read_count.int();
        int lvalue_count = lvalues.contains(key)
                         ? lvalues[key].int() : 0;
        records.push(%(
          function $caller $visibility
          (reads $reads_count) (lvalues $lvalue_count)
        ));
      }
  }
  records.sort();
  return records.list_free();
}

static String _canonical_input(String input) {
  char path[PATH_MAX];
  return realpath(input, path) ? String.new(path) : input;
}

static String _display_input(String input) {
  String path = _canonical_input(input);
  char root_path[PATH_MAX];
  String root = realpath(x2c_get_root(), root_path)
              ? String.new(root_path) : x2c_get_root();
  int length = strlen(root);
  return path.startswith(root) && path[length] == '/'
       ? String.new(path + length + 1) : path;
}

static List _parse_units(Frontend frontend, Array inputs, Map subtrees) {
  Array units = %[];
  foreach (String input, inputs) {
    ParsedUnit parsed;
    if (!frontend.open(input, &parsed)) return NULL;
    String path = parsed.compiler.display_path(input);
    List functions = _analyze_unit(parsed.compiler, parsed.ast);
    Symbol subtree = subtrees ? subtrees[input].symbol() : <none>;
    List record = %(
      unit $path $subtree ${parsed.source_lines}
      (functions @functions)
    );
    record = parsed.context.export(record).list();
    parsed.close(frontend);
    units.push(record);
  }
  units.sort();
  return units.list_free();
}

static List _parse_field_units(
  Frontend frontend, Array inputs, String receiver_name, String field_name) {
  Array units = %[];
  foreach (String input, inputs) {
    ParsedUnit parsed;
    if (!frontend.open(input, &parsed)) return NULL;
    String path = parsed.compiler.display_path(input);
    List sites = _analyze_field_sites_unit(
      parsed.compiler, parsed.ast, path, receiver_name, field_name
    );
    List functions = _field_functions_from_sites(sites);
    if (functions) {
      List record = %(unit $path (functions @functions));
      record = parsed.context.export(record).list();
      units.push(record);
    }
    parsed.close(frontend);
  }
  units.sort();
  return %(
    field $receiver_name $field_name (units @{units.list_free()})
  );
}

static List _parse_field_sites(
  Frontend frontend, Array inputs, String receiver_name, String field_name) {
  Array sites = %[];
  foreach (String input, inputs) {
    ParsedUnit parsed;
    if (!frontend.open(input, &parsed)) return NULL;
    String path = parsed.compiler.display_path(input);
    List records = _analyze_field_sites_unit(
      parsed.compiler, parsed.ast, path, receiver_name, field_name
    );
    records = parsed.context.export(records).list();
    parsed.close(frontend);
    foreach (List record, records) sites.push(record);
  }
  sites.sort();
  return %(
    field-sites $receiver_name $field_name
    (sites @{sites.list_free()})
  );
}

static List _parse_sites(Frontend frontend, Array inputs, String wanted) {
  Array sites = %[];
  foreach (String input, inputs) {
    ParsedUnit parsed;
    if (!frontend.open(input, &parsed)) return NULL;
    String path = parsed.compiler.display_path(input);
    List records = _analyze_sites_unit(
      parsed.compiler, parsed.ast, path, wanted
    );
    records = parsed.context.export(records).list();
    parsed.close(frontend);
    foreach (List record, records) sites.push(record);
  }
  sites.sort();
  return %(sites $wanted (calls @{sites.list_free()}));
}

static List _parse_walk_units(Frontend frontend, Array inputs) {
  Array functions = %[];
  foreach (String input, inputs) {
    ParsedUnit parsed;
    if (!frontend.open(input, &parsed)) return NULL;
    String path = parsed.compiler.display_path(input);
    List records = _analyze_walk_unit(
      parsed.compiler, parsed.ast, path
    );
    records = parsed.context.export(records).list();
    parsed.close(frontend);
    foreach (List record, records) functions.push(record);
  }
  functions.sort();
  return _walk_candidates(functions.list_free());
}

static List _parse_flow_units(
  Frontend frontend, Array inputs, String producer, String consumer) {
  Array functions = %[];
  foreach (String input, inputs) {
    ParsedUnit parsed;
    if (!frontend.open(input, &parsed)) return NULL;
    String path = parsed.compiler.display_path(input);
    List records = Flow_analyze_unit(
      parsed.compiler, parsed.ast, path
    );
    records = parsed.context.export(records).list();
    parsed.close(frontend);
    foreach (List record, records) functions.push(record);
  }
  functions.sort();
  return Flow_finish(functions.list_free(), producer, consumer);
}

static List _parse_tail_units(Frontend frontend, Array inputs) {
  Array units = %[];
  foreach (String input, inputs) {
    ParsedUnit parsed;
    if (!frontend.open(input, &parsed)) return NULL;
    String path = parsed.compiler.display_path(input);
    List functions = _analyze_tail_unit(
      parsed.compiler, parsed.ast, path
    );
    if (functions) {
      List record = %(unit $path (functions @functions));
      record = parsed.context.export(record).list();
      units.push(record);
    }
    parsed.close(frontend);
  }
  units.sort();
  return %(tail-calls (units @{units.list_free()}));
}

static List _parse_loop_allocation_units(
  Frontend frontend, Array inputs, int limit) {
  Array units = %[];
  foreach (String input, inputs) {
    ParsedUnit parsed;
    if (!frontend.open(input, &parsed)) return NULL;
    String path = parsed.compiler.display_path(input);
    List record = LoopAllocations.analyze_unit(
      parsed.compiler, parsed.ast, path
    );
    record = parsed.context.export(record).list();
    parsed.close(frontend);
    units.push(record);
  }
  units.sort();
  return LoopAllocations.finish(units.list_free(), limit);
}

static List _parse_lifetime_units(
  Frontend frontend, Array inputs, String allocation_returns) {
  Array units = %[];
  foreach (String input, inputs) {
    ParsedUnit parsed;
    if (!frontend.open(input, &parsed)) return NULL;
    String path = parsed.compiler.display_path(input);
    Map definitions = project_function_targets(
      parsed.compiler, parsed.ast, path
    );
    List record = Lifetime.analyze_unit(
      parsed.compiler, parsed.ast, path, definitions
    );
    record = parsed.context.export(record).list();
    parsed.close(frontend);
    units.push(record);
  }
  units.sort();
  List records = units.list_free();
  return allocation_returns
       ? Lifetime.allocation_returns(records, allocation_returns)
       : Lifetime.finish(records);
}

static void _index_public_functions(List units, Map public_functions) {
  foreach (List unit, units) {
    match (unit)
      case %(unit ?path ? ? (functions *functions)):
        foreach (List function, functions)
          match (function)
            case %(function ? ?name public ? (calls *)): {
              List targets = public_functions.contains(name)
                           ? public_functions[name].list() : NULL;
              public_functions[name] = cons(%(target $path $name), targets);
            }
  }
}

static void _resolve_call(
  List raw, String path, Map local, Map publics, Map resolved) {
  match (raw) {
    case %(call indirect ?name ?count):
      _increment(resolved, %(indirect $name), count);
    case %(call direct ?identity ?name ?count): {
      Var target;
      if (local.try_get(identity, &target)) {
        List destination = target;
        match (destination)
          case %(target ?target_path ?target_name):
            _increment(
              resolved, %(direct $target_path $target_name), count
            );
        return;
      }
      List candidates = publics.contains(name) ? publics[name].list() : NULL;
      if (candidates && !candidates.cdr()) {
        List destination = candidates.car();
        match (destination)
          case %(target ?target_path ?target_name):
            _increment(
              resolved, %(direct $target_path $target_name), count
            );
      }
      else _increment(resolved, %(external $name), count);
    }
  }
}

static List _resolved_calls(Map calls) {
  Array rows = %[];
  foreach (Var (key, count), calls) {
    List call = key;
    match (call) {
      case %(direct ?path ?name):
        rows.push(%(call direct $path $name ${count.int()}));
      case %(external ?name):
        rows.push(%(call external $name ${count.int()}));
      case %(indirect ?name):
        rows.push(%(call indirect $name ${count.int()}));
    }
  }
  rows.sort();
  return rows.list_free();
}

static void _resolved_unresolved_counts(
  Map resolved, int *external_calls, int *indirect_calls) {
  *external_calls = *indirect_calls = 0;
  foreach (Var (key, count), resolved) {
    List call = key;
    match (call) {
      case %(external ?): *external_calls += count.int();
      case %(indirect ?): *indirect_calls += count.int();
    }
  }
}

static List _resolve_graph(List units, Map attributes) {
  Map publics = %{};
  _index_public_functions(units, publics);
  Array output_units = %[];
  foreach (List unit, units) {
    match (unit)
      case %(unit ?path ?subtree ?source_lines (functions *functions)): {
        Map local = %{};
        foreach (List function, functions)
          match (function)
            case %(function ?identity ?name ? ? (calls *)):
              local[identity] = %(target $path $name);
        Array output_functions = %[];
        foreach (List function, functions)
          match (function)
            case %(
              function ? ?name ?visibility
              (source ?source_name ?source_order)
              (calls *calls)
            ): {
              Map resolved = %{};
              foreach (List call, calls)
                _resolve_call(call, path, local, publics, resolved);
              if ((void *) attributes != NULL) {
                int external_calls, indirect_calls;
                _resolved_unresolved_counts(
                  resolved, &external_calls, &indirect_calls
                );
                attributes[%(target $path $name)] = %(
                  node $subtree $source_lines $source_order $source_name
                  $external_calls $indirect_calls
                );
              }
              output_functions.push(%(
                function $name $visibility
                (calls @{_resolved_calls(resolved)})
              ));
            }
        output_functions.sort();
        output_units.push(%(
          unit $path (functions @{output_functions.list_free()})
        ));
      }
  }
  output_units.sort();
  return %(graph @{output_units.list_free()});
}

static int _reachable(String from, String target, Map adjacency, Map seen) {
  if (from == target) return 1;
  if (seen.contains(from)) return 0;
  seen[from] = 1;
  List next = adjacency.contains(from) ? adjacency[from].list() : NULL;
  foreach (String path, next)
    if (_reachable(path, target, adjacency, seen)) return 1;
  return 0;
}

static List _dependency_cycles(Array paths, Map adjacency) {
  Map assigned = %{};
  Array cycles = %[];
  foreach (String path, paths) {
    if (assigned.contains(path)) continue;
    Array component = %[];
    foreach (String candidate, paths) {
      if (assigned.contains(candidate)) continue;
      if (_reachable(path, candidate, adjacency, %{}) &&
          _reachable(candidate, path, adjacency, %{}))
        component.push(candidate);
    }
    if (component.len() > 1) {
      component.sort();
      List members = component.list_free();
      foreach (String member, members) assigned[member] = 1;
      cycles.push(%(cycle @members));
    }
  }
  cycles.sort();
  return cycles.list_free();
}

static List _digest(List graph) {
  Array units = %[], paths = %[];
  Map adjacency = %{};
  int function_count = 0, direct_count = 0;
  int external_count = 0, indirect_count = 0;
  match (graph)
    case %(graph *graph_units):
      foreach (List unit, graph_units)
        match (unit)
          case %(unit ?path (functions *functions)): {
            paths.push(path);
            int public_count = 0, static_count = 0, internal_count = 0;
            int unit_external = 0, unit_indirect = 0;
            Map dependencies = %{};
            foreach (List function, functions) {
              function_count++;
              match (function) {
                case %(function ? public (calls *calls)): public_count++;
                case %(function ? static (calls *calls)): static_count++;
              }
              match (function)
                case %(function ? ? (calls *calls)):
                  foreach (List call, calls)
                    match (call) {
                      case %(call direct ?target ? ?count): {
                        direct_count += count;
                        if (target == path) internal_count += count;
                        else _increment(
                          dependencies, %(unit $target), count
                        );
                      }
                      case %(call external ? ?count):
                        external_count += count, unit_external += count;
                      case %(call indirect ? ?count):
                        indirect_count += count, unit_indirect += count;
                    }
            }
            Array dependency_rows = %[];
            List adjacent = NULL;
            foreach (Var (key, count), dependencies) {
              match ((List) key)
                case %(unit ?target): {
                  dependency_rows.push(%(unit $target ${count.int()}));
                  adjacent = cons(target, adjacent);
                }
            }
            dependency_rows.sort();
            adjacency[path] = adjacent;
            units.push(%(
              unit $path
              (functions (public $public_count) (static $static_count))
              (internal $internal_count)
              (dependencies @{dependency_rows.list_free()})
              (external $unit_external)
              (indirect $unit_indirect)
            ));
          }
  units.sort();
  paths.sort();
  int unit_count = units.len();
  return %(
    digest
    (totals (units $unit_count) (functions $function_count)
            (direct $direct_count) (external $external_count)
            (indirect $indirect_count))
    (units @{units.list_free()})
    (cycles @{_dependency_cycles(paths, adjacency)})
  );
}

enum {
  ARCHITECTURE_LIMIT = 25,
  ARCHITECTURE_UNIT_FUNCTIONS = 20,
  ARCHITECTURE_COMPONENT_FUNCTIONS = 2,
  ARCHITECTURE_RECIPROCAL_CALLS = 2,
  ARCHITECTURE_BOUNDARY_FUNCTIONS = 2,
  ARCHITECTURE_BRIDGE_SECOND_GROUP = 2
};

static List _ranked_records(Array ranked, int limit) {
  ranked.sort();
  Array records = %[];
  foreach (List row, ranked) {
    if ((int) records.len() == limit) break;
    match (row)
      case %(rank ? ?record): records.push(record);
  }
  return records.list_free();
}

static void _architecture_call_counts(
  List graph, Map definitions, Map cross_units, Map units, Map functions,
  Map calls) {
  match (graph)
    case %(graph *graph_units): {
      foreach (List unit, graph_units)
        match (unit)
          case %(unit ?path (functions *members)):
            foreach (List function, members)
              match (function)
                case %(function ?name ?visibility (calls *)):
                  definitions[%($path $name)] = visibility;
      Map seen_cross_units = %{}, seen_units = %{}, seen_functions = %{};
      foreach (List unit, graph_units)
        match (unit)
          case %(unit ?path (functions *members)):
            foreach (List function, members)
              match (function)
                case %(function ?name ? (calls *outgoing)):
                  foreach (List call, outgoing)
                    match (call)
                      case %(call direct ?target ?callee ?count): {
                        List key = %($target $callee);
                        if (!definitions.contains(key)) continue;
                        _increment(calls, key, count);
                        List unit_key = %($target $callee $path);
                        if (!seen_units.contains(unit_key)) {
                          seen_units[unit_key] = 1;
                          _increment(units, key, 1);
                        }
                        if (target != path &&
                            !seen_cross_units.contains(unit_key)) {
                          seen_cross_units[unit_key] = 1;
                          _increment(cross_units, key, 1);
                        }
                        List function_key = %(
                          $target $callee $path $name
                        );
                        if (!seen_functions.contains(function_key)) {
                          seen_functions[function_key] = 1;
                          _increment(functions, key, 1);
                        }
                      }
    }
}

static List _architecture_choke_points(List graph) {
  Map definitions = %{}, cross_units = %{}, units = %{};
  Map functions = %{}, calls = %{};
  _architecture_call_counts(
    graph, definitions, cross_units, units, functions, calls
  );
  Array ranked = %[];
  foreach (Var (raw_key, raw_visibility), definitions) {
    List key = raw_key;
    Var value;
    int cross = cross_units.try_get(key, &value) ? value.int() : 0;
    if (!cross) continue;
    int unit_count = units.try_get(key, &value) ? value.int() : 0;
    int function_count = functions.try_get(key, &value) ? value.int() : 0;
    int call_count = calls.try_get(key, &value) ? value.int() : 0;
    (String path, String name) = key;
    Symbol visibility = raw_visibility;
    List record = %(
      function $path $name $visibility
      (callers (cross-units $cross) (units $unit_count)
               (functions $function_count))
      (calls $call_count)
    );
    int rank_cross = -cross, rank_functions = -function_count;
    int rank_calls = -call_count;
    ranked.push(%(
      rank ($rank_cross $rank_functions $rank_calls $path $name)
      $record
    ));
  }
  return _ranked_records(ranked, ARCHITECTURE_LIMIT);
}

static Map _unit_edges(List graph) {
  Map edges = %{};
  match (graph)
    case %(graph *units):
      foreach (List unit, units)
        match (unit)
          case %(unit ?path (functions *functions)):
            foreach (List function, functions)
              match (function)
                case %(function ? ? (calls *calls)):
                  foreach (List call, calls)
                    match (call)
                      case %(call direct ?target ? ?count):
                        if (target != path)
                          _increment(edges, %($path $target), count);
  return edges;
}

static List _architecture_reciprocal(List graph) {
  Map edges = _unit_edges(graph);
  Array ranked = %[];
  foreach (Var (raw_key, raw_count), edges) {
    List key = raw_key;
    (String left, String right) = key;
    if (strcmp(left, right) >= 0) continue;
    Var reverse_value;
    if (!edges.try_get(%($right $left), &reverse_value)) continue;
    int forward = raw_count.int(), reverse = reverse_value.int();
    if (forward < ARCHITECTURE_RECIPROCAL_CALLS ||
        reverse < ARCHITECTURE_RECIPROCAL_CALLS)
      continue;
    int lesser = forward < reverse ? forward : reverse;
    int total = forward + reverse;
    List record = %(
      units $left $right
      (calls ($left $right $forward) ($right $left $reverse))
    );
    int rank_lesser = -lesser, rank_total = -total;
    ranked.push(%(
      rank ($rank_lesser $rank_total $left $right) $record
    ));
  }
  return _ranked_records(ranked, ARCHITECTURE_LIMIT);
}

static int _architecture_count(Map counts, List key) {
  Var value;
  return counts.try_get(key, &value) ? value.int() : 0;
}

static void _record_boundary_function(
  Map seen, Map counts, List direction, String name) {
  List key = %(@direction $name);
  if (seen.contains(key)) return;
  seen[key] = 1;
  _increment(counts, direction, 1);
}

static void _record_boundary_participant(
  Map seen, Map counts, String left, String right, String path, String name) {
  List key = %($left $right $path $name);
  if (seen.contains(key)) return;
  seen[key] = 1;
  _increment(counts, %($left $right $path), 1);
}

static List _boundary_direction(
  String from, String to, Map callers, Map callees, Map edges, Map calls) {
  List direction = %($from $to);
  return %(
    direction $from $to
    (functions
      (callers ${_architecture_count(callers, direction)})
      (callees ${_architecture_count(callees, direction)}))
    (edges ${_architecture_count(edges, direction)})
    (calls ${_architecture_count(calls, direction)})
  );
}

static List _architecture_dependency_width(List graph) {
  Map pairs = %{}, participants = %{}, edges = %{}, calls = %{};
  Map callers = %{}, callees = %{}, seen_participants = %{};
  Map seen_callers = %{}, seen_callees = %{};
  match (graph)
    case %(graph *units):
      foreach (List unit, units)
        match (unit)
          case %(unit ?path (functions *functions)):
            foreach (List function, functions)
              match (function)
                case %(function ?caller ? (calls *outgoing)):
                  foreach (List call, outgoing)
                    match (call)
                      case %(call direct ?target ?callee ?count):
                        if (target != path) {
                          String source_path = path, target_path = target;
                          String caller_name = caller, callee_name = callee;
                          String left = strcmp(source_path, target_path) < 0
                                      ? source_path : target_path;
                          String right = left == source_path
                                       ? target_path : source_path;
                          List pair = %($left $right);
                          List direction = %($source_path $target_path);
                          pairs[pair] = 1;
                          _increment(edges, direction, 1);
                          _increment(calls, direction, count);
                          _record_boundary_function(
                            seen_callers, callers, direction, caller_name
                          );
                          _record_boundary_function(
                            seen_callees, callees, direction, callee_name
                          );
                          _record_boundary_participant(
                            seen_participants, participants,
                            left, right, source_path, caller_name
                          );
                          _record_boundary_participant(
                            seen_participants, participants,
                            left, right, target_path, callee_name
                          );
                        }
  Array ranked = %[];
  foreach (Var (raw_pair, raw_value), pairs) {
    (void) raw_value;
    List pair = raw_pair;
    (String left, String right) = pair;
    int left_width = _architecture_count(
      participants, %($left $right $left)
    );
    int right_width = _architecture_count(
      participants, %($left $right $right)
    );
    int lesser = left_width < right_width ? left_width : right_width;
    if (lesser < ARCHITECTURE_BOUNDARY_FUNCTIONS) continue;
    int total_width = left_width + right_width;
    int edge_count = _architecture_count(edges, %($left $right)) +
                     _architecture_count(edges, %($right $left));
    int call_count = _architecture_count(calls, %($left $right)) +
                     _architecture_count(calls, %($right $left));
    List forward = _boundary_direction(
      left, right, callers, callees, edges, calls
    );
    List reverse = _boundary_direction(
      right, left, callers, callees, edges, calls
    );
    List record = %(
      units $left $right
      (functions ($left $left_width) ($right $right_width))
      (directions $forward $reverse)
    );
    int rank_lesser = -lesser, rank_width = -total_width;
    int rank_edges = -edge_count, rank_calls = -call_count;
    ranked.push(%(
      rank
      ($rank_lesser $rank_width $rank_edges $rank_calls $left $right)
      $record
    ));
  }
  return _ranked_records(ranked, ARCHITECTURE_LIMIT);
}

static void _add_neighbor(Map adjacency, String from, String to) {
  List neighbors = adjacency.contains(from)
                 ? adjacency[from].list() : NULL;
  if (!neighbors.contains(to)) adjacency[from] = cons(to, neighbors);
}

static List _unit_function_names(List functions) {
  Array names = %[];
  foreach (List function, functions)
    match (function)
      case %(function ?name ? (calls *)): names.push(name);
  names.sort();
  return names.list_free();
}

static Map _unit_adjacency(String path, List functions) {
  Map adjacency = %{};
  foreach (List function, functions)
    match (function)
      case %(function ?name ? (calls *calls)):
        foreach (List call, calls)
          match (call)
            case %(call direct ?target ?callee ?):
              if (target == path && callee != name) {
                _add_neighbor(adjacency, name, callee);
                _add_neighbor(adjacency, callee, name);
              }
  return adjacency;
}

static void _collect_component(
  String name, String excluded, Map allowed, Map adjacency, Map seen,
  Array members) {
  if (name == excluded || seen.contains(name) ||
      !allowed.contains(name))
    return;
  seen[name] = 1;
  members.push(name);
  List neighbors = adjacency.contains(name)
                 ? adjacency[name].list() : NULL;
  foreach (String neighbor, neighbors)
    _collect_component(
      neighbor, excluded, allowed, adjacency, seen, members
    );
}

static List _components(List names, Map adjacency, String excluded) {
  Map allowed = %{}, seen = %{};
  foreach (String name, names) allowed[name] = 1;
  Array ranked = %[];
  foreach (String name, names) {
    if (name == excluded || seen.contains(name)) continue;
    Array members = %[];
    _collect_component(
      name, excluded, allowed, adjacency, seen, members
    );
    members.sort();
    int size = members.len();
    int rank_size = -size;
    List group = %(group @{members.list_free()});
    ranked.push(%(rank ($rank_size $name) $group));
  }
  return _ranked_records(ranked, INT_MAX);
}

static List _component_sizes(List groups) {
  Array sizes = %[];
  foreach (List group, groups)
    match (group)
      case %(group *members): sizes.push(members.len());
  return sizes.list_free();
}

static List _nontrivial_components(List groups, Array isolated) {
  Array components = %[];
  foreach (List group, groups)
    match (group)
      case %(group *members): {
        if ((int) members.len() >= ARCHITECTURE_COMPONENT_FUNCTIONS)
          components.push(group);
        else isolated.push(members.car());
      }
  return components.list_free();
}

static List _bridge_groups(String name, List components, Map adjacency) {
  foreach (List component, components)
    match (component)
      case %(group *members):
        if (members.contains(name))
          return _components(members, adjacency, name);
  return NULL;
}

static void _collect_unit_bridges(
  String path, List names, Map adjacency, List components, int detailed,
  Array ranked) {
  foreach (String name, names) {
    List groups = _bridge_groups(name, components, adjacency);
    if (!groups || !groups.cdr()) continue;
    List sizes = _component_sizes(groups);
    int second = sizes.cadr().int();
    if (second < ARCHITECTURE_BRIDGE_SECOND_GROUP) continue;
    int outside = 0;
    foreach (Var size, sizes.cdr()) outside += size.int();
    List record = detailed
                ? %(function $name (groups @groups))
                : %(function $path $name (groups @sizes));
    int rank_second = -second, rank_outside = -outside;
    ranked.push(%(
      rank ($rank_second $rank_outside $path $name) $record
    ));
  }
}

static List _architecture_local_components(List graph) {
  Array rows = %[];
  match (graph)
    case %(graph *units):
      foreach (List unit, units)
        match (unit)
          case %(unit ?path (functions *functions)): {
            int function_count = functions.len();
            if (function_count < ARCHITECTURE_UNIT_FUNCTIONS) continue;
            List names = _unit_function_names(functions);
            Map adjacency = _unit_adjacency(path, functions);
            List groups = _components(names, adjacency, NULL);
            Array isolated = %[];
            List components = _nontrivial_components(groups, isolated);
            if ((int) components.len() < 2) continue;
            int isolated_count = isolated.len();
            rows.push(%(
              unit $path (functions $function_count)
              (isolated $isolated_count)
              (components @{_component_sizes(components)})
            ));
          }
  rows.sort();
  return rows.list_free();
}

static List _architecture_bridges(List graph) {
  Array ranked = %[];
  match (graph)
    case %(graph *units):
      foreach (List unit, units)
        match (unit)
          case %(unit ?path (functions *functions)): {
            List names = _unit_function_names(functions);
            Map adjacency = _unit_adjacency(path, functions);
            List components = _components(names, adjacency, NULL);
            _collect_unit_bridges(
              path, names, adjacency, components, 0, ranked
            );
          }
  return _ranked_records(ranked, ARCHITECTURE_LIMIT);
}

static List _architecture(List graph) {
  return %(
    architecture
    (limit $ARCHITECTURE_LIMIT)
    (thresholds
      (unit-functions $ARCHITECTURE_UNIT_FUNCTIONS)
      (component-functions $ARCHITECTURE_COMPONENT_FUNCTIONS)
      (reciprocal-calls $ARCHITECTURE_RECIPROCAL_CALLS)
      (boundary-functions $ARCHITECTURE_BOUNDARY_FUNCTIONS)
      (bridge-second-group $ARCHITECTURE_BRIDGE_SECOND_GROUP))
    (choke-points @{_architecture_choke_points(graph)})
    (reciprocal @{_architecture_reciprocal(graph)})
    (dependency-width @{_architecture_dependency_width(graph)})
    (local-components @{_architecture_local_components(graph)})
    (bridges @{_architecture_bridges(graph)})
  );
}

static int _unit_internal_calls(String path, List functions) {
  int count = 0;
  foreach (List function, functions)
    match (function)
      case %(function ? ? (calls *calls)):
        foreach (List call, calls)
          match (call)
            case %(call direct ?target ? ?amount):
              if (target == path) count += amount;
  return count;
}

static List _structure(List graph, String wanted) {
  Array matches = %[];
  match (graph)
    case %(graph *units):
      foreach (List unit, units)
        match (unit)
          case %(unit ?path (functions *functions)):
            if (path == wanted) {
              List names = _unit_function_names(functions);
              Map adjacency = _unit_adjacency(path, functions);
              List groups = _components(names, adjacency, NULL);
              Array isolated = %[];
              List components = _nontrivial_components(groups, isolated);
              Array bridge_rows = %[];
              _collect_unit_bridges(
                path, names, adjacency, groups, 1, bridge_rows
              );
              isolated.sort();
              int function_count = functions.len();
              matches.push(%(
                unit $path (functions $function_count)
                (internal ${_unit_internal_calls(path, functions)})
                (isolated @{isolated.list_free()})
                (components @components)
                (bridges @{
                  _ranked_records(bridge_rows, INT_MAX)
                })
              ));
            }
  return %(structure $wanted (matches @{matches.list_free()}));
}

static List _between_direction(List graph, String from, String to) {
  Array edges = %[];
  int total = 0;
  match (graph)
    case %(graph *units):
      foreach (List unit, units)
        match (unit)
          case %(unit ?path (functions *functions)):
            if (path == from)
              foreach (List function, functions)
                match (function)
                  case %(function ?caller ?visibility (calls *calls)):
                    foreach (List call, calls)
                      match (call)
                        case %(call direct ?target ?callee ?count):
                          if (target == to) {
                            edges.push(%(
                              call $caller $visibility $callee $count
                            ));
                            total += count;
                          }
  edges.sort();
  return %(
    direction $from $to (count $total)
    (calls @{edges.list_free()})
  );
}

static List _between(List graph, String left, String right) {
  return %(
    between $left $right
    (directions
      ${_between_direction(graph, left, right)}
      ${_between_direction(graph, right, left)})
  );
}

static List _callers(List graph, String target_path, String target_name) {
  Array rows = %[];
  match (graph)
    case %(graph *units):
      foreach (List unit, units)
        match (unit)
          case %(unit ?path (functions *functions)):
            foreach (List function, functions)
              match (function)
                case %(function ?name ?visibility (calls *calls)):
                  foreach (List call, calls)
                    match (call)
                      case %(call direct ?destination ?callee ?count):
                        if (destination == target_path &&
                            callee == target_name)
                          rows.push(%(
                            function $path $name $visibility $count
                          ));
  rows.sort();
  return rows.list_free();
}

static List _focus(List graph, String wanted) {
  Array matches = %[];
  match (graph)
    case %(graph *units):
      foreach (List unit, units)
        match (unit)
          case %(unit ?path (functions *functions)):
            foreach (List function, functions)
              match (function)
                case %(function ?name ?visibility (calls *calls)):
                  if (name == wanted)
                    matches.push(%(
                      function $path $name $visibility
                      (callers @{_callers(graph, path, name)})
                      (calls @calls)
                    ));
  matches.sort();
  return %(focus $wanted (matches @{matches.list_free()}));
}

static void _compare_indexes(List graph, Map by_target, Map by_name) {
  match (graph)
    case %(graph *units):
      foreach (List unit, units)
        match (unit)
          case %(unit ?path (functions *functions)):
            foreach (List function, functions)
              match (function)
                case %(function ?name ?visibility (calls *calls)): {
                  List target = %(target $path $name);
                  by_target[target] = %(
                    function $path $name $visibility (calls @calls)
                  );
                  List targets = by_name.contains(name)
                               ? by_name[name].list() : NULL;
                  by_name[name] = cons(target, targets);
                }
}

static List _compare_exact_target(Map by_name, String name) {
  if (!by_name.contains(name)) return NULL;
  List targets = by_name[name];
  return targets && !targets.cdr() ? targets.car().list() : NULL;
}

static List _compare_definition(Map by_target, Map by_name, String name) {
  List target = _compare_exact_target(by_name, name);
  if (target) {
    List function = by_target[target];
    match (function)
      case %(function ?path ?function_name ?visibility (calls *)):
        return %(function $path $function_name $visibility);
  }
  return %(
    unproved ${by_name.contains(name) ? %"ambiguous" : %"missing"}
  );
}

static List _compare_present_path(List targets, Map by_target) {
  Array rows = %[];
  foreach (List target, targets) {
    List function = by_target[target];
    match (function)
      case %(function ?path ?name ?visibility (calls *)):
        rows.push(%(function $path $name $visibility));
  }
  return %(path @{rows.list_free()});
}

static List _compare_shortest(List start, List destination, Map by_target) {
  if (!start) return %(unproved "entry-unresolved");
  if (!destination) return %(unproved "target-unresolved");
  Array queue = %[];
  Map seen = %{}, predecessor = %{};
  queue.push(start);
  seen[start] = 1;
  for (int index = 0; index < queue.len(); index++) {
    List current = queue[index];
    if (List.equal(current, destination)) {
      List path = NULL;
      while (current) {
        path = cons(current, path);
        if (List.equal(current, start)) break;
        current = predecessor[current];
      }
      return _compare_present_path(path, by_target);
    }
    if (!by_target.contains(current)) continue;
    List function = by_target[current];
    match (function)
      case %(function ? ? ? (calls *calls)):
        foreach (List call, calls)
          match (call)
            case %(call direct ?path ?name ?): {
              List next = %(target $path $name);
              if (!by_target.contains(next) || seen.contains(next))
                continue;
              seen[next] = 1;
              predecessor[next] = current;
              queue.push(next);
            }
  }
  return %(unproved "unreachable");
}

static int _compare_proved(List result) {
  return result && result.car() == <path>;
}

static List _compare_result(
  List graph, String left_name, String right_name, List operations) {
  Map by_target = %{}, by_name = %{};
  _compare_indexes(graph, by_target, by_name);
  List left = _compare_exact_target(by_name, left_name);
  List right = _compare_exact_target(by_name, right_name);
  Array rows = %[];
  foreach (String operation, operations) {
    List destination = _compare_exact_target(by_name, operation);
    List left_path = _compare_shortest(left, destination, by_target);
    List right_path = _compare_shortest(right, destination, by_target);
    int left_proved = _compare_proved(left_path);
    int right_proved = _compare_proved(right_path);
    Symbol status = left_proved && right_proved ? <both>
                  : left_proved ? <left-only>
                  : right_proved ? <right-only> : <neither>;
    rows.push(%(
      operation $operation $status
      (target ${_compare_definition(by_target, by_name, operation)})
      (left $left_path) (right $right_path)
    ));
  }
  rows.sort();
  return %(
    compare $left_name $right_name
    (entries
      (left ${_compare_definition(by_target, by_name, left_name)})
      (right ${_compare_definition(by_target, by_name, right_name)}))
    (operations @{rows.list_free()})
  );
}

static String _dataset_function_id(String path, String name) {
  return %"$path::$name";
}

static void _dataset_mkdirs(String path) {
  char buffer[PATH_MAX];
  if (!path || !path[0] || strlen(path) >= sizeof(buffer))
    raise %(io-fail (operation mkdir) (path $path));
  strcpy(buffer, path);
  for (char *ch = buffer + 1; *ch; ch++) {
    if (*ch != '/') continue;
    *ch = 0;
    if (mkdir(buffer, 0777) && errno != EEXIST) {
      int error = errno;
      raise %(io-fail (operation mkdir) (path $path) (errno $error));
    }
    *ch = '/';
  }
  if (mkdir(buffer, 0777) && errno != EEXIST) {
    int error = errno;
    raise %(io-fail (operation mkdir) (path $path) (errno $error));
  }
}

static void _dataset_write_rows(
  String path, String header, Array rows) {
  File output = path.open("w");
  defer output.close();
  output.printf("%s\n", header);
  foreach (String row, rows) output.printf("%s\n", row);
}

static void _dataset_rows(
  List graph, Map attributes, Array functions, Array src_calls,
  Array lib_calls) {
  match (graph)
    case %(graph *units):
      foreach (List unit, units)
        match (unit)
          case %(unit ?path (functions *unit_functions)):
            foreach (List function, unit_functions)
              match (function)
                case %(
                  function ?name ?visibility (calls *calls)
                ): {
                  List target = %(target $path $name);
                  List node = attributes[target].list();
                  match (node)
                    case %(
                      node ?subtree ?unit_lines ?source_order ?source_name
                      ?external_calls ?indirect_calls
                    ): {
                      String function_id = _dataset_function_id(path, name);
                      String kind = name == %"<top-level>"
                                  ? %"top-level" : %"function";
                      functions.push(
                        %"%s\t%s\t%s\t%s\t%d\t%d\t%s\t%s\t%s\t%d\t%d".printf(
                          function_id, kind, subtree.symbol().str(), path,
                          unit_lines.int(), source_order.int(), source_name,
                          name, visibility.str(), external_calls.int(),
                          indirect_calls.int()
                        )
                      );
                      foreach (List call, calls)
                        match (call)
                          case %(
                            call direct ?callee_path ?callee_name ?count
                          ): {
                            List callee_target = %(
                              target $callee_path $callee_name
                            );
                            List callee_node =
                              attributes[callee_target].list();
                            String callee_id = _dataset_function_id(
                              callee_path, callee_name
                            );
                            String row = %"%s\t%s\t%d".printf(
                              function_id, callee_id, count.int()
                            );
                            Symbol callee_subtree;
                            match (callee_node)
                              case %(node ?callee_group *):
                                callee_subtree = callee_group.symbol();
                            if (subtree.symbol() == <src> &&
                                callee_subtree == <src>)
                              src_calls.push(row);
                            else lib_calls.push(row);
                          }
                    }
                }
}

static void _write_datasets(
  String output, List graph, Map attributes) {
  Array functions = %[], src_calls = %[], lib_calls = %[];
  _dataset_rows(graph, attributes, functions, src_calls, lib_calls);
  functions.sort();
  src_calls.sort();
  lib_calls.sort();
  _dataset_mkdirs(output);
  String function_header = %"".join(%(
    "function_id\tkind\tsubtree\tunit\tunit_lines\tsource_order\t"
    "source_name\temitted_name\tvisibility\texternal_calls\t"
    "indirect_calls"
  ));
  _dataset_write_rows(
    %"$output/functions.tsv",
    function_header, functions
  );
  _dataset_write_rows(
    %"$output/src-calls.tsv",
    %"caller_id\tcallee_id\tstatic_calls", src_calls
  );
  _dataset_write_rows(
    %"$output/lib-calls.tsv",
    %"caller_id\tcallee_id\tstatic_calls", lib_calls
  );
}

static void _usage(String program) {
  Stderr.printf("usage: %s graph|digest [-I DIR] FILE...\n", program);
  Stderr.printf(
    "       %s datasets OUTPUT [-I DIR] SRC_FILE... -- LIB_FILE...\n",
    program
  );
  Stderr.printf("       %s architecture [-I DIR] FILE...\n", program);
  Stderr.printf("       %s structure UNIT [-I DIR] FILE...\n", program);
  Stderr.printf("       %s between LEFT RIGHT [-I DIR] FILE...\n", program);
  Stderr.printf("       %s focus NAME [-I DIR] FILE...\n", program);
  Stderr.printf("       %s field TYPE FIELD [-I DIR] FILE...\n", program);
  Stderr.printf("       %s field-sites TYPE FIELD [-I DIR] FILE...\n", program);
  Stderr.printf("       %s sites NAME [-I DIR] FILE...\n", program);
  Stderr.printf("       %s walks [-I DIR] FILE...\n", program);
  Stderr.printf("       %s tail-calls [-I DIR] FILE...\n", program);
  Stderr.printf(
    "       %s loop-allocations [--all] [-I DIR] FILE...\n", program
  );
  Stderr.printf("       %s lifetime-escapes [-I DIR] FILE...\n", program);
  Stderr.printf(
    "       %s allocation-returns NAME [-I DIR] FILE...\n", program
  );
  Stderr.printf(
    "       %s flows PRODUCER CONSUMER [-I DIR] FILE...\n", program
  );
  Stderr.printf(
    "       %s compare LEFT RIGHT TARGET... -- [-I DIR] FILE...\n",
    program
  );
}

int main(int argc, char **argv) {
  int datasets = argc > 1 && !strcmp(argv[1], "datasets");
  int architecture = argc > 1 && !strcmp(argv[1], "architecture");
  int structure = argc > 1 && !strcmp(argv[1], "structure");
  int between = argc > 1 && !strcmp(argv[1], "between");
  int focus = argc > 1 && !strcmp(argv[1], "focus");
  int field = argc > 1 && !strcmp(argv[1], "field");
  int field_sites = argc > 1 && !strcmp(argv[1], "field-sites");
  int sites = argc > 1 && !strcmp(argv[1], "sites");
  int walks = argc > 1 && !strcmp(argv[1], "walks");
  int tail_calls = argc > 1 && !strcmp(argv[1], "tail-calls");
  int loop_allocations =
    argc > 1 && !strcmp(argv[1], "loop-allocations");
  int loop_limit = LOOP_ALLOCATION_LIMIT;
  int lifetime_escapes =
    argc > 1 && !strcmp(argv[1], "lifetime-escapes");
  int allocation_returns =
    argc > 1 && !strcmp(argv[1], "allocation-returns");
  int flows = argc > 1 && !strcmp(argv[1], "flows");
  int compare = argc > 1 && !strcmp(argv[1], "compare");
  int separator = -1;
  if (compare)
    for (int i = 4; i < argc; i++)
      if (!strcmp(argv[i], "--")) {
        separator = i;
        break;
      }
  if (datasets)
    for (int i = 3; i < argc; i++)
      if (!strcmp(argv[i], "--")) {
        separator = i;
        break;
      }
  int first_input = compare ? separator + 1
                  : datasets ? 3
                  : field || field_sites || flows ? 4
                  : between ? 4
                  : structure || focus || sites || allocation_returns ? 3 : 2;
  if ((compare && separator < 5) ||
      (datasets && (argc < 6 || separator < 4)) ||
      argc <= first_input ||
      (strcmp(argv[1], "graph") && strcmp(argv[1], "digest") &&
       !datasets && !architecture && !structure && !between && !focus &&
       !field &&
       !field_sites && !sites && !walks &&
       !tail_calls && !loop_allocations && !lifetime_escapes &&
       !allocation_returns && !flows && !compare)) {
    _usage(argv[0]);
    return 2;
  }
  x2c_initialize_environment(argv[0]);
  Array inputs = %[], include_dirs = %[], compare_operations = %[];
  Array src_inputs = %[], lib_inputs = %[];
  Map seen = %{}, subtrees = %{};
  String dataset_output = datasets ? String.new(argv[2]) : NULL;
  String wanted = structure ? _display_input(String.new(argv[2]))
                : focus || sites || allocation_returns
                ? String.new(argv[2]) : NULL;
  String left = between ? _display_input(String.new(argv[2])) : NULL;
  String right = between ? _display_input(String.new(argv[3])) : NULL;
  String receiver_name = field || field_sites
                       ? String.new(argv[2]) : NULL;
  String field_name = field || field_sites
                    ? String.new(argv[3]) : NULL;
  String producer = flows ? String.new(argv[2]) : NULL;
  String consumer = flows ? String.new(argv[3]) : NULL;
  String compare_left = compare ? String.new(argv[2]) : NULL;
  String compare_right = compare ? String.new(argv[3]) : NULL;
  if (compare)
    for (int i = 4; i < separator; i++)
      compare_operations.push(String.new(argv[i]));
  compare_operations.sort();
  for (int i = first_input; i < argc; i++) {
    if (datasets && !strcmp(argv[i], "--")) {
      if (i == separator) continue;
      _usage(argv[0]);
      return 2;
    }
    if (loop_allocations && !strcmp(argv[i], "--all")) {
      loop_limit = 0;
      continue;
    }
    if (!strcmp(argv[i], "-I")) {
      if (++i == argc) {
        _usage(argv[0]);
        return 2;
      }
      include_dirs.push(String.new(argv[i]));
      continue;
    }
    if (argv[i][0] == '-') {
      _usage(argv[0]);
      return 2;
    }
    String input = _canonical_input(String.new(argv[i]));
    Symbol subtree = datasets && i > separator ? <lib> : <src>;
    if (seen.contains(input)) {
      if (datasets && subtrees[input].symbol() != subtree) {
        _usage(argv[0]);
        return 2;
      }
    }
    else {
      seen[input] = 1;
      inputs.push(input);
      if (datasets) {
        subtrees[input] = subtree;
        if (subtree == <src>) src_inputs.push(input);
        else lib_inputs.push(input);
      }
    }
  }
  if (!inputs.len() || (datasets &&
      (!src_inputs.len() || !lib_inputs.len()))) {
    _usage(argv[0]);
    return 2;
  }
  inputs.sort();
  Context command = Context.open_isolated_named("x2c graph command");
  int status = 0;
  try {
    Frontend frontend = Frontend.new(include_dirs.list_free());
    List result = NULL;
    if (field)
      result = _parse_field_units(
        frontend, inputs, receiver_name, field_name
      );
    else if (field_sites)
      result = _parse_field_sites(
        frontend, inputs, receiver_name, field_name
      );
    else if (sites)
      result = _parse_sites(frontend, inputs, wanted);
    else if (walks)
      result = _parse_walk_units(frontend, inputs);
    else if (tail_calls)
      result = _parse_tail_units(frontend, inputs);
    else if (loop_allocations)
      result = _parse_loop_allocation_units(
        frontend, inputs, loop_limit
      );
    else if (lifetime_escapes || allocation_returns)
      result = _parse_lifetime_units(
        frontend, inputs, allocation_returns ? wanted : NULL
      );
    else if (flows)
      result = _parse_flow_units(frontend, inputs, producer, consumer);
    else {
      List units = _parse_units(
        frontend, inputs, datasets ? subtrees : NULL
      );
      if (units) {
        Map attributes = datasets ? %{} : NULL;
        List graph = _resolve_graph(units, attributes);
        if (datasets) _write_datasets(dataset_output, graph, attributes);
        result = datasets ? graph
               : !strcmp(argv[1], "graph") ? graph
               : !strcmp(argv[1], "digest") ? _digest(graph)
               : architecture ? _architecture(graph)
               : structure ? _structure(graph, wanted)
               : between ? _between(graph, left, right)
               : compare ? _compare_result(
                   graph, compare_left, compare_right,
                   compare_operations.list_free()
                 )
               : _focus(graph, wanted);
      }
    }
    if (!result) status = 1;
    else if (!datasets)
      Stdout.printf("%s\n", result.repr());
  }
  catch %(not-found *): {
    Stderr.printf("x2c-graph: cannot load the compiler symbol snapshot\n");
    status = 1;
  }
  catch %(io-fail *): {
    Stderr.printf(
      datasets ? "x2c-graph: cannot read input or write datasets\n"
               : "x2c-graph: cannot read compiler support files\n"
    );
    status = 1;
  }
  catch %(incomplete *): {
    Stderr.printf("x2c-graph: incomplete compiler symbol snapshot\n");
    status = 1;
  }
  catch %(malformed *): {
    Stderr.printf("x2c-graph: malformed compiler input or snapshot\n");
    status = 1;
  }
  command.close();
  return status;
}
