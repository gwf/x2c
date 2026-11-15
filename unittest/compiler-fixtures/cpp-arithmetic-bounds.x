// Unsupported arithmetic retains both arms; valid boundary results select one.

#if 9223372036854775807 + 1
int add_overflow_yes;
#else
int add_overflow_no;
#endif

#if (-9223372036854775807 - 1) - 1
int subtract_overflow_yes;
#else
int subtract_overflow_no;
#endif

#if 9223372036854775807 * 2
int multiply_overflow_yes;
#else
int multiply_overflow_no;
#endif

#if -(-9223372036854775807 - 1)
int negate_overflow_yes;
#else
int negate_overflow_no;
#endif

#if 1 << 63
int shift_overflow_yes;
#else
int shift_overflow_no;
#endif

#if -1 << 1
int shift_negative_yes;
#else
int shift_negative_no;
#endif

#if 9223372036854775806 + 1 == 9223372036854775807
int add_max_yes;
#else
int add_max_no;
#endif

#if -9223372036854775807 - 1 < -9223372036854775807
int subtract_min_yes;
#else
int subtract_min_no;
#endif

#if -4611686018427387904 * 2 == (-9223372036854775807 - 1)
int multiply_min_yes;
#else
int multiply_min_no;
#endif

#if -(-9223372036854775807) == 9223372036854775807
int negate_max_yes;
#else
int negate_max_no;
#endif

#if 1 << 62 == 4611686018427387904
int shift_fits_yes;
#else
int shift_fits_no;
#endif

#if 0 << 63 == 0
int shift_zero_yes;
#else
int shift_zero_no;
#endif

