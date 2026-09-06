// Production-C-API x2c Map shim for Jackson Allan's benchmark.

template< typename blueprint > struct x2c_map
{
  struct table_type
  {
    Map map;
  };

  struct itr_type
  {
    unsigned cursor;
    typename blueprint::key_type key;
    typename blueprint::value_type value;
    bool valid;
    bool found_directly;
  };

  static table_type create_table()
  {
    Scope_retain();
    return table_type{ Map_new() };
  }

  static void insert(
    table_type &table,
    const typename blueprint::key_type &key
  )
  {
    typename blueprint::value_type value = {};
    Map_set( table.map, key, value );
  }

  static void erase(
    table_type &table,
    const typename blueprint::key_type &key
  )
  {
    Var value;
    Map_try_del( table.map, key, &value );
  }

  static itr_type find(
    table_type &table,
    const typename blueprint::key_type &key
  )
  {
    itr_type itr = {};
    itr.key = key;
    itr.valid = Map_try_get( table.map, key, &itr.value );
    itr.found_directly = itr.valid;
    return itr;
  }

  static itr_type begin_itr( table_type &table )
  {
    itr_type itr = {};
    itr.valid = Map_try_next(
      table.map,
      &itr.cursor,
      &itr.key,
      &itr.value
    );
    return itr;
  }

  static bool is_itr_valid( table_type &table, itr_type &itr )
  {
    (void)table;
    return itr.valid;
  }

  static void increment_itr( table_type &table, itr_type &itr )
  {
    if( itr.found_directly )
    {
      unsigned length = Map_len( table.map );
      itr.cursor = length ? Var_hash( itr.key ) % length : 0;
      itr.found_directly = false;
    }

    itr.valid = Map_try_next(
      table.map,
      &itr.cursor,
      &itr.key,
      &itr.value
    );
  }

  static const typename blueprint::key_type &get_key_from_itr(
    table_type &table,
    itr_type &itr
  )
  {
    (void)table;
    return itr.key;
  }

  static const typename blueprint::value_type &get_value_from_itr(
    table_type &table,
    itr_type &itr
  )
  {
    (void)table;
    return itr.value;
  }

  static void destroy_table( table_type &table )
  {
    table.map = nullptr;
    Scope_release();
  }
};

template<> struct x2c_map< void >
{
  static constexpr const char *label = "x2c Map";
  static constexpr const char *color = "rgb( 220, 70, 70 )";
  static constexpr bool tombstone_like_mechanism = false;
};

#ifdef X2C_STRING_CSTRING_ENABLED
template<> struct x2c_map< x2c_string_cstring >
{
  struct table_type
  {
    Map map;
  };

  struct itr_type
  {
    unsigned cursor;
    char *key;
    uint64_t value;
    bool valid;
    bool found_directly;
  };

  static table_type create_table()
  {
    Scope_retain();
    return table_type{ Map_new() };
  }

  static void insert( table_type &table, char *const &key )
  {
    Map_set(
      table.map,
      x2c_string_cstring::x2c_key( key ),
      x2c_benchmark_uint_var( 0 )
    );
  }

  static void erase( table_type &table, char *const &key )
  {
    Var value;
    Map_try_del(
      table.map,
      x2c_string_cstring::x2c_key( key ),
      &value
    );
  }

  static itr_type find( table_type &table, char *const &key )
  {
    Var value;
    itr_type itr = {};
    itr.key = key;
    itr.valid = Map_try_get(
      table.map,
      x2c_string_cstring::x2c_key( key ),
      &value
    );
    itr.found_directly = itr.valid;
    return itr;
  }

  static itr_type begin_itr( table_type &table )
  {
    Var key, value;
    itr_type itr = {};
    itr.valid = Map_try_next(
      table.map,
      &itr.cursor,
      &key,
      &value
    );
    if( itr.valid )
      itr.key = x2c_benchmark_string_value( key );
    return itr;
  }

  static bool is_itr_valid( table_type &table, itr_type &itr )
  {
    (void)table;
    return itr.valid;
  }

  static void increment_itr( table_type &table, itr_type &itr )
  {
    if( itr.found_directly )
    {
      unsigned length = Map_len( table.map );
      Var key = x2c_string_cstring::x2c_key( itr.key );
      itr.cursor = length ? Var_hash( key ) % length : 0;
      itr.found_directly = false;
    }

    Var key, value;
    itr.valid = Map_try_next(
      table.map,
      &itr.cursor,
      &key,
      &value
    );
    if( itr.valid )
      itr.key = x2c_benchmark_string_value( key );
  }

  static char *const &get_key_from_itr(
    table_type &table,
    itr_type &itr
  )
  {
    (void)table;
    return itr.key;
  }

  static const uint64_t &get_value_from_itr(
    table_type &table,
    itr_type &itr
  )
  {
    (void)table;
    return itr.value;
  }

  static void destroy_table( table_type &table )
  {
    table.map = nullptr;
    Scope_release();
  }
};
#endif
