// x2c pointer-key blueprint for Jackson Allan's benchmark.
//
// The uint blueprint stores small integers, which is not what a real x2c
// program puts in a Map. This one keys by object identity: every key is a
// Var holding the address of a distinct 32-byte object, which is the shape
// a symbol table, an interning table, or a visited set actually has.
//
// Addresses are aligned, so their low bits carry no information and the
// interesting question is whether the hash avalanches them into the bits
// Map masks. Values stay uint Vars so the lane isolates the key.

#include "x2c-benchmark-abi.h"

#define X2C_POINTER_VAR_ENABLED

#ifndef X2C_VAR_VAR_ENABLED
inline bool operator==( const Var &left, const Var &right )
{
  return left.u64 == right.u64;
}

inline bool operator!=( const Var &left, const Var &right )
{
  return !( left == right );
}
#endif

struct x2c_pointer_var
{
  using key_type = Var;
  using value_type = Var;

  static constexpr const char *label = "x2c pointer key, x2c Var value";

  // Wide enough that consecutive objects land in different cache lines
  // about half the time, as separately allocated objects would.
  static constexpr size_t object_size = 32;

  static uint64_t hash_key( const key_type &key )
  {
    return Var_hash( key );
  }

  static bool cmpr_keys( const key_type &left, const key_type &right )
  {
    return Var_equal( left, right );
  }

  // One contiguous block, matching how the upstream c-string blueprint
  // builds its keys. The addresses are still distinct and aligned.
  static void fill_unique_keys( std::vector< key_type > &keys )
  {
    static std::vector< unsigned char > backing_data;

    backing_data.resize( keys.size() * object_size );

    for( size_t i = 0; i < keys.size(); ++i )
      keys[ i ] = x2c_benchmark_pointer_var(
        backing_data.data() + i * object_size
      );
  }
};
