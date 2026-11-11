/*  stress.x -- An animation load with a displayed frame rate.

    The program redraws on every frame and animates as many items as the
    slider asks for. It has two loads. Shapes paints moving circles on a
    canvas, which measures drawing. Components lays out a card for each
    item with a spinner, a badge, and a moving progress bar, which measures
    layout and component work. The header shows the frame rate, the time
    between frames, the time the program spent describing the frame, and
    the vertices and triangles of the frame before.

      stress [--no-vsync]                   open a window
      stress --frames N [LOAD [ITEMS]]      time N frames off screen
      stress --shot IMAGE.png [LOAD [ITEMS]]  draw one image off screen

    LOAD is `shapes` or `components`. A window waits for the display unless
    `--no-vsync` is given, so its frame rate stops at the display's rate.
*/

import "x2cui" with App, Offscreen, Ui;

#include "time.x"

#include <math.h>

enum { SHAPES, COMPONENTS, HISTORY = 240 };

typedef struct Stress {
  int load;            // SHAPES or COMPONENTS
  float items;         // how many items the load animates
  float clock;         // seconds of animation so far
  float times[HISTORY];  // the last times between frames, in ms
  double frame_sum;    // seconds between frames since the figures changed
  double draw_sum;     // seconds spent in `draw` since the figures changed
  int frames;          // frames since the figures changed
  String rate, frame_time, draw_time, vertices, triangles;
} Stress;

static float item_limit(int load) => load == SHAPES ? 50000 : 3000;

static Stress stress_new(int load, float items) {
  Stress stress = { .load = load, .items = items,
                    .rate = "-", .frame_time = "-", .draw_time = "-",
                    .vertices = "-", .triangles = "-" };
  return stress;
}

/* Records one frame. The figures on screen change four times a second, so
   they stay readable, and each shows the mean since the last change. */
static void record(Stress &stress, double frame, double draw, Ui ui) {
  for (int i = 1; i < HISTORY; i++) stress.times[i - 1] = stress.times[i];
  stress.times[HISTORY - 1] = (float) (frame * 1000);
  stress.frame_sum += frame;
  stress.draw_sum += draw;
  stress.frames++;
  if (stress.frame_sum < 0.25) return;
  const cui_draw_data *data = ui.get_draw_data();
  int vertices = data.vertex_count, triangles = data.index_count / 3;
  stress.rate = String.format("%.0f", stress.frames / stress.frame_sum);
  stress.frame_time =
    String.format("%.1f ms", stress.frame_sum * 1000 / stress.frames);
  stress.draw_time =
    String.format("%.1f ms", stress.draw_sum * 1000 / stress.frames);
  stress.vertices = %"$vertices";
  stress.triangles = %"$triangles";
  stress.frame_sum = stress.draw_sum = 0;
  stress.frames = 0;
}

// the two loads

static float fraction(float value) => value - floorf(value);

/* Moves from 0 to 1 and back as `phase` grows by one. */
static float sweep(float phase) {
  float part = fraction(phase);
  return part < 0.5f ? 2 * part : 2 - 2 * part;
}

typedef struct Field { int count; float clock; cui_color colors[6]; } Field;

/* Returns a number from 0 up to 1 for item `item` and its property
   `property`. The numbers of different items and properties are
   unrelated, as random draws are, and the same on every run. */
static float chance(int item, int property) {
  unsigned bits = (unsigned) item * 0x9e3779b9u + (unsigned) property;
  bits = (bits ^ bits >> 16) * 0x85ebca6bu;
  bits = (bits ^ bits >> 13) * 0xc2b2ae35u;
  bits ^= bits >> 16;
  return (bits >> 8) / 16777216.0f;
}

/* Returns where a point that left 0 and travelled `distance` is, when it
   turns back at 0 and at `extent`. */
static float reflected(float distance, float extent) {
  float along = fmodf(fabsf(distance), 2 * extent);
  return along < extent ? along : 2 * extent - along;
}

/* Each circle has its own start, direction, speed, size, and color, and
   moves in a straight line that turns back at the edges. Its place
   depends only on its index and the clock, so a frame is the same
   wherever it is drawn. */
