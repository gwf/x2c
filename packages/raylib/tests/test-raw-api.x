/*  test-raw-api.x -- The pinned raylib API reached through the package.

    The package publishes src/raylib-6.0.h, so importing it is enough to
    call upstream declarations the client never wraps.
*/

import "raylib";

#include "test-support.x"

$(import "../../../unittest/test-macros.xmacro")

static void raylib_raw_header(void) {
  EXPECT_INT_EQ(RAYLIB_VERSION_MAJOR, 6);
  EXPECT_INT_EQ(RAYLIB_VERSION_MINOR, 0);

  Image image = GenImageColor(8, 8, BLACK);
  EXPECT_TRUE(IsImageValid(image));
  EXPECT_TRUE(ColorIsEqual(GetImageColor(image, 0, 0), BLACK));

  // Unwrapped upstream operations stay callable on the raw path.
  ImageDrawTriangleEx(
    &image, (Vector2) { 0, 0 }, (Vector2) { 7, 0 }, (Vector2) { 0, 7 },
    RED, GREEN, BLUE
  );
  EXPECT_FALSE(ColorIsEqual(GetImageColor(image, 1, 1), BLACK));

  int count = 0;
  Color *palette = LoadImagePalette(image, 16, &count);
  EXPECT_TRUE(count > 0);
  UnloadImagePalette(palette);

  EXPECT_INT_EQ(GetPixelDataSize(8, 8, image.format), 8 * 8 * 4);
  UnloadImage(image);

  Vector2 point = { 4, 6 };
  EXPECT_INT_EQ(point.x, 4);
  EXPECT_INT_EQ(point.y, 6);
  EXPECT_NOT_NULL((void *) InitWindow);
  EXPECT_NOT_NULL((void *) DrawText);
}

static void raylib_image_and_text_bounds(void) {
  Image image = GenImageColor(2, 2, RED);
  Image outside = ImageFromImage(image, (Rectangle) { 10, 10, 1, 1 });
  EXPECT_NULL(outside.data);
  if (outside.data) UnloadImage(outside);
  Image whole = ImageFromImage(image, (Rectangle) { 0, 0, 2, 2 });
  EXPECT_TRUE(IsImageValid(whole));
  EXPECT_TRUE(ColorIsEqual(GetImageColor(whole, 1, 1), RED));
  UnloadImage(whole);
  UnloadImage(image);

  Image empty = GenImageColor(0, 0, RED);
  EXPECT_NULL(empty.data);
  if (empty.data) UnloadImage(empty);
  EXPECT_STR_EQ(TextInsert("abcd", "X", 2), "abXcd");
  EXPECT_STR_EQ(TextSubtext("abcd", 0, 2), "ab");
}

void raylib_raw_suite(void) {
  $test.run(raylib_raw_header);
  $test.run(raylib_image_and_text_bounds);
}

int main(void) {
  TestHarness_begin();
  $test.suite(raylib_raw_suite);
  return TestHarness_finish();
}
