/*  raylib.x -- raylib images with ordinary x2c methods.

    This package admits raylib's PLATFORM_MEMORY profile, which renders in
    software with no display and no GPU, so an Image is the whole product and
    an exported PNG is byte-for-byte reproducible.

    Image keeps raylib's names and semantics while replacing its in-out
    convention: `ImageBlurGaussian(&image, 4)` becomes `image.blur(4)`.
    ImagePixels owns one `LoadImageColors` buffer so pixels can be read and
    written by index. Vector2 keeps raylib's arithmetic behind operators.

    This unit is the `raylib` package entry: `import "raylib"` reaches every
    name above `#pragma private` as `raylib__*`. The vendored `raylib-6.0.h`
    stays public because these methods take raylib's own record types, and it
    is also the raw API for everything below.
 */

#include "raylib-6.0.h"
#include <math.h>

typedef enum RaylibText {
  RAYLIBTEXT_NAMESPACE
} RaylibText;

typedef struct ImagePixels {
  Color *data;
  int width;
  int height;
} *ImagePixels;

typedef struct RaylibWindow *RaylibWindow;

protocol RaylibVector(T) {
  T T.add(T, T);
  T T.sub(T, T);
  T T.mul(T, T);
  T T.neg(T);
  int T.equal(T, T);
}

protocol ImagePixelIndex(T) {
  associated Key = int;
  associated Value = Color;

  Value T.getindex(T, Key);
  Value T.setindex(T, Key, Value);
}

inline Vector2 Vector2.add(Vector2 a, Vector2 b) {
  return (Vector2) { a.x + b.x, a.y + b.y };
}

inline Vector2 Vector2.sub(Vector2 a, Vector2 b) {
  return (Vector2) { a.x - b.x, a.y - b.y };
}

inline Vector2 Vector2.mul(Vector2 a, Vector2 b) {
  return (Vector2) { a.x * b.x, a.y * b.y };
}

inline Vector2 Vector2.neg(Vector2 vector) {
  return (Vector2) { -vector.x, -vector.y };
}

inline int Vector2.equal(Vector2 a, Vector2 b) {
  return fabsf(a.x - b.x) <= 0.000001f && fabsf(a.y - b.y) <= 0.000001f;
}

inline Vector2 Vector2.scale(Vector2 vector, float scale) {
  return (Vector2) { vector.x * scale, vector.y * scale };
}

inline float Vector2.len(Vector2 vector) {
  return sqrtf(vector.x * vector.x + vector.y * vector.y);
}

inline float Vector2.distance(Vector2 a, Vector2 b) {
  return (a - b).len();
}

inline Vector2 Vector2.normalize(Vector2 vector) {
  float length = vector.len();
  return length ? vector.scale(1.0f / length) : vector;
}

inline Vector2 Vector2.lerp(Vector2 a, Vector2 b, float amount) {
  return a + (b - a).scale(amount);
}

protocol RaylibVector(Vector2);

inline Color Color.rgb(int red, int green, int blue) {
  return (Color) {
    (unsigned char) red, (unsigned char) green, (unsigned char) blue, 255
  };
}

inline Color Color.rgba(int red, int green, int blue, int alpha) {
  return (Color) {
    (unsigned char) red, (unsigned char) green,
    (unsigned char) blue, (unsigned char) alpha
  };
}

$x2c.foreign.alias(GetColor) inline Color Color.from_hex(unsigned int rgba);

$x2c.foreign.alias(ColorFromHSV)
inline Color Color.from_hsv(float hue, float saturation, float value);

$x2c.foreign.alias(ColorIsEqual) inline bool Color.equal(Color a, Color b);

$x2c.foreign.alias(Fade) inline Color Color.fade(Color color, float alpha);

$x2c.foreign.alias(ColorToInt) inline int Color.to_int(Color color);

$x2c.foreign.alias(ColorNormalize) inline Vector4 Color.normalize(Color color);

