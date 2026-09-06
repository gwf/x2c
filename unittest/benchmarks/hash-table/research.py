#!/usr/bin/env python3
"""Measure auditable, algorithm-preserving U32Map source variants."""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
from pathlib import Path
import platform
import statistics
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[3]
HERE = ROOT / "unittest/benchmarks/hash-table"
SOURCE = HERE / "x2c/u32-map.x"
BASELINE_COMMIT = "8c8515935d78cd3809f150601584220185cb38e2"
BASELINE_PATH = "examples/hash-table-benchmark/x2c/u32-map.x"
BRIDGE = HERE / "x2c/u32-map-bridge.c"
ABI = HERE / "x2c/u32-map-abi.h"
TEST = HERE / "x2c/test-u32-map.c"
UDB = HERE / "udb3/u32-test.c"
UDB_SOURCE = ROOT / "unittest/build/benchmarks/hash-table/udb3/source"
RESULTS = ROOT / "unittest/build/benchmarks/hash-table/research/results"
COMPILER = ROOT / "builds/0/x2c"


PSL_OLD = "(map.capacity + index - stored_start) & map.mask"
PSL_NEW = "(index - stored_start) & map.mask"

RECORD_ZERO_OLD = """\
  map.records = _resize(map.records, capacity, sizeof(U32MapRecord));
  memset(map.records + map.record_capacity, 0,
         (capacity - map.record_capacity) * sizeof(U32MapRecord));
  map.record_capacity = capacity;
"""
RECORD_ZERO_NEW = """\
  map.records = _resize(map.records, capacity, sizeof(U32MapRecord));
  map.record_capacity = capacity;
"""

EXPAND_OLD = """\
  for (uint32_t i = 0; i < old_capacity; i++)
    if (!old_slots[i].hash && old_slots[i].index)
      map._save_record(old_slots[i].index);

  map.slots = slots;
  map.capacity = capacity;
  map.mask = capacity - 1;
  for (uint32_t i = 0; i < old_capacity; i++)
    if (old_slots[i].hash) map._reinsert(old_slots[i], 0);
"""
EXPAND_NEW = """\
  map.slots = slots;
  map.capacity = capacity;
  map.mask = capacity - 1;
  for (uint32_t i = 0; i < old_capacity; i++) {
    if (old_slots[i].hash)
      map._reinsert(old_slots[i], 0);
    else if (old_slots[i].index)
      map._save_record(old_slots[i].index);
  }
"""

ACCESS_OLD = """\
static uint32_t *U32Map.key(U32Map map, U32MapItr itr) {
  if (!map.valid(itr)) _fail();
  return &map.records[map.slots[itr.slot].index].key;
}

static uint32_t *U32Map.value(U32Map map, U32MapItr itr) {
  if (!map.valid(itr)) _fail();
  return &map.records[map.slots[itr.slot].index].value;
}
"""
ACCESS_NEW = """\
macro Unit $u32.record_accessor(
  Name $method, Param $map, Param $itr, Expr $body
) => {
  static inline uint32_t *U32Map.$method($map, $itr) {
    return $body;
  }
}

$u32.record_accessor(
  key, U32Map map, U32MapItr itr,
  &map.records[map.slots[itr.slot].index].key
);
$u32.record_accessor(
  value, U32Map map, U32MapItr itr,
  &map.records[map.slots[itr.slot].index].value
);
"""

CACHE_FIND_OLD = """\
  uint32_t start = hash & map.mask;
  for (uint32_t psl = 0; psl < map.capacity; psl++) {
"""
CACHE_FIND_NEW = """\
  uint32_t start = hash & map.mask;
  U32MapRecord *records = map.records;
  for (uint32_t psl = 0; psl < map.capacity; psl++) {
"""
CACHE_INSERT_OLD = """\
retry:;
  uint32_t start = hash & map.mask;
  for (uint32_t psl = 0; psl < map.capacity; psl++) {
"""
CACHE_INSERT_NEW = """\
retry:;
  uint32_t start = hash & map.mask;
  U32MapRecord *records = map.records;
  for (uint32_t psl = 0; psl < map.capacity; psl++) {
"""

ERASE_CHECK_OLD = """\
static void U32Map.erase_itr(U32Map map, U32MapItr itr) {
  if (!map.valid(itr)) _fail();
"""
ERASE_CHECK_NEW = """\
static void U32Map.erase_itr(U32Map map, U32MapItr itr) {
"""

RECORD_CLEAR_OLD = "  map.records[record] = (U32MapRecord) { 0 };\n"
RECORD_INDEX_OLD = "  uint32_t record = slot.index;\n"

PRIVATE_OLD = "#pragma private\n"
PRIVATE_HINT_NEW = """\
#pragma private

macro Expression $u32.unlikely(Expr $condition) => (
  __builtin_expect(!!($condition), 0)
)
"""
GROWTH_OLD = "if (map.used >= map.capacity / 2)"
GROWTH_NEW = "if ($u32.unlikely(map.used >= map.capacity / 2))"

