/*  mail.x -- A mail message list in a window.

    The list shows the messages of one folder that match a search, one
    interactive row each. A row draws its own fill when selected or
    hovered and a hairline between unselected rows; clicking it selects
    and reads the message, and its context menu marks, stars, or files it.

      mail                    open a window
      mail --shot IMAGE.png   draw the inbox off screen
*/

import "x2cui" with App, Offscreen, TextField, Ui;

enum { INBOX, STARRED, SENT, ARCHIVE };

static List folder_names = %("Inbox" "Starred" "Sent" "Archive");

class Message {
  int id, folder;
  String from, time, subject, preview;
  bool unread, starred;
} *;

// A row is: from, time, subject, preview, folder, unread, starred.
void Message.init(Message m, int id, List row) {
  m.id = id;
  m.from = row[0];
  m.time = row[1];
  m.subject = row[2];
  m.preview = row[3];
  m.folder = row[4];
  m.unread = (int) row[5];
  m.starred = (int) row[6];
}

typedef struct Mail {
  Array messages;
  int folder;
  Message selected;      // NULL when no message is selected
  TextField query;
  int panes;             // 3, 2, or 1, from the window's width
  bool reading, drawer, compose;
} Mail;

static List samples = %(
  ("Jonas Berg" "9:41" "Review of the onboarding flow"
   "I went through all six screens on a 13 inch laptop." 0 1 1)
  ("Priya Nair" "8:15" "Invoice 2024-118"
   "The October invoice is attached. Payment terms are 30 days." 0 1 0)
  ("Tomas Rivera" "Yesterday" "Export is slow for large projects"
   "A 900 file project takes about four minutes to export." 0 0 1)
  ("Lena Fischer" "Yesterday" "Re: Release notes draft"
   "Looks good. I tightened the second paragraph and fixed two links." 0 0 0)
  ("Aiko Tanaka" "Mon" "Icons for the settings page"
   "Here are the twelve icons at 16 and 20 px, outline only." 0 0 0)
  ("Sam Whitfield" "Mon" "Office closed on Friday"
   "The building is closed for maintenance. Work from home if you can." 3 0 1));

static bool in_folder(Message m, int folder) =>
  folder == STARRED ? m.starred : m.folder == folder;

// Whether the sender, subject, or preview contains the query, in any case.
static bool matches(Message m, TextField query) {
  String needle = query.text().lower();
  return !needle.len() ||
         %"$(m.from) $(m.subject) $(m.preview)".lower().contains(needle);
}

static void message_list(Ui ui, Mail &a) {
  List shown = a.messages.list().filter(
    %!(Message m) => in_folder(m, a.folder) && matches(m, a.query));

  ui.column (width: fill, height: fill, gap: 10, pad: 12) {
    ui.row (pad_x: 4, pad_top: 4, gap: 6, width: fill) {
      if (a.panes < 3 && ui.icon_button(menu, tooltip: "Folders"))
        a.drawer = true;
      ui.box (width: fill) ui.heading(folder_names[a.folder], 4);
      if (a.panes < 3 && ui.icon_button(square_pen, tooltip: "Compose"))
        a.compose = true;
    }
    ui.search("search", a.query, placeholder: "Search mail", size: sm);

    ui.scroll (id: "list", gap: 0, fade_edges: true) {
      ui.each (Message m in shown, key: m.id) {
        ui.item (row, selected: a.selected == m) {
          if (row.clicked) {
            a.selected = m;
            m.unread = false;
            a.reading = true;
          }
          ui.row (width: fill, pad_y: 12, pad_right: 12, align: start) {
            // Every row keeps the dot's gutter, so names line up.
            ui.box (width: 26, pad_top: 6, align: center)
              if (m.unread)
                ui.box (width: 7, height: 7, radius: 4, bg: accent) {}
            ui.column (gap: 3, width: fill) {
              ui.row (gap: 8, width: fill) {
                ui.text(m.from, font: m.unread ? medium : body,
                        nowrap: true, width: fill);
                ui.text(m.time, size: 12, color: text_muted, nowrap: true);
              }
              ui.text(m.subject, font: medium, size: 12.5, nowrap: true);
              ui.text(m.preview, size: 12, color: text_secondary, nowrap: true);
            }
          }
        }
        ui.context_menu ("row-menu") {
          if (ui.menu_item(m.unread ? "Mark as read" : "Mark as unread",
                           icon: mail))
            m.unread = !m.unread;
          if (ui.menu_item(m.starred ? "Unstar" : "Star", icon: star))
            m.starred = !m.starred;
          if (ui.menu_item("Archive", icon: archive)) m.folder = ARCHIVE;
        }
      }
      if (!shown.len())
        ui.empty_state("No messages", icon: inbox,
                       description: "You are all caught up.");
    }
  }
}

static Mail open_mail(void) {
  Mail a = { .messages = [], .query = TextField.new(64), .panes = 1 };
  int id = 0;
  foreach (List row in samples) a.messages.push(Message.new(id++, row));
  return a;
}

// The inbox with its second message selected and read.
static int shot(String image) {
  Mail a = open_mail();
  a.selected = a.messages[1];
  a.selected.unread = false;
  Offscreen screen = auto Offscreen.open(420, 600);
  // The second and third frames settle layout and opening animations.
  for (int frame = 0; frame < 3; frame++) {
    screen.begin();
    message_list(screen.ui(), a);
    screen.end();
  }
  screen.write_png(image);
  printf("%s: %d draw commands\n", image, screen.commands());
  return screen.commands() ? 0 : 1;
}

int main(int argc, char **argv) {
  if (argc == 3 && !strcmp(argv[1], "--shot")) return shot(argv[2]);
  Mail a = open_mail();
  App app = auto App.open({ .title = "Mail", .width = 420, .height = 600,
                            .min_width = 320, .min_height = 360 });
  while (app.frame()) message_list(app.ui(), a);
  return 0;
}