$x2c.foreign.alias(ColorToHSV) inline Vector3 Color.to_hsv(Color color);

$x2c.foreign.alias(ColorTint) inline Color Color.tint(Color color, Color tint);

$x2c.foreign.alias(ColorBrightness)
inline Color Color.brightness(Color color, float factor);

$x2c.foreign.alias(ColorContrast)
inline Color Color.contrast(Color color, float contrast);

$x2c.foreign.alias(ColorAlpha)
inline Color Color.alpha(Color color, float alpha);

$x2c.foreign.alias(ColorAlphaBlend)
inline Color Color.blend(Color destination, Color source, Color tint);

$x2c.foreign.alias(ColorLerp)
inline Color Color.lerp(Color a, Color b, float amount);

$x2c.foreign.alias(IsImageValid) inline bool Image.valid(Image image);

$x2c.foreign.alias(UnloadImage) inline void Image.free(Image image);

$x2c.foreign.alias(ImageCopy) inline Image Image.copy(Image image);

$x2c.foreign.alias(ImageFromImage)
inline Image Image.crop_copy(Image image, Rectangle rectangle);

$x2c.foreign.alias(ImageFromChannel)
inline Image Image.channel(Image image, int selected);

$x2c.foreign.alias(ImageFormat)
inline void Image.format(Image *image, int new_format);

$x2c.foreign.alias(ImageToPOT)
inline void Image.to_power_of_two(Image *image, Color fill);

$x2c.foreign.alias(ImageCrop)
inline void Image.crop(Image *image, Rectangle rectangle);

$x2c.foreign.alias(ImageAlphaCrop)
inline void Image.alpha_crop(Image *image, float threshold);

$x2c.foreign.alias(ImageAlphaClear)
inline void Image.alpha_clear(Image *image, Color color, float threshold);

$x2c.foreign.alias(ImageAlphaMask)
inline void Image.alpha_mask(Image *image, Image mask);

$x2c.foreign.alias(ImageAlphaPremultiply)
inline void Image.alpha_premultiply(Image *image);

$x2c.foreign.alias(ImageBlurGaussian)
inline void Image.blur_gaussian(Image *image, int size);

$x2c.foreign.alias(ImageResize)
inline void Image.resize(Image *image, int width, int height);

$x2c.foreign.alias(ImageResizeNN)
inline void Image.resize_nearest(Image *image, int width, int height);

$x2c.foreign.alias(ImageResizeCanvas)
inline void Image.resize_canvas(
  Image *image, int width, int height, int offset_x, int offset_y, Color fill);

$x2c.foreign.alias(ImageMipmaps)
inline void Image.mipmaps(Image *image);

$x2c.foreign.alias(ImageFlipVertical)
inline void Image.flip_vertical(Image *image);

$x2c.foreign.alias(ImageFlipHorizontal)
inline void Image.flip_horizontal(Image *image);

$x2c.foreign.alias(ImageRotate)
inline void Image.rotate(Image *image, int degrees);

$x2c.foreign.alias(ImageRotateCW)
inline void Image.rotate_clockwise(Image *image);

$x2c.foreign.alias(ImageRotateCCW)
inline void Image.rotate_counterclockwise(Image *image);

$x2c.foreign.alias(ImageColorTint)
inline void Image.tint(Image *image, Color color);

$x2c.foreign.alias(ImageColorInvert)
inline void Image.invert(Image *image);

$x2c.foreign.alias(ImageColorGrayscale)
inline void Image.grayscale(Image *image);

$x2c.foreign.alias(ImageColorContrast)
inline void Image.contrast(Image *image, float contrast);

$x2c.foreign.alias(ImageColorBrightness)
inline void Image.brightness(Image *image, int brightness);

$x2c.foreign.alias(ImageColorReplace)
inline void Image.replace_color(Image *image, Color color, Color replacement);

$x2c.foreign.alias(GetImageAlphaBorder)
inline Rectangle Image.alpha_border(Image image, float threshold);

