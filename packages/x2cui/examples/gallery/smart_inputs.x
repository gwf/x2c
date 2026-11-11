#pragma once

/*  smart_inputs.x -- the gallery's Smart inputs page */

#include "state.x"

static TextField title, owner, url, weight, message;

static void prepare(void) {
  title = TextField.new(128);
  owner = TextField.new(64);
  url = TextField.new(96);
  weight = TextField.new(16);
  message = TextField.new(160);
  title.set("Q3 roadmap");
  owner.set("Jonas Berg");
  url.set("cui.dev");
  weight.set("72");
  message.set("Release notes are up ");
}

void page_smart_inputs(Ui ui, Gallery g) {
  static bool ready = false;
  if (!ready) {
    prepare();
    ready = true;
  }
  static float opacity = 80, radius = 12, blur = 24;
  static double amount = 1249.5, salary = 98000;
  static cui_key_combo combo = { CUI_MOD_PRIMARY | CUI_MOD_SHIFT,
                                 CUI_KEY_P };
  static cui_key_combo combo2 = { 0, CUI_KEY_NONE };

  section(ui, "Inline edit",
          "Click the text to edit it in place. Enter saves, Esc cancels.");
  $cui.column(ui, { .gap = 6 }) {
    ui.inline_edit("title", title, { .font = CUI_FONT_DISPLAY, .size = 26 });
    ui.inline_edit("owner", owner, { .placeholder = "Add an owner" });
  }

  section(ui, "Scrub fields",
          "Drag sideways to change the value, Shift for fine steps, click "
          "to type.");
  $cui.row(ui, { .gap = 12, .wrap = true }) {
    ui.scrub("Opacity", opacity, 0, 100, { .suffix = "%" });
    ui.scrub("Radius", radius, 0, 48, { .step = 0.5f, .format = "%.1f",
                                        .suffix = "px" });
    ui.scrub("Blur", blur, 0, 80, { .suffix = "px",
                                    .width = CUI_PX(140) });
  }

  section(ui, "Money", "Grouped digits at rest, plain digits while typing.");
  $cui.row(ui, { .gap = 12, .align = CUI_ALIGN_START }) {
    $cui.box(ui, { .width = CUI_PX(240) })
      ui.money_input("amount", amount, { .label = "Amount", .code = "USD" });
    $cui.box(ui, { .width = CUI_PX(240) })
      ui.money_input("salary", salary, {
        .label = "Salary", .symbol = "\xe2\x82\xac", .code = "EUR",
        .decimals = -1, .hint = "Gross per year" });
  }

  section(ui, "Prefix and suffix",
          "Any text field can carry muted text before and after the "
          "value.");
  $cui.row(ui, { .gap = 12, .wrap = true }) {
    ui.input("url", url, { .prefix = "https://", .width = CUI_PX(260) });
    ui.input("weight", weight, { .suffix = "kg", .width = CUI_PX(120) });
  }

  section(ui, "Shortcut recorder",
          "Click, then press a combination. Backspace clears.");
  $cui.row(ui, { .gap = 12, .wrap = true }) {
    ui.shortcut_recorder("palette-key", combo, {});
    ui.shortcut_recorder("search-key", combo2, {
      .placeholder = "Record shortcut" });
  }

  static char recent[256];
  static int tone;
  section(ui, "Emoji picker",
          "Search by name, jump by group, pick a skin tone. Recent emoji "
          "come first.");
  $cui.row(ui, { .gap = 8, .align = CUI_ALIGN_CENTER, .width = CUI_FILL,
                 .max_width = 480 }) {
    ui.input("message", message, { .width = CUI_FILL });
    if (ui.icon_button(CUI_ICON_SMILE, { .tooltip = "Emoji" }))
      ui.popover_toggle("emoji-pop");
    $cui.popover(ui, "emoji-pop", { .placement = CUI_PLACE_BOTTOM_END,
                                    .width = 340, .pad = 0 }) {
      String e = ui.emoji_picker("emoji", {
        .recent = recent, .recent_cap = sizeof recent, .tone = &tone,
        .height = 260 });
      if (e) {
        String text = message.text() + e;
        if (text.len() < message.capacity) {
          message.set(text);
          ui.popover_close("emoji-pop");
        }
      }
    }
  }
}
