#pragma once

/*  planning.x -- the gallery's Planning page */

#include "state.x"

typedef struct kb_card {
  int id;
  String title, tag, who;
  cui_tone tone;
  int comments, files;
  float progress;
} kb_card;

static kb_card kb_cards[] = {
  { 1, "Audit the color tokens for contrast", "Design", "Maya Okafor",
    CUI_TONE_VIOLET, 3, 0, 0 },
  { 2, "Virtualize the activity feed", "Perf", "Jonas Berg", CUI_TONE_TEAL,
    1, 2, 0 },
  { 3, "Dark mode screenshots for docs", "Docs", "Aiko Tanaka",
    CUI_TONE_ROSE, 0, 4, 0 },
  { 4, "Keyboard nav in the date range picker", "A11y", "Priya Nair",
    CUI_TONE_INFO, 5, 0, 0.6f },
  { 5, "IME composition on Windows", "Platform", "Daniel Mensah",
    CUI_TONE_WARNING, 2, 1, 0.3f },
  { 6, "Spring presets", "Motion", "Rosa Delgado", CUI_TONE_VIOLET, 4, 0,
    1 },
  { 7, "Glyph atlas eviction", "Perf", "Lena Fischer", CUI_TONE_TEAL, 0, 0,
    1 },
  { 8, "Retina screenshots", "Docs", "Aiko Tanaka", CUI_TONE_ROSE, 1, 3, 1 },
};
// The card ids in each column, in order, and how many each column holds.
static int kb_cols[4][8] = { { 1, 2, 3 }, { 4, 5 }, { 6 }, { 7, 8 } };
static int kb_len[4] = { 3, 2, 1, 2 };

static kb_card *kb_find(int id) {
  for (int k = 0; k < $cui.count(kb_cards); k++)
    if (kb_cards[k].id == id) return &kb_cards[k];
  return NULL;
}

static void kb_apply(const cui_kanban_move *m) {
  int *from = kb_cols[m.from_column], *to = kb_cols[m.to_column];
  int at = -1;
  for (int k = 0; k < kb_len[m.from_column]; k++)
    if (from[k] == m.card) at = k;
  if (at < 0 || (m.to_column != m.from_column && kb_len[m.to_column] >= 8))
    return;
  for (int k = at; k < kb_len[m.from_column] - 1; k++) from[k] = from[k + 1];
  kb_len[m.from_column]--;
  int idx = m.to_index < 0 ? 0
          : m.to_index > kb_len[m.to_column] ? kb_len[m.to_column]
          : m.to_index;
  for (int k = kb_len[m.to_column]; k > idx; k--) to[k] = to[k - 1];
  to[idx] = m.card;
  kb_len[m.to_column]++;
}

