#ifndef X2CUI_STRESS_PLATFORM_H
#define X2CUI_STRESS_PLATFORM_H

#ifdef __EMSCRIPTEN__
int stress_wait_visible(void);
#else
static inline int stress_wait_visible(void) { return 0; }
#endif

#endif