Color Image.color_at(Image image, int x, int y) {
  if (x < 0 || y < 0 || x >= image.width || y >= image.height) {
    raise %(bad-arg (library "raylib") (operation "image color")
            (x $x) (y $y) (width ${image.width}) (height ${image.height}));
  }
  return GetImageColor(image, x, y);
}

inline void Image.clear(Image image, Color color) {
  ImageClearBackground(&image, color);
}

inline void Image.draw_pixel(Image image, Vector2 position, Color color) {
  ImageDrawPixelV(&image, position, color);
}

inline void Image.draw_pixel_xy(Image image, int x, int y, Color color) {
  ImageDrawPixel(&image, x, y, color);
}

inline void Image.draw_line(
  Image image, Vector2 start, Vector2 end, int thickness, Color color) {
  ImageDrawLineEx(&image, start, end, thickness, color);
}

inline void Image.draw_thin_line(
  Image image, Vector2 start, Vector2 end, Color color) {
  ImageDrawLineV(&image, start, end, color);
}

inline void Image.draw_circle(
  Image image, Vector2 center, int radius, Color color) {
  ImageDrawCircleV(&image, center, radius, color);
}

inline void Image.draw_circle_lines(
  Image image, Vector2 center, int radius, Color color) {
  ImageDrawCircleLinesV(&image, center, radius, color);
}

inline void Image.draw_rectangle(
  Image image, Rectangle rectangle, Color color) {
  ImageDrawRectangleRec(&image, rectangle, color);
}

inline void Image.draw_rectangle_xy(
  Image image, int x, int y, int width, int height, Color color) {
  ImageDrawRectangle(&image, x, y, width, height, color);
}

inline void Image.draw_rectangle_lines(
  Image image, Rectangle rectangle, int thickness, Color color) {
  ImageDrawRectangleLines(&image, rectangle, thickness, color);
}

inline void Image.draw_triangle(
  Image image, Vector2 first, Vector2 second, Vector2 third, Color color) {
  ImageDrawTriangle(&image, first, second, third, color);
}

inline void Image.draw(
  Image image, Image source, Rectangle source_rectangle,
  Rectangle destination_rectangle, Color tint) {
  ImageDraw(&image, source, source_rectangle, destination_rectangle, tint);
}

/** Draws `text` into `image`, loading raylib's default font on first use. */
void Image.draw_text(
  Image image, String text, int x, int y, int size, Color color);

/** Fills the convex polygon `points`, a List of `(x y)` coordinate pairs. */
void Image.draw_polygon(Image image, List points, Color color);

/** Strokes the closed outline of the polygon `points`. */
void Image.draw_polygon_lines(
  Image image, List points, int thickness, Color color);

/** Returns a `width` by `height` image filled with one color. */
Image Image.new(int width, int height, Color color);

/** Returns a linear gradient image; `direction` is in degrees, 0 vertical. */
Image Image.gradient_linear(
  int width, int height, int direction, Color start, Color end);

/** Returns a radial gradient image from `inner` at the center to `outer`. */
Image Image.gradient_radial(
  int width, int height, float density, Color inner, Color outer);

/** Returns a square gradient image from `inner` at the center to `outer`. */
Image Image.gradient_square(
  int width, int height, float density, Color inner, Color outer);

/** Returns a checkerboard of `checks_x` by `checks_y` alternating cells. */
Image Image.checked(
  int width, int height, int checks_x, int checks_y, Color first,
  Color second);

/** Returns white noise where `factor` is the fraction of white pixels. */
Image Image.white_noise(int width, int height, float factor);

/** Returns Perlin noise sampled at `offset_x`, `offset_y` with `scale`. */
Image Image.perlin_noise(
  int width, int height, int offset_x, int offset_y, float scale);

/** Returns a cellular-noise image whose cells are `tile_size` across. */
Image Image.cellular(int width, int height, int tile_size);