NOINLINE_PUSH = (
    "#pragma clang attribute push(__attribute__((noinline)), "
    "apply_to=function)\n"
)
NOINLINE_POP = "#pragma clang attribute pop\n\n"
STORE_RECORD_START = "static uint32_t U32Map._store_record(\n"
FIND_START = "static U32MapSlot *U32Map._find(\n"
REINSERT_START = "static void U32Map._reinsert(\n"
EXPAND_START = "static void U32Map._expand(U32Map map) {\n"
RESERVE_RECORDS_OLD = """\
static void U32Map._reserve_records(U32Map map, uint32_t needed) {
  if (needed <= map.record_capacity) return;
  uint32_t capacity = map.record_capacity;
  while (capacity < needed) capacity = _double_capacity(capacity);
  map.records = _resize(map.records, capacity, sizeof(U32MapRecord));
  memset(map.records + map.record_capacity, 0,
         (capacity - map.record_capacity) * sizeof(U32MapRecord));
  map.record_capacity = capacity;
}
"""
GROW_RECORDS_NEW = f"""\
{NOINLINE_PUSH}static void U32Map._grow_records(
  U32Map map, uint32_t needed
) {{
  uint32_t capacity = map.record_capacity;
  while (capacity < needed) capacity = _double_capacity(capacity);
  map.records = _resize(map.records, capacity, sizeof(U32MapRecord));
  memset(map.records + map.record_capacity, 0,
         (capacity - map.record_capacity) * sizeof(U32MapRecord));
  map.record_capacity = capacity;
}}
{NOINLINE_POP}"""
RESERVE_RECORDS_CALL_OLD = (
    "      map._reserve_records(map.record_length + 1);\n"
)
GROW_RECORDS_CALL_NEW = """\
      if (map.record_length == map.record_capacity)
        map._grow_records(map.record_length + 1);
"""
MAP_NEW_START = "static U32Map U32Map.new(void) {\n"
OUTLINED_INSERT_HELPER = f"""\
{NOINLINE_PUSH}static U32MapItr U32Map._insert_hashed(
  U32Map map, uint32_t key, uint32_t hash, uint32_t initial,
  int *inserted, uint32_t index, uint32_t stored_psl
) {{
  if ($u32.unlikely(map._would_exceed_max_load())) {{
    map._expand();
    return map.get_or_insert_hashed(
      key, (uint64_t) hash, initial, inserted
    );
  }}

  U32MapSlot *slot = map.slots + index;
  if (!slot.hash) {{
    U32_MAP_PROFILE_ADD(empty_insertions, 1);
    uint32_t record = map._store_record(key, initial, slot.index);
    *slot = (U32MapSlot) {{ .hash = hash, .index = record }};
  }}
  else {{
    U32_MAP_PROFILE_ADD(robin_hood_insertions, 1);
    uint32_t record = map._store_record(key, initial, 0);
    U32MapSlot displaced = *slot;
    *slot = (U32MapSlot) {{ .hash = hash, .index = record }};
    map._reinsert(displaced, stored_psl + 1);
  }}

  *inserted = 1;
  return (U32MapItr) {{ .slot = index }};
}}
{NOINLINE_POP}{MAP_NEW_START}"""
INSERT_RETRY_OLD = "retry:;\n"
INSERT_EMPTY_OLD = """\
    if (!slot.hash) {
      if ($u32.unlikely(map._would_exceed_max_load())) {
        map._expand();
        goto retry;
      }
      U32_MAP_PROFILE_ADD(empty_insertions, 1);
      uint32_t record = map._store_record(key, initial, slot.index);
      *slot = (U32MapSlot) { .hash = hash, .index = record };
      *inserted = 1;
      return (U32MapItr) { .slot = index };
    }
"""
INSERT_EMPTY_NEW = """\
    if (!slot.hash) {
      return map._insert_hashed(
        key, hash, initial, inserted, index, 0
      );
    }
"""
INSERT_DISPLACED_OLD = """\
    if (stored_psl < psl) {
      if ($u32.unlikely(map._would_exceed_max_load())) {
        map._expand();
        goto retry;
      }
      U32_MAP_PROFILE_ADD(robin_hood_insertions, 1);
      uint32_t record = map._store_record(key, initial, 0);
      U32MapSlot displaced = *slot;
      *slot = (U32MapSlot) { .hash = hash, .index = record };
      map._reinsert(displaced, stored_psl + 1);
      *inserted = 1;
      return (U32MapItr) { .slot = index };
    }
"""
INSERT_DISPLACED_NEW = """\
    if (stored_psl < psl) {
      return map._insert_hashed(
        key, hash, initial, inserted, index, stored_psl
      );
    }
"""
OUTLINE_INSERTION_RECIPE = [
    (MAP_NEW_START, OUTLINED_INSERT_HELPER, 1),
    (INSERT_RETRY_OLD, "", 1),
    (INSERT_EMPTY_OLD, INSERT_EMPTY_NEW, 1),
    (INSERT_DISPLACED_OLD, INSERT_DISPLACED_NEW, 1),
]
OUTLINE_RECORD_GROWTH_RECIPE = [
    (RESERVE_RECORDS_OLD, GROW_RECORDS_NEW, 1),
    (RESERVE_RECORDS_CALL_OLD, GROW_RECORDS_CALL_NEW, 1),
]

