/*  clones.x -- experimental binding-aware structural clone candidates */

#pragma once
#include "frontend.x"
#include "targets.x"

#pragma private
#include <stdint.h>
#include <limits.h>
#include <stdlib.h>
#include <time.h>

typedef struct CloneCell {
  uint64_t head, tail, occurrences;
} CloneCell;

typedef struct CloneIndex {
  CloneCell *cells;
  uint64_t *slots, *sizes;
  size_t count, capacity, slot_count;
  uint64_t visits;
  int sequence, minimum, unlocated;
  Map atoms, sites;
  ParsedUnit *parsed;
  Map statics;
  String path, function;
} CloneIndex;

static uint64_t _clone_hash(uint64_t head, uint64_t tail) {
  uint64_t value = head * 11400714819323198485ULL ^ tail;
  value ^= value >> 30;
  value *= 13787848793156543929ULL;
  return value ^ (value >> 27);
}

static void _clone_rehash(CloneIndex *index, size_t count) {
  free(index.slots);
  index.slots = calloc(count, sizeof(uint64_t));
  if (!index.slots) raise %(alloc-fail (owner "graph clones"));
  index.slot_count = count;
  for (size_t i = 1; i <= index.count; i++) {
    CloneCell cell = index.cells[i];
    size_t slot = _clone_hash(cell.head, cell.tail) & (count - 1);
    while (index.slots[slot]) slot = (slot + 1) & (count - 1);
    index.slots[slot] = i;
  }
}

static uint64_t _clone_cons(
  CloneIndex *index, uint64_t head, uint64_t tail) {
  index.visits++;
  if ((index.count + 1) * 2 >= index.slot_count)
    _clone_rehash(index, index.slot_count ? index.slot_count * 2 : 1024);
  size_t slot = _clone_hash(head, tail) & (index.slot_count - 1);
  while (index.slots[slot]) {
    uint64_t id = index.slots[slot];
    CloneCell *cell = &index.cells[id];
    if (cell.head == head && cell.tail == tail) {
      cell.occurrences++;
      return id * 2;
    }
    slot = (slot + 1) & (index.slot_count - 1);
  }
  if (index.count >= INT_MAX / 2)
    raise %(size-limit (owner "graph clones"));
  if (index.count + 1 >= index.capacity) {
    index.capacity = index.capacity ? index.capacity * 2 : 1024;
    CloneCell *cells = realloc(
      index.cells, index.capacity * sizeof(CloneCell));
    if (!cells) raise %(alloc-fail (owner "graph clones"));
    index.cells = cells;
    uint64_t *sizes = realloc(
      index.sizes, index.capacity * sizeof(uint64_t));
    if (!sizes) raise %(alloc-fail (owner "graph clones"));
    index.sizes = sizes;
    index.sizes[0] = 0;
  }
  uint64_t id = ++index.count;
  index.cells[id].head = head;
  index.cells[id].tail = tail;
  index.cells[id].occurrences = 1;
  index.sizes[id] = 1 + (head & 1 ? 0 : index.sizes[head / 2])
                     + index.sizes[tail / 2];
  index.slots[slot] = id;
  return id * 2;
}

static uint64_t _clone_atom(CloneIndex *index, Var value) {
  Var found;
  if (index.atoms.try_get(value, found)) return found.integer();
  if (index.atoms.len() >= INT_MAX / 2)
    raise %(size-limit (owner "graph clones"));
  uint64_t id = index.atoms.len() * 2 + 1;
  value = index.parsed.context.export(value);
  index.atoms[value] = (int) id;
  return id;
}

static int _clone_local(CloneIndex *index, List binding) {
  Map facts = index.parsed.compiler.semantic_binding_facts();
  if (!facts.contains(%(automatic $binding))) return 0;
  Var declared;
  if (facts.try_get(%(type $binding), declared)) {
    Type type = declared;
    if (type.is_extern() || type.is_function()) return 0;
  }
  return 1;
}

/* The ordered identity stream establishes one bijection per fragment.
   This optional verification is separate from linear structural indexing. */
