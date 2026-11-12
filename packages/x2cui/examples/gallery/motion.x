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
  ui.card (gap: 18, pad: 20, width: CUI_FILL) {
    ui.row (gap: 10, align: CUI_ALIGN_CENTER) {
      ui.loader(style: CUI_LOADER_DOTS, size: 22);
      ui.shimmer_text("Thinking about your question\xe2\x80\xa6",
                      size: 15);
    }
    $cui.id_index(ui, replay) {
      ui.typewriter("tw", "CUI draws a full frame in a fraction of a "
                          "millisecond, so text can stream in as fast as "
                          "it arrives.", caret: true, size: 15);
      ui.text_reveal("rv", "The release build finished in 3 minutes 42 "
                           "seconds.",
                     size: 20, font: CUI_FONT_DISPLAY);
    }
    ui.row (gap: 8, align: CUI_ALIGN_CENTER) {
      ui.text("Deploying to", font: CUI_FONT_DISPLAY, size: 26);
      ui.word_rotate("rot", %("staging." "eu-west." "us-east."
                              "all regions."),
                     2.2f, font: CUI_FONT_DISPLAY, size: 26);
    }
    if (ui.button("Replay", size: CUI_SIZE_SM,
                            icon: CUI_ICON_ROTATE_CCW,
                            variant: CUI_BUTTON_OUTLINE))
      replay++;
  }
  section(ui, "Gradient text and spotlight cards",
          "A light follows the pointer across a card and along its edge. "
          "A beam marks the one card that is live.");
  ui.gradient_text("Kiln 2.4", font: CUI_FONT_DISPLAY, size: 34,
                               animate: true);
  ui.row (gap: 14, align: CUI_ALIGN_STRETCH, width: CUI_FILL) {
    List cards = %(("Software" "Plain C into a pixel buffer. No GPU needed.")
                   ("OpenGL 3.3" "The default on desktop. Deploying now.")
                   ("Your own"
                    "The core emits triangles; bring any GPU API."));
    int k = 0;
    foreach (List card in cards) {
      (String title, String blurb) = card;
      $cui.id_index(ui, k)
      ui.spotlight ("spot", width: CUI_GROW(1), beam: k == 1) {
        ui.text(title, font: CUI_FONT_MEDIUM, size: 15);
        ui.text(blurb, size: 13, color: CUI_COLOR_TEXT_SECONDARY);
      }
      k++;
    }
  }
  section(ui, "Loaders", "Dots, bars, pulse, orbit and grid.");
  ui.row (gap: 36, align: CUI_ALIGN_CENTER) {
    for (int k = 0; k < 5; k++)
      ui.loader(style: (cui_loader_style) k, size: 28);
  }
  section(ui, "Dock", "Icons grow as the pointer passes.");
  ui.row (width: CUI_FILL, justify: CUI_JUSTIFY_CENTER,
          height: CUI_PX(110), align: CUI_ALIGN_END)
  ui.dock ("dock") {
    if (ui.dock_item(CUI_ICON_FOLDER, "Files",
                     color: CUI_RGB(0x3b82f6), running: true))
      ui.toast("Files");
    ui.dock_item(CUI_ICON_MAIL, "Mail", color: CUI_RGB(0x0ea5e9),
                                        badge: 3, running: true);
    ui.dock_item(CUI_ICON_CALENDAR, "Calendar",
                 color: CUI_RGB(0xef4444));
    ui.dock_item(CUI_ICON_MUSIC, "Music", color: CUI_RGB(0xec4899),
                                          running: true);
    ui.dock_item(CUI_ICON_SQUARE_TERMINAL, "Terminal",
                 color: CUI_RGB(0x27272a));
    ui.dock_item(CUI_ICON_PALETTE, "Design", color: CUI_RGB(0x8b5cf6));
    ui.dock_separator();
    ui.dock_item(CUI_ICON_SETTINGS, "Settings");
    ui.dock_item(CUI_ICON_TRASH_2, "Trash");
  }
  ui.row (gap: 28, align: CUI_ALIGN_START, width: CUI_FILL) {
    ui.column (width: CUI_GROW(1), gap: 10) {
      section(ui, "Control tiles", "Big toggles for quick settings.");
      ui.box (dir: CUI_GRID, columns: 2, gap: 10,
              width: CUI_PX(300)) {
        ui.control_tile("Wi-Fi", wifi, icon: CUI_ICON_WIFI,
                                       detail: wifi ? "Home" : "Off");
        ui.control_tile("Hotspot", bt, icon: CUI_ICON_RADIO);
        ui.control_tile("Focus", focus,
          icon: CUI_ICON_MOON, detail: focus ? "Until 6 pm" : "Off");
        ui.control_tile("AirShare", airdrop,
          icon: CUI_ICON_SHARE_2,
          detail: airdrop ? "Everyone" : "Contacts only");
      }
      ui.control_tile("Dark appearance", dark_tile,
        icon: CUI_ICON_SUN, wide: true, width: CUI_PX(300));
    }
    ui.column (width: CUI_GROW(1), gap: 10) {
      section(ui, "Now playing", "Artwork, a scrubber and transport.");
      int ev = ui.now_playing("np", np);
      if (ev & CUI_PLAYER_NEXT) ui.toast("Next track");
      if (np.playing) {
        np.position += ui.delta_time();
        if (np.position > np.duration) np.position = 0;
      }
      section(ui, "Waveform", "Click or drag to seek.");
      ui.card (pad: 14, gap: 8, width: CUI_PX(360))
      ui.row (gap: 12, align: CUI_ALIGN_CENTER,
              width: CUI_FILL) {
        ui.icon_button(CUI_ICON_PLAY, size: CUI_SIZE_SM,
                                      variant: CUI_BUTTON_SECONDARY);
        ui.box (width: CUI_FILL)
          ui.waveform("wave", peaks, $cui.count(peaks), progress,
                      height: 34);
        ui.text("0:42", size: 12, tabular: true,
                        color: CUI_COLOR_TEXT_MUTED);
      }
      section(ui, "Tab bar", "For compact layouts.");
      static const cui_tab_bar_item tabs[] = {
        { CUI_ICON_HOUSE, "Home", 0 }, { CUI_ICON_SEARCH, "Search", 0 },
        { CUI_ICON_INBOX, "Inbox", 4 }, { CUI_ICON_USER, "Profile", 0 } };
      ui.tab_bar("tabs", tabs, $cui.count(tabs), tab,
                 width: CUI_PX(360));
    }
  }
}
