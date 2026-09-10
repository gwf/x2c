# raylib 6.0 profile

- Upstream commit: `dbc56a87da87d973a9c5baa4e7438a9d20121d28`, reported by
  the header as raylib 6.0
- Source archive: `https://github.com/raysan5/raylib/archive/dbc56a87da87d973a9c5baa4e7438a9d20121d28.tar.gz`
- Source archive SHA-256:
  `81b06ce7c19cf3b634b0271c23c361ba6ad8bf45fb8b036abbfeb4260ec1e126`
- `include/raylib.h` SHA-256:
  `047e7255f93f8c34039cab906ad76136706b5c7b4c5b5b065d84141963ee9b6b`
- `include/raymath.h` SHA-256:
  `2b8b88f5b3f748e3cf8bdbfb8b7da23a76c755dc40f9c6e455bfc09b3669d028`
- License: zlib/libpng, reproduced verbatim in
  `LICENSES/raylib-6.0-zlib.txt` (SHA-256
  `ade2bfa075d00a3e4e2d64341e9fc2dfd0565ab491fd9c7b06ab3f2a693692d6`)

The native sources receive the hash-checked
[image/text backport](patches/README.md). The published headers and build
features remain those of 6.0. Preparing this package also requires `patch`.

## Default build profile

Three raylib translation units are compiled into `libraylib.a`: `rcore.c`,
`rtextures.c`, and `rtext.c`. `rcore.c` includes the `PLATFORM_MEMORY`
backend from `platforms/rcore_memory.c` and the software renderer in
`external/rlsw.h`. Every other raylib module -- models, audio, shapes, and
rlgl's GPU backends -- is left out of the archive.

Each is built with `-O2 -std=c99 -D_GNU_SOURCE -fno-strict-aliasing`,
`-Wall -Wno-missing-braces -Werror=pointer-arith`, and these feature macros:

- `PLATFORM_MEMORY` and `GRAPHICS_API_OPENGL_SOFTWARE`: no display, no
  window system, no GPU. raylib renders into main memory, which is why an
  exported PNG is reproducible byte for byte and why the package can be
  tested against exact expected bytes.
- `EXTERNAL_CONFIG_FLAGS`: `src/config.h`'s defaults are off, so the list
  below is the whole enabled surface.
- `SUPPORT_MODULE_RTEXTURES`, `SUPPORT_MODULE_RTEXT`,
  `SUPPORT_DEFAULT_FONT`: image and text operations with raylib's built-in
  font.
- `SUPPORT_FILEFORMAT_PNG`: PNG is the only image file format that loads or
  saves.
- `SUPPORT_FILEFORMAT_TTF`: load TrueType fonts for smooth image text.
- `SUPPORT_IMAGE_EXPORT`: `ExportImage` writes files.
- `SUPPORT_IMAGE_GENERATION`: the `GenImage*` gradient, checker, noise, and
  cellular generators.
- `UNICODE`: UTF-8 codepoint handling in the text module.

Disabled by leaving the macro out: every non-PNG file format (BMP, TGA, JPG,
GIF, PIC, PNM, PSD, QOI, DDS, PKM, KTX, PVR, ASTC, HDR), SVG rasterization,
other font file loading (BDF, FNT), image manipulation extras that are in
other modules, and all of models, meshes, materials, animation, audio,
shapes, VR, camera, gestures, gamepad, and automation events.

`InitWindow` exists in this profile and starts raylib's software renderer;
`src/raylib.x` calls it once, on the first text operation, because raylib's
default font is loaded there and its glyph texture is only valid afterwards.
There is no display and no event loop.

## Linkage and dependencies

- Static: `libraylib.a`, the three objects above, linked by full path so it
  does not collide with the package's own `builds/libraylib.a`.
- Linked dependencies: the platform C runtime, `libm`, and `-pthread`. No
  windowing system, no OpenGL, no audio backend, and no platform framework.
- Upstream source stays in the dependency cache. The local
  [image/text patch](patches/README.md) is applied during preparation.
  `src/raylib-6.0.h` includes the prepared upstream header and rejects a
  different release.

## Bundled third-party code

The compiled modules embed single-file libraries from raylib's own
`src/external/`: `rlsw`, `stb_image`, `stb_image_write`,
`stb_image_resize2`, `stb_perlin`, `stb_truetype`, `stb_rect_pack`, `sdefl`,
and `sinfl`. Their notices remain in the pinned raylib source distribution;
the package reproduces the licence files required by its admitted profiles,
including `LICENSES/rlsw-MIT.txt` for the memory renderer.

`dependency.json` is the machine-readable source and build record.
`make verify-headers` checks both admitted header hashes, and `make verify`
additionally checks the exact PNG geometry both examples produce.

## The optional windowed profile

`dependency-desktop.json` builds the same pinned raylib release with a window
backend, so `make run-interactive` can show an `Image` on screen. It is not
what `make packages-check` builds, because a window needs a WindowServer
connection; the automated package checks run without a graphical login.

- Profile: `static-desktop-glfw-opengl33`.
- Compile-time: `-DPLATFORM_DESKTOP_GLFW -DGRAPHICS_API_OPENGL_33`, plus the
  memory profile's `SUPPORT_*` set except `SUPPORT_FILEFORMAT_TTF`, and
  `SUPPORT_MODULE_RSHAPES`.
- Modules: `rcore.c`, `rshapes.c`, `rtextures.c`, `rtext.c`, and `rglfw.c` —
  five archive members. `rmodels.c` and `raudio.c` stay uncompiled, so there
  is no 3D and no audio in the claim or the link line.
- `rglfw.c` compiles as Objective-C (`-x objective-c`, before the input, and
  `-U_GNU_SOURCE`), which is what raylib's own `src/Makefile` does on macOS.
- Header hashes are the two above, unchanged: the profile changes the
  compiled backend, not the API.
- Linked dependencies add `-framework OpenGL -framework Cocoa -framework
  IOKit -framework CoreVideo`. Those come from the macOS SDK and are not
  redistributed; building and running remain subject to Apple's SDK and
  platform terms, and nothing from the SDK is copied into this repository.
- Bundled third-party code adds GLFW, vendored inside raylib at
  `src/external/glfw` under the zlib licence, retained as
  `LICENSES/glfw-zlib.txt`.

The two profiles are separate entries in the shared dependency cache, keyed
on the manifest bytes, so preparing one neither invalidates nor replaces the
other. macOS remains the only platform this package claims; the same profile
on Linux would need X11 or Wayland development headers, which is a different
intake.
