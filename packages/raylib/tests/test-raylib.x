/*  test-raylib.x -- Focused tests for raylib images, colors, and text. */

import "raylib" with ImagePixels, RaylibText, RaylibWindow;

#include "test-support.x"

$(import "../../../unittest/test-macros.xmacro")

static void raylib_vectors_use_methods_and_operators(void) {
  Vector2 first = { 2.0f, 3.0f };
  Vector2 second = { 4.0f, 5.0f };
  Vector2 sum = first + second;
  Vector2 difference = second - first;
  Vector2 negated = -first;

  EXPECT_TRUE(sum == (Vector2) { 6.0f, 8.0f });
  EXPECT_TRUE(difference == (Vector2) { 2.0f, 2.0f });
  EXPECT_TRUE(negated == (Vector2) { -2.0f, -3.0f });
  EXPECT_TRUE(first.scale(2.0f) == (Vector2) { 4.0f, 6.0f });
  EXPECT_TRUE(first.distance(second) > 2.8f);
}

static void raylib_colors_keep_native_operations(void) {
  Color blue = Color.from_hex(0x147df5ff);
  EXPECT_TRUE(blue.equal((Color) { 20, 125, 245, 255 }));
  EXPECT_INT_EQ(blue.alpha(0.5f).a, 127);
  EXPECT_TRUE(blue.lerp(WHITE, 0.5f).r > blue.r);
}

static void raylib_colors_build_from_named_components(void) {
  Color opaque = Color.rgb(20, 125, 245);
  Color faded = Color.rgba(20, 125, 245, 64);

  EXPECT_TRUE(opaque.equal(Color.from_hex(0x147df5ff)));
  EXPECT_INT_EQ(opaque.a, 255);
  EXPECT_INT_EQ(faded.a, 64);
  EXPECT_INT_EQ(faded.g, 125);
  EXPECT_INT_EQ(Color.to_int(opaque), 0x147df5ff);
}

static void raylib_images_draw_and_export(void) {
  Image image = Image.new(64, 48, RAYWHITE);
  defer image.free();
  EXPECT_TRUE(image.valid());

  image.draw_rectangle_xy(8, 8, 24, 16, RED);
  image.draw_line((Vector2) { 0, 0 }, (Vector2) { 63, 47 }, 3, BLUE);
  EXPECT_TRUE(image.color_at(12, 12).equal(RED));
  EXPECT_FALSE(image.color_at(40, 30).equal(RAYWHITE));

  image.export(%"builds/test-image.png");
  EXPECT_TRUE(FileExists("builds/test-image.png"));

  image.resize_nearest(32, 24);
  EXPECT_INT_EQ(image.width, 32);
  EXPECT_INT_EQ(image.height, 24);
}

static void raylib_export_raises_io_failure(void) {
  Image image = Image.new(2, 2, BLACK);
  defer image.free();

  int caught = 0;
  try image.export(%"builds/missing/output.png");
  catch %(io-fail *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<library>).string(), %"raylib");
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"ExportImage");
    EXPECT_TRUE(detail.assoc(<message>).string().len() > 0);
  }
  EXPECT_TRUE(caught);
}

static void raylib_loads_an_image_from_disk(void) {
  String path = %"builds/test-load.png";
  Image written = Image.new(12, 9, GREEN);
  written.draw_pixel_xy(3, 4, RED);
  written.export(path);
  written.free();

  Image read = Image.load(path);
  defer read.free();
  EXPECT_INT_EQ(read.width, 12);
  EXPECT_INT_EQ(read.height, 9);
  EXPECT_TRUE(read.color_at(3, 4).equal(RED));
  EXPECT_TRUE(read.color_at(0, 0).equal(GREEN));
}

static void raylib_load_raises_io_failure(void) {
  int caught = 0;
  try {
    Image absent = Image.load(%"builds/no-such-image.png");
    absent.free();
  }
  catch %(io-fail *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<library>).string(), %"raylib");
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"LoadImage");
    EXPECT_STR_EQ(detail.assoc(<path>).string(), %"builds/no-such-image.png");
    EXPECT_TRUE(detail.assoc(<message>).string().len() > 0);
  }
  EXPECT_TRUE(caught);
}

