/* Collection reads both arms of a condition it cannot evaluate, so it sees
   a linkage group that an include splits across two segments. */
#ifdef C_LINKAGE_SPLIT_CPLUSPLUS
extern "C" {
#endif
#include "c-linkage-split-inner.h"
#ifdef C_LINKAGE_SPLIT_CPLUSPLUS
}
#endif
