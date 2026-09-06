// Derived from Jackson Allan's cstring_uint64_fnv1a blueprint.
// Copyright (c) 2024 Jackson L. Allan.
// Distributed under the MIT License (see LICENSE in this directory).

#include <cstring>

#include "x2c-benchmark-abi.h"

#define X2C_STRING_CSTRING_ENABLED

struct x2c_string_cstring
{
  using key_type = char *;
  using value_type = uint64_t;

  static constexpr const char *label =
    "16-char string-content key, 64-bit value";
  static constexpr size_t string_length = 16;

  static uint64_t hash_key( const key_type &key )
  {
    size_t hash = 0xcbf29ce484222325ull;
    char *c = key;
    while( *c )
      hash = ( (unsigned char)*c++ ^ hash ) * 0x100000001b3ull;

    return hash;
  }

  static bool cmpr_keys( const key_type &left, const key_type &right )
  {
    return strcmp( left, right ) == 0;
  }

  static std::vector< char > &backing_data()
  {
    static std::vector< char > data;
    return data;
  }

  static std::vector< Var > &x2c_keys()
  {
    static std::vector< Var > keys;
    return keys;
  }

  static std::vector< String > &x2c_strings()
  {
    static std::vector< String > strings;
    return strings;
  }

  static size_t x2c_index( const key_type &key )
  {
    return static_cast< size_t >(
      key - backing_data().data()
    ) / string_length;
  }

  static Var x2c_key( const key_type &key )
  {
    return x2c_keys()[ x2c_index( key ) ];
  }

  static String x2c_string_key( const key_type &key )
  {
    return x2c_strings()[ x2c_index( key ) ];
  }

  static void fill_unique_keys( std::vector< key_type > &keys )
  {
    std::vector< char > &data = backing_data();
    std::vector< Var > &strings = x2c_keys();
    std::vector< String > &canonical = x2c_strings();
    data.resize( keys.size() * string_length );
    strings.resize( keys.size() );
    canonical.resize( keys.size() );

    char current[ string_length ];
    memset( current, 'a', string_length - 1 );
    current[ string_length - 1 ] = '\0';

    for( size_t i = 0; i < keys.size(); ++i )
    {
      keys[ i ] = data.data() + i * string_length;
      memcpy( keys[ i ], current, string_length );
      strings[ i ] = x2c_benchmark_string_var( keys[ i ] );
      canonical[ i ] = x2c_benchmark_string( keys[ i ] );

      for( size_t j = 0; j < string_length - 1; ++j )
      {
        if( ++current[ j ] <= 'z' )
          break;

        current[ j ] = 'a';
      }
    }
  }
};