static void raylib_measures_text_before_drawing(void) {
  int narrow = RaylibText.width(%"ab", 20);
  int wide = RaylibText.width(%"abcdef", 20);
  int larger = RaylibText.width(%"ab", 40);
  // size takes raylib's own spacing; width uses the default font's.
  Vector2 spaced = RaylibText.size(%"abcdef", 20, 1.0f);
  Vector2 shorter = RaylibText.size(%"ab", 20, 1.0f);

  EXPECT_TRUE(narrow > 0);
  EXPECT_TRUE(wide > narrow);
  EXPECT_TRUE(larger > narrow);
  EXPECT_TRUE(spaced.x > shorter.x);
  EXPECT_INT_EQ((int) spaced.y, 20);
  EXPECT_INT_EQ(RaylibText.width(%"", 20), 0);
}

static void raylib_generates_gradients_and_noise(void) {
  Image checker = Image.checked(8, 8, 2, 2, BLACK, WHITE);
  defer checker.free();
  EXPECT_INT_EQ(checker.width, 8);
  EXPECT_TRUE(checker.color_at(0, 0).equal(BLACK));
  EXPECT_TRUE(checker.color_at(2, 0).equal(WHITE));

  Image dark = Image.white_noise(16, 16, 0.0f);
  defer dark.free();
  EXPECT_TRUE(dark.color_at(7, 7).equal(BLACK));

  Image light = Image.white_noise(16, 16, 1.0f);
  defer light.free();
  EXPECT_TRUE(light.color_at(7, 7).equal(WHITE));

  Image linear = Image.gradient_linear(16, 16, 0, BLACK, WHITE);
  defer linear.free();
  EXPECT_TRUE(linear.color_at(8, 15).r > linear.color_at(8, 0).r);

  Image radial = Image.gradient_radial(16, 16, 0.0f, WHITE, BLACK);
  defer radial.free();
  EXPECT_TRUE(radial.color_at(8, 8).r > radial.color_at(0, 0).r);

  Image perlin = Image.perlin_noise(16, 16, 0, 0, 4.0f);
  defer perlin.free();
  EXPECT_TRUE(perlin.valid());

  Image cells = Image.cellular(16, 16, 4);
  defer cells.free();
  EXPECT_TRUE(cells.valid());

  Image square = Image.gradient_square(16, 16, 0.0f, WHITE, BLACK);
  defer square.free();
  EXPECT_TRUE(square.color_at(8, 8).r > square.color_at(0, 0).r);
}

static void raylib_pixels_read_filter_and_write_back(void) {
  Image source = Image.new(4, 3, BLUE);
  defer source.free();
  source.draw_pixel_xy(1, 1, RED);

  ImagePixels pixels = source.pixels();
  defer pixels.free();
  EXPECT_INT_EQ(pixels.len(), 12);
  EXPECT_INT_EQ(pixels.width, 4);
  EXPECT_INT_EQ(pixels.height, 3);
  EXPECT_TRUE(pixels[5].equal(RED));
  EXPECT_TRUE(pixels.at(1, 1).equal(RED));
  EXPECT_TRUE(pixels[0].equal(BLUE));
  pixels.put(2, 1, GREEN);
  EXPECT_TRUE(pixels.at(2, 1).equal(GREEN));

  int changed = 0;
  for (int index = 0; index < pixels.len(); index++) {
    if (!pixels[index].equal(BLUE)) continue;
    pixels[index] = Color.rgba(0, 0, 0, 0);
    changed++;
  }
  EXPECT_INT_EQ(changed, 10);

  Image filtered = pixels.image();
  defer filtered.free();
  EXPECT_INT_EQ(filtered.width, 4);
  EXPECT_INT_EQ(filtered.height, 3);
  EXPECT_TRUE(filtered.color_at(1, 1).equal(RED));
  EXPECT_TRUE(filtered.color_at(2, 1).equal(GREEN));
  EXPECT_INT_EQ(filtered.color_at(0, 0).a, 0);
  // The source image is untouched: pixels own a copy of its colors.
  EXPECT_TRUE(source.color_at(0, 0).equal(BLUE));
}

