/*  climate-trends.x -- Render one week's high temperatures to a PNG. */

import "raylib";

static void _label(
  Image chart, Font font, String text, int x, int y, int size, Color color
) {
  ImageDrawTextEx(
    &chart, font, text, (Vector2) { x * 3, y * 3 }, size * 3, 0, color
  );
}

int main(void) {
  List days = %("Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun");
  List highs = %(68 72 74 71 76 79 77);
  String output = %"builds/climate-trends.png";

  Color paper = Color.from_hex(0xf8f7f3ff);
  Color ink = Color.from_hex(0x243b40ff);
  Color muted = Color.from_hex(0x718082ff);
  Color teal = Color.from_hex(0x168477ff);
  Color fill = Color.from_hex(0xe2eee7ff);
  InitWindow(1, 1, "chart");
  defer CloseWindow();
  Font font = LoadFontEx("examples/fonts/Lato-Regular.ttf", 84, NULL, 0);
  defer UnloadFont(font);
  if (font.baseSize != 84) return 1;

  Image chart = Image.new(2160, 960, paper);
  defer chart.free();
  _label(chart, font, %"Seattle", 38, 28, 28, ink);
  _label(chart, font, %"A week of daily highs", 40, 68, 16, muted);
  _label(chart, font, %"TEMPERATURE / F", 514, 38, 12, muted);

  Vector2 origin = { 84, 252 }, previous = { 0 };
  foreach(int tick, %(60 70 80)) {
    int y = (int) origin.y - (tick - 60) * 6;
    _label(chart, font, %"$tick", 40, y - 7, 14, muted);
    chart.draw_line(
      (Vector2) { 222, y * 3 }, (Vector2) { 1950, y * 3 }, 3,
      Color.from_hex(0xdce2ddff)
    );
  }
  int index = 0;
  foreach(int high, highs) {
    Vector2 offset = { index * 94, -(high - 60) * 6 };
    Vector2 point = origin + offset;
    if (index) {
      chart.draw_triangle(
        previous.scale(3), (Vector2) { previous.x * 3, origin.y * 3 },
        point.scale(3), fill
      );
      chart.draw_triangle(
        point.scale(3), (Vector2) { previous.x * 3, origin.y * 3 },
        (Vector2) { point.x * 3, origin.y * 3 }, fill
      );
      chart.draw_line(previous.scale(3), point.scale(3), 9, teal);
    }
    previous = point;
    index++;
  }
  index = 0;
  foreach(int high, highs) {
    Vector2 point = origin + (Vector2) { index * 94, -(high - 60) * 6 };
    chart.draw_circle(point.scale(3), 18, paper);
    chart.draw_circle(point.scale(3), 12, teal);
    _label(chart, font, days[index], (int) point.x - 12, 278, 14, muted);
    _label(
      chart, font, %"$high", (int) point.x - 9, (int) point.y - 26, 16, ink
    );
    index++;
  }

  chart.resize(1440, 640);
  chart.export(output);
  printf("wrote %s from %d daily highs\n", output, highs.len());
  return 0;
}
