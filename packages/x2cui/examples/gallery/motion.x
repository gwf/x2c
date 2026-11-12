#pragma once

/*  motion.x -- the gallery's Motion page */

#include <math.h>

#include "state.x"

static float peaks[96];

static void prepare(void) {
  for (int k = 0; k < 96; k++)
    peaks[k] = 0.18f + 0.8f * fabsf(sinf(k * 0.37f) * sinf(k * 0.11f + 1.3f));
}

void page_motion(Ui ui, Gallery g) {
  static bool ready = false;
  if (!ready) {
    prepare();
    ready = true;
  }
  static int replay;
  static float progress = 0.36f;
  static bool wifi = true, bt = false, focus = true, airdrop = false,
              dark_tile = true;
  static int tab = 0;
  static cui_now_playing np = {
    "Low Tide", "Marlow Avenue", 0, { 0xc8, 0x55, 0x3d, 255 }, 76, 222,
    true };
  section(ui, "Text effects", "A shimmer for pending work, a typewriter for "
                              "streamed text, words that settle into "
                              "place.");
  ui.card (gap: 18, pad: 20, width: fill) {
    ui.row (gap: 10, align: center) {
      ui.loader(style: dots, size: 22);
      ui.shimmer_text("Thinking about your question\xe2\x80\xa6",
                      size: 15);
    }
    ui.id (replay) {
      ui.typewriter("tw", "CUI draws a full frame in a fraction of a "
                          "millisecond, so text can stream in as fast as "
                          "it arrives.", caret: true, size: 15);
      ui.text_reveal("rv", "The release build finished in 3 minutes 42 "
                           "seconds.",
                     size: 20, font: display);
    }
    ui.row (gap: 8, align: center) {
      ui.text("Deploying to", font: display, size: 26);
      ui.word_rotate("rot", %("staging." "eu-west." "us-east."
                              "all regions."),
                     2.2f, font: display, size: 26);
    }
    if (ui.button("Replay", size: sm,
                            icon: rotate_ccw,
                            variant: outline))
      replay++;
  }
  section(ui, "Gradient text and spotlight cards",
          "A light follows the pointer across a card and along its edge. "
          "A beam marks the one card that is live.");
  ui.gradient_text("Kiln 2.4", font: display, size: 34,
                               animate: true);
  ui.row (gap: 14, align: stretch, width: fill) {
    List cards = %(("Software" "Plain C into a pixel buffer. No GPU needed.")
                   ("OpenGL 3.3" "The default on desktop. Deploying now.")
                   ("Your own"
                    "The core emits triangles; bring any GPU API."));
    int k = 0;
    foreach (List card in cards) {
      (String title, String blurb) = card;
      ui.id (k)
      ui.spotlight ("spot", width: grow(1), beam: k == 1) {
        ui.text(title, font: medium, size: 15);
        ui.text(blurb, size: 13, color: text_secondary);
      }
      k++;
    }
  }
  section(ui, "Loaders", "Dots, bars, pulse, orbit and grid.");
  ui.row (gap: 36, align: center) {
    for (int k = 0; k < 5; k++)
      ui.loader(style: (cui_loader_style) k, size: 28);
  }
  section(ui, "Dock", "Icons grow as the pointer passes.");
  ui.row (width: fill, justify: center,
          height: 110, align: end)
  ui.dock ("dock") {
    if (ui.dock_item(folder, "Files",
                     color: CUI_RGB(0x3b82f6), running: true))
      ui.toast("Files");
    ui.dock_item(mail, "Mail", color: CUI_RGB(0x0ea5e9),
                                        badge: 3, running: true);
    ui.dock_item(calendar, "Calendar",
                 color: CUI_RGB(0xef4444));
    ui.dock_item(music, "Music", color: CUI_RGB(0xec4899),
                                          running: true);
    ui.dock_item(square_terminal, "Terminal",
                 color: CUI_RGB(0x27272a));
    ui.dock_item(palette, "Design", color: CUI_RGB(0x8b5cf6));
    ui.dock_separator();
    ui.dock_item(settings, "Settings");
    ui.dock_item(trash_2, "Trash");
  }
  ui.row (gap: 28, align: start, width: fill) {
    ui.column (width: grow(1), gap: 10) {
      section(ui, "Control tiles", "Big toggles for quick settings.");
      ui.box (dir: grid, columns: 2, gap: 10,
              width: 300) {
        ui.control_tile("Wi-Fi", wifi, icon: CUI_ICON_WIFI,
                                       detail: wifi ? "Home" : "Off");
        ui.control_tile("Hotspot", bt, icon: radio);
        ui.control_tile("Focus", focus,
          icon: moon, detail: focus ? "Until 6 pm" : "Off");
        ui.control_tile("AirShare", airdrop,
          icon: share_2,
          detail: airdrop ? "Everyone" : "Contacts only");
      }
      ui.control_tile("Dark appearance", dark_tile,
        icon: sun, wide: true, width: 300);
    }
    ui.column (width: grow(1), gap: 10) {
      section(ui, "Now playing", "Artwork, a scrubber and transport.");
      int ev = ui.now_playing("np", np);
      if (ev & CUI_PLAYER_NEXT) ui.toast("Next track");
      if (np.playing) {
        np.position += ui.delta_time();
        if (np.position > np.duration) np.position = 0;
      }
      section(ui, "Waveform", "Click or drag to seek.");
      ui.card (pad: 14, gap: 8, width: 360)
      ui.row (gap: 12, align: center,
              width: fill) {
        ui.icon_button(play, size: sm,
                                      variant: secondary);
        ui.box (width: fill)
          ui.waveform("wave", peaks, progress,
                      height: 34);
        ui.text("0:42", size: 12, tabular: true,
                        color: text_muted);
      }
      section(ui, "Tab bar", "For compact layouts.");
      static const cui_tab_bar_item tabs[] = {
        { CUI_ICON_HOUSE, "Home", 0 }, { CUI_ICON_SEARCH, "Search", 0 },
        { CUI_ICON_INBOX, "Inbox", 4 }, { CUI_ICON_USER, "Profile", 0 } };
      ui.tab_bar("tabs", tabs, tab,
                 width: 360);
    }
  }
}
