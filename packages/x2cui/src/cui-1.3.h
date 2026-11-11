#ifndef X2C_CUI_1_3_H
#define X2C_CUI_1_3_H

#include <cui/cui.h>
#include <cui/cui_app.h>
#include <cui/cui_render.h>
#include <cui/cui_icons.h>

#if CUI_VERSION_MAJOR != 1 || CUI_VERSION_MINOR != 3
#error "the x2c CUI client requires CUI 1.3"
#endif

/* Defined in x2cui-window.c; `App.frame` calls it. */
void x2cui_title_bar(void *window, bool dark);

#endif