/** Reads an image file from disk, raising `<io-fail>` when raylib cannot. */
Image Image.load(String path);

/** Writes `image` to `path`, choosing the format from its extension. */
void Image.export(Image image, String path);

/** Copies `image`'s pixels into an owned RGBA buffer the caller frees. */
ImagePixels Image.pixels(Image image);

/** Returns how many pixels `pixels` holds. */
int ImagePixels.len(ImagePixels pixels);

/** Returns the pixel at `index`, raising `<bad-arg>` when out of range. */
Color ImagePixels.getindex(ImagePixels pixels, int index);

/** Stores `color` at `index`, raising `<bad-arg>` when out of range. */
Color ImagePixels.setindex(ImagePixels pixels, int index, Color color);

/** Returns the pixel at `(x, y)`, raising `<bad-arg>` when out of range. */
Color ImagePixels.at(ImagePixels pixels, int x, int y);

/** Stores `color` at `(x, y)`, raising `<bad-arg>` when out of range. */
Color ImagePixels.put(ImagePixels pixels, int x, int y, Color color);

/** Returns a new RGBA image holding a copy of these pixels. */
Image ImagePixels.image(ImagePixels pixels);

/** Releases the native pixel buffer; idempotent, and returns NULL. */
ImagePixels ImagePixels.free(ImagePixels pixels);

/** Returns the width `text` occupies in the default font at `size`. */
int RaylibText.width(String text, int size);

/** Returns the size `text` occupies in the default font with `spacing`. */
Vector2 RaylibText.size(String text, int size, float spacing);

/*  A window shows an Image on screen. Under the admitted PLATFORM_MEMORY
    profile these methods link and run but nothing appears, because that
    profile compiles no window backend; `dependency-desktop.json` builds the
    GLFW profile that does. Everything above works identically on both. */

/** Opens the process's window, raising `<init-fail>` if it cannot. */
RaylibWindow RaylibWindow.open(int width, int height, String title);

/** Uploads `image` as the window's displayed texture, replacing any prior. */
void RaylibWindow.upload(RaylibWindow window, Image image);

/** Draws the uploaded image for one frame. */
void RaylibWindow.present(RaylibWindow window);

/** True once the user has asked to close the window. */
int RaylibWindow.should_close(RaylibWindow window);

/** Caps the frame rate; 0 leaves it uncapped. */
void RaylibWindow.target_fps(RaylibWindow window, int fps);

/** Returns the borrowed uploaded texture, valid until upload or close. */
Texture2D *RaylibWindow.native(RaylibWindow window);

/** Closes the window and its texture; idempotent, and returns NULL. */
RaylibWindow RaylibWindow.close(RaylibWindow window);

protocol ImagePixelIndex(ImagePixels);

#pragma private

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*  raylib's text operations read the default font, which only InitWindow
    loads and whose glyph texture only the software renderer validates. The
    package owns that process-global renderer: it starts on the first text
    operation and closes at exit, so no caller manages a window that this
    display-less profile does not have. */
static int _raylib_renderer_started = 0;
static int _raylib_exit_registered = 0;
static int _raylib_trace_started = 0;
static char _raylib_trace_message[1024];

/*  RaylibWindow is the same process-global window under a caller's control,
    so there is one of it and closing it releases the texture it uploaded. */
struct RaylibWindow {
  Texture2D texture;
  int opened;
  int uploaded;
  int closed;
};

static struct RaylibWindow _raylib_window;

static void _raylib_renderer_close(void) {
  if (IsWindowReady()) CloseWindow();
  _raylib_renderer_started = 0;
}

static void _raylib_register_exit(void) {
  if (_raylib_exit_registered) return;
  atexit(_raylib_renderer_close);
  _raylib_exit_registered = 1;
}

static void _raylib_trace(int level, const char *text, va_list arguments) {
  if (level < LOG_WARNING || !text) return;
  vsnprintf(
    _raylib_trace_message, sizeof(_raylib_trace_message), text, arguments
  );
}