static void _clone_bindings(
  CloneIndex *index, Var value, Map names, Array stream) {
  if (value is not <list>) return;
  List node = value;
  match (node) {
    case %(binding ? ?): {
      if (!_clone_local(index, node)) return;
      if (!names.contains(node)) names[node] = names.len();
      stream.push(names[node]);
      return;
    }
    case %(at ? ?inner): {
      _clone_bindings(index, inner, names, stream);
      return;
    }
  }
  foreach (Var child, node) _clone_bindings(index, child, names, stream);
}

static int _clone_origin(Var value) {
  if (value is not <list>) return 0;
  List node = value;
  match (node) case %(at ?origin ?): return origin.integer();
  foreach (Var child, node) {
    int origin = _clone_origin(child);
    if (origin) return origin;
  }
  return 0;
}

static int _clone_root(List node) {
  Var tag = node.car();
  return tag is <symbol> &&
    %(function expr stmnt block if while for foreach return op call).contains(
      tag);
}

static uint64_t _clone_list(CloneIndex *index, List node, int origin) {
  if (!node) return 0;
  uint64_t head = _clone_value(index, node.car(), origin);
  uint64_t tail = _clone_list(index, node.cdr(), origin);
  return _clone_cons(index, head, tail);
}

static uint64_t _clone_value(CloneIndex *index, Var value, int origin) {
  if (index.sequence == INT_MAX)
    raise %(size-limit (owner "graph clones"));
  int start = index.sequence++;
  if (value is not <list>) return _clone_atom(index, value);
  List node = value;
  if (!node) return 0;
  match (node) {
    case %(at ?next ?inner):
      return _clone_value(index, inner, next.integer());
    case %(binding ? ?): {
      if (_clone_local(index, node))
        return _clone_atom(index, %(local));
      String name = index.parsed.compiler.emitted_binding_name(node);
      Var source_key;
      int file_static = index.statics.contains(node);
      if (index.parsed.compiler.semantic_binding_facts().try_get(
        %(src-key $node), source_key))
        file_static |= index.parsed.compiler.sym.file_statics().contains(
          source_key);
      List key = file_static
               ? %(global ${index.path} $name) : %(global $name);
      return _clone_atom(index, key);
    }
  }
  uint64_t id = _clone_list(index, node, origin);
  uint64_t size = index.sizes[id / 2];
  if (size >= index.minimum && _clone_root(node)) {
    if (!origin) origin = _clone_origin(node);
    if (!origin) { index.unlocated++; return id; }
    Array stream = [];
    _clone_bindings(index, node, {}, stream);
    List key = %(${(int) id} @{stream.list_free()});
    List site = %(
      site ${index.function}
      ${project_location(index.parsed.compiler, index.path, origin)}
      (kind ${node.car()}) (span $start ${index.sequence})
      (unit ${index.path})
    );
    key = index.parsed.context.export(key);
    site = index.parsed.context.export(site);
    List prior = index.sites.contains(key) ? index.sites[key].list() : NULL;
    index.sites[key] = index.parsed.context.export(cons(site, prior));
  }
  return id;
}

/* A smaller match adds nothing when all its occurrences lie in one
   already reported group's occurrences. Spans belong to input units. */
static int _clone_covered(List sites, List parents) {
  foreach (List site, sites) {
    int found = 0;
    match (site)
      case %(site ?function ? ? (span ?start ?end) (unit ?unit)):
        foreach (List parent, parents)
          match (parent)
            case %(site ?outer_function ? ?
                   (span ?outer_start ?outer_end) (unit ?outer_unit)):
              if (outer_function == function && outer_unit == unit &&
                  outer_start.integer() <= start.integer() &&
                  outer_end.integer() >= end.integer()) {
                found = 1;
                break;
              }
    if (!found) return 0;
  }
  return 1;
}

