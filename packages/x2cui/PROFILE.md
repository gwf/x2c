# CUI 1.3.1 profile

- Upstream release: tag `v1.3.1` of `yappologistic/CUI`, reported by the
  header as CUI 1.3.1
- Source archive: `https://github.com/yappologistic/CUI/archive/refs/tags/v1.3.1.tar.gz`
- Source archive SHA-256:
  `d925329943d377b748995efed5603b47ff469eb956c297244b562a73b74641d5`
- Public header SHA-256 values: `headers.sha256` pins `cui/cui.h`,
  `cui/cui_app.h`, `cui/cui_icons.h`, and `cui/cui_render.h`
- License: MIT, reproduced verbatim in `LICENSES/cui-1.3.1-MIT.txt`.
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

Because both patches add declarations to `cui.h`, `headers.sha256` pins
the patched header. The browser profile applies a third patch; see
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
compiles CUI from this pinned source and `src/cui-1.3.h` rejects another
minor version, so the records a program fills always match the archive.

## macOS

`dependency-darwin.json`. The window layer is Cocoa and is Objective-C, so
`cui.c` is compiled with `-x objective-c -fobjc-arc -D_DARWIN_C_SOURCE`.
A program links `libcui.a` with the Cocoa, QuartzCore, and OpenGL
frameworks. Apple's frameworks are part of the system and are not
redistributed. Verified on macOS arm64.

## Linux

`dependency.json`. The window layer is X11. `cui.c` is compiled as C with
`-std=gnu99`, and a program links `libcui.a` with `-lX11 -ldl -lm
-lpthread`. Building needs the X11 development headers on the host.

This profile has not been built or run. The package is not in `PACKAGES`
in `packages/Makefile` until it has been.

## Browser

`dependency-wasm.json`, prepared with `CC=emcc AR=emar`. Emscripten
compiles `cui.c` with `-m64 -Os -fsigned-char -sSUPPORT_LONGJMP=emscripten
-sUSE_SDL=2 -DCUI_PLATFORM_SDL2`. The first four flags are those of x2c's
browser runtime. `CUI_PLATFORM_SDL2` selects CUI's SDL2 window layer, and
`-sUSE_SDL=2` supplies Emscripten's SDL2 port, which Emscripten downloads
and builds on first use. SDL2 is under the zlib license, reproduced in
`LICENSES/sdl2-zlib.txt`. The SDL2 version is the one the installed
Emscripten ships; this package does not pin it.

A third patch, `patches/web-opengl-es.patch`, is applied to
`src/platform/cui_app_sdl2.c`. CUI's SDL2 layer asks for a desktop OpenGL
3.3 core context, which a browser does not offer. Under `__EMSCRIPTEN__`
the patch asks for OpenGL ES 3.0, which is WebGL 2. CUI's OpenGL renderer
already writes ES 3.0 shaders when it sees an ES context. Without the
patch CUI falls back to its software renderer, which on a high-density
display draws into one quarter of the canvas.

A program links with `-sJSPI`, so that waiting for input returns control
to the browser, and with `-sMIN_WEBGL_VERSION=2 -sMAX_WEBGL_VERSION=2
-sGL_ENABLE_GET_PROC_ADDRESS=1`. It needs a browser with 64-bit
WebAssembly memory, JavaScript Promise Integration, and WebGL 2.

Verified on 2026-11-10 with Emscripten 6.0.13 and SDL 2.32.10: under
Node 26 for off-screen drawing, and in the Chromium of the Claude desktop
app's browser pane for the window. Not run in Safari or Firefox.

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
files. Gary admitted the SIL Open Font License 1.1 and the Unicode License
V3 for this profile on 2026-11-10; `packages/LICENSE-POLICY.md` does not
list either by name.

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