static void _raylib_trace_reset(void) {
  if (!_raylib_trace_started) {
    SetTraceLogCallback(_raylib_trace);
    _raylib_trace_started = 1;
  }
  _raylib_trace_message[0] = '\0';
}

static String _raylib_trace_detail(void) {
  return _raylib_trace_message[0]
    ? String.new(_raylib_trace_message) : %"raylib reported no detail";
}

static void _raylib_renderer(void) {
  if (_raylib_renderer_started) return;
  _raylib_trace_reset();
  if (!IsWindowReady()) InitWindow(1, 1, %"x2c raylib");
  if (!IsWindowReady()) {
    String message = _raylib_trace_detail();
    raise %(init-fail (library "raylib") (operation "InitWindow")
            (message $message));
  }
  _raylib_register_exit();
  _raylib_renderer_started = 1;
}

static void _raylib_window_live(RaylibWindow window, String operation) {
  if (!window || window.closed || !IsWindowReady()) {
    raise %(bad-state (library "raylib") (operation $operation)
            (reason "this window was closed"));
  }
}

RaylibWindow RaylibWindow.open(int width, int height, String title) {
  if (width <= 0 || height <= 0) {
    raise %(bad-arg (library "raylib") (operation "InitWindow")
            (width $width) (height $height));
  }
  if (_raylib_window.opened && !_raylib_window.closed) {
    raise %(bad-state (library "raylib") (operation "InitWindow")
            (reason "a RaylibWindow is already open"));
  }
  /* Text operations may already have started the 1x1 renderer window; this
     one replaces it, because raylib owns exactly one. */
  if (IsWindowReady()) CloseWindow();
  _raylib_renderer_started = 0;
  _raylib_trace_reset();
  InitWindow(width, height, title);
  if (!IsWindowReady()) {
    String message = _raylib_trace_detail();
    raise %(init-fail (library "raylib") (operation "InitWindow")
            (message $message)
            (width $width) (height $height));
  }
  _raylib_register_exit();
  _raylib_renderer_started = 1;
  _raylib_window = (struct RaylibWindow) { .opened = 1 };
  return &_raylib_window;
}

void RaylibWindow.upload(RaylibWindow window, Image image) {
  _raylib_window_live(window, %"upload");
  if (!image.valid()) {
    raise %(bad-arg (library "raylib") (operation "LoadTextureFromImage")
            (reason "this image holds no pixels"));
  }
  Texture2D loaded = LoadTextureFromImage(image);
  if (!IsTextureValid(loaded)) {
    raise %(init-fail (library "raylib")
            (operation "LoadTextureFromImage")
            (reason "raylib did not create a texture"));
  }
  if (window.uploaded) UnloadTexture(window.texture);
  window.texture = loaded;
  window.uploaded = 1;
}

void RaylibWindow.present(RaylibWindow window) {
  _raylib_window_live(window, %"present");
  BeginDrawing();
  ClearBackground(RAYWHITE);
  if (window.uploaded) DrawTexture(window.texture, 0, 0, WHITE);
  EndDrawing();
}

int RaylibWindow.should_close(RaylibWindow window) {
  _raylib_window_live(window, %"should_close");
  return WindowShouldClose() != 0;
}

void RaylibWindow.target_fps(RaylibWindow window, int fps) {
  _raylib_window_live(window, %"target_fps");
  SetTargetFPS(fps);
}

Texture2D *RaylibWindow.native(RaylibWindow window) {
  _raylib_window_live(window, %"native");
  if (!window.uploaded) {
    raise %(bad-state (library "raylib") (operation "native")
            (reason "this window has no uploaded image"));
  }
  return &window.texture;
}

RaylibWindow RaylibWindow.close(RaylibWindow window) {
  if (!window || window.closed) return NULL;
  if (window.uploaded && IsWindowReady()) UnloadTexture(window.texture);
  window.uploaded = 0;
  window.closed = 1;
  if (IsWindowReady()) CloseWindow();
  _raylib_renderer_started = 0;
  return NULL;
}

