// x2c Var-key/Var-value blueprint for Jackson Allan's benchmark.

#include <numeric>

#include "x2c-benchmark-abi.h"

#define X2C_VAR_VAR_ENABLED

inline bool operator==( const Var &left, const Var &right )
{
  return left.u64 == right.u64;
}

inline bool operator!=( const Var &left, const Var &right )
{
  return !( left == right );
}

struct x2c_var_var
{
  using key_type = Var;
  using value_type = Var;

  static constexpr const char *label = "x2c Var key, x2c Var value";

  static uint64_t hash_key( const key_type &key )
  {
    return Var_hash( key );
  }

  static bool cmpr_keys( const key_type &left, const key_type &right )
  {
    return Var_equal( left, right );
  }

  static void fill_unique_keys( std::vector< key_type > &keys )
  {
    for( size_t i = 0; i < keys.size(); ++i )
      keys[ i ] = x2c_benchmark_uint_var(
        static_cast< unsigned >( i )
      );
  }
};
