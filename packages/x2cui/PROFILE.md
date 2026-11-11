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

The native source receives no patch.

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
  named arguments and block scopes in C. The package's methods and `$cui.`
  macros replace them.
- x2c does not check C macro constants such as `CUI_COLOR_ACCENT`. A
  misspelled one is reported by the C compiler, not by x2c.
- A header string macro such as `CUI_ICON_CHECK` is a value. It cannot be
  written next to a string literal for C to join.
- Variadic functions, such as `cui_textf`, have no method and are called
  as C.