static Image _raylib_generated(
  Image image, String operation, int width, int height) {
  if (!image.valid()) {
    raise %(alloc-fail (library "raylib") (operation $operation)
            (width $width) (height $height));
  }
  return image;
}

static void _raylib_pixels_live(ImagePixels pixels, String operation) {
  if (!pixels || !pixels.data) {
    raise %(bad-state (library "raylib") (operation $operation)
            (reason "these image pixels were released"));
  }
}

static int _raylib_pixel_offset(
  ImagePixels pixels, int index, String operation) {
  _raylib_pixels_live(pixels, operation);
  if (index < 0 || index >= pixels.width * pixels.height) {
    raise %(bad-arg (library "raylib") (operation $operation) (index $index)
            (count ${pixels.width * pixels.height}));
  }
  return index;
}

static int _raylib_pixel_xy(
  ImagePixels pixels, int x, int y, String operation) {
  _raylib_pixels_live(pixels, operation);
  if (x < 0 || y < 0 || x >= pixels.width || y >= pixels.height) {
    raise %(bad-arg (library "raylib") (operation $operation)
            (x $x) (y $y) (width ${pixels.width})
            (height ${pixels.height}));
  }
  return y * pixels.width + x;
}

/*  raylib has no polygon record, so a polygon crosses as a List of (x y)
    pairs and is copied into the Vector2 span its own fan and line
    operations take. */
static Vector2 *_raylib_vertices(List points, String operation, int *count) {
  int total = points.len();
  if (total < 3) {
    raise %(bad-arg (library "raylib") (operation $operation) (points $total)
            (reason "a polygon needs at least three points"));
  }

  Vector2 *vertices = Scope.malloc((size_t) total * sizeof(Vector2));
  int index = 0;
  foreach(List point, points) {
    if (point.len() != 2) {
      raise %(bad-arg (library "raylib") (operation $operation)
              (reason "each polygon point is an (x y) pair"));
    }
    float x = point[0], y = point[1];
    vertices[index++] = (Vector2) { x, y };
  }
  *count = total;
  return vertices;
}

void Image.draw_text(
  Image image, String text, int x, int y, int size, Color color) {
  _raylib_renderer();
  ImageDrawText(&image, text, x, y, size, color);
}

void Image.draw_polygon(Image image, List points, Color color) {
  Scope.retain();
  defer Scope.release();

  int count = 0;
  Vector2 *vertices = _raylib_vertices(points, %"draw polygon", &count);
  ImageDrawTriangleFan(&image, vertices, count, color);
}

void Image.draw_polygon_lines(
  Image image, List points, int thickness, Color color) {
  Scope.retain();
  defer Scope.release();

  int count = 0;
  Vector2 *vertices = _raylib_vertices(points, %"draw polygon lines", &count);
  for (int index = 0; index < count; index++)
    ImageDrawLineEx(
      &image, vertices[index], vertices[(index + 1) % count],
      thickness, color
    );
}

Image Image.new(int width, int height, Color color) {
  return _raylib_generated(
    GenImageColor(width, height, color), %"GenImageColor", width, height
  );
}

Image Image.gradient_linear(
  int width, int height, int direction, Color start, Color end) {
  return _raylib_generated(
    GenImageGradientLinear(width, height, direction, start, end),
    %"GenImageGradientLinear", width, height
  );
}

Image Image.gradient_radial(
  int width, int height, float density, Color inner, Color outer) {
  return _raylib_generated(
    GenImageGradientRadial(width, height, density, inner, outer),
    %"GenImageGradientRadial", width, height
  );
}

Image Image.gradient_square(
  int width, int height, float density, Color inner, Color outer) {
  return _raylib_generated(
    GenImageGradientSquare(width, height, density, inner, outer),
    %"GenImageGradientSquare", width, height
  );
}