PARALLEL_RECORD_OLD = """\
typedef struct U32MapRecord {
  uint32_t key, value;
} U32MapRecord;
"""
PARALLEL_RECORD_NEW = """\
typedef struct U32MapRecord {
  uint32_t value;
} U32MapRecord;
"""
PARALLEL_MAP_STORAGE_OLD = """\
  U32MapSlot *slots;
  U32MapRecord *records;
"""
PARALLEL_MAP_STORAGE_NEW = """\
  U32MapSlot *slots;
  uint32_t *keys;
  U32MapRecord *records;
"""
PARALLEL_STORE_OLD = (
    "  map.records[index] = "
    "(U32MapRecord) { .key = key, .value = value };\n"
)
PARALLEL_STORE_NEW = """\
  (void) key;
  map.records[index] = (U32MapRecord) { .value = value };
"""
PARALLEL_FIND_OLD = """\
static U32MapSlot *U32Map._find(
  U32Map map, uint32_t key, uint32_t hash
) {
  uint32_t start = hash & map.mask;
  U32MapRecord *records = map.records;
  for (uint32_t psl = 0; psl < map.capacity; psl++) {
    uint32_t index = (start + psl) & map.mask;
    U32MapSlot *slot = map.slots + index;
    if (!slot.hash) return NULL;
    if (slot.hash == hash && records[slot.index].key == key)
      return slot;
    uint32_t stored_start = slot.hash & map.mask;
    uint32_t stored_psl = (map.capacity + index - stored_start) & map.mask;
    if (stored_psl < psl) return NULL;
  }
  return NULL;
}
"""
PARALLEL_FIND_NEW = """\
static U32MapSlot *U32Map._find(
  U32Map map, uint32_t key, uint32_t hash
) {
  uint32_t start = hash & map.mask;
  uint32_t *keys = map.keys;
  for (uint32_t psl = 0; psl < map.capacity; psl++) {
    uint32_t index = (start + psl) & map.mask;
    U32MapSlot *slot = map.slots + index;
    if (!slot.hash) return NULL;
    if (slot.hash == hash && keys[index] == key) return slot;
    uint32_t stored_start = slot.hash & map.mask;
    uint32_t stored_psl = (map.capacity + index - stored_start) & map.mask;
    if (stored_psl < psl) return NULL;
  }
  return NULL;
}
"""
PARALLEL_REINSERT_OLD = """\
static void U32Map._reinsert(
  U32Map map, U32MapSlot displaced, uint32_t initial_psl
) {
  uint32_t start = displaced.hash & map.mask;
  for (uint32_t psl = initial_psl; psl < map.capacity; psl++) {
    U32_MAP_PROFILE_ADD(reinsert_probes, 1);
    U32_MAP_PROFILE_MAX(max_reinsert_probe, psl + 1);
    uint32_t index = (start + psl) & map.mask;
    U32MapSlot *slot = map.slots + index;
    if (!slot.hash) {
      if (slot.index && slot.index != displaced.index)
        map._save_record(slot.index);
      *slot = displaced;
      return;
    }
    uint32_t stored_start = slot.hash & map.mask;
    uint32_t stored_psl =
      (map.capacity + index - stored_start) & map.mask;
    if (stored_psl < psl) {
      U32_MAP_PROFILE_ADD(reinsert_swaps, 1);
      U32MapSlot swap = *slot; *slot = displaced; displaced = swap;
      start = stored_start;
      psl = stored_psl;
    }
  }
  _fail();
}
"""
PARALLEL_REINSERT_NEW = """\
static void U32Map._reinsert(
  U32Map map, U32MapSlot displaced, uint32_t displaced_key,
  uint32_t initial_psl
) {
  uint32_t start = displaced.hash & map.mask;
  for (uint32_t psl = initial_psl; psl < map.capacity; psl++) {
    U32_MAP_PROFILE_ADD(reinsert_probes, 1);
    U32_MAP_PROFILE_MAX(max_reinsert_probe, psl + 1);
    uint32_t index = (start + psl) & map.mask;
    U32MapSlot *slot = map.slots + index;
    if (!slot.hash) {
      if (slot.index && slot.index != displaced.index)
        map._save_record(slot.index);
      *slot = displaced;
      map.keys[index] = displaced_key;
      return;
    }
    uint32_t stored_start = slot.hash & map.mask;
    uint32_t stored_psl =
      (map.capacity + index - stored_start) & map.mask;
    if (stored_psl < psl) {
      U32_MAP_PROFILE_ADD(reinsert_swaps, 1);
      U32MapSlot swap = *slot; *slot = displaced; displaced = swap;
      uint32_t swap_key = map.keys[index];
      map.keys[index] = displaced_key;
      displaced_key = swap_key;
      start = stored_start;
      psl = stored_psl;
    }
  }
  _fail();
}
"""
PARALLEL_EXPAND_OLD = """\
static void U32Map._expand(U32Map map) {
  U32_MAP_PROFILE_ADD(expansions, 1);
  U32_MAP_PROFILE_EXPAND_BEGIN();
  uint32_t old_capacity = map.capacity;
  uint32_t capacity = _double_capacity(old_capacity);
  U32MapSlot *old_slots = map.slots;
  U32MapSlot *slots = _allocate(capacity, sizeof(U32MapSlot));
  memset(slots, 0, capacity * sizeof(U32MapSlot));

  map.slots = slots;
  map.capacity = capacity;
  map.mask = capacity - 1;
  for (uint32_t i = 0; i < old_capacity; i++) {
    if (old_slots[i].hash) {
      U32_MAP_PROFILE_ADD(expansion_records, 1);
      map._reinsert(old_slots[i], 0);
    }
    else if (old_slots[i].index)
      map._save_record(old_slots[i].index);
  }
  U32_MAP_PROFILE_EXPAND_END();
  free(old_slots);
}
"""
PARALLEL_EXPAND_NEW = """\
static void U32Map._expand(U32Map map) {
  U32_MAP_PROFILE_ADD(expansions, 1);
  U32_MAP_PROFILE_EXPAND_BEGIN();
  uint32_t old_capacity = map.capacity;
  uint32_t capacity = _double_capacity(old_capacity);
  U32MapSlot *old_slots = map.slots;
  uint32_t *old_keys = map.keys;
  U32MapSlot *slots = _allocate(capacity, sizeof(U32MapSlot));
  memset(slots, 0, capacity * sizeof(U32MapSlot));
  uint32_t *keys = _allocate(capacity, sizeof(uint32_t));
  memset(keys, 0, capacity * sizeof(uint32_t));

  map.slots = slots;
  map.keys = keys;
  map.capacity = capacity;
  map.mask = capacity - 1;
  for (uint32_t i = 0; i < old_capacity; i++) {
    if (old_slots[i].hash) {
      U32_MAP_PROFILE_ADD(expansion_records, 1);
      map._reinsert(old_slots[i], old_keys[i], 0);
    }
    else if (old_slots[i].index)
      map._save_record(old_slots[i].index);
  }
  U32_MAP_PROFILE_EXPAND_END();
  free(old_slots);
  free(old_keys);
}
"""
PARALLEL_INSERT_OLD = """\
    uint32_t record = map._store_record(key, initial, slot.index);
    *slot = (U32MapSlot) { .hash = hash, .index = record };
"""
PARALLEL_INSERT_NEW = """\
    uint32_t record = map._store_record(key, initial, slot.index);
    *slot = (U32MapSlot) { .hash = hash, .index = record };
    map.keys[index] = key;
"""
PARALLEL_DISPLACE_OLD = """\
    U32MapSlot displaced = *slot;
    *slot = (U32MapSlot) { .hash = hash, .index = record };
    map._reinsert(displaced, stored_psl + 1);
"""
PARALLEL_DISPLACE_NEW = """\
    U32MapSlot displaced = *slot;
    uint32_t displaced_key = map.keys[index];
    *slot = (U32MapSlot) { .hash = hash, .index = record };
    map.keys[index] = key;
    map._reinsert(displaced, displaced_key, stored_psl + 1);
"""
PARALLEL_NEW_OLD = """\
  map.slots = _allocate(map.capacity, sizeof(U32MapSlot));
  memset(map.slots, 0, map.capacity * sizeof(U32MapSlot));
  map.record_capacity = 2;
"""
PARALLEL_NEW_NEW = """\
  map.slots = _allocate(map.capacity, sizeof(U32MapSlot));
  memset(map.slots, 0, map.capacity * sizeof(U32MapSlot));
  map.keys = _allocate(map.capacity, sizeof(uint32_t));
  memset(map.keys, 0, map.capacity * sizeof(uint32_t));
  map.record_capacity = 2;
"""
PARALLEL_FREE_OLD = """\
  free(map.slots);
  free(map.records);
"""
PARALLEL_FREE_NEW = """\
  free(map.slots);
  free(map.keys);
  free(map.records);
"""
PARALLEL_ACCESS_KEY_OLD = """\
  &map.records[map.slots[itr.slot].index].key
"""
PARALLEL_ACCESS_KEY_NEW = """\
  &map.keys[itr.slot]
"""
PARALLEL_LOOKUP_DECL_OLD = "  U32MapRecord *records = map.records;\n"
PARALLEL_LOOKUP_DECL_NEW = "  uint32_t *keys = map.keys;\n"
PARALLEL_LOOKUP_KEY_OLD = "records[slot.index].key == key"
PARALLEL_LOOKUP_KEY_NEW = "keys[index] == key"
PARALLEL_ERASE_CLEAR_OLD = """\
  map.records[record] = (U32MapRecord) { 0 };
  slot.hash = 0;
"""
PARALLEL_ERASE_CLEAR_NEW = """\
  map.records[record] = (U32MapRecord) { 0 };
  map.keys[index] = 0;
  slot.hash = 0;
"""
PARALLEL_BACKSHIFT_OLD = """\
    U32MapSlot swap = map.slots[empty];
    map.slots[empty] = *next;
    *next = swap;
"""
PARALLEL_BACKSHIFT_NEW = """\
    U32MapSlot swap = map.slots[empty];
    map.slots[empty] = *next;
    *next = swap;
    uint32_t swap_key = map.keys[empty];
    map.keys[empty] = map.keys[index];
    map.keys[index] = swap_key;
"""

