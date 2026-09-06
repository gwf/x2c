# raylib client

This experimental package provides an x2c interface to raylib 6.0 built for
`PLATFORM_MEMORY`: raylib renders into main memory with no display and no
GPU, so an `Image` is the whole product and an exported PNG is reproducible
byte for byte. `PROFILE.md` records the admitted build.

It is an importable package: `src/raylib.x` is its entry unit and every
public name compiles to `raylib__*`. raylib's own record types keep their own
spelling, so a program that names only those needs no `with` clause at all:

```x2c
import "raylib";

int main(void) {
  Image chart = Image.new(320, 120, Color.from_hex(0xf7f8fcff));
  defer chart.free();

  Vector2 origin = { 20, 100 }, step = { 60, -18 };
  for (int index = 0; index < 5; index++)
    chart.draw_circle(origin + step.scale(index), 6, BLUE);

  chart.draw_text(%"five points", 20, 12, 20, DARKGRAY);
  chart.export(%"chart.png");
  return 0;
}
```

`Image`, `Color`, `Vector2`, `Rectangle`, and every `RAYWHITE`-style constant
arrive through the published `src/raylib-6.0.h`. The package's own types,
`ImagePixels`, `RaylibText`, and `RaylibWindow`, are `raylib__*` names and
need `with` or the alias:
`import "raylib" with ImagePixels, RaylibText, RaylibWindow;`.

Build the package once with `make build`, then compile a consumer with
`--package-dir <packages>`, `--c-system-dir <prefix>/include`, and
`-I <prefix>/include`; the driver adds the package's `builds` and `src`
directories and links `builds/libraylib.a`. The `-I` is what lets x2c's own
collection read `raylib.h` and know that `Vector2` is a type.

## Images

`Image` methods replace raylib's in-out convention. Where C writes
`ImageBlurGaussian(&image, 4)`, x2c writes `image.blur_gaussian(4)`,
and the same shape covers `format`, `crop`, `alpha_crop`, `alpha_clear`,
`alpha_mask`, `alpha_premultiply`, `resize`, `resize_nearest`,
`resize_canvas`, `mipmaps`, `to_power_of_two`, `flip_vertical`,
`flip_horizontal`, `rotate`, `rotate_clockwise`,
`rotate_counterclockwise`, `tint`, `invert`, `grayscale`, `contrast`,
`brightness`, and `replace_color`. Each has a pointer receiver, so an
addressable `Image` is updated in place without copying its owned pointer.

Drawing methods (`clear`, `draw_pixel`, `draw_line`, `draw_circle`,
`draw_rectangle`, `draw_triangle`, `draw_polygon`, `draw_text`, `draw`)
return nothing, because they change pixels the `Image` already points at.

`Image.new`, the `GenImage*` family (`gradient_linear`, `gradient_radial`,
`gradient_square`, `checked`, `white_noise`, `perlin_noise`, `cellular`),
and `Image.load` produce an image; `image.free()` releases it, and
`defer image.free()` belongs on the line after. Scope owns no raylib memory.

`Image.load` raises `<io-fail>` carrying `LoadImage` and the path when raylib
cannot read the file; a missing image file is a failure, not an absence.
`Image.export` raises the same cause for `ExportImage`. Generation raises
`<alloc-fail>` with raylib's own operation name.

`draw_polygon` takes a `List` of `(x y)` pairs, because raylib has no polygon
record, and fills it with `ImageDrawTriangleFan`, so the polygon must be
convex. `draw_polygon_lines` strokes the closed outline. raylib truncates its
triangle edge steps to integers, so vertices on whole pixels fill cleanest.
Fewer than three points, or an element that is not a pair, raises
`<bad-arg>`.

## Pixels

`image.pixels()` returns an `ImagePixels` that owns one `LoadImageColors`
buffer -- a copy of the image's colors as RGBA, whatever the image's own
format. Index it to read and write:

```x2c
ImagePixels pixels = photo.pixels();
defer pixels.free();

for (int index = 0; index < pixels.len(); index++)
  if (pixels[index].r < 96) pixels[index] = Color.rgba(0, 0, 0, 0);

Image cleaned = pixels.image();
defer cleaned.free();
```

The ownership rule: `ImagePixels` owns the buffer and nothing else does. The
image it came from is untouched, and freeing that image does not affect the
pixels. `pixels.image()` returns a new RGBA image holding its own copy, so
the caller frees the pixels and the image separately, in either order.
`pixels.free()` is idempotent and returns NULL; any later index or `len`
raises `<bad-state>`. An index outside `0 .. len() - 1` raises `<bad-arg>`
carrying the index and the count. `pixels.data`, `pixels.width`, and
`pixels.height` are public fields for callers that want the raw `Color *`;
that pointer is valid until `free`.
`pixels.at(x, y)` and `pixels.put(x, y, color)` provide checked two-dimensional
access. `image.color_at(x, y)` uses the same bounds rule.

