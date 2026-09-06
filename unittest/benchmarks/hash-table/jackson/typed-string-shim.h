// Production-C-API MapStringString shim for Jackson Allan's benchmark.
//
// It stores the same interned key bytes as the x2c Map shim and a String
// value of the same eight-byte width, so the pair differs only in whether
// the key and value cross the Var layer.

template< typename blueprint > struct x2c_typed_string_map
{
};

template<> struct x2c_typed_string_map< void >
{
  static constexpr const char *label = "x2c MapStringString";
  static constexpr const char *color = "rgb( 70, 130, 220 )";
  static constexpr bool tombstone_like_mechanism = false;
};

#ifdef X2C_STRING_CSTRING_ENABLED
template<> struct x2c_typed_string_map< x2c_string_cstring >
{
  struct table_type
  {
    MapStringString map;
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
    return table_type{ MapStringString_new() };
  }

  static void insert( table_type &table, char *const &key )
  {
    MapStringString_set(
      table.map,
      x2c_string_cstring::x2c_string_key( key ),
      nullptr
    );
  }

  static void erase( table_type &table, char *const &key )
  {
    String value;
    MapStringString_try_del(
      table.map,
      x2c_string_cstring::x2c_string_key( key ),
      &value
    );
  }

  static itr_type find( table_type &table, char *const &key )
  {
    String value;
    itr_type itr = {};
    itr.key = key;
    itr.valid = MapStringString_try_get(
      table.map,
      x2c_string_cstring::x2c_string_key( key ),
      &value
    );
    if( itr.valid )
      itr.value = (uint64_t)(uintptr_t)value;
    itr.found_directly = itr.valid;
    return itr;
  }

  static itr_type begin_itr( table_type &table )
  {
    String key, value;
    itr_type itr = {};
    itr.valid = MapStringString_try_next(
      table.map,
      &itr.cursor,
      &key,
      &value
    );
    if( itr.valid )
    {
      itr.key = key;
      itr.value = (uint64_t)(uintptr_t)value;
    }
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
      unsigned length = MapStringString_len( table.map );
      String key = x2c_string_cstring::x2c_string_key( itr.key );
      itr.cursor = length ? String_hash( key ) % length : 0;
      itr.found_directly = false;
    }

    String key, value;
    itr.valid = MapStringString_try_next(
      table.map,
      &itr.cursor,
      &key,
      &value
    );
    if( itr.valid )
    {
      itr.key = key;
      itr.value = (uint64_t)(uintptr_t)value;
    }
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
