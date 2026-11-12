#pragma once

/*  choices.x -- scenes for choice groups, tabs, guided steps, assistant
    prompts, calendars and schedules, and animation and property editors

    These components read arrays of CUI's records. The arrays are static C
    arrays written with designated initializers, and each method form
    supplies the count of its array. The calendars show fixed dates in
    November 2026.
*/

#include "scene.x"

static void scene_radio_cards(Ui ui) {
  static int place = 1;
  ui.box (width: fill, max_width: 420)
    ui.radio_cards("places", [
      {title: "This computer",
       description: "Saved next to the project. Nothing leaves the machine.",
       icon: monitor},
      {title: "Team server",
       description: "Synced to your company server every few minutes.",
       icon: server, badge: "Default"},
      {title: "Both",
       description: "A local copy, uploaded to the server every night.",
       icon: layers}], place);
}

static void scene_toggle_group(Ui ui) {
  static bool format[4] = { true, false, true, false };
  static bool align[3] = { true, false, false };
  ui.row (gap: 12, wrap: true) {
    ui.toggle_group("format", %("Bold" "Italic" "Underline" "Code"), format,
                    icons: [bold, italic, underline, code], icon_only: true);
    ui.toggle_group("align", %("Left" "Center" "Right"), align,
                    exclusive: true);
  }
}

static void scene_multi_select(Ui ui) {
  static bool chosen[8] = { true, false, true, false, false, true };
  ui.box (width: 320)
    ui.multi_select("langs", %("C" "C++" "Rust" "Zig" "Go" "Swift" "Kotlin"
                               "Odin"), chosen, label: "Languages",
                                                searchable: true);
}

static void scene_tab_bar(Ui ui) {
  static const cui_tab_bar_item tabs[] = {
    { CUI_ICON_HOUSE, "Home", 0 }, { CUI_ICON_SEARCH, "Search", 0 },
    { CUI_ICON_INBOX, "Inbox", 4 }, { CUI_ICON_USER, "Profile", 0 } };
  static int tab = 2;
  ui.card (width: 360, pad: 1, gap: 0) {
    ui.column (pad: 20, gap: 8, width: fill) {
      ui.heading("Inbox", 3);
      ui.text("4 unread messages from your team.",
              color: text_secondary);
    }
    ui.box (pad: 12, width: fill)
      ui.tab_bar("tabs", tabs, tab, width: fill);
  }
}

static void scene_doc_tabs(Ui ui) {
  static cui_doc_tab tabs[] = {
    { "README.md", CUI_ICON_FILE_TEXT, "docs/README.md", false },
    { "tile_cache.c", CUI_ICON_CODE, "src/tile_cache.c", true },
    { "tile_cache.h", CUI_ICON_CODE, "src/tile_cache.h", false },
    { "CHANGELOG.md", CUI_ICON_FILE_TEXT, "CHANGELOG.md", true } };
  static int open = 4, selected = 1;
  ui.card (width: fill, max_width: 620, pad: 1,
           gap: 0) {
    cui_doc_tabs_result result = ui.doc_tabs("docs", tabs, open, selected,
      no_reorder: true);
    if (result.close >= 0) {
      for (int k = result.close; k < open - 1; k++) tabs[k] = tabs[k + 1];
      open--;
      if (selected >= open) selected = open - 1;
    }
    if (open > 0) ui.column (pad: 16, gap: 6, width: fill) {
      ui.text(tabs[selected].tooltip, font: medium);
      ui.text(tabs[selected].dirty ? "Unsaved changes" : "Saved",
              size: 13, color: text_muted);
    }
  }
}

static void scene_speed_dial(Ui ui) {
  static const cui_speed_action actions[] = {
    { CUI_ICON_FILE_TEXT, "New note" }, { CUI_ICON_IMAGE, "Upload image" },
    { CUI_ICON_MIC, "Record memo" } };
  static int chosen = 1;
  ui.row (gap: 16, align: center) {
    int picked = ui.speed_dial("create", actions,
                               tooltip: "Create");
    if (picked >= 0) chosen = picked;
    ui.text(%"Last created: $(actions[chosen].label)",
            color: text_secondary);
  }
}

