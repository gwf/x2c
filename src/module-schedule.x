/*  module-schedule.x -- directed declaration components

    Copyright (c) 2026 Gary William Flake

    Dependencies point from a provider to providers whose declarations it
    uses. Components permit mutual declarations, without changing ownership
    or the source order of compile-time effects.
*/

#pragma once
#include "array.x"
#include "map.x"

static typedef struct DeclarationSchedule {
  Map dependencies, indices, low, active;
  Array stack, groups;
  int next;
} DeclarationSchedule;

/** Returns strongly connected declaration groups, prerequisites first.
    Provider and dependency list order breaks ties deterministically.
    A referenced provider absent from the map has no outgoing edges.
*/
List declaration_components(List providers, Map dependencies) {
  DeclarationSchedule s = {
    .dependencies = dependencies, .indices = {}, .low = {},
    .active = {}, .stack = [], .groups = [], .next = 1};
  foreach (String provider, providers)
    if (!(provider in s.indices)) s.visit(provider);
  return s.groups.list_free();
}

/** Schedules requested providers in prerequisite component order.
    Unrequested graph vertices connect components but receive no body work.
    Members of one component retain their original provider order.
*/
List declaration_work(List providers, Map dependencies) {
  Array groups = [], work = [];
  Map components = {};
  foreach (List component, declaration_components(providers, dependencies)) {
    int index = groups.len();
    Array selected = [];
    groups.push(selected);
    foreach (String provider, component) components[provider] = index;
  }
  foreach (String provider, providers) {
    Array selected = groups[(int) components[provider]];
    selected.push(provider);
  }
  foreach (Array selected, groups)
    if (selected.len()) work.push(selected.list_free());
  return work.list_free();
}

static void DeclarationSchedule.visit(
  DeclarationSchedule &s, String provider) {
  int index = s.next++;
  s.indices[provider] = s.low[provider] = index;
  s.active[provider] = 1;
  s.stack.push(provider);
  Var edges = s.dependencies[provider];
  if (edges is <list>) foreach (String dependency, edges.list()) {
    int candidate;
    if (!(dependency in s.indices)) {
      s.visit(dependency);
      candidate = s.low[dependency];
    }
    else {
      if (!(dependency in s.active)) continue;
      candidate = s.indices[dependency];
    }
    if (candidate < (int) s.low[provider]) s.low[provider] = candidate;
  }
  if ((int) s.low[provider] != index) return;
  Array group = [];
  String member;
  do {
    member = s.stack[-1];
    s.stack.pop();
    s.active.del(member);
    group.push(member);
  } while (member != provider);
  s.groups.push(group.reverse().list_free());
}