static void paint_shapes(cui_ctx *context, cui_rect area, void *user) {
  Ui ui = context;
  Field *field = user;
  for (int i = 0; i < field.count; i++) {
    float radius = 3 + 6 * chance(i, 0);
    float wide = area.w - 2 * radius, high = area.h - 2 * radius;
    float angle = 6.2831853f * chance(i, 1);
    float travelled = (30 + 220 * chance(i, 2)) * field.clock;
    cui_vec2 centre = {
      area.x + radius + reflected(wide * chance(i, 3) +
                                  travelled * cosf(angle), wide),
      area.y + radius + reflected(high * chance(i, 4) +
                                  travelled * sinf(angle), high) };
    ui.draw_circle(centre, radius, field.colors[(int) (6 * chance(i, 5))]);
  }
}

static void draw_shapes(Ui ui, Stress &stress) {
  Field field = { (int) stress.items, stress.clock };
  for (int i = 0; i < 6; i++)
    field.colors[i] = ui.color_of(CUI_COLOR_SERIES(i));
  // The canvas copies the field, because it paints when the frame ends.
  ui.canvas("shapes", CUI_FILL, CUI_FILL, paint_shapes, &field,
            sizeof field);
}

static void draw_components(Ui ui, Stress &stress) {
  int count = (int) stress.items;
  $cui.row(ui, { .width = CUI_FILL, .height = CUI_FILL, .wrap = true,
                 .gap = 8, .scroll_y = true }) {
    for (int i = 0; i < count; i++) {
      float value = sweep(stress.clock * (0.1f + 0.5f * chance(i, 6)) +
                          chance(i, 7));
      $cui.id_index(ui, i)
      $cui.card(ui, { .width = CUI_PX(96), .pad = 8, .gap = 6 }) {
        $cui.row(ui, { .gap = 8, .align = CUI_ALIGN_CENTER }) {
          ui.spinner(14);
          ui.badge(%"$i", { .tone = (cui_tone) (i % 9) });
        }
        ui.progress(value, {});
      }
    }
  }
}

// the frame

static void figure(Ui ui, String label, String value) {
  $cui.column(ui, { .width = CUI_PX(120), .gap = 2 }) {
    ui.text(label, { .size = 12, .color = CUI_COLOR_TEXT_MUTED });
    ui.text(value, { .size = 22, .font = CUI_FONT_MEDIUM, .tabular = true,
                     .nowrap = true });
  }
}

typedef struct History {
  float times[HISTORY];
  cui_color line, guide;
} History;

/* The chart's scale is 0 to 33.3 ms, two frames of a 60 Hz display, so a
   steady rate is a flat line and a slow frame is a spike. A frame slower
   than that raises the scale. The guide marks 16.7 ms. */
static void paint_history(cui_ctx *context, cui_rect area, void *user) {
  Ui ui = context;
  History *history = user;
  float limit = 1000 / 30.0f;
  for (int i = 0; i < HISTORY; i++)
    if (history.times[i] > limit) limit = history.times[i];
  float guide = area.y + area.h * (1 - 1000 / 60.0f / limit);
  ui.draw_line((cui_vec2){ area.x, guide },
               (cui_vec2){ area.x + area.w, guide }, 1, history.guide);
  cui_vec2 points[HISTORY];
  for (int i = 0; i < HISTORY; i++)
    points[i] = (cui_vec2){
      area.x + area.w * i / (HISTORY - 1),
      area.y + area.h * (1 - history.times[i] / limit) };
  ui.draw_polyline(points, HISTORY, 1.5f, history.line, false);
}

static void draw_history(Ui ui, Stress &stress) {
  History history = { .line = ui.color_of(CUI_COLOR_ACCENT),
                      .guide = ui.color_of(CUI_COLOR_BORDER) };
  memcpy(history.times, stress.times, sizeof history.times);
  $cui.column(ui, { .width = CUI_FILL, .min_width = 240, .gap = 2 }) {
    ui.text("Between frames, last 240, with a guide at 16.7 ms",
            { .size = 12, .color = CUI_COLOR_TEXT_MUTED, .nowrap = true });
    // The canvas copies the history, because it paints when the frame ends.
    ui.canvas("history", CUI_FILL, CUI_PX(40), paint_history, &history,
              sizeof history);
  }
}