void page_planning(Ui ui, Gallery g) {
  List col_names = %("Backlog" "In progress" "Review" "Done");
  static const unsigned col_dots[4] = { 0x94a3b8, 0x3b82f6, 0xf59e0b,
                                        0x22c55e };
  section(ui, "Kanban", "Drag cards within and between columns. Columns can "
                        "carry a work-in-progress limit.");
  ui.kanban_begin("board");
  for (int c = 0; c < 4; c++) {
    String col_name = col_names[c];
    if (ui.kanban_column_begin(col_name, kb_len[c], {
          .dot = CUI_RGB(col_dots[c]), .limit = c == 1 ? 3 : 0,
          .width = 264 }))
      ui.toast("New card", { .description = col_name });
    for (int k = 0; k < kb_len[c]; k++) {
      kb_card *cd = kb_find(kb_cols[c][k]);
      if (!cd) continue;
      if (ui.kanban_card_begin(cd.id)) ui.toast(cd.title, {});
      ui.badge(cd.tag, { .tone = cd.tone, .size = CUI_SIZE_SM });
      ui.text(cd.title, { .font = CUI_FONT_MEDIUM, .size = 13.5f,
                          .line_height = 1.35f });
      if (cd.progress > 0 && cd.progress < 1)
        ui.progress(cd.progress, { .height = 4 });
      $cui.row(ui, { .gap = 10, .align = CUI_ALIGN_CENTER,
                     .width = CUI_FILL }) {
        ui.avatar(cd.who, { .size = 22 });
        ui.spacer();
        if (cd.files) {
          ui.icon(CUI_ICON_PAPERCLIP, 12, CUI_COLOR_TEXT_MUTED);
          ui.text(%"$(cd.files)", { .size = 12,
                                    .color = CUI_COLOR_TEXT_MUTED });
        }
        if (cd.comments) {
          ui.icon(CUI_ICON_MESSAGE_SQUARE, 12, CUI_COLOR_TEXT_MUTED);
          ui.text(%"$(cd.comments)", { .size = 12,
                                       .color = CUI_COLOR_TEXT_MUTED });
        }
        if (cd.progress >= 1)
          ui.icon(CUI_ICON_CIRCLE_CHECK, 14, CUI_COLOR_SUCCESS);
      }
      ui.kanban_card_end();
    }
    ui.kanban_column_end();
  }
  cui_kanban_move mv;
  if (ui.kanban_end(mv)) kb_apply(&mv);

  section(ui, "Week calendar", "Drag events to move them in 15 minute "
                               "steps, or pull the bottom edge to resize.");
  static cui_cal_event events[] = {
    { "Standup", "Zoom", 0, 9.5f, 9.75f, CUI_TONE_INFO },
    { "Design review", "Room 2", 0, 11, 12.5f, CUI_TONE_VIOLET },
    { "Lunch with Maya", NULL, 1, 12.5f, 13.5f, CUI_TONE_SUCCESS },
    { "Standup", "Zoom", 1, 9.5f, 9.75f, CUI_TONE_INFO },
    { "Release planning", "Room 1", 2, 10, 11.5f, CUI_TONE_WARNING },
    { "1:1 Jonas", NULL, 2, 10.5f, 11, CUI_TONE_ROSE },
    { "Focus time", "No meetings", 2, 14, 17, CUI_TONE_TEAL },
    { "Standup", "Zoom", 3, 9.5f, 9.75f, CUI_TONE_INFO },
    { "Customer call", "Northlight", 3, 15, 16, CUI_TONE_DANGER },
    { "Demo day", "All hands", 4, 16, 17.5f, CUI_TONE_VIOLET },
    { "Gym", NULL, 5, 10, 11.5f, CUI_TONE_SUCCESS },
  };
  cui_date today = cui_date_today();
  int td = cui_date_to_days(today);
  int monday = td - ((td + 3) % 7 + 7) % 7;
  int ev = ui.week_calendar(
    "week", cui_date_from_days(monday), events, $cui.count(events),
    { .start_hour = 8, .end_hour = 19, .height = CUI_PX(420) });
  if (ev >= 0)
    ui.toast(events[ev].title, { .description = events[ev].detail });

  section(ui, "Gantt", "Drag bars to reschedule, pull either end to change "
                       "the length. Arrows follow dependencies.");
  static cui_gantt_task tasks[] = {
    { "Research", "Maya Okafor", 0, 5, 1, CUI_TONE_TEAL, -1, false },
    { "Wireframes", "Aiko Tanaka", 4, 10, 1, CUI_TONE_TEAL, 0, false },
    { "Design system", "Rosa Delgado", 8, 17, 0.7f, CUI_TONE_TEAL, 1,
      false },
    { "Core engine", "Jonas Berg", 6, 20, 0.55f, CUI_TONE_INFO, 0, false },
    { "Platform backends", "Daniel Mensah", 14, 26, 0.2f, CUI_TONE_TEAL, 3,
      false },
    { "Beta", NULL, 27, 27, 0, CUI_TONE_WARNING, 4, true },
    { "Docs and launch", "Priya Nair", 28, 36, 0, CUI_TONE_SUCCESS, 5,
      false },
  };
  cui_date origin = cui_date_from_days(monday - 7);
  int tk = ui.gantt("plan", tasks, $cui.count(tasks), origin, 42,
                    { .today = 7 + (td - monday) });
  if (tk >= 0) {
    int days = tasks[tk].end - tasks[tk].start;
    String dur = %"$days days";
    ui.toast(tasks[tk].name, {
      .description = tasks[tk].milestone ? "Milestone" : dur });
  }
  section(ui, "Month calendar", "Bars for days off and trips, timed events "
                                "in time order, +N more when a day is "
                                "full.");
  static cui_date month, picked;
  cui_date now = cui_date_today();
  int base = cui_date_to_days((cui_date){ now.year, now.month, 1 });
  static cui_month_event mev[12];
  static const char *const titles[12] = {
    "Standup", "Design review", "Offsite", "1:1", "Release", "Planning",
    "Customer call", "Lunch", "Retro", "Holiday", "Demo", "Board meeting" };
  for (int k = 0; k < 12; k++) {
    bool span = k == 2 || k == 9;
    int day = base + (k * 5) % 27;
    mev[k] = (cui_month_event){
      titles[k], cui_date_from_days(day),
      span ? cui_date_from_days(day + 2) : (cui_date){ 0 },
      9.0f + (float) (k % 8), span || k == 4, (cui_tone) (1 + k % 8) };
  }
  cui_month_result mr = ui.month_calendar(
    "month", month, mev, $cui.count(mev), { .selected = &picked });
  if (mr.event >= 0)
    ui.toast(mev[mr.event].title, {
      .description = "Opened from the month calendar" });
}
