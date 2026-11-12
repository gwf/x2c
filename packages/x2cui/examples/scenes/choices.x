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
  static int tab = 2;
  ui.card (width: 360, pad: 1, gap: 0) {
    ui.column (pad: 20, gap: 8, width: fill) {
      ui.heading("Inbox", 3);
      ui.text("4 unread messages from your team.",
              color: text_secondary);
    }
    ui.box (pad: 12, width: fill)
      ui.tab_bar("tabs", [
        {icon: house, label: "Home"}, {icon: search, label: "Search"},
        {icon: inbox, label: "Inbox", badge: 4},
        {icon: user, label: "Profile"}], tab, width: fill);
  }
}

static void scene_doc_tabs(Ui ui) {
  static DocTabs tabs = DocTabs.of([
    {title: "README.md", icon: file_text, tooltip: "docs/README.md"},
    {title: "tile_cache.c", icon: code, tooltip: "src/tile_cache.c",
     dirty: true},
    {title: "tile_cache.h", icon: code, tooltip: "src/tile_cache.h"},
    {title: "CHANGELOG.md", icon: file_text, tooltip: "CHANGELOG.md",
     dirty: true}]);
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
      ui.text(tabs.at(selected).tooltip, font: medium);
      ui.text(tabs.at(selected).dirty ? "Unsaved changes" : "Saved",
              size: 13, color: text_muted);
    }
  }
}

static void scene_speed_dial(Ui ui) {
  static SpeedActions actions = SpeedActions.of([
    {icon: file_text, label: "New note"}, {icon: image, label: "Upload image"},
    {icon: mic, label: "Record memo"}]);
  static int chosen = 1;
  ui.row (gap: 16, align: center) {
    int picked = ui.speed_dial("create", actions,
                               tooltip: "Create");
    if (picked >= 0) chosen = picked;
    ui.text(%"Last created: $(actions.at(chosen).label)",
            color: text_secondary);
  }
}

static void scene_checklist(Ui ui) {
  static CheckSteps steps_1 = CheckSteps.of([
    {title: "Create your workspace",
     description: "Pick a name and invite your team.", action: "Create",
     done: true},
    {title: "Connect a repository",
     description: "Link GitHub or GitLab to sync issues and pull requests.",
     action: "Connect"},
    {title: "Import your data",
     description: "Bring tasks over from a CSV or another tool.",
     action: "Import"},
    {title: "Turn on notifications",
     description: "Get pinged when something needs you.", action: "Enable"}]);
  ui.box (width: 460) {
    int done = ui.checklist("onboarding", steps_1,
      title: "Set up your workspace");
    if (done >= 0) steps_1.at(done).done = true;
  }
}

// The tour opens on its second step, which points at the Share button.
static void scene_tour(Ui ui) {
  static TourSteps steps_2 = TourSteps.of([
    {target: 0, title: "Welcome to Fieldnotes",
     body: "A quick look at the things you will use every day.", placement: 0},
    {target: 0, title: "Share with your team",
     body: "People you invite can comment without an account.",
     placement: bottom_end},
    {target: 0, title: "Export anywhere",
     body: "Send a report to PDF, Markdown, or a drive.",
     placement: bottom_end}]);
  static int step = 1;
  ui.card (width: fill, max_width: 620, pad: 1,
           gap: 0) {
    ui.row (gap: 8, align: center, width: fill,
            pad: 12) {
      ui.heading("Q3 field report", 4);
      ui.spacer();
      ui.button("Share", icon: users,
                         variant: outline);
      steps_2.at(1).target = ui.last_id();
      ui.button("Export", icon: download,
                          variant: primary);
      steps_2.at(2).target = ui.last_id();
    }
    ui.separator();
    ui.column (pad: 20, gap: 10, width: fill)
      ui.text("Survey results from the coastal sites, with photos and the "
              "soil samples sent to the lab.",
              color: text_secondary);
  }
  if (step >= 0) ui.tour("intro", steps_2, step);
}

