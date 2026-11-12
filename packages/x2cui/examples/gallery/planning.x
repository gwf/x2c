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
  static CalEvents events = CalEvents.of([
    {title: "Standup", detail: "Zoom", day: 0, start: 9.5f, end: 9.75f,
     tone: info},
    {title: "Design review", detail: "Room 2", day: 0, start: 11, end: 12.5f,
     tone: violet},
    {title: "Lunch with Maya", day: 1, start: 12.5f, end: 13.5f,
     tone: success},
    {title: "Standup", detail: "Zoom", day: 1, start: 9.5f, end: 9.75f,
     tone: info},
    {title: "Release planning", detail: "Room 1", day: 2, start: 10,
     end: 11.5f, tone: warning},
    {title: "1:1 Jonas", day: 2, start: 10.5f, end: 11, tone: rose},
    {title: "Focus time", detail: "No meetings", day: 2, start: 14, end: 17,
     tone: teal},
    {title: "Standup", detail: "Zoom", day: 3, start: 9.5f, end: 9.75f,
     tone: info},
    {title: "Customer call", detail: "Northlight", day: 3, start: 15, end: 16,
     tone: danger},
    {title: "Demo day", detail: "All hands", day: 4, start: 16, end: 17.5f,
     tone: violet},
    {title: "Gym", day: 5, start: 10, end: 11.5f, tone: success}]);
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
  static GanttTasks tasks = GanttTasks.of([
    {name: "Research", owner: "Maya Okafor", start: 0, end: 5, progress: 1,
     tone: teal, depends_on: -1},
    {name: "Wireframes", owner: "Aiko Tanaka", start: 4, end: 10, progress: 1,
     tone: teal, depends_on: 0},
    {name: "Design system", owner: "Rosa Delgado", start: 8, end: 17,
     progress: 0.7f, tone: teal, depends_on: 1},
    {name: "Core engine", owner: "Jonas Berg", start: 6, end: 20,
     progress: 0.55f, tone: info, depends_on: 0},
    {name: "Platform backends", owner: "Daniel Mensah", start: 14, end: 26,
     progress: 0.2f, tone: teal, depends_on: 3},
    {name: "Beta", start: 27, end: 27, progress: 0, tone: warning,
     depends_on: 4, milestone: true},
    {name: "Docs and launch", owner: "Priya Nair", start: 28, end: 36,
     progress: 0, tone: success, depends_on: 5}]);
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
  // Twelve events spread over this month, built on the first frame.
  static MonthEvents month_events = MonthEvents.of([]);
  List titles = %("Standup" "Design review" "Offsite" "1:1" "Release"
                  "Planning" "Customer call" "Lunch" "Retro" "Holiday" "Demo"
                  "Board meeting");
  for (int k = month_events.len(); k < titles.len(); k++) {
    bool span = k == 2 || k == 9;
    int day = base + (k * 5) % 27;
    month_events.push(cui_month_event.of(
      title: titles[k], start: cui_date_from_days(day),
      end: span ? cui_date_from_days(day + 2) : cui_date.of(),
      time: 9.0f + (float) (k % 8), all_day: span || k == 4,
      tone: (cui_tone) (1 + k % 8)));
  }
  cui_month_result mr = ui.month_calendar(
    "month", month, month_events, selected: &picked);
  if (mr.event >= 0)
    ui.toast(month_events[mr.event].title,
      description: "Opened from the month calendar");
}
