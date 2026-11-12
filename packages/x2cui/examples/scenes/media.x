#pragma once

/*  media.x -- scenes for media, messages, disclosure, feedback,
    pickers, audio controls, and capture
*/

#include "scene.x"

#include <math.h>

static void scene_dock_item(Ui ui) {
  ui.row (width: fill, height: fill,
          justify: center, align: end)
  ui.dock ("dock") {
    ui.dock_item(folder, "Files", color: 0x3b82f6,
                                           running: true);
    ui.dock_item(mail, "Mail", color: 0x0ea5e9,
                                        badge: 3, running: true);
    ui.dock_item(calendar, "Calendar",
                 color: 0xef4444);
    ui.dock_item(music, "Music", color: 0xec4899,
                                          running: true);
    ui.dock_item(square_terminal, "Terminal",
                 color: 0x27272a);
    ui.dock_separator();
    ui.dock_item(settings, "Settings");
    ui.dock_item(trash_2, "Trash");
  }
}

static void scene_control_tile(Ui ui) {
  static bool wifi = true, hotspot = false, focus = true, dark = true;
  ui.box (dir: grid, columns: 2, gap: 10,
          width: 300) {
    ui.control_tile("Wi-Fi", wifi, icon: CUI_ICON_WIFI,
                                   detail: "Home");
    ui.control_tile("Hotspot", hotspot, icon: radio);
    ui.control_tile("Focus", focus, icon: moon,
                                    detail: "Until 6 pm");
  }
  ui.box (width: 300)
    ui.control_tile("Dark appearance", dark, icon: CUI_ICON_SUN,
                                             wide: true,
                                             width: fill);
}

static void scene_now_playing(Ui ui) {
  static cui_now_playing track = {
    .title = "Low Tide", .artist = "Marlow Avenue",
    .art_color = { 0xc8, 0x55, 0x3d, 255 }, .position = 76,
    .duration = 222, .playing = true };
  ui.now_playing("player", track);
}

static void scene_radial_gauge(Ui ui) {
  ui.row (gap: 28, align: center) {
    ui.radial_gauge("cpu", 72, 0, 100, unit: "%", label: "CPU load",
                                       bands: [
                                         {to: 60, tone: success},
                                         {to: 85, tone: warning},
                                         {to: 100, tone: danger}],
                                         band_count: 3);
    ui.radial_gauge("rps", 1840, 0, 2500,
      label: "Requests per second", show_target: true,
      target: 2000);
  }
}

