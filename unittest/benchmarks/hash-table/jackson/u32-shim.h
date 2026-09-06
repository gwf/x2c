// Runtime-free U32Map shim for Jackson Allan's benchmark.

#include "x2c-u32-map-abi.h"

template< typename blueprint > struct x2c_u32_map
{
  using table_type = X2CU32Map;
  using itr_type = X2CU32MapItr;

  static table_type create_table()
  {
    return x2c_u32_map_new();
  }

  static void insert(
    table_type &table,
    const typename blueprint::key_type &key
  )
  {
#ifdef U32_MAP_COMPACT_RESULT
    X2CU32MapResult result = x2c_u32_map_get_or_insert_hashed(
      table, key, blueprint::hash_key( key ), 0
    );
    *x2c_u32_map_result_value( table, result ) = {};
#elif defined(U32_MAP_SPLIT_RESULT)
    X2CU32MapValueResult result =
      x2c_u32_map_get_or_insert_value_hashed(
        table, key, blueprint::hash_key( key ), 0
      );
    *result.value = {};
#elif defined(U32_MAP_DIRECT_RESULT)
    X2CU32MapResult result = x2c_u32_map_get_or_insert_hashed(
      table, key, blueprint::hash_key( key ), 0
    );
    *result.value = {};
#elif defined(U32_MAP_OUT_VALUE)
    int inserted;
    uint32_t *value;
    (void)x2c_u32_map_get_or_insert_hashed(
      table, key, blueprint::hash_key( key ), 0, &inserted, &value
    );
    (void)inserted;
    *value = {};
#else
    int inserted;
    itr_type itr = x2c_u32_map_get_or_insert_hashed(
      table, key, blueprint::hash_key( key ), 0, &inserted
    );
    (void)inserted;
    *x2c_u32_map_value( table, itr ) = {};
#endif
  }

  static void erase(
    table_type &table,
    const typename blueprint::key_type &key
  )
  {
    itr_type itr = x2c_u32_map_find_hashed(
      table, key, blueprint::hash_key( key )
    );
    if( x2c_u32_map_valid( table, itr ) )
      x2c_u32_map_erase_itr( table, itr );
  }

  static itr_type find(
    table_type &table,
    const typename blueprint::key_type &key
  )
  {
    return x2c_u32_map_find_hashed(
      table, key, blueprint::hash_key( key )
    );
  }

  static itr_type begin_itr( table_type &table )
  {
    return x2c_u32_map_first( table );
  }

  static bool is_itr_valid( table_type &table, itr_type &itr )
  {
    return x2c_u32_map_valid( table, itr );
  }

  static void increment_itr( table_type &table, itr_type &itr )
  {
    itr = x2c_u32_map_next( table, itr );
  }

  static const typename blueprint::key_type &get_key_from_itr(
    table_type &table,
    itr_type &itr
  )
  {
    return *x2c_u32_map_key( table, itr );
  }

  static const typename blueprint::value_type &get_value_from_itr(
    table_type &table,
    itr_type &itr
  )
  {
    return *x2c_u32_map_value( table, itr );
  }

  static void destroy_table( table_type &table )
  {
    x2c_u32_map_free( table );
    table = nullptr;
  }
};

template<> struct x2c_u32_map< void >
{
  static constexpr const char *label = "x2c U32Map";
  static constexpr const char *color = "rgb( 220, 70, 70 )";
  static constexpr bool tombstone_like_mechanism = false;
};