Image Image.checked(
  int width, int height, int checks_x, int checks_y, Color first,
  Color second) {
  return _raylib_generated(
    GenImageChecked(width, height, checks_x, checks_y, first, second),
    %"GenImageChecked", width, height
  );
}

Image Image.white_noise(int width, int height, float factor) {
  return _raylib_generated(
    GenImageWhiteNoise(width, height, factor),
    %"GenImageWhiteNoise", width, height
  );
}

Image Image.perlin_noise(
  int width, int height, int offset_x, int offset_y, float scale) {
  return _raylib_generated(
    GenImagePerlinNoise(width, height, offset_x, offset_y, scale),
    %"GenImagePerlinNoise", width, height
  );
}

Image Image.cellular(int width, int height, int tile_size) {
  return _raylib_generated(
    GenImageCellular(width, height, tile_size),
    %"GenImageCellular", width, height
  );
}

Image Image.load(String path) {
  _raylib_trace_reset();
  Image image = LoadImage(path);
  if (!image.valid()) {
    String message = _raylib_trace_detail();
    raise %(io-fail (library "raylib") (operation "LoadImage") (path $path)
            (message $message));
  }
  return image;
}

void Image.export(Image image, String path) {
  _raylib_trace_reset();
  if (!ExportImage(image, path)) {
    String message = _raylib_trace_detail();
    raise %(io-fail (library "raylib") (operation "ExportImage") (path $path)
            (message $message));
  }
}

ImagePixels Image.pixels(Image image) {
  Color *data = LoadImageColors(image);
  if (!data) {
    raise %(alloc-fail (library "raylib") (operation "LoadImageColors")
            (width ${image.width}) (height ${image.height}));
  }

  ImagePixels pixels = Scope.calloc(1, sizeof(struct ImagePixels));
  pixels.data = data;
  pixels.width = image.width;
  pixels.height = image.height;
  return pixels;
}

int ImagePixels.len(ImagePixels pixels) {
  _raylib_pixels_live(pixels, %"pixels len");
  return pixels.width * pixels.height;
}

Color ImagePixels.getindex(ImagePixels pixels, int index) {
  return pixels.data[_raylib_pixel_offset(pixels, index, %"pixels index")];
}

Color ImagePixels.setindex(ImagePixels pixels, int index, Color color) {
  pixels.data[_raylib_pixel_offset(pixels, index, %"pixels store")] = color;
  return color;
}

Color ImagePixels.at(ImagePixels pixels, int x, int y) {
  return pixels.data[_raylib_pixel_xy(pixels, x, y, %"pixels at")];
}

Color ImagePixels.put(ImagePixels pixels, int x, int y, Color color) {
  pixels.data[_raylib_pixel_xy(pixels, x, y, %"pixels put")] = color;
  return color;
}

Image ImagePixels.image(ImagePixels pixels) {
  _raylib_pixels_live(pixels, %"pixels image");
  size_t bytes = (size_t) pixels.width * pixels.height * sizeof(Color);
  Color *copy = MemAlloc((unsigned int) bytes);
  if (!copy) {
    raise %(alloc-fail (library "raylib") (operation "MemAlloc")
            (bytes $bytes));
  }

  memcpy(copy, pixels.data, bytes);
  return (Image) {
    copy, pixels.width, pixels.height, 1,
    PIXELFORMAT_UNCOMPRESSED_R8G8B8A8
  };
}

ImagePixels ImagePixels.free(ImagePixels pixels) {
  if (!pixels || !pixels.data) return NULL;
  UnloadImageColors(pixels.data);
  pixels.data = NULL;
  return NULL;
}

int RaylibText.width(String text, int size) {
  _raylib_renderer();
  return MeasureText(text ? text : "", size);
}

Vector2 RaylibText.size(String text, int size, float spacing) {
  _raylib_renderer();
  return MeasureTextEx(
    GetFontDefault(), text ? text : "", (float) size, spacing
  );
}
