#pragma once

/*  social.x -- the gallery's Social and media page */

#include "state.x"

#include <math.h>

// Paints a daytime landscape into `px`, w by h RGBA pixels, in grey or in
// colour.
static void make_scene(unsigned char *px, int w, int h, bool color) {
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      float fx = (float) x / w, fy = (float) y / h;
      // clear daytime sky
      float r = 0.56f + fy * 0.34f, g = 0.72f + fy * 0.2f,
            b = 0.88f + fy * 0.06f;
      // round at a 1.6 aspect
      float sun = (fx - 0.72f) * (fx - 0.72f) * 15.4f +
                  (fy - 0.24f) * (fy - 0.24f) * 6.0f;
      if (sun < 0.024f) {
        r = 1.0f;
        g = 0.97f;
        b = 0.86f;
      }
      float m1 = 0.5f + 0.1f * sinf(fx * 6.0f + 0.6f) +
                 0.03f * sinf(fx * 23.0f);
      float m2 = 0.68f + 0.06f * sinf(fx * 4.0f + 2.1f) +
                 0.02f * sinf(fx * 31.0f);
      // far hills in haze
      if (fy > m1) {
        r = 0.5f;
        g = 0.6f;
        b = 0.62f - fy * 0.08f;
      }
      // near fields
      if (fy > m2) {
        r = 0.3f - (fy - m2) * 0.2f;
        g = 0.45f - (fy - m2) * 0.25f;
        b = 0.3f;
      }
      if (!color) {
        float l = r * 0.3f + g * 0.59f + b * 0.11f;
        l = l * 0.85f + 0.05f;
        r = g = b = l;
      }
      unsigned char *p = px + (y * w + x) * 4;
      p[0] = (unsigned char) (fminf(1, fmaxf(0, r)) * 255);
      p[1] = (unsigned char) (fminf(1, fmaxf(0, g)) * 255);
      p[2] = (unsigned char) (fminf(1, fmaxf(0, b)) * 255);
      p[3] = 255;
    }
  }
}

typedef struct cmp_textures {
  cui_texture before, after;
} cmp_textures;

// CUI calls this, so its first parameter is CUI's own `cui_ctx *`.
static void cmp_textures_free(cui_ctx *context, void *data) {
  Ui ui = context;
  cmp_textures *tx = data;
  ui.image_destroy(tx.before);
  ui.image_destroy(tx.after);
}

