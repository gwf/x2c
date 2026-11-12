/*  x2cui-window.c -- the native window's title bar follows the theme

    CUI gives a macOS window its light or dark appearance once, when it
    creates the window, and the system draws the title bar in its own
    gray. `x2cui_title_bar` gives the title bar the theme's background
    color, and the light or dark appearance that keeps its title and
    buttons readable. It acts only when either has changed. Other
    platforms draw no themed title bar through CUI, so the function does
    nothing there.
*/

#include <stdbool.h>

#if defined(__APPLE__) && !defined(__EMSCRIPTEN__)

#include <objc/message.h>
#include <objc/runtime.h>

typedef id (*send_text)(id, SEL, const char *);
typedef id (*send_object)(id, SEL, id);
typedef id (*send_flag)(id, SEL, BOOL);
typedef id (*send_color)(id, SEL, double, double, double, double);

/* `rgb` is the background as 0xRRGGBB. */
void x2cui_title_bar(void *window, bool dark, unsigned rgb) {
  static void *shown;
  static bool shown_dark;
  static unsigned shown_rgb;
  if (!window) return;
  if (window == shown && dark == shown_dark && rgb == shown_rgb) return;
  shown = window;
  shown_dark = dark;
  shown_rgb = rgb;
  id name = ((send_text) objc_msgSend)(
    (id) objc_getClass("NSString"), sel_registerName("stringWithUTF8String:"),
    dark ? "NSAppearanceNameDarkAqua" : "NSAppearanceNameAqua");
  id appearance = ((send_object) objc_msgSend)(
    (id) objc_getClass("NSAppearance"), sel_registerName("appearanceNamed:"),
    name);
  id color = ((send_color) objc_msgSend)(
    (id) objc_getClass("NSColor"),
    sel_registerName("colorWithSRGBRed:green:blue:alpha:"),
    (rgb >> 16 & 255) / 255.0, (rgb >> 8 & 255) / 255.0,
    (rgb & 255) / 255.0, 1.0);
  ((send_object) objc_msgSend)(
    (id) window, sel_registerName("setAppearance:"), appearance);
  ((send_flag) objc_msgSend)(
    (id) window, sel_registerName("setTitlebarAppearsTransparent:"), YES);
  ((send_object) objc_msgSend)(
    (id) window, sel_registerName("setBackgroundColor:"), color);
}

#else

void x2cui_title_bar(void *window, bool dark, unsigned rgb) {
  (void) window;
  (void) dark;
  (void) rgb;
}

#endif
