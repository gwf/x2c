# CUI experimental profile

- Upstream revision: `a5c9ef5efc39b3fc783758362f6b8f9f130f5883` of
  `yappologistic/CUI`, after v1.4.0. The upstream header still reports 1.4.0.
- Source archive: `https://github.com/yappologistic/CUI/archive/a5c9ef5efc39b3fc783758362f6b8f9f130f5883.tar.gz`
- Source archive SHA-256:
  `c1814ad77ae16c3a1930a3512ca1c08001e9bcb89925ac6fdea76481cd9b866b`
- Public header SHA-256 values: `headers.sha256` pins `cui/cui.h`,
  `cui/cui_app.h`, `cui/cui_icons.h`, and `cui/cui_render.h`
- License: MIT, reproduced verbatim in `LICENSES/cui-1.4.0-MIT.txt`.
  `licenses.sha256` pins every file under `LICENSES/`.

Every profile applies `patches/table-row-state.patch`. It adds two
functions to CUI, `cui_table_row_hovered` and `cui_table_row_pressed`,
which return the hover and press `cui_table_row` already computes for the
row's highlight; CUI returns only the click. The patch adds a field to
CUI's private table record and changes nothing CUI draws.

Every profile then applies `patches/focusable-canvas.patch`. It adds
`cui_canvas_ex`, which is `cui_canvas` with interaction flags, and
`cui_focus_visible`, which a painter calls to learn whether an id has
keyboard focus with its ring showing. With `CUI_CANVAS_FOCUSABLE` the
canvas is in the Tab order, and Enter or Space clicks it, as CUI's
interaction does for a button. `cui_canvas` calls `cui_canvas_ex` with no
flags and behaves as before. `ui.item` uses the flag.

Every profile also applies `patches/component-input.patch`. It adds ordered
input capture, a synchronous component-first keyboard dispatcher, and custom
component focus participation. The host retains its queue, key maps, commands,
fallback scopes, and reconciliation. `cui_key_down` remains physical state;
`cui_key_action_down` excludes consumed or inactive downs until release and is
used by built-in held-key actions. Focus requests admit only participating
canvases and expire at completed submission. No callback registry or CUI event
queue is added. The same patch exposes baseline-sheared text drawing through
`cui_draw_text_slanted`, so custom text components need no draw-vertex access.