static void scene_checklist(Ui ui) {
  static cui_check_step steps[] = {
    { "Create your workspace", "Pick a name and invite your team.", "Create",
      true },
    { "Connect a repository",
      "Link GitHub or GitLab to sync issues and pull requests.", "Connect",
      false },
    { "Import your data", "Bring tasks over from a CSV or another tool.",
      "Import", false },
    { "Turn on notifications", "Get pinged when something needs you.",
      "Enable", false } };
  ui.box (width: 460) {
    int done = ui.checklist("onboarding", steps,
      title: "Set up your workspace");
    if (done >= 0) steps[done].done = true;
  }
}

// The tour opens on its second step, which points at the Share button.
static void scene_tour(Ui ui) {
  static cui_tour_step steps[] = {
    { 0, "Welcome to Fieldnotes",
      "A quick look at the things you will use every day.", 0 },
    { 0, "Share with your team",
      "People you invite can comment without an account.",
      CUI_PLACE_BOTTOM_END },
    { 0, "Export anywhere", "Send a report to PDF, Markdown, or a drive.",
      CUI_PLACE_BOTTOM_END } };
  static int step = 1;
  ui.card (width: fill, max_width: 620, pad: 1,
           gap: 0) {
    ui.row (gap: 8, align: center, width: fill,
            pad: 12) {
      ui.heading("Q3 field report", 4);
      ui.spacer();
      ui.button("Share", icon: users,
                         variant: outline);
      steps[1].target = ui.last_id();
      ui.button("Export", icon: download,
                          variant: primary);
      steps[2].target = ui.last_id();
    }
    ui.separator();
    ui.column (pad: 20, gap: 10, width: fill)
      ui.text("Survey results from the coastal sites, with photos and the "
              "soil samples sent to the lab.",
              color: text_secondary);
  }
  if (step >= 0) ui.tour("intro", steps, step);
}

static void scene_agent_plan(Ui ui) {
  static const cui_plan_step steps[] = {
    { "Search for sources", "3 results", CUI_TASK_DONE },
    { "Read the attached report", "Page 12 of 40", CUI_TASK_RUNNING },
    { "Compare the numbers with last quarter", NULL, CUI_TASK_PENDING },
    { "Draft the summary", NULL, CUI_TASK_PENDING },
    { "Check the citations", NULL, CUI_TASK_PENDING } };
  ui.box (width: fill, max_width: 460)
    ui.agent_plan("plan", steps,
      title: "Research plan");
}

static void scene_prompt_suggestions(Ui ui) {
  static const cui_prompt_suggestion suggestions[] = {
    { CUI_ICON_CODE, "Explain this code", "Walk through what it does" },
    { CUI_ICON_CHART_BAR, "Analyze a dataset", "Find trends and outliers" },
    { CUI_ICON_PENCIL, "Draft an email", "Clear and friendly" },
    { CUI_ICON_BUG, "Debug an error", "Paste the stack trace" } };
  static int picked = -1;
  ui.column (gap: 12, width: fill, max_width: 560) {
    ui.heading("What can I help with?", 3);
    int chosen = ui.prompt_suggestions(
      "starters", suggestions, columns: 2);
    if (chosen >= 0) picked = chosen;
    if (picked >= 0) ui.muted(suggestions[picked].title);
  }
}

static void scene_model_picker(Ui ui) {
  static int model = 1;
  ui.row (gap: 8, align: center) {
    ui.text("Answer with", color: text_secondary);
    ui.model_picker("model", [
      {name: "Atlas", detail: "Longer answers, reads files and code",
       badge: "New", icon: layers},
      {name: "Atlas Fast", detail: "Short answers in about a second",
       icon: zap},
      {name: "Atlas Mini", detail: "Runs on your own machine", icon: box}], model,
      placement: bottom_start);
  }
}

