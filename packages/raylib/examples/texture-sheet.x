/*  texture-sheet.x -- Publish procedural texture tiles and a preview sheet.

    An art pipeline generates tiles, writes them out, and then builds one
    contact sheet from the files it just published, so the sheet shows what
    the tiles on disk actually contain.
*/

import "raylib" with ImagePixels, RaylibText;

#include <math.h>

static int tile_size = 160;
static int knockout_cut = 96;

static Color ink = { 42, 48, 62, 255 };
static Color edge = { 206, 214, 229, 255 };

static String _tile_path(int index) {
  return %"builds/tile-$index.png";
}

/* Write one generated tile out and release it in the same breath. */
static void _publish(Image tile, int index) {
  defer tile.free();
  tile.export(_tile_path(index));
}

/* Scale a tile into place on the sheet and centre its caption underneath. */
static void _place(
  Image sheet, Image tile, int x, int y, int size, String caption) {
  Rectangle source = { 0, 0, tile.width, tile.height };
  Rectangle target = { x, y, size, size };
  sheet.draw(tile, source, target, WHITE);
  sheet.draw_rectangle_lines(target, 2, edge);
  sheet.draw_text(
    caption, x + (size - RaylibText.width(caption, 16)) / 2, y + size + 10,
    16, Color.rgb(94, 102, 120)
  );
}

/* The vertices of a regular polygon, as the (x y) pairs draw_polygon
   takes. raylib truncates its triangle edge steps to integers, so whole
   pixels give the cleanest fill. */
static List _polygon(Vector2 center, int sides, float radius) {
  List points = NULL;
  for (int index = 0; index < sides; index++) {
    float angle = -1.5707963f + index * 6.2831853f / sides;
    Vector2 spoke = {
      roundf(cosf(angle) * radius), roundf(sinf(angle) * radius)
    };
    Vector2 point = center + spoke;
    points = cons(%(${point.x} ${point.y}), points);
  }
  return points.reverse();
}

int main(void) {
  List captions = %(
    "linear gradient" "radial gradient" "checkerboard" "perlin noise"
  );

  _publish(
    Image.gradient_linear(
      tile_size, tile_size, 45,
      Color.rgb(20, 125, 245), Color.rgb(34, 160, 107)
    ), 0
  );
  _publish(
    Image.gradient_radial(
      tile_size, tile_size, 0.4f,
      Color.rgb(255, 214, 102), Color.rgb(240, 90, 60)
    ), 1
  );
  _publish(
    Image.checked(
      tile_size, tile_size, 8, 8,
      Color.rgb(238, 241, 247), Color.rgb(198, 208, 226)
    ), 2
  );
  _publish(Image.perlin_noise(tile_size, tile_size, 128, 128, 6.0f), 3);

  Image sheet = Image.new(900, 600, Color.rgb(247, 248, 252));
  defer sheet.free();
  sheet.draw_text(%"Procedural texture tiles", 36, 30, 32, ink);
  sheet.draw_text(
    %"generated, written to builds/, and read back from disk",
    38, 74, 18, Color.rgb(120, 128, 146)
  );

  int column = 0;
  foreach(String caption, captions) {
    Image tile = Image.load(_tile_path(column));
    _place(
      sheet, tile, 36 + column * (tile_size + 22), 112, tile_size, caption
    );
    tile.free();
    column++;
  }

  /* Read the noise tile back as x2c values, make its dark pixels
     transparent, and rebuild an image from the result. */
  Image noise = Image.load(_tile_path(3));
  ImagePixels pixels = noise.pixels();
  defer pixels.free();
  noise.free();

  int cleared = 0;
  for (int index = 0; index < pixels.len(); index++) {
    Color pixel = pixels[index];
    if (pixel.r >= knockout_cut) continue;
    pixels[index] = Color.rgba(pixel.r, pixel.g, pixel.b, 0);
    cleared++;
  }

  Image backdrop = Image.checked(
    32, 32, 4, 4, Color.rgb(202, 212, 228), Color.rgb(248, 250, 253)
  );
  defer backdrop.free();
  Image knockout = pixels.image();
  defer knockout.free();

  // The backdrop only exists so the transparent pixels read as transparent.
  Rectangle whole = { 0, 0, 32, 32 }, panel = { 36, 330, 220, 220 };
  sheet.draw(backdrop, whole, panel, WHITE);
  _place(
    sheet, knockout, 36, 330, 220,
    %"noise below $knockout_cut removed"
  );

  sheet.draw_text(%"Sheet report", 300, 336, 24, ink);
  sheet.draw_text(
    %"${captions.len()} tiles at $tile_size square, read from PNG",
    300, 378, 18, Color.rgb(94, 102, 120)
  );
  sheet.draw_text(
    %"$cleared of ${pixels.len()} noise pixels made transparent",
    300, 406, 18, Color.rgb(94, 102, 120)
  );

  Vector2 badge = { 802, 452 };
  List pentagon = _polygon(badge, 5, 58.0f);
  sheet.draw_polygon(pentagon, Color.rgb(20, 125, 245));
  sheet.draw_polygon_lines(pentagon, 3, Color.rgb(12, 78, 156));
  sheet.draw_text(
    %"PASS", 802 - RaylibText.width(%"PASS", 20) / 2, 442, 20, WHITE
  );

  String output = %"builds/texture-sheet.png";
  sheet.export(output);

  /* A tile that was never published is a raylib failure, not an absence. */
  String missing = %"builds/tile-9.png";
  try {
    Image absent = Image.load(missing);
    absent.free();
  }
  catch %(io-fail *detail): {
    printf("%s\n", %"${detail.assoc(<operation>).string()} refused $missing");
  }

  printf(
    "%s\n",
    %"wrote $output from ${captions.len()} tiles, $cleared cleared"
  );
  return 0;
}
