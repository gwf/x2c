#pragma once

/*  inputs.x -- the gallery's Inputs page */

#include "state.x"

void page_inputs(Ui ui, Gallery g) {
  section(ui, "Text fields", "Labels above, hints and errors below.");
  ui.card (gap: 16) {
    ui.box (dir: grid, columns: 2, min_column_width: 260,
            gap: 16) {
      ui.input("name", g.name, label: "Full name",
                               placeholder: "Maya Okafor");
      ui.input("email", g.email, label: "Email",
                                 icon: at_sign,
                                 hint: "We never share your email.");
      bool short_password =
        !g.password.empty() && g.password.text().len() < 8;
      ui.input("password", g.password,
        label: "Password", password: true,
        placeholder: "At least 8 characters",
        error: short_password ? "Use 8 or more characters." : NULL);
      ui.search("search", g.search, label: "Search",
                                    placeholder: "Search projects");
    }
    ui.textarea("bio", g.bio, label: "About", height: 96,
                              hint: "Markdown is supported.");
  }
  section(ui, "Tags, codes and password strength", NULL);
  ui.card (gap: 16) {
    ui.tag_input("tags", g.tags, label: "Topics",
                                 placeholder: "Add a topic");
    ui.column (gap: 8) {
      ui.label("Verification code");
      if (ui.otp_input("otp", g.otp, 6))
        ui.toast("Code entered", tone: success);
    }
    ui.column (gap: 8) {
      ui.input("new-pw", g.password,
        label: "New password", password: true,
        placeholder: "Try a long passphrase");
      ui.password_strength(g.password.text());
    }
  }
  section(ui, "Pickers", NULL);
  ui.card (gap: 16) {
    ui.box (dir: grid, columns: 2, min_column_width: 260,
            gap: 16) {
      ui.select("country", %("Canada" "Denmark" "Germany" "Iran" "Japan"
                             "Kenya" "Netherlands" "Portugal"
                             "United States"),
                g.country, label: "Country");
      ui.select("framework", %("C99" "C11" "C17" "C23" "C++17"
                               "Objective-C" "Zig" "Odin" "Rust"),
                g.framework, label: "Language", searchable: true,
                             placeholder: "Pick a language");
      ui.date_picker("due", g.date, label: "Due date");
      ui.number("qty", g.quantity, 0, 99, label: "Seats",
                                          width: fill);
    }
    ui.column (gap: 6) {
      ui.label("Brand color");
      ui.color_picker("brand", g.color);
    }
  }
}