static void scene_chat_message(Ui ui) {
  ui.card (width: fill, pad: 16, gap: 0) {
    ui.chat_divider("Today");
    ui.chat_message("Did the data grid make it into 1.1?",
                    author: "Jonas Berg", time: "9:41");
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

static void scene_comment(Ui ui) {
  static int likes[3] = { 12, 3, 0 };
  static bool liked[3] = { true, false, false };
  ui.card (width: fill, pad: 14, gap: 4) {
    ui.comment("c1", "Tomas Rivera",
               "The new numbers match the staging run. I would still test "
               "the import on a large file before Friday.",
               time: "2h", likes: &likes[0], liked: &liked[0],
               badge: "Author");
    ui.comment("c2", "Priya Nair", "Agreed. I have a 2 GB export we can use.",
               time: "1h", depth: 1, likes: &likes[1],
               liked: &liked[1]);
    ui.comment("c3", "Maya Okafor", "Scheduled it for 3 pm.",
               time: "40m", depth: 1, likes: &likes[2],
               liked: &liked[2], edited: true);
  }
}

static void scene_carousel(Ui ui) {
  static int slide = 1;
  static String titles[] = { "Faster exports", "ARM64 runners",
                             "Shortcuts everywhere" };
  static String notes[] = {
    "A 900 file project now exports in 40 seconds, down from four minutes.",
    "Linux and macOS jobs can run on ARM64 machines in every plan.",
    "Every action in the editor has a key, listed under Help, Shortcuts." };
  static const unsigned colors[] = { 0x1f2a37, 0x0f3d3e, 0x3a2e22 };
  ui.carousel ("tour", 3, slide, height: 200) {
    for (int k = 0; k < 3; k++) ui.carousel_slide ()
    ui.box (width: fill, height: fill,
            bg: colors[k], radius: 16, pad: 28,
            gap: 8, justify: end) {
      ui.text(titles[k], font: display, size: 24,
                         color: 0xffffff);
      ui.text(notes[k], color: CUI_RGBA(0xffffffc0));
    }
  }
}

// A landscape of sky, sun, hills, and fields, in color or in gray.
static void paint_landscape(unsigned char *pixels, int w, int h, bool color) {
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      float fx = (float) x / w, fy = (float) y / h;
      float r = 0.56f + fy * 0.34f, g = 0.72f + fy * 0.2f;
      float b = 0.88f + fy * 0.06f;
      float sun = (fx - 0.72f) * (fx - 0.72f) * 15.4f +
                  (fy - 0.24f) * (fy - 0.24f) * 6.0f;
      if (sun < 0.024f) { r = 1.0f; g = 0.97f; b = 0.86f; }
      float hills = 0.5f + 0.1f * sinf(fx * 6.0f + 0.6f);
      float fields = 0.68f + 0.06f * sinf(fx * 4.0f + 2.1f);
      if (fy > hills) { r = 0.5f; g = 0.6f; b = 0.62f - fy * 0.08f; }
      if (fy > fields) {
        r = 0.3f - (fy - fields) * 0.2f;
        g = 0.45f - (fy - fields) * 0.25f;
        b = 0.3f;
      }
      if (!color) r = g = b = (r * 0.3f + g * 0.59f + b * 0.11f) * 0.85f;
      unsigned char *p = pixels + (y * w + x) * 4;
      p[0] = (unsigned char) (fminf(1, fmaxf(0, r)) * 255);
      p[1] = (unsigned char) (fminf(1, fmaxf(0, g)) * 255);
      p[2] = (unsigned char) (fminf(1, fmaxf(0, b)) * 255);
      p[3] = 255;
    }
  }
}

static void scene_image_compare(Ui ui) {
  static cui_texture before, after;
  static float split = 0.42f;
  if (!before) {
    static unsigned char gray[480 * 300 * 4], color[480 * 300 * 4];
    paint_landscape(gray, 480, 300, false);
    paint_landscape(color, 480, 300, true);
    before = ui.image_create(480, 300, gray);
    after = ui.image_create(480, 300, color);
  }
  ui.image_compare("compare", before, after, split,
    width: 480, height: 300, before_label: "Before",
    after_label: "After", aspect: 480.0f / 300.0f);
}

static void scene_card_stack_item(Ui ui) {
  static String cities[] = { "Kyoto", "Lisbon", "Reykjavik" };
  static const unsigned colors[] = { 0xc8553d, 0x2d3047, 0x5b8e7d };
  ui.card_stack (swiped, "deck", 3, width: 240, height: 200)
  for (int k = 0; k < 3; k++) ui.card_stack_item (k)
  ui.box (width: fill, height: fill,
          bg: colors[k], radius: 25, pad: 20,
          gap: 4, justify: end) {
    ui.text(cities[k], font: display, size: 22,
                       color: 0xffffff);
    ui.text("Swipe right to save", size: 13, font: medium,
                                   color: CUI_RGBA(0xfffffff0));
  }
  (void) swiped;
}

static void scene_counter(Ui ui) {
  ui.label("Revenue this month");
  ui.counter("revenue", 48210, format: "$%.0f", size: 34,
                               group_thousands: true);
}

static void scene_code_block(Ui ui) {
  ui.code_block("counter",
    "#include <cui/cui.h>\n"
    "\n"
    "/* A counter with a button */\n"
    "static int clicks = 0;\n"
    "\n"
    "void frame(cui_ctx *ui) {\n"
    "    if (cui_button(ui, \"Click me\")) clicks++;\n"
    "    cui_textf(ui, \"Clicked %d times\", clicks);\n"
    "}\n",
    lang: "c", title: "counter.c", line_numbers: true,
    highlight_from: 7, highlight_to: 7);
}

