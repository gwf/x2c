/*  x2cui-window.c -- the native window's title bar follows the theme

    CUI gives a macOS window its light or dark appearance once, when it
    creates the window. `x2cui_title_bar` gives the window the appearance
    again when the theme has changed. Other platforms draw no themed title
    bar through CUI, so the function does nothing there.
*/

#include <stdbool.h>

#if defined(__APPLE__) && !defined(__EMSCRIPTEN__)

#include <objc/message.h>
#include <objc/runtime.h>

typedef id (*send_text)(id, SEL, const char *);
typedef id (*send_object)(id, SEL, id);

void x2cui_title_bar(void *window, bool dark) {
  static void *shown;
  static bool shown_dark;
  if (!window || (window == shown && dark == shown_dark)) return;
  shown = window;
  shown_dark = dark;
  id name = ((send_text) objc_msgSend)(
    (id) objc_getClass("NSString"), sel_registerName("stringWithUTF8String:"),
    dark ? "NSAppearanceNameDarkAqua" : "NSAppearanceNameAqua");
  id appearance = ((send_object) objc_msgSend)(
    (id) objc_getClass("NSAppearance"), sel_registerName("appearanceNamed:"),
    name);
  ((send_object) objc_msgSend)(
    (id) window, sel_registerName("setAppearance:"), appearance);
}

#else

void x2cui_title_bar(void *window, bool dark) {
  (void) window;
  (void) dark;
}

#endif
