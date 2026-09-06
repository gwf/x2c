// boost::unordered_flat_map shim for x2c's 32-bit production Var hash.

#include "../boost_unordered_flat_map/boost_unordered.hpp"

template< typename blueprint > struct x2c_boost_unordered_flat_map
{
  struct hash
  {
    std::size_t operator()(
      const typename blueprint::key_type &key
    ) const
    {
      return blueprint::hash_key( key );
    }
  };

  struct cmpr
  {
    bool operator()(
      const typename blueprint::key_type &left,
      const typename blueprint::key_type &right
    ) const
    {
      return blueprint::cmpr_keys( left, right );
    }
  };

  using table_type = boost::unordered_flat_map<
    typename blueprint::key_type,
    typename blueprint::value_type,
    hash,
    cmpr
  >;

  static table_type create_table()
  {
    table_type table;
    table.max_load_factor( MAX_LOAD_FACTOR );
    return table;
  }

  static typename table_type::iterator find(
    table_type &table,
    const typename blueprint::key_type &key
  )
  {
    return table.find( key );
  }

  static void insert(
    table_type &table,
    const typename blueprint::key_type &key
  )
  {
    table[ key ] = typename blueprint::value_type();
  }

  static void erase(
    table_type &table,
    const typename blueprint::key_type &key
  )
  {
    table.erase( key );
  }

  static typename table_type::iterator begin_itr( table_type &table )
  {
    return table.begin();
  }

  static bool is_itr_valid(
    table_type &table,
    typename table_type::iterator &itr
  )
  {
    return itr != table.end();
  }

  static void increment_itr(
    table_type &table,
    typename table_type::iterator &itr
  )
  {
    (void)table;
    ++itr;
  }

  static const typename blueprint::key_type &get_key_from_itr(
    table_type &table,
    typename table_type::iterator &itr
  )
  {
    (void)table;
    return itr->first;
  }

  static const typename blueprint::value_type &get_value_from_itr(
    table_type &table,
    typename table_type::iterator &itr
  )
  {
    (void)table;
    return itr->second;
  }

  static void destroy_table( table_type &table )
  {
    (void)table;
  }
};

template<> struct x2c_boost_unordered_flat_map< void >
{
  static constexpr const char *label = "boost";
  static constexpr const char *color = "rgb( 104, 110, 230 )";
  static constexpr bool tombstone_like_mechanism = true;
};
