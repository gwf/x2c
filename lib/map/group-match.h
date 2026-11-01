/* Group control matching; the scalar path also supports portability tests. */
#ifndef X2C_MAP_GROUP_MATCH_H
#define X2C_MAP_GROUP_MATCH_H
#include <stdint.h>
#if defined(__aarch64__) && !defined(X2C_MAP_FORCE_SCALAR)
#include <arm_neon.h>
#endif
static inline unsigned x2c_map_group_match(const unsigned char *controls, unsigned char wanted) {
#if defined(__aarch64__) && !defined(X2C_MAP_FORCE_SCALAR)
  static const unsigned char weights[16] = {
    1,2,4,8,16,32,64,128,1,2,4,8,16,32,64,128
  };
  uint8x16_t matches = vandq_u8(vceqq_u8(vld1q_u8(controls), vdupq_n_u8(wanted)), vld1q_u8(weights));
  return (unsigned)vaddv_u8(vget_low_u8(matches)) |
         ((unsigned)vaddv_u8(vget_high_u8(matches)) << 8);
#else
  unsigned matches = 0;
  for (unsigned i = 0; i < 16; ++i) matches |= (unsigned)(controls[i] == wanted) << i;
  return matches;
#endif
}
#endif
