// Runtime-free U32Map configuration for Jackson Allan's benchmark.

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

#define BLUEPRINT_1 uint32_uint32_murmur

#if defined(X2C_SHIM_SCALAR_ONLY)
#define SHIM_1 x2c_u32_map
#elif defined(X2C_SHIM_ANKERL_ONLY)
#define SHIM_1 ankerl_unordered_dense
#elif defined(X2C_SHIM_TSL_ONLY)
#define SHIM_1 tsl_robin_map
#elif defined(X2C_SHIM_SKA_ONLY)
#define SHIM_1 ska_bytell_hash_map
#elif defined(X2C_SHIM_STD_ONLY)
#define SHIM_1 std_unordered_map
#elif defined(X2C_SHIM_BOOST_ONLY)
#define SHIM_1 boost_unordered_flat_map
#elif defined(X2C_SHIM_ABSL_ONLY)
#define SHIM_1 absl_flat_hash_map
#elif defined(X2C_FIXED_POLICY_PROFILE)
#define SHIM_1 x2c_u32_map
#define SHIM_2 boost_unordered_flat_map
#define SHIM_3 absl_flat_hash_map
#define SHIM_4 ankerl_unordered_dense
#else
#define SHIM_1 x2c_u32_map
#define SHIM_2 ankerl_unordered_dense
#define SHIM_3 tsl_robin_map
#define SHIM_4 ska_bytell_hash_map
#define SHIM_5 std_unordered_map
#endif