PARALLEL_KEYS_RECIPE = [
    (PARALLEL_RECORD_OLD, PARALLEL_RECORD_NEW, 1),
    (PARALLEL_MAP_STORAGE_OLD, PARALLEL_MAP_STORAGE_NEW, 1),
    (PARALLEL_STORE_OLD, PARALLEL_STORE_NEW, 1),
    (PARALLEL_FIND_OLD, PARALLEL_FIND_NEW, 1),
    (PARALLEL_REINSERT_OLD, PARALLEL_REINSERT_NEW, 1),
    (PARALLEL_EXPAND_OLD, PARALLEL_EXPAND_NEW, 1),
    (PARALLEL_INSERT_OLD, PARALLEL_INSERT_NEW, 1),
    (PARALLEL_DISPLACE_OLD, PARALLEL_DISPLACE_NEW, 1),
    (PARALLEL_NEW_OLD, PARALLEL_NEW_NEW, 1),
    (PARALLEL_FREE_OLD, PARALLEL_FREE_NEW, 1),
    (PARALLEL_ACCESS_KEY_OLD, PARALLEL_ACCESS_KEY_NEW, 1),
    (PARALLEL_LOOKUP_DECL_OLD, PARALLEL_LOOKUP_DECL_NEW, 1),
    (PARALLEL_LOOKUP_KEY_OLD, PARALLEL_LOOKUP_KEY_NEW, 1),
    (PARALLEL_ERASE_CLEAR_OLD, PARALLEL_ERASE_CLEAR_NEW, 1),
    (PARALLEL_BACKSHIFT_OLD, PARALLEL_BACKSHIFT_NEW, 1),
]

DIRECT_RESULT_ITR_OLD = """\
typedef struct U32MapItr {
  uint32_t slot;
} U32MapItr;
"""
DIRECT_RESULT_ITR_NEW = """\
typedef struct U32MapItr {
  uint32_t slot;
} U32MapItr;

typedef struct U32MapResult {
  uint32_t *value;
  U32MapItr itr;
  int inserted;
} U32MapResult;
"""
DIRECT_RESULT_RETRY_OLD = """\
    return map.get_or_insert_hashed(
      key, (uint64_t) hash, initial, inserted
    );
"""
DIRECT_RESULT_RETRY_NEW = """\
    return map.get_or_insert_hashed(key, (uint64_t) hash, initial);
"""
DIRECT_RESULT_INSERT_RETURN_OLD = """\
  *inserted = 1;
  return (U32MapItr) { .slot = index };
"""
DIRECT_RESULT_INSERT_RETURN_NEW = """\
  return (U32MapResult) {
    .value = &map.records[slot.index].value,
    .itr = (U32MapItr) { .slot = index },
    .inserted = 1
  };
"""
DIRECT_RESULT_FOUND_OLD = """\
        U32_MAP_PROFILE_ADD(key_matches, 1);
        return (U32MapItr) { .slot = index };
"""
DIRECT_RESULT_FOUND_NEW = """\
        U32_MAP_PROFILE_ADD(key_matches, 1);
        return (U32MapResult) {
          .value = &records[slot.index].value,
          .itr = (U32MapItr) { .slot = index },
          .inserted = 0
        };
"""
DIRECT_RESULT_EMPTY_CALL_OLD = """\
      return map._insert_hashed(
        key, hash, initial, inserted, index, 0
      );
"""
DIRECT_RESULT_EMPTY_CALL_NEW = """\
      return map._insert_hashed(key, hash, initial, index, 0);
"""
DIRECT_RESULT_DISPLACE_CALL_OLD = """\
      return map._insert_hashed(
        key, hash, initial, inserted, index, stored_psl
      );
"""
DIRECT_RESULT_DISPLACE_CALL_NEW = """\
      return map._insert_hashed(
        key, hash, initial, index, stored_psl
      );
"""

DIRECT_RESULT_RECIPE = [
    (DIRECT_RESULT_ITR_OLD, DIRECT_RESULT_ITR_NEW, 1),
    ("static U32MapItr U32Map._insert_hashed(\n",
     "static U32MapResult U32Map._insert_hashed(\n", 1),
    ("  int *inserted, uint32_t index, uint32_t stored_psl\n",
     "  uint32_t index, uint32_t stored_psl\n", 1),
    (DIRECT_RESULT_RETRY_OLD, DIRECT_RESULT_RETRY_NEW, 1),
    (DIRECT_RESULT_INSERT_RETURN_OLD, DIRECT_RESULT_INSERT_RETURN_NEW, 1),
    ("static U32MapItr U32Map.get_or_insert_hashed(\n",
     "static U32MapResult U32Map.get_or_insert_hashed(\n", 1),
    ("  uint32_t initial, int *inserted\n", "  uint32_t initial\n", 1),
    ("  if (!map || !inserted) _fail();\n", "  if (!map) _fail();\n", 1),
    ("  *inserted = 0;\n", "", 1),
    (DIRECT_RESULT_FOUND_OLD, DIRECT_RESULT_FOUND_NEW, 1),
    (DIRECT_RESULT_EMPTY_CALL_OLD, DIRECT_RESULT_EMPTY_CALL_NEW, 1),
    (DIRECT_RESULT_DISPLACE_CALL_OLD, DIRECT_RESULT_DISPLACE_CALL_NEW, 1),
    ("  _fail();\n  return _invalid_itr();\n}\n\n"
     "static void U32Map.erase_itr",
     "  _fail();\n  return (U32MapResult) { 0 };\n}\n\n"
     "static void U32Map.erase_itr", 1),
    ("  if (!map.valid(itr)) _fail();\n", "", 1),
]

SPLIT_RESULT_ITR_NEW = """\
typedef struct U32MapItr {
  uint32_t slot;
} U32MapItr;

typedef struct U32MapValueResult {
  uint32_t *value;
  int inserted;
} U32MapValueResult;
"""
SPLIT_RESULT_METHOD = """\
static U32MapValueResult U32Map.get_or_insert_value_hashed(
  U32Map map, uint32_t key, uint64_t supplied_hash, uint32_t initial
) {
  if (!map) _fail();
  U32_MAP_PROFILE_ADD(operations, 1);
  uint32_t hash = _stored_hash(supplied_hash);
  uint32_t start = hash & map.mask;
  U32MapRecord *records = map.records;
  for (uint32_t psl = 0; psl < map.capacity; psl++) {
    U32_MAP_PROFILE_ADD(probes, 1);
    U32_MAP_PROFILE_MAX(max_probe, psl + 1);
    uint32_t index = (start + psl) & map.mask;
    U32MapSlot *slot = map.slots + index;
    if (slot.hash == hash) {
      U32_MAP_PROFILE_ADD(hash_matches, 1);
      if (records[slot.index].key == key) {
        U32_MAP_PROFILE_ADD(key_matches, 1);
        return (U32MapValueResult) {
          .value = &records[slot.index].value,
          .inserted = 0
        };
      }
    }

    uint32_t stored_psl = 0;
    if (slot.hash) {
      uint32_t stored_start = slot.hash & map.mask;
      stored_psl =
        (map.capacity + index - stored_start) & map.mask;
      if (stored_psl >= psl) continue;
    }

    int inserted;
    U32MapItr itr = map._insert_hashed(
      key, hash, initial, &inserted, index, stored_psl
    );
    return (U32MapValueResult) {
      .value = &map.records[map.slots[itr.slot].index].value,
      .inserted = inserted
    };
  }
  _fail();
  return (U32MapValueResult) { 0 };
}

"""