The patches add declarations to `cui.h`, so `headers.sha256` pins the patched
header. The browser profile also applies its OpenGL ES patch; see
[Browser](#browser).

## Build profile

CUI's own release tool, `tools/amalgamate.py`, writes the library as one
file, `cui.c`. That file is compiled once with `-O2` into `libcui.a`.
Preparing the package therefore requires Python 3, which
`packages/tools/deps.py` already requires.

No configuration macro is defined, so the archive holds everything the
amalgamation enables by default:

- every component in `cui.h`;
- the software renderer and the OpenGL 3.3 / ES 3.0 renderer. The OpenGL
  renderer loads its entry points through a loader function and needs no
  OpenGL headers;
- the window layer `cui_app` for the host system;
- the embedded default fonts and icon font;
- PNG and JPEG loading through stb_image, and PNG writing.

Left out by leaving the macro undefined: Arabic-script shaping and
bidirectional text (`CUI_TEXT_SHAPING`), which upstream marks experimental.

CUI's option records gain fields between minor versions. The package
compiles CUI from this pinned source and `src/cui-1.4.h` rejects another
minor version, so the records a program fills always match the archive.

## macOS

`dependency-darwin.json`. The window layer is Cocoa and is Objective-C, so
`cui.c` is compiled with `-x objective-c -fobjc-arc -D_DARWIN_C_SOURCE`.
A program links `libcui.a` with the Cocoa, QuartzCore, and OpenGL
frameworks. Apple's frameworks are part of the system and are not
redistributed. Revision `a5c9ef5efc39` was verified on macOS arm64 on 2026-11-16:
`make check example` passes 34 tests (146 assertions) and draws all 232
component scenes, with zero unmatched entries. The gallery draws all 31
pages off screen. No native window was opened for this integration.

## Linux

`dependency.json`. The window layer is X11. `cui.c` is compiled as C with
`-std=gnu99`, and a program links `libcui.a` with `-lX11 -ldl -lm
-lpthread`. Building needs the X11 development headers on the host,
`libx11-dev` on Ubuntu. CUI loads OpenGL when a window opens, so linking
needs no OpenGL package. Emoji draw only when the host has an emoji font.

The previous CUI 1.3.1 profile was verified on Ubuntu 24.04 arm64 and
x86_64 with `make check`, which draws off screen and needs no X server.
The experimental revision has not been run on Linux. A window has not been opened
on Linux.

## Browser

`dependency-wasm.json`, prepared with `CC=emcc AR=emar`. Emscripten
compiles `cui.c` with `-m64 -Os -fsigned-char -sSUPPORT_LONGJMP=emscripten
-sUSE_SDL=2 -DCUI_PLATFORM_SDL2`. The first four flags are those of x2c's
browser runtime. `CUI_PLATFORM_SDL2` selects CUI's SDL2 window layer, and
`-sUSE_SDL=2` supplies Emscripten's SDL2 port, which Emscripten downloads
and builds on first use. SDL2 is under the zlib license, reproduced in
`LICENSES/sdl2-zlib.txt`. The SDL2 version is the one the installed
Emscripten ships; this package does not pin it.

The browser-specific `patches/web-opengl-es.patch` is applied to
`src/platform/cui_app_sdl2.c`. CUI's SDL2 layer asks for a desktop OpenGL
3.3 core context, which a browser does not offer. Under `__EMSCRIPTEN__`
the patch asks for OpenGL ES 3.0, which is WebGL 2. CUI's OpenGL renderer
already writes ES 3.0 shaders when it sees an ES context. Without the
patch CUI falls back to its software renderer, which on a high-density
display draws into one quarter of the canvas.

A program links with `-sJSPI -sASYNCIFY_IGNORE_INDIRECT=1`, so that waiting
for input returns control to the browser without marking synchronous
`invoke_*` exception wrappers as suspending. Nested wrappers otherwise
raise `SuspendError: trying to suspend JS frames` in Emscripten 6.0.13,
including the gallery's table sort. Gallery and stress callbacks are
synchronous; their frame loops call the asynchronous waits outside those
callbacks. Explicit async imports retain their JSPI marking.
The programs also link with `-sMIN_WEBGL_VERSION=2 -sMAX_WEBGL_VERSION=2
-sGL_ENABLE_GET_PROC_ADDRESS=1`. They need a browser with 64-bit
WebAssembly memory, JavaScript Promise Integration, and WebGL 2.

Revision `a5c9ef5efc39` was built on 2026-11-16 with Emscripten 6.0.13
and Node 26.12.1. `make web web-check` builds gallery and stress and
renders all 31 gallery pages with zero empty pages using the browser's JSPI
settings. Headless Chromium checks covered the four new pages, keyboard
waveform seeking, the selection bar, table sorting by name/role/status, and
both animated stress modes. The website's demo installer also copied the
artifacts into its standalone hidden routes. Safari, Firefox, native OS
clipboard access, and native IME/window-state behavior were not tested.

The new clipboard test uses platform hooks and checks owned String lifetime.
The wheel test checks both axes and one-time consumption. Voice resampling
checks peaks and independent result storage. The component input contract is shared by native and browser profiles. Capture
preserves input-call order and borrowed text lifetime. Dispatch accepts key,
committed-text, and focus events before component submission; callbacks are
synchronous and must not build UI or recursively inject input. It does not add
IME composition or pair physical keys with separately delivered committed text.
The host must reconcile draw-time focus/layer changes before its next event.

On 2026-11-17, the shared component patch compiled natively on macOS arm64.
Its focused raw tests cover eligible and invalid focus targets, revocation,
physical versus actionable held state, repeat metadata, inactive input,
reactivation, unhandled Tab navigation, and modal-popover eligibility at both
completed-frame and next-frame input boundaries. Unrelated root popovers remain
excluded by the modal. The parent integration records
application and web validation separately.

## Bundled third-party content

All of this is compiled into `libcui.a` from the pinned archive:

| Component | License | Notice |
| --- | --- | --- |
| Inter font, subset | SIL Open Font License 1.1 | `LICENSES/inter-OFL-1.1.txt` |
| Geist and Geist Mono fonts, subset | SIL Open Font License 1.1 | `LICENSES/geist-OFL-1.1.txt` |
| Lucide icon font | ISC | `LICENSES/lucide-ISC.txt` |
| Unicode 17 emoji, bidi, and joining data | Unicode License V3 | `LICENSES/unicode-V3.txt` |
| stb_truetype, stb_image, stb_image_write, stb_rect_pack | public domain or MIT | in the upstream sources |

The fonts are embedded as data and are not distributed as separate font
files. The project admitted the SIL Open Font License 1.1 and the Unicode
License V3 for this profile on 2026-11-10; `packages/LICENSE-POLICY.md` does
not list either by name.

## Foreign-declaration limits

- x2c does not expand CUI's lowercase `cui_name(...)` macros, which supply
  named arguments and block scopes in C. The package's methods and their
  method forms, such as `ui.button("Add", variant: primary)` and
  `ui.row (gap: 8) { ... }`, replace them.
- x2c does not check C macro constants such as `CUI_COLOR_ACCENT`. A
  misspelled one is reported by the C compiler, not by x2c.
- A header string macro such as `CUI_ICON_CHECK` is a value. It cannot be
  written next to a string literal for C to join.
- A variadic function, such as `cui_textf`, has no generated method. The
  four that format text have hand-written methods that take x2c values,
  such as `ui.textf("%d items", n)`; the C functions remain callable as
  C.