void page_social(Ui ui, Gallery g) {
  static int likes[3] = { 12, 3, 0 };
  static bool liked[3] = { true, false, false };
  static int slide = 1;
  static float split = 0.45f;
  static int deck = 0;
  static double revenue = 48210;
  /* Textures belong to one Ui, so they live in its state store; they are
     freed with the state, a few seconds after the page is left, and made
     again on the way back. */
  cui_id tid = ui.make_id("cmp-textures");
  cmp_textures *tx = ui.state(tid, sizeof *tx);
  if (!tx.before) {
    static unsigned char a[640 * 400 * 4], b[640 * 400 * 4];
    make_scene(a, 640, 400, false);
    make_scene(b, 640, 400, true);
    tx.before = ui.image_create(640, 400, a);
    tx.after = ui.image_create(640, 400, b);
    ui.state_on_free(tid, cmp_textures_free);
  }
  // This frame's textures, from the state above.
  cui_texture before = tx.before, after = tx.after;
  ui.row (gap: 24, align: start, width: fill) {
    ui.column (width: grow(1), gap: 10) {
      section(ui, "Chat", "Grouped bubbles, read receipts and a typing "
                          "indicator.");
      ui.card (gap: 0, pad: 16) {
        ui.chat_divider("Today");
        ui.chat_message("Did the data grid make it into 1.1?",
          author: "Jonas Berg", time: "9:41", last_in_group: false);
        ui.chat_message("I need it for the billing page.",
          author: "Jonas Berg", grouped: true, last_in_group: true);
        ui.chat_message("It did. 2,000 rows scroll at 60 fps on my laptop.",
                        mine: true);
        ui.chat_message("Shift and Ctrl clicks select like a spreadsheet.",
          mine: true, grouped: true, last_in_group: true,
          status: "Read", time: "9:43");
        ui.typing_indicator("Jonas");
      }
    }
    ui.column (width: grow(1), gap: 10) {
      section(ui, "Comments", "Threads with replies, likes and badges.");
      ui.card (gap: 4, pad: 14) {
        ui.comment("c1", "Tomas Rivera", "The new numbers match the staging "
                   "run. I would still test the import on a large file "
                   "before Friday.",
          time: "2h", likes: &likes[0], liked: &liked[0],
          badge: "Author");
        ui.comment("c2", "Priya Nair", "Agreed. I have a 2 GB export we can "
                   "use.",
          time: "1h", depth: 1, likes: &likes[1],
          liked: &liked[1]);
        ui.comment("c3", "Maya Okafor", "Scheduled it for 3 pm.",
          time: "40m", depth: 1, likes: &likes[2], liked: &liked[2],
          edited: true);
      }
    }
  }
  section(ui, "Presence", "Who is here now. Hover to spread them out.");
  ui.row (gap: 24, align: center) {
    ui.presence("here", [
      {name: "Maya Okafor", color: {r: 0x7c, g: 0x5c, b: 0xff, a: 255},
       avatar: 0},
      {name: "Jonas Berg", color: {r: 0x22, g: 0xc5, b: 0x8b, a: 255},
       avatar: 0},
      {name: "Priya Nair", color: {r: 0xf5, g: 0x9e, b: 0x0b, a: 255},
       avatar: 0},
      {name: "Lena Fischer", color: {r: 0x38, g: 0xbd, b: 0xf8, a: 255},
       avatar: 0, idle: true},
      {name: "Aiko Tanaka", color: {r: 0xec, g: 0x48, b: 0x99, a: 255},
       avatar: 0},
      {name: "Daniel Mensah", color: {r: 0x10, g: 0xb9, b: 0x81, a: 255},
       avatar: 0},
      {name: "Rosa Delgado", color: {r: 0xa8, g: 0x55, b: 0xf7, a: 255},
       avatar: 0}], 5, 30);
    ui.counter("rev", revenue, format: "$%.0f", size: 34,
                               group_thousands: true);
    if (ui.button("Add a sale", size: sm,
                                icon: plus))
      revenue += 1287;
  }

  section(ui, "Ticker", "A continuous strip of figures. It pauses under the "
                        "pointer.");
  ui.ticker("tick", [
    {label: "Revenue", value: "$48.2k", delta: 6.9f},
    {label: "Active users", value: "12,408", delta: 3.1f},
    {label: "Churn", value: "1.7%", delta: -0.6f, lower_is_better: true},
    {label: "Latency", value: "182 ms", delta: -8.4f, lower_is_better: true},
    {label: "Builds", value: "1,204", delta: 12.0f},
    {label: "Uptime", value: "99.98%", delta: 0}]);

  section(ui, "Carousel", "Drag, flick, scroll sideways or use the arrows "
                          "and dots.");
  ui.carousel ("tour", 4, slide, height: 200, auto_advance: 6) {
    // A slide is: title, description, and background color.
    List slides = %(
      ("Faster exports"
       "A 900 file project now exports in 40 seconds, down from four minutes."
       0x1f2a37)
      ("ARM64 runners"
       "Linux and macOS jobs can run on ARM64 machines in every plan."
       0x0f3d3e)
      ("Shortcuts everywhere"
       "Every action in the editor has a key, listed under Help, Shortcuts."
       0x3a2e22)
      ("Smaller downloads"
       "The desktop app is 38 MB lighter after dropping the bundled browser."
       0x2b2f3a));
    foreach (List slide in slides) ui.carousel_slide () {
      (String title, String desc, unsigned top) = slide;
      ui.box (width: fill, height: fill, bg: top, radius: 16, pad: 28,
              gap: 8, justify: end) {
        ui.text(title, font: display, size: 24,
                       color: 0xffffff);
        ui.text(desc, color: CUI_RGBA(0xffffffc0));
      }
    }
  }

  static cui_image_view view;
  static cui_rect crop;
  ui.row (gap: 24, align: start, width: fill,
          wrap: true) {
    ui.column (width: grow(3), min_width: 280, gap: 10) {
      section(ui, "Image viewer", "Wheel to zoom around the pointer, drag "
                                  "to pan, double-click for 100%.");
      ui.image_viewer("viewer", after, 640, 400, view,
                      height: 260);
    }
    ui.column (width: grow(2), min_width: 240, gap: 10) {
      section(ui, "Cropper", "Drag the corners; the square keeps its "
                             "shape.");
      ui.cropper("cropper", after, 640, 400, crop,
        aspect: 1, height: 260);
    }
  }
  ui.row (gap: 24, align: start, width: fill) {
    ui.column (width: grow(1), gap: 10) {
      section(ui, "Before and after", "Drag the divider.");
      ui.image_compare("cmp", before, after, split,
        height: 230, aspect: 640.0f / 400.0f);
    }
    ui.column (width: grow(1), gap: 10,
               align: center) {
      section(ui, "Card stack", "Flick the top card away, left or right.");
      // A card is: city and background color.
      List cities = %(("Kyoto" 0xc8553d) ("Lisbon" 0x2d3047)
                      ("Reykjavik" 0x5b8e7d) ("Oaxaca" 0xb7791f)
                      ("Hanoi" 0x1f3a5f));
      ui.card_stack (dir, "deck", 3, width: 260, height: 200)
      for (int k = 0; k < 3; k++) {
        (String name, unsigned color) = cities[(deck + k) % cities.len()];
        ui.card_stack_item (k)
        ui.box (width: fill, height: fill,
                bg: color, radius: 25, pad: 20,
                justify: end, gap: 4) {
          ui.text(name, font: display, size: 22,
                        color: 0xffffff);
          ui.text("Swipe right to save",
            size: 13, font: medium,
            color: CUI_RGBA(0xfffffff0));
        }
      }
      if (dir) {
        deck = (deck + 1) % 5;
        ui.toast(dir > 0 ? "Saved" : "Skipped");
      }
    }
  }
}
