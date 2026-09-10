---
section: packages
tab: raylib
title: Draw a week of weather.
image: packages/climate-trends.png
imageAlt: Line chart of Seattle daily high temperatures from Monday to Sunday.
imageWidth: 1440
imageHeight: 640
---

<!-- ignore: source excerpt; the complete example requires its optional package and setup. -->
```x2c,ignore
import "raylib";

Image chart = Image.new(2160, 960, paper);
defer chart.free();
Vector2 origin = { 84, 252 }, previous = { 0 };
int index = 0;
foreach(int high, highs) {
  Vector2 offset = { index * 94, -(high - 60) * 6 };
  Vector2 point = origin + offset;
  // ... fill the area below each segment ...
  if (index)
    chart.draw_line(
      previous.scale(3), point.scale(3), 9, teal
    );
  previous = point;
  index++;
}

// ... draw labels with the bundled TrueType font ...
chart.resize(1440, 640);
chart.export(output);
```

Turn seven daily temperatures into a PNG with ordinary vectors, Lists,
and drawing methods. Each temperature becomes a point; lines join the
points over a pale filled area, and labels mark the days and highs. The complete program
renders this chart into memory, with no display or GPU.

[Full example](https://github.com/gwf/x2c/blob/main/packages/raylib/examples/climate-trends.x) / [Package guide](https://github.com/gwf/x2c/blob/main/packages/raylib/README.md)
