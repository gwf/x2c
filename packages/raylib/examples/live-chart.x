/*  live-chart.x -- Show the weekly climate chart in a window. */

import "raylib" with RaylibWindow;

#include "chart.x"

int main(void) {
  int series = 0;
  Image chart = $auto(chart_image(&series));

  RaylibWindow window = $auto(RaylibWindow.open(
    chart.width, chart.height, "Weekly high temperature"
  ));

  window.upload(chart);
  window.target_fps(60);
  printf("%s\n", %"showing $series series; press Esc to close");

  while (!window.should_close()) window.present();
  return 0;
}