static void scene_json_view(Ui ui) {
  ui.json_view("package",
    "{\"name\": \"cui\", \"version\": \"1.1.0\", \"private\": false,\n"
    " \"downloads\": 128400,\n"
    " \"platforms\": [\"windows\", \"macos\", \"linux\"],\n"
    " \"renderer\": {\"backend\": \"opengl\", \"vsync\": true,\n"
    "              \"msaa\": null},\n"
    " \"authors\": [{\"name\": \"Maya\", \"commits\": 412},\n"
    "             {\"name\": \"Jonas\", \"commits\": 388}]}",
    expand_depth: 1);
}

static void scene_hover_card(Ui ui) {
  ui.row (gap: 6, align: center) {
    ui.text("Assigned to");
    ui.link("@jonas");
    ui.hover_card ("jonas-card", width: 300)
    ui.row (gap: 12, align: start) {
      ui.avatar("Jonas Berg", size: 44, status: "online");
      ui.column (gap: 4, width: fill) {
        ui.text("Jonas Berg", font: medium);
        ui.text("Engineer on the rendering team.",
                size: 13, color: text_secondary);
      }
    }
    ui.text("and due Friday.");
  }
  ui.text("Rest the pointer on @jonas to open his card.",
          size: 12, color: text_muted);
}

static void scene_confirm_popover(Ui ui) {
  static bool open = true;
  if (ui.button("Delete branch", icon: trash_2) || open) {
    ui.popover_open("confirm-delete");
    open = false;
  }
  ui.confirm_popover("confirm-delete",
    title: "Delete feature/grid?",
    description: "The branch and its 12 commits are removed from the "
                   "remote.",
    confirm_label: "Delete branch", danger: true);
}

static void scene_expandable_text(Ui ui) {
  ui.box (width: 440)
    ui.expandable_text("about",
      "CUI is a component library for C. It draws everything itself, so an "
      "app looks the same on Windows, macOS and Linux, and it ships the "
      "parts most apps need: inputs, pickers, menus, dialogs, tables, "
      "charts and a command palette.", lines: 2);
}

static void scene_expandable_card(Ui ui) {
  static bool billing = true, security = false;
  ui.column (gap: 14, width: 440) {
    ui.expandable_card ("Billing", billing,
        description: "Pro plan, renews on December 1",
        icon: credit_card, badge: "Active",
        badge_tone: success)
    ui.row (gap: 8) {
      ui.button("Change plan", size: sm);
      ui.button("Invoices", size: sm,
                            variant: ghost);
    }
    ui.expandable_card ("Security", security,
        description: "Two-factor authentication is on",
        icon: shield)
      ui.text("Recovery codes");
  }
}

static void scene_banner(Ui ui) {
  static bool open = true;
  ui.banner("CUI 1.1 is out: data grid, kanban and forty new components.",
            open, action: "Read the notes", dismissible: true);
}

static void scene_countdown(Ui ui) {
  ui.column (gap: 8) {
    ui.label("Launch in");
    ui.countdown("launch", 2 * 86400 + 5 * 3600 + 42 * 60 + 18);
  }
  ui.column (gap: 8) {
    ui.label("Sale ends in");
    ui.countdown("sale", 5 * 3600 + 42 * 60 + 18,
                 compact: true, hide_days: true);
  }
}

static void scene_date_range_picker(Ui ui) {
  static cui_date_range trip = { { 2026, 11, 3 }, { 2026, 11, 14 } };
  ui.box (width: 300)
    ui.date_range_picker("trip", trip, label: "Trip dates",
                                       width: fill);
}

static void scene_time_picker(Ui ui) {
  static int start_hour = 9, start_minute = 30;
  static int end_hour = 18, end_minute = 45;
  ui.row (gap: 12) {
    ui.time_picker("start", start_hour, start_minute,
                   label: "Start", width: 180);
    ui.time_picker("end", end_hour, end_minute,
      label: "End", twelve_hour: true, minute_step: 15,
      width: 180);
  }
}