## Colors, vectors, and text

`Color.rgb` and `Color.rgba` build a color from named components;
`Color.from_hex` and `Color.from_hsv` are raylib's `GetColor` and
`ColorFromHSV`. `fade`, `tint`, `brightness`, `contrast`, `alpha`, `blend`,
`lerp`, `normalize`, `to_hsv`, `to_int`, and `equal` are the rest of raylib's
color operations under x2c names.

`Vector2` carries raylib's arithmetic behind operators through the package's
own `RaylibVector(T)` protocol: `a + b`, `a - b`, `a * b`, `-a`, and `a == b`
work, alongside `scale`, `len`, `distance`, `normalize`, and `lerp`.
`Vector3` and `Vector4` have no methods here; `Color.normalize` and
`Color.to_hsv` still return them, and raymath is on the raw path.

`RaylibText.width(text, size)` is raylib's `MeasureText` and
`RaylibText.size(text, size, spacing)` is `MeasureTextEx` over the default
font. The two do not agree by default: `MeasureText` derives its spacing from
the font size, so pass raylib's own spacing to `size` when you need the pair
to match.

## The renderer this profile needs

raylib's text operations read a default font that only `InitWindow` loads,
and its glyph texture is only valid once the software renderer has started.
The package owns that process-global state: `draw_text`, `RaylibText.width`,
and `RaylibText.size` start the renderer on first use and close it at exit.
The package captures raylib's main trace warnings and errors for raised
causes. The pinned software renderer also prints one `RLSW` initialization
line directly when text first starts it; raylib's trace callback cannot
suppress that line.

`RaylibWindow` puts that same process-global window under a caller's
control, so an `Image` can be shown rather than exported. Under this profile
its methods link and run but nothing appears, because no window backend is
compiled in; `make run-interactive` rebuilds the package against
`dependency-desktop.json`, which compiles GLFW and links the macOS window
frameworks, and there the window is real. Everything else in this package
behaves identically on both.

Only one `RaylibWindow` may be open. `upload` rejects an invalid texture,
`native()` returns a borrowed `Texture2D *` until the next upload or close,
and opening a second window raises `<bad-state>` rather than repurposing the
first handle.

Nothing here is reentrant: raylib's renderer, default font, and trace log are
process-global. Use one thread.

## No Lisp surface

An `Image` is an opaque native buffer and `ImagePixels` owns another;
neither is a value Lisp can take apart, and a binding would have to load,
convert, and free on every call. This package has no Lisp bindings.

## Examples

`examples/climate-trends.x` is the self-contained short application (`make
short-example`). It renders seven temperatures from x2c Lists into a 720x320
PNG with lines, markers, labels, and text. Its source shows the complete
ordinary drawing path and contains no pointer arithmetic, buffer, or status
code.

`examples/texture-sheet.x` is the broader application (`make example`). It
generates four procedural tiles, writes each to disk, reads them back with
`Image.load`, walks the noise tile's pixels and makes the dark ones
transparent, composites everything onto one sheet with captions centred by
measured width, draws a polygon badge, and reports what a missing tile does.

## Native API

`src/raylib-6.0.h` includes the real upstream header and rejects a different
release. Importing the package is enough to reach it: `tests/test-raw-api.x`
says only `import "raylib"` and then calls `ImageDrawTriangleEx`,
`LoadImagePalette`, and `GetPixelDataSize` directly. Use it for interpolated
triangles, palettes, raw and memory image loading, image-to-code export,
codepoint and text utilities, and anything else the admitted profile
compiles.

Everything outside that profile -- models, audio, and every non-PNG format
-- is not merely unwrapped, it is not in the archive. `PROFILE.md` lists
what each profile enables.

## Build and test

`make prepare` downloads, verifies, and builds raylib in the shared
dependency cache. `make run` and `make test` prepare it automatically when
absent and reuse it when present. Set `X2C_DEPS_DIR` to move the shared
cache, or `RAYLIB_PREFIX` to diagnose another compatible installation.

```sh
make verify-headers
make test
make run
make verify
```

`make verify` runs both examples and both suites and then checks the exact
PNG signature, geometry, and hash of the two sheets.

```sh
make run-interactive
```

opens a window instead. It prepares the second profile, rebuilds the package
against it, and runs `examples/live-chart.x`, which shows the larger weekly
chart from `examples/chart.x`. It needs a graphical login on the Mac, since
the process has to reach WindowServer. Run `make build` afterwards to restore
the memory-rendering profile.

The client, tests, and examples are licensed under
[Apache-2.0](../../LICENSE).
raylib retains the zlib terms reproduced under `LICENSES/`, as does the GLFW
copy vendored inside it and used only by the windowed profile. The dependency
is admitted under the policy in `../LICENSE-POLICY.md`.