SPLIT_RESULT_RECIPE = [
    (DIRECT_RESULT_ITR_OLD, SPLIT_RESULT_ITR_NEW, 1),
    ("static U32MapProfile U32Map.profile(void) {\n",
     SPLIT_RESULT_METHOD +
     "static U32MapProfile U32Map.profile(void) {\n", 1),
    ("  if (!map.valid(itr)) _fail();\n", "", 1),
]

OUT_VALUE_RETRY_NEW = """\
    return map.get_or_insert_hashed(
      key, (uint64_t) hash, initial, inserted, value
    );
"""
OUT_VALUE_INSERT_RETURN_NEW = """\
  *inserted = 1;
  if (value) *value = &map.records[slot.index].value;
  return (U32MapItr) { .slot = index };
"""
OUT_VALUE_FOUND_NEW = """\
        U32_MAP_PROFILE_ADD(key_matches, 1);
        if (value) *value = &records[slot.index].value;
        return (U32MapItr) { .slot = index };
"""
OUT_VALUE_EMPTY_CALL_NEW = """\
      return map._insert_hashed(
        key, hash, initial, inserted, value, index, 0
      );
"""
OUT_VALUE_DISPLACE_CALL_NEW = """\
      return map._insert_hashed(
        key, hash, initial, inserted, value, index, stored_psl
      );
"""

OUT_VALUE_RECIPE = [
    ("  int *inserted, uint32_t index, uint32_t stored_psl\n",
     "  int *inserted, uint32_t **value, uint32_t index,\n"
     "  uint32_t stored_psl\n", 1),
    (DIRECT_RESULT_RETRY_OLD, OUT_VALUE_RETRY_NEW, 1),
    (DIRECT_RESULT_INSERT_RETURN_OLD, OUT_VALUE_INSERT_RETURN_NEW, 1),
    ("  uint32_t initial, int *inserted\n",
     "  uint32_t initial, int *inserted, uint32_t **value\n", 1),
    (DIRECT_RESULT_FOUND_OLD, OUT_VALUE_FOUND_NEW, 1),
    (DIRECT_RESULT_EMPTY_CALL_OLD, OUT_VALUE_EMPTY_CALL_NEW, 1),
    (DIRECT_RESULT_DISPLACE_CALL_OLD, OUT_VALUE_DISPLACE_CALL_NEW, 1),
    ("  if (!map.valid(itr)) _fail();\n", "", 1),
]

COMPACT_RESULT_ITR_OLD = """\
typedef struct U32MapItr {
  uint32_t slot;
} U32MapItr;
"""
COMPACT_RESULT_ITR_NEW = """\
typedef struct U32MapItr {
  uint32_t slot;
} U32MapItr;

typedef struct U32MapResult {
  uint32_t slot, record_and_inserted;
} U32MapResult;

#define U32_MAP_RESULT_INSERTED 0x80000000u
"""
COMPACT_RESULT_INSERT_OLD = """\
static U32MapItr U32Map._insert_hashed(
  U32Map map, uint32_t key, uint32_t hash, uint32_t initial,
  int *inserted, uint32_t index, uint32_t stored_psl
) {
  if ($u32.unlikely(map._would_exceed_max_load())) {
    map._expand();
    return map.get_or_insert_hashed(
      key, (uint64_t) hash, initial, inserted
    );
  }

  U32MapSlot *slot = map.slots + index;
  if (!slot.hash) {
    U32_MAP_PROFILE_ADD(empty_insertions, 1);
    uint32_t record = map._store_record(key, initial, slot.index);
    *slot = (U32MapSlot) { .hash = hash, .index = record };
  }
  else {
    U32_MAP_PROFILE_ADD(robin_hood_insertions, 1);
    uint32_t record = map._store_record(key, initial, 0);
    U32MapSlot displaced = *slot;
    *slot = (U32MapSlot) { .hash = hash, .index = record };
    map._reinsert(displaced, stored_psl + 1);
  }

  *inserted = 1;
  return (U32MapItr) { .slot = index };
}
"""
COMPACT_RESULT_INSERT_NEW = """\
static U32MapResult U32Map._insert_hashed(
  U32Map map, uint32_t key, uint32_t hash, uint32_t initial,
  uint32_t index, uint32_t stored_psl
) {
  if ($u32.unlikely(map._would_exceed_max_load())) {
    map._expand();
    return map.get_or_insert_hashed(key, (uint64_t) hash, initial);
  }

  U32MapSlot *slot = map.slots + index;
  uint32_t record;
  if (!slot.hash) {
    U32_MAP_PROFILE_ADD(empty_insertions, 1);
    record = map._store_record(key, initial, slot.index);
    *slot = (U32MapSlot) { .hash = hash, .index = record };
  }
  else {
    U32_MAP_PROFILE_ADD(robin_hood_insertions, 1);
    record = map._store_record(key, initial, 0);
    U32MapSlot displaced = *slot;
    *slot = (U32MapSlot) { .hash = hash, .index = record };
    map._reinsert(displaced, stored_psl + 1);
  }

  if (record & U32_MAP_RESULT_INSERTED) _fail();
  return (U32MapResult) {
    .slot = index,
    .record_and_inserted = record | U32_MAP_RESULT_INSERTED
  };
}
"""
COMPACT_RESULT_GET_OLD = """\
static U32MapItr U32Map.get_or_insert_hashed(
  U32Map map, uint32_t key, uint64_t supplied_hash,
  uint32_t initial, int *inserted
) {
  if (!map || !inserted) _fail();
  U32_MAP_PROFILE_ADD(operations, 1);
  *inserted = 0;
  uint32_t hash = _stored_hash(supplied_hash);
  uint32_t start = hash & map.mask;
  U32MapRecord *records = map.records;
  for (uint32_t psl = 0; psl < map.capacity; psl++) {
    U32_MAP_PROFILE_ADD(probes, 1);
    U32_MAP_PROFILE_MAX(max_probe, psl + 1);
    uint32_t index = (start + psl) & map.mask;
    U32MapSlot *slot = map.slots + index;
    if (slot.hash == hash) {
      U32_MAP_PROFILE_ADD(hash_matches, 1);
      if (records[slot.index].key == key) {
        U32_MAP_PROFILE_ADD(key_matches, 1);
        return (U32MapItr) { .slot = index };
      }
    }

    if (!slot.hash) {
      return map._insert_hashed(
        key, hash, initial, inserted, index, 0
      );
    }

    uint32_t stored_start = slot.hash & map.mask;
    uint32_t stored_psl =
      (map.capacity + index - stored_start) & map.mask;
    if (stored_psl < psl) {
      return map._insert_hashed(
        key, hash, initial, inserted, index, stored_psl
      );
    }
  }
  _fail();
  return _invalid_itr();
}
"""
COMPACT_RESULT_GET_NEW = """\
static U32MapResult U32Map.get_or_insert_hashed(
  U32Map map, uint32_t key, uint64_t supplied_hash, uint32_t initial
) {
  if (!map) _fail();
  U32_MAP_PROFILE_ADD(operations, 1);
  uint32_t hash = _stored_hash(supplied_hash);
  uint32_t start = hash & map.mask;
  U32MapRecord *records = map.records;
  for (uint32_t psl = 0; psl < map.capacity; psl++) {
    U32_MAP_PROFILE_ADD(probes, 1);
    U32_MAP_PROFILE_MAX(max_probe, psl + 1);
    uint32_t index = (start + psl) & map.mask;
    U32MapSlot *slot = map.slots + index;
    if (slot.hash == hash) {
      U32_MAP_PROFILE_ADD(hash_matches, 1);
      if (records[slot.index].key == key) {
        U32_MAP_PROFILE_ADD(key_matches, 1);
        return (U32MapResult) {
          .slot = index, .record_and_inserted = slot.index
        };
      }
    }

    if (!slot.hash)
      return map._insert_hashed(key, hash, initial, index, 0);

    uint32_t stored_start = slot.hash & map.mask;
    uint32_t stored_psl =
      (map.capacity + index - stored_start) & map.mask;
    if (stored_psl < psl) {
      return map._insert_hashed(
        key, hash, initial, index, stored_psl
      );
    }
  }
  _fail();
  return (U32MapResult) { 0 };
}
"""
COMPACT_RESULT_ACCESSORS = """\
static inline int U32Map.result_inserted(U32MapResult result) {
  return !!(result.record_and_inserted & U32_MAP_RESULT_INSERTED);
}

static inline uint32_t *U32Map.result_value(
  U32Map map, U32MapResult result
) {
  uint32_t record =
    result.record_and_inserted & ~U32_MAP_RESULT_INSERTED;
  return &map.records[record].value;
}

"""