static void scene_wheel_picker(Ui ui) {
  static int day = 13, month = 10, year = 6;
  List days = %("1" "2" "3" "4" "5" "6" "7" "8" "9" "10" "11" "12" "13" "14"
                "15" "16" "17" "18" "19" "20" "21" "22" "23" "24" "25" "26"
                "27" "28" "29" "30" "31");
  List months = %("January" "February" "March" "April" "May" "June" "July"
                  "August" "September" "October" "November" "December");
  List years = %("2020" "2021" "2022" "2023" "2024" "2025" "2026" "2027"
                 "2028" "2029" "2030" "2031");
  ui.row () ui.card (pad: 8) ui.row (gap: 0) {
    ui.wheel_picker("day", days, day,
      width: 64, loop: true, join_right: true);
    ui.wheel_picker("month", months, month,
      width: 128, loop: true, join_left: true,
      join_right: true);
    ui.wheel_picker("year", years, year,
      width: 80, join_left: true);
  }
}

static void scene_ruler_slider(Ui ui) {
  static float height = 172;
  ui.box (width: 400)
    ui.ruler_slider("Height", height, 120, 220, unit: "cm");
}

static void scene_knob(Ui ui) {
  static float cutoff = 2400, resonance = 0.35f, drive = 4.5f, pan = -0.2f;
  ui.row () ui.card (pad: 18, gap: 16) {
    ui.label("Filter");
    ui.row (gap: 14) {
      ui.knob("Cutoff", cutoff, 20, 20000,
              unit: "Hz", log_scale: true, reset: 1000);
      ui.knob("Resonance", resonance, 0, 1, format: "%.2f");
      ui.knob("Drive", drive, 0, 12, format: "%.1f", unit: "dB");
      ui.knob("Pan", pan, -1, 1, bipolar: true, format: "%+.2f");
    }
  }
}

static void scene_fader(Ui ui) {
  static float gains[4] = { -6, 0, -12.5f, -3 };
  static String names[4] = { "Vocals", "Guitar", "Bass", "Drums" };
  static const float marks[] = { 6, 0, -6, -12, -24, -48 };
  ui.row () ui.card (pad: 18, dir: row, gap: 10) {
    for (int k = 0; k < 4; k++) ui.id (k)
      ui.fader(names[k], gains[k], -48, 6,
        unit: "dB", length: 170, ticks: k == 0 ? marks : NULL,
        tick_count: k == 0 ? 6 : 0);
  }
}

static void scene_signature_pad(Ui ui) {
  ui.column (gap: 8, width: 400) {
    ui.label("Sign here");
    ui.signature_pad("signature", width: fill, height: 140,
                                  placeholder: "Draw your signature");
  }
}

static void scene_dropzone(Ui ui) {
  ui.box (width: 400)
    ui.dropzone("files", description: "PNG, JPG or PDF, up to 25 MB",
                         accept: "png;jpg;pdf", height: 200);
}

static Scene media_scenes[] = {
  { "dock_item", scene_dock_item },
  { "control_tile", scene_control_tile },
  { "now_playing", scene_now_playing },
  { "radial_gauge", scene_radial_gauge },
  { "chat_message", scene_chat_message },
  { "comment", scene_comment },
  { "carousel", scene_carousel },
  { "carousel_slide", scene_carousel },
  { "image_compare", scene_image_compare },
  { "card_stack_item", scene_card_stack_item },
  { "counter", scene_counter },
  { "code_block", scene_code_block },
  { "json_view", scene_json_view },
  { "hover_card", scene_hover_card },
  { "confirm_popover", scene_confirm_popover },
  { "expandable_text", scene_expandable_text },
  { "expandable_card", scene_expandable_card },
  { "banner", scene_banner },
  { "countdown", scene_countdown },
  { "date_range_picker", scene_date_range_picker },
  { "time_picker", scene_time_picker },
  { "wheel_picker", scene_wheel_picker },
  { "ruler_slider", scene_ruler_slider },
  { "knob", scene_knob },
  { "fader", scene_fader },
  { "signature_pad", scene_signature_pad },
  { "dropzone", scene_dropzone },
};

Family media_family(void) => (Family){
  "Media, messages, and pickers", media_scenes,
  sizeof media_scenes / sizeof *media_scenes };
