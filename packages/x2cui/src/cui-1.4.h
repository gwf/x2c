#ifndef X2C_CUI_1_4_H
#define X2C_CUI_1_4_H

#include <cui/cui.h>
#include <cui/cui_app.h>
#include <cui/cui_render.h>
#include <cui/cui_icons.h>

#if CUI_VERSION_MAJOR != 1 || CUI_VERSION_MINOR != 4
#error "the x2c CUI client requires CUI 1.4"
#endif

/* Defined in x2cui-window.c; `App.frame` calls it. */
void x2cui_title_bar(void *window, bool dark, unsigned rgb);

#endif