static void scene_month_calendar(Ui ui) {
  static const cui_month_event events[] = {
    { "Design sprint", { 2026, 11, 2 }, { 2026, 11, 4 }, 0, true,
      CUI_TONE_VIOLET },
    { "Standup", { 2026, 11, 9 }, { 0 }, 9.5f, false, CUI_TONE_INFO },
    { "Customer call", { 2026, 11, 10 }, { 0 }, 11, false, CUI_TONE_DANGER },
    { "Offsite, Lisbon", { 2026, 11, 12 }, { 2026, 11, 14 }, 0, true,
      CUI_TONE_WARNING },
    { "Demo day", { 2026, 11, 20 }, { 0 }, 16, false, CUI_TONE_VIOLET },
    { "Holiday", { 2026, 11, 26 }, { 2026, 11, 27 }, 0, true,
      CUI_TONE_SUCCESS },
    { "Board meeting", { 2026, 11, 30 }, { 0 }, 10, false, CUI_TONE_DANGER } };
  static cui_date month = { 2026, 11, 1 }, picked = { 2026, 11, 10 };
  ui.month_calendar("month", month, events,
    selected: &picked, today: { 2026, 11, 10 }, cell_height: 58);
}

static void scene_week_calendar(Ui ui) {
  static cui_cal_event events[] = {
    { "Standup", "Zoom", 0, 9.5f, 9.75f, CUI_TONE_INFO },
    { "Design review", "Room 2", 0, 13, 14.5f, CUI_TONE_VIOLET },
    { "Release planning", "Room 1", 1, 10, 11.5f, CUI_TONE_WARNING },
    { "Focus time", "No meetings", 2, 14, 17, CUI_TONE_TEAL },
    { "Customer call", "Northlight", 3, 15, 16, CUI_TONE_DANGER },
    { "Demo day", "All hands", 4, 11, 12.5f, CUI_TONE_SUCCESS } };
  cui_date monday = { 2026, 11, 9 };
  ui.week_calendar("week", monday, events,
    start_hour: 8, end_hour: 18, hour_height: 34,
    height: 344);
}

static void scene_gantt(Ui ui) {
  static cui_gantt_task tasks[] = {
    { "Research", "Maya Okafor", 0, 3, 1, CUI_TONE_TEAL, -1, false },
    { "Wireframes", "Aiko Tanaka", 3, 7, 1, CUI_TONE_TEAL, 0, false },
    { "Core engine", "Jonas Berg", 5, 13, 0.55f, CUI_TONE_INFO, 0, false },
    { "Platform backends", "Daniel Mensah", 10, 16, 0.2f, CUI_TONE_TEAL, 2,
      false },
    { "Beta", NULL, 17, 17, 0, CUI_TONE_WARNING, 3, true },
    { "Docs and launch", "Priya Nair", 18, 20, 0, CUI_TONE_SUCCESS, 4,
      false } };
  cui_date origin = { 2026, 11, 2 };
  ui.gantt("plan", tasks, origin, 21,
    day_width: 20, today: 8);
}

// A shot: a logo that slides in and fades up, over a sound clip.
static void scene_timeline_editor(Ui ui) {
  enum { KEYS = 8 };
  static cui_curve_key slide[KEYS] = {
    { 0, 0 }, { 1.5f, 320 }, { 3, 360 }, { 5, 360 } };
  static cui_curve_key fade[KEYS] = {
    { 0, 0, 0, 0, 0, 0, CUI_CURVE_LINEAR }, { 1, 1 }, { 4.5f, 1 },
    { 5, 0, 0, 0, 0, 0, CUI_CURVE_LINEAR } };
  static cui_timeline_clip sounds[2] = {
    { 0.5f, 2.5f, 0, "Whoosh", false },
    { 3, 4.75f, 0.5f, "Street ambience", false } };
  static cui_timeline_track tracks[] = {
    { "Logo", CUI_ICON_IMAGE, 0 },
    { "Position X", NULL, 1, .keys = slide, .key_count = 4,
      .key_capacity = KEYS },
    { "Opacity", NULL, 1, .keys = fade, .key_count = 4,
      .key_capacity = KEYS },
    { "Sound", CUI_ICON_AUDIO_LINES, 0, .color = 3, .clips = sounds,
      .clip_count = 2 } };
  static float time = 1.5f;
  ui.timeline_editor("shot", tracks, time,
    end: 5, fps: 24, toggles: true);
}