COMPACT_RESULT_RECIPE = [
    (COMPACT_RESULT_ITR_OLD, COMPACT_RESULT_ITR_NEW, 1),
    (COMPACT_RESULT_INSERT_OLD, COMPACT_RESULT_INSERT_NEW, 1),
    (COMPACT_RESULT_GET_OLD, COMPACT_RESULT_GET_NEW, 1),
    ("static void U32Map.erase_itr", COMPACT_RESULT_ACCESSORS +
     "static void U32Map.erase_itr", 1),
    ("  if (!map.valid(itr)) _fail();\n", "", 1),
]

RECORD_ITERATOR_ITR_NEW = """\
typedef struct U32MapItr {
  uint32_t slot, record;
} U32MapItr;
"""
RECORD_ITERATOR_FIND_OLD = """\
  return slot ? (U32MapItr) { .slot = (uint32_t) (slot - map.slots) } :
                _invalid_itr();
"""
RECORD_ITERATOR_FIND_NEW = """\
  return slot ? (U32MapItr) {
                  .slot = (uint32_t) (slot - map.slots),
                  .record = slot.index
                } : _invalid_itr();
"""

RECORD_ITERATOR_RECIPE = [
    (COMPACT_RESULT_ITR_OLD, RECORD_ITERATOR_ITR_NEW, 1),
    ("return (U32MapItr) { .slot = UINT32_MAX };",
     "return (U32MapItr) { .slot = UINT32_MAX, .record = 0 };", 1),
    ("map.slots[itr.slot].index", "itr.record", 2),
    ("return (U32MapItr) { .slot = index };",
     "return (U32MapItr) { .slot = index, .record = slot.index };", 2),
    (RECORD_ITERATOR_FIND_OLD, RECORD_ITERATOR_FIND_NEW, 1),
    ("return (U32MapItr) { .slot = i };",
     "return (U32MapItr) { .slot = i, .record = map.slots[i].index };", 2),
    ("  uint32_t record = slot.index;\n", "  uint32_t record = itr.record;\n", 1),
    ("  if (!map.valid(itr)) _fail();\n", "", 1),
]


