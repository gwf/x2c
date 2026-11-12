#pragma once

/*  planning.x -- the gallery's Planning page */

#include "state.x"

// One card of the board.
class Card {
  int id;
  String title, tag, who;
  cui_tone tone;
  int comments, files;
  float progress;
} *;

// A row is: id, title, tag, who, tone, comments, files, progress.
void Card.init(Card card, List row) {
  card.id = row[0];
  card.title = row[1];
  card.tag = row[2];
  card.who = row[3];
  card.tone = cui_tone.named(row[4]);
  card.comments = row[5];
  card.files = row[6];
  card.progress = (float) row[7];
}

// One column of the board: its title, dot, card limit, and cards in order.
class Column {
  String name;
  unsigned dot;
  int limit;
  Array cards;
} *;

void Column.init(Column c, String name, unsigned dot, int limit, List rows) {
  c.name = name;
  c.dot = dot;
  c.limit = limit;
  c.cards = [];
  foreach (List row in rows) c.cards.push(Card.new(row));
}

// The board's columns, in order.
static Array board;

static Array new_board(void) => [
  Column.new("Backlog", 0x94a3b8, 0, %(
    (1 "Audit the color tokens for contrast" "Design" "Maya Okafor" violet
     3 0 0)
    (2 "Virtualize the activity feed" "Perf" "Jonas Berg" teal 1 2 0)
    (3 "Dark mode screenshots for docs" "Docs" "Aiko Tanaka" rose 0 4 0))),
  Column.new("In progress", 0x3b82f6, 3, %(
    (4 "Keyboard nav in the date range picker" "A11y" "Priya Nair" info
     5 0 0.6)
    (5 "IME composition on Windows" "Platform" "Daniel Mensah" warning
     2 1 0.3))),
  Column.new("Review", 0xf59e0b, 0, %(
    (6 "Spring presets" "Motion" "Rosa Delgado" violet 4 0 1))),
  Column.new("Done", 0x22c55e, 0, %(
    (7 "Glyph atlas eviction" "Perf" "Lena Fischer" teal 0 0 1)
    (8 "Retina screenshots" "Docs" "Aiko Tanaka" rose 1 3 1)))];

// Moves the card CUI reports moved from its column to its new place.
static void move_card(Array board, cui_kanban_move m) {
  Column from = board[m.from_column], to = board[m.to_column];
  for (int k = 0; k < (int) from.cards.len(); k++) {
    Card card = from.cards[k];
    if (card.id != m.card) continue;
    from.cards.remove(k);
    int at = m.to_index < 0 ? 0 : m.to_index;
    to.cards.insert(at < (int) to.cards.len() ? at : (int) to.cards.len(),
                    card);
    return;
  }
}

static void draw_card(Ui ui, Card card) {
  ui.kanban_card (clicked, card.id) {
    if (clicked) ui.toast(card.title);
    ui.badge(card.tag, tone: card.tone, size: sm);
    ui.text(card.title, font: medium, size: 13.5f, line_height: 1.35f);
    if (card.progress > 0 && card.progress < 1)
      ui.progress(card.progress, height: 4);
    ui.row (gap: 10, align: center, width: fill) {
      ui.avatar(card.who, size: 22);
      ui.spacer();
      if (card.files) {
        ui.icon(paperclip, 12, text_muted);
        ui.text(%"$(card.files)", size: 12, color: text_muted);
      }
      if (card.comments) {
        ui.icon(message_square, 12, text_muted);
        ui.text(%"$(card.comments)", size: 12, color: text_muted);
      }
      if (card.progress >= 1) ui.icon(circle_check, 14, success);
    }
  }
}

void page_planning(Ui ui, Gallery g) {
  if (!board) board = new_board();
  section(ui, "Kanban", "Drag cards within and between columns. Columns can "
                        "carry a work-in-progress limit.");
  ui.kanban (moved, mv, "board")
  foreach (Column column in board) {
    // The column declares `added`, so it is a block of its own.
    ui.kanban_column (added, column.name, column.cards.len(), dot: column.dot,
                      limit: column.limit, width: 264) {
      if (added) ui.toast("New card", description: column.name);
      foreach (Card card in column.cards) draw_card(ui, card);
    }
  }
  if (moved) move_card(board, mv);

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
    "week", cui_date_from_days(monday), events,
    start_hour: 8, end_hour: 19, height: 420);
  if (ev >= 0)
    ui.toast(events[ev].title, description: events[ev].detail);

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
  int tk = ui.gantt("plan", tasks, origin, 42,
                    today: 7 + (td - monday));
  if (tk >= 0) {
    int days = tasks[tk].end - tasks[tk].start;
    String dur = %"$days days";
    ui.toast(tasks[tk].name,
      description: tasks[tk].milestone ? "Milestone" : dur);
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
    "month", month, mev, selected: &picked);
  if (mr.event >= 0)
    ui.toast(mev[mr.event].title,
      description: "Opened from the month calendar");
}