static void draw(Ui ui, Stress &stress) {
  stress.clock += ui.delta_time();
  $cui.column(ui, { .width = CUI_FILL, .height = CUI_FILL, .pad = 16,
                    .gap = 12, .bg = CUI_COLOR_BACKGROUND }) {
    $cui.row(ui, { .gap = 16, .align = CUI_ALIGN_CENTER, .wrap = true }) {
      figure(ui, "Frames per second", stress.rate);
      figure(ui, "Between frames", stress.frame_time);
      figure(ui, "Describing a frame", stress.draw_time);
      figure(ui, "Vertices", stress.vertices);
      figure(ui, "Triangles", stress.triangles);
      draw_history(ui, stress);
    }
    $cui.row(ui, { .gap = 16, .align = CUI_ALIGN_CENTER }) {
      if (ui.segmented("load", %("Shapes" "Components"), stress.load, {}))
        stress.items = stress.load == SHAPES ? 2000 : 200;
      ui.slider("items", stress.items, 10, item_limit(stress.load),
                { .step = 10, .show_value = true, .width = CUI_FILL });
    }
    if (stress.load == SHAPES) draw_shapes(ui, stress);
    else draw_components(ui, stress);
  }
  // An idle window stops redrawing; the load must not.
  ui.request_redraw();
}

static double seconds(void) => Time.monotonic().total_seconds();

static int run_window(bool no_vsync) {
  App app = auto App.open({ .title = "x2cui stress", .width = 1240,
                            .height = 820, .continuous = true,
                            .no_vsync = no_vsync });
  Stress stress = stress_new(SHAPES, 2000);
  double last = seconds(), spent = 0;
  while (app.frame()) {
    double now = seconds();
    record(stress, now - last, spent, app.ui());
    last = now;
    draw(app.ui(), stress);
    spent = seconds() - now;
  }
  return 0;
}

// off screen

static Stress chosen(int argc, char **argv) {
  int load = argc > 3 && !strcmp(argv[3], "components") ? COMPONENTS
                                                        : SHAPES;
  float items = argc > 4 ? (float) atof(argv[4])
                         : load == SHAPES ? 2000 : 200;
  return stress_new(load, items);
}

/* Draws one frame and returns the seconds spent describing it. */
static double frame(Offscreen screen, Stress &stress) {
  double before = seconds();
  screen.begin();
  draw(screen.ui(), stress);
  double describing = seconds() - before;
  screen.end();
  return describing;
}

/* Prints the mean time to describe a frame and the mean time of a whole
   frame, which adds layout, painting, and the software renderer. */
static int time_frames(Stress stress, int count) {
  Offscreen screen = auto Offscreen.open(1240, 820);
  for (int i = 0; i < 30; i++) frame(screen, stress);
  double describing = 0, start = seconds();
  for (int i = 0; i < count; i++) describing += frame(screen, stress);
  double whole = seconds() - start;
  const cui_draw_data *data = screen.ui().get_draw_data();
  int items = (int) stress.items;
  int vertices = data.vertex_count, triangles = data.index_count / 3;
  String load = stress.load == SHAPES ? "shapes" : "components";
  printf("%s, %d items, %d frames\n", load, items, count);
  printf("  describing a frame  %8.3f ms\n", describing * 1000 / count);
  printf("  whole frame         %8.3f ms\n", whole * 1000 / count);
  printf("  vertices %d, triangles %d\n", vertices, triangles);
  return 0;
}

static int shot(Stress stress, String path) {
  Offscreen screen = auto Offscreen.open(1240, 820);
  double last = 0;
  for (int i = 0; i < 60; i++) {
    record(stress, 1.0 / 60, last, screen.ui());
    last = frame(screen, stress);
  }
  screen.write_png(path);
  return 0;
}

int main(int argc, char **argv) {
  if (argc > 2 && !strcmp(argv[1], "--frames"))
    return time_frames(chosen(argc, argv), atoi(argv[2]));
  if (argc > 2 && !strcmp(argv[1], "--shot"))
    return shot(chosen(argc, argv), argv[2]);
  return run_window(argc > 1 && !strcmp(argv[1], "--no-vsync"));
}
