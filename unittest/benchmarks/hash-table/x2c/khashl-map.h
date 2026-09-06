/*  khashl-map.h -- the Map-shaped surface of the khashl storage spike */

#ifndef X2C_KHASHL_MAP_H
#define X2C_KHASHL_MAP_H

#include "x2c.h"

typedef struct KhashlMapTable *KhashlMap;

KhashlMap khashl_map_new(void);
KhashlMap khashl_map_new_capacity(unsigned capacity);
void khashl_map_free(KhashlMap map);
unsigned khashl_map_len(KhashlMap map);
void khashl_map_set(KhashlMap map, Var key, Var value);
int khashl_map_try_get(KhashlMap map, Var key, Var *out);
Var khashl_map_updateindex(KhashlMap map, Var key, Symbol op, Var rhs);
int khashl_map_try_del(KhashlMap map, Var key, Var *out);
int khashl_map_try_next(
  KhashlMap map, unsigned *cursor, Var *key, Var *value
);

#endif