static void raylib_pixels_reject_an_index_out_of_range(void) {
  Image image = Image.new(2, 2, BLACK);
  defer image.free();
  ImagePixels pixels = image.pixels();
  defer pixels.free();

  int caught = 0;
  try {
    Color beyond = pixels[4];
    (void) beyond;
  }
  catch %(bad-arg *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"pixels index");
    EXPECT_INT_EQ(detail.assoc(<index>).int(), 4);
  }
  EXPECT_TRUE(caught);

  caught = 0;
  try pixels.at(2, 0);
  catch %(bad-arg *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"pixels at");
  }
  EXPECT_TRUE(caught);

  caught = 0;
  try pixels.put(0, -1, WHITE);
  catch %(bad-arg *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"pixels put");
  }
  EXPECT_TRUE(caught);

  caught = 0;
  try pixels[-1] = WHITE;
  catch %(bad-arg *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"pixels store");
  }
  EXPECT_TRUE(caught);
}

static void raylib_image_color_rejects_coordinates_out_of_range(void) {
  Image image = Image.new(2, 2, BLACK);
  defer image.free();

  int caught = 0;
  try image.color_at(2, 0);
  catch %(bad-arg *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"image color");
  }
  EXPECT_TRUE(caught);
}

static void raylib_image_mutators_update_the_owned_image(void) {
  Image image = Image.new(5, 3, Color.rgba(200, 100, 50, 64));
  defer image.free();
  Image mask = Image.new(8, 4, Color.rgba(0, 0, 0, 128));
  defer mask.free();

  image.format(PIXELFORMAT_UNCOMPRESSED_R5G6B5);
  EXPECT_INT_EQ(image.color_at(0, 0).a, 255);
  ImagePixels converted = image.pixels();
  defer converted.free();
  Image rgba = converted.image();
  defer rgba.free();
  EXPECT_INT_EQ(rgba.format, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8);
  EXPECT_INT_EQ(rgba.color_at(0, 0).a, 255);
  image.format(PIXELFORMAT_UNCOMPRESSED_R8G8B8A8);
  image.to_power_of_two(BLANK);
  EXPECT_INT_EQ(image.width, 8);
  image.crop((Rectangle) { 0, 0, 6, 3 });
  image.alpha_crop(0.0f);
  image.alpha_clear(BLACK, 0.1f);
  image.resize_canvas(8, 4, 1, 0, BLANK);
  image.alpha_mask(mask);
  image.alpha_premultiply();
  image.blur_gaussian(1);
  image.resize(6, 4);
  image.resize_nearest(8, 4);
  image.mipmaps();
  image.flip_vertical();
  image.flip_horizontal();
  image.rotate(180);
  image.rotate_clockwise();
  image.rotate_counterclockwise();
  image.tint(WHITE);
  image.invert();
  image.grayscale();
  image.contrast(0.0f);
  image.brightness(0);
  Color before = image.color_at(0, 0);
  image.replace_color(before, RED);
  EXPECT_TRUE(image.valid());
  EXPECT_INT_EQ(image.width, 8);
  EXPECT_INT_EQ(image.height, 4);
}

static void raylib_released_pixels_stay_released(void) {
  Image image = Image.new(2, 2, BLACK);
  defer image.free();
  ImagePixels pixels = image.pixels();

  EXPECT_NULL(pixels.free());
  EXPECT_NULL(pixels.free());

  int caught = 0;
  try {
    Color stale = pixels[0];
    (void) stale;
  }
  catch %(bad-state *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<library>).string(), %"raylib");
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"pixels index");
  }
  EXPECT_TRUE(caught);
}

static void raylib_draws_triangles_and_polygons(void) {
  Image image = Image.new(40, 40, WHITE);
  defer image.free();

  image.draw_triangle(
    (Vector2) { 2, 2 }, (Vector2) { 16, 2 }, (Vector2) { 2, 16 }, RED
  );
  EXPECT_TRUE(image.color_at(4, 4).equal(RED));

  List pentagon = %((20 4) (36 16) (30 34) (10 34) (4 16));
  image.draw_polygon(pentagon, BLUE);
  EXPECT_TRUE(image.color_at(20, 20).equal(BLUE));
  EXPECT_TRUE(image.color_at(38, 38).equal(WHITE));

  image.draw_polygon_lines(pentagon, 2, GREEN);
  EXPECT_TRUE(image.color_at(20, 4).equal(GREEN));
  EXPECT_TRUE(image.color_at(20, 20).equal(BLUE));
}

