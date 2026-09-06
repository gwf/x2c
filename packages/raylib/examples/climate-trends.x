/*  climate-trends.x -- Render one week's high temperatures to a PNG. */

import "raylib";

int main(void) {
  List days = %("Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun");
  List highs = %(68 72 74 71 76 79 77);
  String output = %"builds/climate-trends.png";

  Image chart = Image.new(720, 320, Color.from_hex(0xf7f8fcff));
  defer chart.free();
  Rectangle panel = { 28, 24, 664, 270 };
  chart.draw_rectangle(panel, WHITE);
  chart.draw_rectangle_lines(panel, 2, Color.from_hex(0xd7dce5ff));
  chart.draw_text(%"Seattle weekly high", 54, 42, 28, DARKGRAY);

  Vector2 origin = { 72, 242 }, previous = { 0 };
  int index = 0;
  foreach(int high, highs) {
    Vector2 offset = { index * 88, -(high - 60) * 8 };
    Vector2 point = origin + offset;
    if (index) chart.draw_line(previous, point, 4, BLUE);
    chart.draw_circle(point, 7, BLUE);
    chart.draw_text(days[index], (int) point.x - 16, 256, 18, DARKGRAY);
    chart.draw_text(
      %"$high F", (int) point.x - 18, (int) point.y - 28, 16, GRAY
    );
    previous = point;
    index++;
  }

  chart.export(output);
  printf("wrote %s from %d daily highs\n", output, highs.len());
  return 0;
}