static void scene_curve_editor(Ui ui) {
  static cui_curve_key keys[16] = {
    { 0, 0 }, { 0.55f, 0.66f, -0.22f, -0.42f, 0.24f, 0.46f, CUI_CURVE_FREE },
    { 1.2f, 1.08f }, { 2, 1 } };
  static int count = 4, selected = 1;
  ui.box (width: fill, max_width: 620)
    ui.curve_editor("ease", keys, count,
      x_max: 2, y_max: 1.2f, x_label: "Time", y_label: "Value",
      selected: &selected);
}

static void scene_gradient_editor(Ui ui) {
  static cui_gradient_stop stops[12] = {
    { 0, { 0xFF, 0xF1, 0xC1, 0xFF } }, { 0.24f, { 0xFF, 0xB1, 0x4A, 0xFF } },
    { 0.58f, { 0xE2, 0x55, 0x2B, 0xFF } },
    { 1, { 0x5C, 0x1F, 0x16, 0x00 } } };
  static int count = 4, selected = 2;
  ui.column (width: fill, max_width: 560, gap: 10) {
    ui.text("Flame color over lifetime", font: medium,
                                         size: 13);
    ui.gradient_editor("flame", stops, count,
      selected: &selected);
  }
}

static void scene_prop_vec2(Ui ui) {
  static bool open = true;
  static float size[2] = { 1280, 720 }, anchor[2] = { 0.5f, 0.5f };
  ui.card (width: fill, max_width: 460, pad_x: 16,
           pad_y: 6, gap: 0)
  ui.inspector ("canvas") {
    if (ui.inspector_group("Canvas", open)) {
      ui.prop_vec2("Size", size, step: 1, format: "%.0f",
                                 suffix: "px");
      ui.prop_vec2("Anchor", anchor, min: 0, max: 1,
                                     format: "%.2f");
    }
  }
}

static void scene_prop_vec3(Ui ui) {
  static bool open = true;
  static float position[3] = { 1.25f, 0, -3.5f }, rotation[3] = { 0, 45, 0 };
  static float scale[3] = { 1, 1, 1 };
  ui.card (width: fill, max_width: 460, pad_x: 16,
           pad_y: 6, gap: 0)
  ui.inspector ("transform") {
    if (ui.inspector_group("Transform", open)) {
      ui.prop_vec3("Position", position, step: 0.05f,
                                         format: "%.2f");
      ui.prop_vec3("Rotation", rotation, step: 1, format: "%.0f");
      ui.prop_vec3("Scale", scale, step: 0.01f, format: "%.2f");
    }
  }
}

static void scene_prop_vec4(Ui ui) {
  static bool open = true;
  static float orientation[4] = { 0, 0.38f, 0, 0.92f };
  static float tint[4] = { 1, 0.85f, 0.6f, 1 };
  ui.card (width: fill, max_width: 540, pad_x: 16,
           pad_y: 6, gap: 0)
  ui.inspector ("light") {
    if (ui.inspector_group("Light", open)) {
      ui.prop_vec4("Orientation", orientation, min: -1, max: 1,
                                               format: "%.2f");
      ui.prop_vec4("Tint", tint, min: 0, max: 1,
                                 format: "%.2f");
    }
  }
}

static Scene choices_scenes[] = {
  { "radio_cards", scene_radio_cards },
  { "toggle_group", scene_toggle_group },
  { "multi_select", scene_multi_select },
  { "tab_bar", scene_tab_bar },
  { "doc_tabs", scene_doc_tabs },
  { "speed_dial", scene_speed_dial },
  { "checklist", scene_checklist },
  { "tour", scene_tour },
  { "agent_plan", scene_agent_plan },
  { "prompt_suggestions", scene_prompt_suggestions },
  { "model_picker", scene_model_picker },
  { "month_calendar", scene_month_calendar },
  { "week_calendar", scene_week_calendar },
  { "gantt", scene_gantt },
  { "timeline_editor", scene_timeline_editor },
  { "curve_editor", scene_curve_editor },
  { "gradient_editor", scene_gradient_editor },
  { "prop_vec2", scene_prop_vec2 },
  { "prop_vec3", scene_prop_vec3 },
  { "prop_vec4", scene_prop_vec4 },
};

Family choices_family(void) {
  return (Family){ "Choices and planning", choices_scenes,
                   sizeof choices_scenes / sizeof *choices_scenes };
}