List graph_clones(Frontend frontend, Array inputs, int minimum) {
  CloneIndex index = {0};
  defer { free(index.cells); free(index.slots); free(index.sizes); }
  index.minimum = minimum;
  index.atoms = {};
  index.sites = {};
  double parse_seconds = 0, index_seconds = 0;
  foreach (String input, inputs) {
    ParsedUnit parsed;
    clock_t start = clock();
    int ok = frontend.start(input, parsed);
    if (ok) {
      parsed.compiler.own_diagnostics();
      ok = parsed.collect(frontend) && parsed.parse();
    }
    parse_seconds += (double) (clock() - start) / CLOCKS_PER_SEC;
    if (!ok) {
      foreach (Var entry, parsed.compiler.diagnostics())
        parsed.compiler.print_diagnostic(entry);
      parsed.close();
      return NULL;
    }
    start = clock();
    index.parsed = &parsed;
    index.sequence = 0;
    index.path = parsed.compiler.display_path(input);
    index.statics = {};
    foreach (List node, parsed.ast)
      match (node)
        case %(function ?type (bind ?binding ?) ?):
          if (((Type) type).is_static()) index.statics[binding] = 1;
    foreach (List node, parsed.ast) {
      index.function = "<top-level>";
      match (node)
        case %(function ? (bind ?binding ?) ?):
          index.function = parsed.compiler.emitted_binding_name(binding);
      _clone_value(&index, node, 0);
    }
    index_seconds += (double) (clock() - start) / CLOCKS_PER_SEC;
    parsed.close();
  }
  Array ranked = [];
  foreach (Var (key, value), index.sites) {
    List sites = value;
    int count = sites.len();
    if (count < 2) continue;
    uint64_t id = key.list().car().integer() / 2;
    uint64_t size = index.sizes[id];
    sites = sites.sort();
    ranked.push(
      %(${-(int64_t) (size * (count - 1))}
        ${-(int64_t) size} $count
        ${ (int64_t) index.cells[id].occurrences} (sites @sites)));
  }
  ranked.sort();
  Array candidates = [], retained = [];
  int total = ranked.len(), suppressed = 0;
  for (int i = 0; i < total && candidates.len() < 25; i++) {
    List row = ranked[i];
    match (row) case %(?score ?size ?count ?occurrences (sites *sites)): {
      int covered = 0;
      foreach (List parent, retained)
        if (_clone_covered(sites, parent)) { covered = 1; break; }
      if (covered) { suppressed++; continue; }
      retained.push(sites);
      candidates.push(
        %(candidate (score ${-score.integer()})
          (size ${-size.integer()}) (verified-occurrences $count)
          (structural-occurrences $occurrences) (sites @{sites[:8]})));
    }
  }
  uint64_t unique[64] = {0}, visits[64] = {0}, repeated[64] = {0};
  for (size_t i = 1; i <= index.count; i++) {
    unsigned bucket = 0;
    for (uint64_t size = index.sizes[i]; size > 1; size >>= 1) bucket++;
    unique[bucket]++;
    visits[bucket] += index.cells[i].occurrences;
    if (index.cells[i].occurrences > 1) repeated[bucket]++;
  }
  Array distribution = [];
  for (int i = 0; i < 64; i++)
    if (unique[i]) distribution.push(
      %(bucket
        (minimum-size ${(int64_t) (1ULL << i)})
        (unique-cells ${(int64_t) unique[i]})
        (repeated-cells ${(int64_t) repeated[i]})
        (occurrences ${(int64_t) visits[i]})));
  List result = %(clones
    (policy local-binding-bijection literals-preserved globals-preserved)
    (summary (units ${inputs.len()}) (cons-visits ${(int64_t) index.visits})
      (unique-cells ${(int64_t) index.count})
      (cell-bytes ${(int64_t) (index.count * sizeof(CloneCell))})
      (cell-capacity-bytes ${(int64_t) (index.capacity * sizeof(CloneCell))})
      (index-bytes ${(int64_t) (index.slot_count * sizeof(uint64_t))})
      (size-capacity-bytes ${(int64_t) (index.capacity * sizeof(uint64_t))})
      (atoms ${index.atoms.len()}) (verification-groups ${index.sites.len()})
      (unlocated-root-occurrences ${index.unlocated})
      (candidate-groups $total) (suppressed-before-limit $suppressed)
      (minimum-size $minimum) (limit 25) (site-limit 8)
      (parse-cpu-seconds $parse_seconds) (index-cpu-seconds $index_seconds))
    (size-distribution @{distribution.list_free()})
    (candidates @{candidates.list_free()}));
  return result;
}