RECIPES: dict[str, list[tuple[str, str, int]]] = {
    "baseline": [],
    "parallel-keys": PARALLEL_KEYS_RECIPE,
    "direct-result": DIRECT_RESULT_RECIPE,
    "split-result": SPLIT_RESULT_RECIPE,
    "out-value": OUT_VALUE_RECIPE,
    "compact-result": COMPACT_RESULT_RECIPE,
    "record-iterator": RECORD_ITERATOR_RECIPE,
    "psl-subtract": [(PSL_OLD, PSL_NEW, 3)],
    "no-record-zero": [(RECORD_ZERO_OLD, RECORD_ZERO_NEW, 1)],
    "fused-expand": [(EXPAND_OLD, EXPAND_NEW, 1)],
    "unchecked-macro-access": [(ACCESS_OLD, ACCESS_NEW, 1)],
    "cache-records": [
        (CACHE_INSERT_OLD, CACHE_INSERT_NEW, 1),
        (CACHE_FIND_OLD, CACHE_FIND_NEW, 1),
        ("map.records[slot.index].key", "records[slot.index].key", 2),
    ],
    "unchecked-iterators": [
        (ACCESS_OLD, ACCESS_NEW, 1),
        (ERASE_CHECK_OLD, ERASE_CHECK_NEW, 1),
    ],
    "no-record-clear": [
        (RECORD_INDEX_OLD, "", 1),
        (RECORD_CLEAR_OLD, "", 1),
    ],
    "unlikely-growth": [
        (PRIVATE_OLD, PRIVATE_HINT_NEW, 1),
        (GROWTH_OLD, GROWTH_NEW, 2),
    ],
    "noinline-store-record": [
        (STORE_RECORD_START, NOINLINE_PUSH + STORE_RECORD_START, 1),
        (FIND_START, NOINLINE_POP + FIND_START, 1),
    ],
    "noinline-reinsert": [
        (REINSERT_START, NOINLINE_PUSH + REINSERT_START, 1),
        (EXPAND_START, NOINLINE_POP + EXPAND_START, 1),
    ],
    "noinline-store-and-reinsert": [
        (STORE_RECORD_START, NOINLINE_PUSH + STORE_RECORD_START, 1),
        (FIND_START, NOINLINE_POP + FIND_START, 1),
        (REINSERT_START, NOINLINE_PUSH + REINSERT_START, 1),
        (EXPAND_START, NOINLINE_POP + EXPAND_START, 1),
    ],
    "outline-record-growth": OUTLINE_RECORD_GROWTH_RECIPE,
    "outline-insertion": OUTLINE_INSERTION_RECIPE,
    "outline-insertion-and-growth": [
        *OUTLINE_RECORD_GROWTH_RECIPE,
        *OUTLINE_INSERTION_RECIPE,
    ],
    "psl-fused": [
        (PSL_OLD, PSL_NEW, 3),
        (EXPAND_OLD, EXPAND_NEW, 1),
    ],
    "fused-macro": [
        (EXPAND_OLD, EXPAND_NEW, 1),
        (ACCESS_OLD, ACCESS_NEW, 1),
    ],
    "zero-fused": [
        (RECORD_ZERO_OLD, RECORD_ZERO_NEW, 1),
        (EXPAND_OLD, EXPAND_NEW, 1),
    ],
    "psl-macro": [
        (PSL_OLD, PSL_NEW, 3),
        (ACCESS_OLD, ACCESS_NEW, 1),
    ],
    "zero-macro": [
        (RECORD_ZERO_OLD, RECORD_ZERO_NEW, 1),
        (ACCESS_OLD, ACCESS_NEW, 1),
    ],
    "psl-fused-macro": [
        (PSL_OLD, PSL_NEW, 3),
        (EXPAND_OLD, EXPAND_NEW, 1),
        (ACCESS_OLD, ACCESS_NEW, 1),
    ],
    "structural": [
        (PSL_OLD, PSL_NEW, 3),
        (RECORD_ZERO_OLD, RECORD_ZERO_NEW, 1),
        (EXPAND_OLD, EXPAND_NEW, 1),
    ],
    "all-candidates": [
        (PSL_OLD, PSL_NEW, 3),
        (RECORD_ZERO_OLD, RECORD_ZERO_NEW, 1),
        (EXPAND_OLD, EXPAND_NEW, 1),
        (ACCESS_OLD, ACCESS_NEW, 1),
    ],
    "all-cache": [
        (CACHE_INSERT_OLD, CACHE_INSERT_NEW, 1),
        (CACHE_FIND_OLD, CACHE_FIND_NEW, 1),
        ("map.records[slot.index].key", "records[slot.index].key", 2),
        (PSL_OLD, PSL_NEW, 3),
        (RECORD_ZERO_OLD, RECORD_ZERO_NEW, 1),
        (EXPAND_OLD, EXPAND_NEW, 1),
        (ACCESS_OLD, ACCESS_NEW, 1),
    ],
    "all-unchecked": [
        (PSL_OLD, PSL_NEW, 3),
        (RECORD_ZERO_OLD, RECORD_ZERO_NEW, 1),
        (EXPAND_OLD, EXPAND_NEW, 1),
        (ACCESS_OLD, ACCESS_NEW, 1),
        (ERASE_CHECK_OLD, ERASE_CHECK_NEW, 1),
        (RECORD_INDEX_OLD, "", 1),
        (RECORD_CLEAR_OLD, "", 1),
    ],
    "all-hinted": [
        (PRIVATE_OLD, PRIVATE_HINT_NEW, 1),
        (GROWTH_OLD, GROWTH_NEW, 2),
        (CACHE_INSERT_OLD, CACHE_INSERT_NEW, 1),
        (CACHE_FIND_OLD, CACHE_FIND_NEW, 1),
        ("map.records[slot.index].key", "records[slot.index].key", 2),
        (PSL_OLD, PSL_NEW, 3),
        (RECORD_ZERO_OLD, RECORD_ZERO_NEW, 1),
        (EXPAND_OLD, EXPAND_NEW, 1),
        (ACCESS_OLD, ACCESS_NEW, 1),
    ],
    "portable-core": [
        (PRIVATE_OLD, PRIVATE_HINT_NEW, 1),
        (GROWTH_OLD, GROWTH_NEW, 2),
        (CACHE_INSERT_OLD, CACHE_INSERT_NEW, 1),
        (CACHE_FIND_OLD, CACHE_FIND_NEW, 1),
        ("map.records[slot.index].key", "records[slot.index].key", 2),
        (EXPAND_OLD, EXPAND_NEW, 1),
        (ACCESS_OLD, ACCESS_NEW, 1),
    ],
    "portable-psl": [
        (PRIVATE_OLD, PRIVATE_HINT_NEW, 1),
        (GROWTH_OLD, GROWTH_NEW, 2),
        (CACHE_INSERT_OLD, CACHE_INSERT_NEW, 1),
        (CACHE_FIND_OLD, CACHE_FIND_NEW, 1),
        ("map.records[slot.index].key", "records[slot.index].key", 2),
        (PSL_OLD, PSL_NEW, 3),
        (EXPAND_OLD, EXPAND_NEW, 1),
        (ACCESS_OLD, ACCESS_NEW, 1),
    ],
}


