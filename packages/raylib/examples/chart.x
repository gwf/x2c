/*  chart.x -- The weekly climate chart, drawn once for two programs.

    climate-trends.x exports it to a PNG that `make verify` checks byte for
    byte; live-chart.x shows the same Image in a window. Sharing the drawing
    is what keeps the gated artifact and the demonstration the same picture.
 */
#pragma once

import "raylib";

/** Renders a 1200x675 Image and writes its series count when requested. */
Image chart_image(int *series);

#pragma private

Image chart_image(int *series) {
  List days = %("Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun");
  List cities = %(
    ("Georgetown" 0x147df5ff (68 72 74 71 76 79 77))
    ("Seattle"    0x22a06bff (57 59 61 60 63 64 62))
    ("Austin"     0xf28c28ff (82 85 88 91 93 90 87))
  );
  List ticks = %(50 60 70 80 90 100);

  Image chart = Image.new(1200, 675, Color.from_hex(0xf7f8fcff));

  Rectangle panel = { 48, 42, 1104, 588 };
  chart.draw_rectangle(panel, WHITE);
  chart.draw_rectangle_lines(panel, 2, Color.from_hex(0xd7dce5ff));
  chart.draw_text(%"Weekly high temperature", 84, 68, 36, DARKGRAY);
  chart.draw_text(
    %"A deterministic raylib Image rendered from x2c Lists",
    86, 112, 20, GRAY
  );

  Vector2 origin = { 120, 555 };
  float x_step = 142.0f, y_scale = 8.0f;

  foreach(int temperature, ticks) {
    float y = origin.y - (temperature - 50) * y_scale;
    Vector2 left = { origin.x, y }, right = { origin.x + x_step * 6, y };
    chart.draw_thin_line(left, right, Color.from_hex(0xe6e9efff));
    chart.draw_text(
      %"$temperature F", 64, (int) y - 9, 18,
      Color.from_hex(0x667085ff)
    );
  }

  int day_index = 0;
  foreach(String day, days) {
    int x = (int) (origin.x + day_index * x_step);
    chart.draw_text(day, x - 18, 578, 18, DARKGRAY);
    day_index++;
  }

  int city_index = 0;
  foreach(List city, cities) {
    String name = city[0];
    unsigned int rgba = city[1];
    List readings = city[2];
    Color color = Color.from_hex(rgba);
    Vector2 previous = { 0 };
    int reading_index = 0;

    foreach(int temperature, readings) {
      Vector2 offset = {
        reading_index * x_step,
        -(temperature - 50) * y_scale
      };
      Vector2 point = origin + offset;
      if (reading_index) chart.draw_line(previous, point, 5, color);
      chart.draw_circle(point, 8, color);
      chart.draw_circle_lines(point, 9, color.contrast(-0.25f));
      previous = point;
      reading_index++;
    }

    int legend_y = 166 + city_index * 36;
    chart.draw_rectangle_xy(884, legend_y, 24, 8, color);
    chart.draw_text(name, 920, legend_y - 8, 20, DARKGRAY);
    city_index++;
  }

  if (series) *series = cities.len();
  return chart;
}
