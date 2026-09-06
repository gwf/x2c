/*  live-chart.x -- Show the weekly climate chart in a window. */

import "raylib" with RaylibWindow;

#include "chart.x"

int main(void) {
  int series = 0;
  Image chart = chart_image(&series);
  defer chart.free();

  RaylibWindow window = RaylibWindow.open(
    chart.width, chart.height, %"Weekly high temperature"
  );
  defer window.close();

  window.upload(chart);
  window.target_fps(60);
  printf("%s\n", %"showing $series series; press Esc to close");

  while (!window.should_close()) window.present();
  return 0;
}