class ResearchError(RuntimeError):
    pass


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def baseline_source(commit: str) -> str:
    completed = subprocess.run(
        ["git", "show", f"{commit}:{BASELINE_PATH}"], cwd=ROOT,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode:
        raise ResearchError(
            f"cannot read retained baseline {commit}: "
            f"{completed.stderr.strip()}"
        )
    return completed.stdout


def run(
    command: list[str | Path], *, output: Path | None = None
) -> subprocess.CompletedProcess[str]:
    rendered = [str(part) for part in command]
    completed = subprocess.run(
        rendered, cwd=ROOT, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, check=False,
    )
    if output:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(completed.stdout, encoding="utf-8")
    if completed.returncode:
        sys.stdout.write(completed.stdout)
        raise ResearchError(
            f"command failed ({completed.returncode}): {' '.join(rendered)}"
        )
    return completed


def apply_recipe(source: str, recipe: list[tuple[str, str, int]]) -> str:
    result = source
    for old, new, expected in recipe:
        actual = result.count(old)
        if actual != expected:
            raise ResearchError(
                f"recipe expected {expected} matches, found {actual}"
            )
        result = result.replace(old, new)
    return result


def final_checkpoint(output: str) -> tuple[str, str, float]:
    rows = [line.split("\t") for line in output.splitlines()
            if line.startswith(("MI\t", "MD\t"))]
    if not rows:
        raise ResearchError("udb3 output contains no measurement row")
    row = rows[-1]
    return row[2], row[3], float(row[6])


def compile_variant(
    result: Path, name: str, source_text: str, cc: str
) -> tuple[Path, dict[str, str]]:
    variant = result / "variants" / name
    generated = variant / "generated"
    generated.mkdir(parents=True)
    x_source = variant / f"{name}.x"
    x_source.write_text(source_text, encoding="utf-8")
    run(
        [COMPILER, "translate", "--out-dir", generated, x_source],
        output=variant / "translate.log",
    )
    generated_c = generated / f"{name}.c"
    generated_h = generated / f"{name}.h"
    define = f'-DX2C_U32_MAP_GENERATED="{name}.c"'
    defines = [define]
    if name == "direct-result":
        defines.append("-DU32_MAP_DIRECT_RESULT")
    elif name == "split-result":
        defines.append("-DU32_MAP_SPLIT_RESULT")
    elif name == "out-value":
        defines.append("-DU32_MAP_OUT_VALUE")
    elif name == "compact-result":
        defines.append("-DU32_MAP_COMPACT_RESULT")
    elif name == "record-iterator":
        defines.append("-DU32_MAP_RECORD_ITERATOR")
    includes = [
        "-I", generated, "-I", HERE / "x2c", "-I", UDB_SOURCE,
        "-iquote", ROOT / "include",
    ]
    binary = variant / "udb3"
    compile_command = [
        cc, "-std=c11", "-O3", "-DNDEBUG", "-Wall", "-Wextra",
        "-Werror", *defines, *includes, UDB, BRIDGE, "-o", binary,
    ]
    run(compile_command, output=variant / "compile.log")

    differential = variant / "differential"
    run([
        cc, "-std=c11", "-O3", "-DNDEBUG", "-Wall", "-Wextra",
        "-Werror", *defines, *includes,
        "-I", ROOT / "unittest/build/benchmarks/hash-table/vendor",
        TEST, BRIDGE, "-o", differential,
    ], output=variant / "compile-differential.log")
    run([differential], output=variant / "differential.log")

    assembly = variant / "assembly.s"
    run([
        cc, "-std=c11", "-O3", "-DNDEBUG", *defines, *includes,
        "-Rpass=inline", "-Rpass-missed=inline", "-S", BRIDGE,
        "-o", assembly,
    ], output=variant / "inline-report.log")
    unresolved = run(["nm", "-u", binary]).stdout
    (variant / "nm-u.txt").write_text(unresolved, encoding="utf-8")
    forbidden = [symbol for symbol in
                 ("x2c", "Var", "Scope", "Bytes", "Block")
                 if symbol.lower() in unresolved.lower()]
    if forbidden:
        raise ResearchError(f"{name} has runtime symbols: {forbidden}")
    return binary, {
        "source_sha256": sha256(x_source),
        "generated_c_sha256": sha256(generated_c),
        "generated_h_sha256": sha256(generated_h),
        "compile": " ".join(str(part) for part in compile_command),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--variants", nargs="+", choices=RECIPES,
        default=[name for name in RECIPES
                 if name not in (
                     "parallel-keys", "direct-result", "split-result",
                     "out-value", "compact-result", "record-iterator"
                 )],
    )
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("-N", dest="inputs", type=int, default=20_000_000)
    parser.add_argument("-n", dest="initial", type=int, default=2_500_000)
    parser.add_argument("-k", dest="checkpoints", type=int, default=5)
    parser.add_argument("--cc", default="cc")
    parser.add_argument("--baseline-commit", default=BASELINE_COMMIT)
    parser.add_argument(
        "--source", choices=("retained", "current"), default="retained",
        help="derive variants from the retained baseline or current U32Map",
    )
    args = parser.parse_args()
    if args.repeats < 1 or args.inputs <= args.initial or args.checkpoints < 2:
        parser.error("require repeats >= 1, N > n, and k >= 2")
    current_only = {
        "parallel-keys", "direct-result", "split-result", "out-value",
        "compact-result",
        "record-iterator",
    }
    if current_only.intersection(args.variants) and args.source != "current":
        parser.error("selected variant requires --source current")
    return args


def main() -> int:
    args = parse_args()
    if not COMPILER.exists() or not (UDB_SOURCE / "common.c").exists():
        raise ResearchError(
            "run benchmark smoke once to prepare prerequisites"
        )
    timestamp = dt.datetime.now(dt.timezone.utc).strftime(
        "%Y%m%dT%H%M%S.%fZ"
    )
    result = RESULTS / timestamp
    result.mkdir(parents=True, exist_ok=False)
    source = (SOURCE.read_text(encoding="utf-8")
              if args.source == "current"
              else baseline_source(args.baseline_commit))
    metadata: dict[str, object] = {
        "started_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "host": platform.platform(),
        "machine": platform.machine(),
        "x2c_commit": run(["git", "rev-parse", "HEAD"]).stdout.strip(),
        "x2c_source_sha256": sha256(SOURCE),
        "baseline_commit": (args.baseline_commit
                            if args.source == "retained" else None),
        "source": args.source,
        "baseline_source_sha256": hashlib.sha256(
            source.encode("utf-8")
        ).hexdigest(),
        "compiler_sha256": sha256(COMPILER),
        "compiler": args.cc,
        "flags": ["-std=c11", "-O3", "-DNDEBUG"],
        "inputs": args.inputs,
        "initial": args.initial,
        "checkpoints": args.checkpoints,
        "repeats": args.repeats,
        "variants": {},
    }
    (result / "metadata.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    binaries: dict[str, Path] = {}
    for name in args.variants:
        print(f"compile {name}", flush=True)
        binaries[name], details = compile_variant(
            result, name, apply_recipe(source, RECIPES[name]), args.cc
        )
        metadata["variants"][name] = details

    rows: list[list[object]] = []
    expected: dict[str, tuple[str, str]] = {}
    order_log: list[str] = []
    for workload, delete in (("count", False), ("mixed", True)):
        for repeat in range(args.repeats):
            offset = repeat % len(args.variants)
            order = args.variants[offset:] + args.variants[:offset]
            if delete:
                order = list(reversed(order))
            order_log.append(
                f"{workload} repeat={repeat + 1}: {' '.join(order)}"
            )
            for name in order:
                print(f"run {workload} {repeat + 1}/{args.repeats} {name}",
                      flush=True)
                command: list[str | Path] = [
                    binaries[name], "-N", str(args.inputs), "-n",
                    str(args.initial), "-k", str(args.checkpoints),
                ]
                if delete:
                    command.append("-d")
                raw = result / "raw" / workload / f"{repeat + 1}-{name}.log"
                completed = run(command, output=raw)
                size, checksum, timing = final_checkpoint(completed.stdout)
                identity = size, checksum
                if workload not in expected:
                    expected[workload] = identity
                elif expected[workload] != identity:
                    raise ResearchError(
                        f"{name} {workload} mismatch: {identity} != "
                        f"{expected[workload]}"
                    )
                rows.append([name, workload, repeat + 1, size, checksum,
                             f"{timing:.4f}"])

    with (result / "measurements.tsv").open(
        "w", newline="", encoding="utf-8"
    ) as destination:
        writer = csv.writer(destination, delimiter="\t")
        writer.writerow([
            "variant", "workload", "repeat", "table_size", "checksum",
            "us_per_input",
        ])
        writer.writerows(rows)

    summary_rows: list[list[object]] = []
    for workload in ("count", "mixed"):
        baseline = sorted(float(row[5]) for row in rows
                          if row[0] == "baseline" and row[1] == workload)
        baseline_median = statistics.median(baseline) if baseline else None
        for name in args.variants:
            values = sorted(float(row[5]) for row in rows
                            if row[0] == name and row[1] == workload)
            median = statistics.median(values)
            delta = ""
            if baseline_median is not None:
                delta = f"{(median / baseline_median - 1.0) * 100.0:.2f}"
            summary_rows.append([
                name, workload, f"{median:.4f}", f"{min(values):.4f}",
                f"{max(values):.4f}", delta,
            ])
    with (result / "summary.tsv").open(
        "w", newline="", encoding="utf-8"
    ) as destination:
        writer = csv.writer(destination, delimiter="\t")
        writer.writerow([
            "variant", "workload", "median_us_per_input", "minimum",
            "maximum", "delta_vs_baseline_pct",
        ])
        writer.writerows(summary_rows)
    (result / "run-order.txt").write_text(
        "\n".join(order_log) + "\n", encoding="utf-8"
    )
    metadata["completed_utc"] = dt.datetime.now(dt.timezone.utc).isoformat()
    metadata["status"] = "complete"
    (result / "metadata.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"results={result}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ResearchError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