static void scene_agent_plan(Ui ui) {
  ui.box (width: fill, max_width: 460)
    ui.agent_plan("plan", [
      {title: "Search for sources", detail: "3 results", status: done},
      {title: "Read the attached report", detail: "Page 12 of 40",
       status: running},
      {title: "Compare the numbers with last quarter", status: pending},
      {title: "Draft the summary", status: pending},
      {title: "Check the citations", status: pending}],
      title: "Research plan");
}

static void scene_prompt_suggestions(Ui ui) {
  static PromptSuggestions suggestions = PromptSuggestions.of([
    {icon: code, title: "Explain this code",
     detail: "Walk through what it does"},
    {icon: chart_bar, title: "Analyze a dataset",
     detail: "Find trends and outliers"},
    {icon: pencil, title: "Draft an email", detail: "Clear and friendly"},
    {icon: bug, title: "Debug an error", detail: "Paste the stack trace"}]);
  static int picked = -1;
  ui.column (gap: 12, width: fill, max_width: 560) {
    ui.heading("What can I help with?", 3);
    int chosen = ui.prompt_suggestions(
      "starters", suggestions, columns: 2);
    if (chosen >= 0) picked = chosen;
    if (picked >= 0) ui.muted(suggestions.at(picked).title);
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
      {name: "Atlas Mini", detail: "Runs on your own machine", icon: box}],
      model,
      placement: bottom_start);
  }
}

static void scene_month_calendar(Ui ui) {
  static cui_date month = { 2026, 11, 1 }, picked = { 2026, 11, 10 };
  ui.month_calendar("month", month, [
    {title: "Design sprint", start: {year: 2026, month: 11, day: 2},
     end: {year: 2026, month: 11, day: 4}, all_day: true,
     tone: violet},
    {title: "Standup", start: {year: 2026, month: 11, day: 9}, time: 9.5f,
     tone: info},
    {title: "Customer call", start: {year: 2026, month: 11, day: 10},
     time: 11, tone: danger},
    {title: "Offsite, Lisbon", start: {year: 2026, month: 11, day: 12},
     end: {year: 2026, month: 11, day: 14}, all_day: true,
     tone: warning},
    {title: "Demo day", start: {year: 2026, month: 11, day: 20},
     time: 16, tone: violet},
    {title: "Holiday", start: {year: 2026, month: 11, day: 26},
     end: {year: 2026, month: 11, day: 27}, all_day: true,
     tone: success},
    {title: "Board meeting", start: {year: 2026, month: 11, day: 30},
     time: 10, tone: danger}],
    selected: &picked, today: { 2026, 11, 10 }, cell_height: 58);
}

static void scene_week_calendar(Ui ui) {
  static CalEvents events = CalEvents.of([
    {title: "Standup", detail: "Zoom", day: 0, start: 9.5f, end: 9.75f,
     tone: info},
    {title: "Design review", detail: "Room 2", day: 0, start: 13, end: 14.5f,
     tone: violet},
    {title: "Release planning", detail: "Room 1", day: 1, start: 10,
     end: 11.5f, tone: warning},
    {title: "Focus time", detail: "No meetings", day: 2, start: 14, end: 17,
     tone: teal},
    {title: "Customer call", detail: "Northlight", day: 3, start: 15, end: 16,
     tone: danger},
    {title: "Demo day", detail: "All hands", day: 4, start: 11, end: 12.5f,
     tone: success}]);
  cui_date monday = { 2026, 11, 9 };
  ui.week_calendar("week", monday, events,
    start_hour: 8, end_hour: 18, hour_height: 34,
    height: 344);
}

