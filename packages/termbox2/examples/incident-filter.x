/*  incident-filter.x -- filter a live incident list with termbox2. */

import "termbox2" with Termbox, TermboxEvent;

#include <locale.h>

static List _read_incidents(String path) {
  File input = File.open(path, "r");
  if (!input) return NULL;
  defer input.close();

  List incidents = NULL;
  int line_number = 0;
  foreach(String line, input) {
    line_number++;
    List fields = line.strip("\r\n").split("|");
    if (fields.len() != 4) {
      raise %(malformed (app "incident-filter")
              (path $path) (line $line_number)
              (reason "want time|severity|service|text"));
      return NULL;
    }
    String time = fields[0];
    String severity = fields[1];
    String service = fields[2];
    String text = fields[3];
    incidents = cons(%($time $severity $service $text), incidents);
  }
  return incidents.reverse();
}

static int _matches(List incident, String filter) {
  if (!filter) return 1;
  String searchable = %"${incident[1]} ${incident[2]} ${incident[3]}".lower();
  return searchable.contains(filter.lower());
}

static List _matching(List incidents, String filter) {
  List matched = NULL;
  foreach(List incident, incidents)
    if (_matches(incident, filter)) matched = cons(incident, matched);
  return matched.reverse();
}

static uintattr_t _severity_color(String severity) {
  if (severity == %"CRITICAL") return TB_RED | TB_BOLD;
  if (severity == %"ERROR") return TB_RED;
  if (severity == %"WARN") return TB_YELLOW;
  return TB_GREEN;
}

/*  The list starts one row below the frame's top edge. */
static const int LIST_TOP = 2;

static void _draw(Termbox terminal, List matched, String filter, int chosen) {
  int width = terminal.width(), height = terminal.height();
  if (width < 8 || height < 6) {
    raise %(bad-state (library "termbox2") (operation "draw")
            (reason "terminal is too small for the incident list")
            (width $width) (height $height));
  }

  terminal.clear();
  terminal.fill(0, 0, width, 1, %" ", TB_WHITE | TB_BOLD, TB_BLUE);
  terminal.print(
    0, 0, %"incident filter - UTF-8 and EGC output",
    TB_WHITE | TB_BOLD, TB_BLUE
  );

  int row = 0;
  foreach(List incident, matched) {
    if (row >= height - 4) break;
    String severity = incident[1];
    String service = incident[2];
    String text = incident[3];
    uintattr_t foreground = _severity_color(severity), background = TB_DEFAULT;
    if (row == chosen) {
      foreground = TB_BLACK;
      background = TB_CYAN;
      terminal.fill(
        1, LIST_TOP + row, width - 2, 1, %" ", foreground, background
      );
    }
    terminal.print(
      1, LIST_TOP + row, %"$severity $service: $text",
      foreground, background
    );
    row++;
  }

  /*  The frame is drawn last, so a long incident line is clipped by the
      border rather than printed over it. */
  terminal.box(0, 1, width, height - 2, TB_CYAN, TB_DEFAULT);

  String shown = filter ? filter : %"<all>";
  String prompt = %"filter: ";
  terminal.fill(0, height - 1, width, 1, %" ", TB_BLACK, TB_WHITE);
  terminal.print(
    0, height - 1,
    %"$prompt$shown | ${matched.len()} matches | click selects | " +
    %"Backspace edits | Esc quits",
    TB_BLACK, TB_WHITE
  );
  terminal.set_cursor(
    Termbox.measure(prompt) + Termbox.measure(filter), height - 1
  );
  terminal.present();
}

static List _run(String path) {
  Termbox terminal = Termbox.open();
  defer terminal.close();

  List incidents = _read_incidents(path);
  List matched = NULL;
  Array typed = %[];
  String filter = NULL;
  int chosen = -1, dirty = 1;

  terminal.set_input_mode(TB_INPUT_ESC | TB_INPUT_MOUSE);
  terminal.set_output_mode(TB_OUTPUT_NORMAL);

  while (1) {
    if (dirty) {
      filter = typed.join(NULL);
      matched = _matching(incidents, filter);
      _draw(terminal, matched, filter, chosen);
      dirty = 0;
    }

    TermboxEvent event = terminal.peek(100);
    if (!event.available()) continue;
    if (event.is_resize()) {
      dirty = 1;
      continue;
    }
    if (event.is_mouse()) {
      int row = event.y() - LIST_TOP;
      if (event.key() != TB_KEY_MOUSE_LEFT) continue;
      if (row < 0 || row >= matched.len()) continue;
      chosen = row;
      dirty = 1;
      continue;
    }
    if (!event.is_key()) continue;

    if (event.key() == TB_KEY_ESC || event.key() == TB_KEY_CTRL_C) break;
    if (event.key() == TB_KEY_BACKSPACE || event.key() == TB_KEY_BACKSPACE2) {
      typed.pop();
      chosen = -1;
      dirty = 1;
      continue;
    }

    String text = event.text();
    if (text) {
      typed.push(text);
      chosen = -1;
      dirty = 1;
    }
  }

  filter = typed.join(NULL);
  String service = chosen < 0 ? %"<none>" :
    matched[chosen].list()[2].string();
  return %($filter ${matched.len()} $service);
}

static int _report_failure(Symbol cause, List detail) {
  Stderr.printf("failed: %s\n", cons(cause, detail).repr());
  return 2;
}

int main(int argc, char **argv) {
  if (!setlocale(LC_CTYPE, "")) {
    Stderr.puts("failed: cannot initialize the character locale");
    return 2;
  }
  String path = argc > 1 ? String.new(argv[1]) : %"examples/incidents.log";

  try {
    List result = _run(path);
    Stdout.printf(
      "quit: filter=%s matches=%d selected=%s\n",
      result[0].string(), result[1].integer(), result[2].string()
    );
  }
  catch %(term-error *detail):
    return _report_failure(<term-error>, detail);
  catch %(io-fail *detail): return _report_failure(<io-fail>, detail);
  catch %(not-found *detail): return _report_failure(<not-found>, detail);
  catch %(malformed *detail): return _report_failure(<malformed>, detail);
  catch %(bad-arg *detail): return _report_failure(<bad-arg>, detail);
  catch %(bad-state *detail): return _report_failure(<bad-state>, detail);
  catch: {
    Stderr.puts("failed: unknown error");
    return 2;
  }
  return 0;
}