static void raylib_polygons_reject_malformed_points(void) {
  Image image = Image.new(8, 8, WHITE);
  defer image.free();

  int caught = 0;
  try image.draw_polygon(%((1 1) (5 1)), RED);
  catch %(bad-arg *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"draw polygon");
    EXPECT_INT_EQ(detail.assoc(<points>).int(), 2);
  }
  EXPECT_TRUE(caught);

  caught = 0;
  try image.draw_polygon(%((1 1) (5 1) (3 5 7)), RED);
  catch %(bad-arg *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<library>).string(), %"raylib");
  }
  EXPECT_TRUE(caught);
}

/*  Under the admitted profile no window backend is compiled, so these
    methods run without anything appearing. What is checked here is the
    contract that holds on both profiles: one window at a time, an upload
    that replaces its predecessor, presentation that does not raise, and a
    close that is idempotent and invalidates the handle. The window a caller
    sees is proved by examples/live-chart.x under dependency-desktop.json,
    which no gate can run. */
static void raylib_window_owns_one_native_window(void) {
  Image frame = Image.new(64, 48, BLUE);
  defer frame.free();

  RaylibWindow window = RaylibWindow.open(64, 48, %"x2c window test");
  EXPECT_INT_EQ(window != NULL, 1);

  int no_texture = 0;
  try window.native();
  catch %(bad-state *detail): no_texture = 1;
  EXPECT_INT_EQ(no_texture, 1);

  int duplicate = 0;
  try RaylibWindow.open(64, 48, %"duplicate window");
  catch %(bad-state *detail): duplicate = 1;
  EXPECT_INT_EQ(duplicate, 1);

  window.upload(frame);
  EXPECT_TRUE(IsTextureValid(*window.native()));
  Image replacement = Image.new(64, 48, RED);
  defer replacement.free();
  window.upload(replacement);
  EXPECT_TRUE(IsTextureValid(*window.native()));

  for (int repeat = 0; repeat < 3; repeat++) window.present();
  window.target_fps(0);
  Image screen = LoadImageFromScreen();
  defer screen.free();
  EXPECT_TRUE(screen.valid());
  Color center = screen.color_at(32, 24);
  // PLATFORM_MEMORY exposes its software framebuffer as BGRA on macOS.
  EXPECT_INT_EQ(center.r, RED.b);
  EXPECT_INT_EQ(center.g, RED.g);
  EXPECT_INT_EQ(center.b, RED.r);
  EXPECT_INT_EQ(center.a, RED.a);

  EXPECT_INT_EQ(window.close() == NULL, 1);
  EXPECT_INT_EQ(window.close() == NULL, 1);

  int stale = 0;
  try window.present();
  catch %(bad-state *detail): stale = 1;
  EXPECT_INT_EQ(stale, 1);
}

static void raylib_window_rejects_an_empty_extent(void) {
  int refused = 0;
  try {
    RaylibWindow window = RaylibWindow.open(0, 48, %"x2c window test");
    window.close();
  }
  catch %(bad-arg *detail): refused = 1;
  EXPECT_INT_EQ(refused, 1);
}

void raylib_suite(void) {
  $test.run(raylib_vectors_use_methods_and_operators);
  $test.run(raylib_colors_keep_native_operations);
  $test.run(raylib_colors_build_from_named_components);
  $test.run(raylib_images_draw_and_export);
  $test.run(raylib_export_raises_io_failure);
  $test.run(raylib_loads_an_image_from_disk);
  $test.run(raylib_load_raises_io_failure);
  $test.run(raylib_measures_text_before_drawing);
  $test.run(raylib_generates_gradients_and_noise);
  $test.run(raylib_pixels_read_filter_and_write_back);
  $test.run(raylib_pixels_reject_an_index_out_of_range);
  $test.run(raylib_released_pixels_stay_released);
  $test.run(raylib_image_color_rejects_coordinates_out_of_range);
  $test.run(raylib_image_mutators_update_the_owned_image);
  $test.run(raylib_draws_triangles_and_polygons);
  $test.run(raylib_polygons_reject_malformed_points);
  $test.run(raylib_window_owns_one_native_window);
  $test.run(raylib_window_rejects_an_empty_extent);
}

int main(void) {
  TestHarness_begin();
  $test.suite(raylib_suite);
  return TestHarness_finish();
}