static void scene_gantt(Ui ui) {
  static GanttTasks tasks = GanttTasks.of([
    {name: "Research", owner: "Maya Okafor", start: 0, end: 3, progress: 1,
     tone: teal, depends_on: -1},
    {name: "Wireframes", owner: "Aiko Tanaka", start: 3, end: 7, progress: 1,
     tone: teal, depends_on: 0},
    {name: "Core engine", owner: "Jonas Berg", start: 5, end: 13,
     progress: 0.55f, tone: info, depends_on: 0},
    {name: "Platform backends", owner: "Daniel Mensah", start: 10, end: 16,
     progress: 0.2f, tone: teal, depends_on: 2},
    {name: "Beta", start: 17, end: 17, progress: 0, tone: warning,
     depends_on: 3, milestone: true},
    {name: "Docs and launch", owner: "Priya Nair", start: 18, end: 20,
     progress: 0, tone: success, depends_on: 4}]);
  cui_date origin = { 2026, 11, 2 };
  ui.gantt("plan", tasks, origin, 21,
    day_width: 20, today: 8);
}

// A shot: a logo that slides in and fades up, over a sound clip.
static void scene_timeline_editor(Ui ui) {
  enum { KEYS = 8 };
  static cui_curve_key slide[KEYS] = {
    cui_curve_key.of(x: 0, y: 0), cui_curve_key.of(x: 1.5f, y: 320),
    cui_curve_key.of(x: 3, y: 360), cui_curve_key.of(x: 5, y: 360) };
  static cui_curve_key fade[KEYS] = {
    cui_curve_key.of(x: 0, y: 0, mode: CUI_CURVE_LINEAR),
    cui_curve_key.of(x: 1, y: 1), cui_curve_key.of(x: 4.5f, y: 1),
    cui_curve_key.of(x: 5, y: 0, mode: CUI_CURVE_LINEAR) };
  static cui_timeline_clip sounds[2] = {
    cui_timeline_clip.of(start: 0.5f, end: 2.5f, name: "Whoosh"),
    cui_timeline_clip.of(start: 3, end: 4.75f, offset: 0.5f,
                         name: "Street ambience") };
  // A track's keys and clips are buffers CUI grows through the track's
  // own count and capacity, so they stay C arrays the tracks point to.
  static TimelineTracks tracks = TimelineTracks.of([
    {name: "Logo", icon: image},
    {name: "Position X", depth: 1, keys: slide, key_count: 4,
     key_capacity: KEYS},
    {name: "Opacity", depth: 1, keys: fade, key_count: 4, key_capacity: KEYS},
    {name: "Sound", icon: audio_lines, color: 3, clips: sounds,
     clip_count: 2}]);
  static float time = 1.5f;
  ui.timeline_editor("shot", tracks, time,
    end: 5, fps: 24, toggles: true);
}

static void scene_curve_editor(Ui ui) {
  static CurveKeys keys = CurveKeys.of([
    {x: 0, y: 0},
    {x: 0.55f, y: 0.66f, in_dx: -0.22f, in_dy: -0.42f, out_dx: 0.24f,
     out_dy: 0.46f, mode: CUI_CURVE_FREE},
    {x: 1.2f, y: 1.08f}, {x: 2, y: 1}]);
  static int selected = 1;
  ui.box (width: fill, max_width: 620)
    ui.curve_editor("ease", keys,
      x_max: 2, y_max: 1.2f, x_label: "Time", y_label: "Value",
      selected: &selected);
}

static void scene_gradient_editor(Ui ui) {
  static GradientStops stops = GradientStops.of([
    {pos: 0, color: {r: 0xFF, g: 0xF1, b: 0xC1, a: 0xFF}},
    {pos: 0.24f, color: {r: 0xFF, g: 0xB1, b: 0x4A, a: 0xFF}},
    {pos: 0.58f, color: {r: 0xE2, g: 0x55, b: 0x2B, a: 0xFF}},
    {pos: 1, color: {r: 0x5C, g: 0x1F, b: 0x16, a: 0x00}}]);
  static int selected = 2;
  ui.column (width: fill, max_width: 560, gap: 10) {
    ui.text("Flame color over lifetime", font: medium,
                                         size: 13);
    ui.gradient_editor("flame", stops,
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
