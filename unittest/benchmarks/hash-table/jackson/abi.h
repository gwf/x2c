// Narrow C ABI declarations for using x2c from a C++ benchmark.
//
// x2c's generated C headers intentionally use C tag/typedef conventions that
// are not valid C++. Timed calls below name the production symbols directly;
// only key construction, which occurs before timing, uses a bridge function.

#pragma once

union Var
{
  unsigned long u64;
  double f64;
  void *p64;
};

using Map = void *;
using MapStringString = void *;
using String = char *;

static_assert( sizeof( Var ) == 8 );

extern "C" {
unsigned Var_hash( Var value );
int Var_equal( Var left, Var right );
unsigned String_hash( String string );

void Scope_retain( void );
void Scope_release( void );

Map Map_new( void );
unsigned Map_len( Map map );
void Map_set( Map map, Var key, Var value );
int Map_try_get( Map map, Var key, Var *value );
int Map_try_del( Map map, Var key, Var *value );
int Map_try_next(
  Map map,
  unsigned *cursor,
  Var *key,
  Var *value
);

MapStringString MapStringString_new( void );
unsigned MapStringString_len( MapStringString map );
void MapStringString_set(
  MapStringString map,
  String key,
  String value
);
int MapStringString_try_get(
  MapStringString map,
  String key,
  String *value
);
int MapStringString_try_del(
  MapStringString map,
  String key,
  String *value
);
int MapStringString_try_next(
  MapStringString map,
  unsigned *cursor,
  String *key,
  String *value
);

Var x2c_benchmark_uint_var( unsigned value );
String x2c_benchmark_string( const char *string );
Var x2c_benchmark_pointer_var( void *pointer );
Var x2c_benchmark_string_var( const char *string );
char *x2c_benchmark_string_value( Var value );
}
