// x2c adapter configuration for Jackson Allan's benchmark.

#ifndef KEY_COUNT
#define KEY_COUNT 200000
#endif

#ifndef KEY_COUNT_MEASUREMENT_INTERVAL
#define KEY_COUNT_MEASUREMENT_INTERVAL 500
#endif

#ifndef RUN_COUNT
#define RUN_COUNT 14
#endif

#ifndef DISCARDED_RUNS_COUNT
#define DISCARDED_RUNS_COUNT 4
#endif

#define MAX_LOAD_FACTOR 0.75

#ifndef APPROXIMATE_CACHE_SIZE
#define APPROXIMATE_CACHE_SIZE 20000000
#endif

#ifndef MILLISECOND_COOLDOWN_BETWEEN_BENCHMARKS
#define MILLISECOND_COOLDOWN_BETWEEN_BENCHMARKS 1000
#endif

#define BENCHMARK_INSERT_NONEXISTING
#define BENCHMARK_ERASE_EXISTING
#define BENCHMARK_INSERT_EXISTING
#define BENCHMARK_ERASE_NONEXISTING
#define BENCHMARK_GET_EXISTING
#define BENCHMARK_GET_NONEXISTING
#define BENCHMARK_ITERATION

#ifdef X2C_STRING_PROFILE
#define BLUEPRINT_1 x2c_string_cstring
#elif defined( X2C_POINTER_PROFILE )
#define BLUEPRINT_1 x2c_pointer_var
#else
#define BLUEPRINT_1 x2c_var_var
#endif

#define SHIM_1 x2c_map

// The string profile adds the typed String Map beside the Var Map, so the
// two x2c rows differ only in whether keys and values cross Var.
#ifdef X2C_STRING_PROFILE
#define SHIM_2 x2c_typed_string_map
#ifdef X2C_FIXED_POLICY_PROFILE
#define SHIM_3 x2c_boost_unordered_flat_map
#define SHIM_4 absl_flat_hash_map
#define SHIM_5 x2c_ankerl_unordered_dense
#else
#define SHIM_3 x2c_ankerl_unordered_dense
#define SHIM_4 tsl_robin_map
#define SHIM_5 ska_bytell_hash_map
#define SHIM_6 std_unordered_map
#endif
#elif defined( X2C_FIXED_POLICY_PROFILE )
#define SHIM_2 x2c_boost_unordered_flat_map
#define SHIM_3 absl_flat_hash_map
#define SHIM_4 x2c_ankerl_unordered_dense
#else
#define SHIM_2 x2c_ankerl_unordered_dense
#define SHIM_3 tsl_robin_map
#define SHIM_4 ska_bytell_hash_map
#define SHIM_5 std_unordered_map
#endif
