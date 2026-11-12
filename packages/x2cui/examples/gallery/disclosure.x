#pragma once

/*  disclosure.x -- the gallery's Disclosure page */

#include "state.x"

void page_disclosure(Ui ui, Gallery g) {
  static bool banner = true;
  static bool card1 = true, card2 = false;
  static cui_check_step steps[] = {
    { "Create your workspace", "Pick a name and invite your team.", "Create",
      true },
    { "Connect a repository",
      "Link GitHub or GitLab to sync issues and pull requests.", "Connect",
      false },
    { "Import your data", "Bring tasks over from a CSV or another tool.",
      "Import", false },
    { "Turn on notifications", "Get pinged when something needs you.",
      "Enable", false },
  };
  static int deleted;
  if (ui.banner("CUI 1.1 is out: data grid, kanban and forty new "
                "components.", banner,
        action: "Read the notes", dismissible: true))
    ui.toast("Opening release notes");
  if (!banner && ui.button("Show the banner again", size: sm))
    banner = true;

  section(ui, "Hover card", "Rest the pointer on a name.");
  ui.row (gap: 6, wrap: true) {
    ui.text("Assigned to");
    ui.link("@jonas");
    ui.hover_card ("grace-card", width: 300)
    ui.row (gap: 12, align: start) {
      ui.avatar("Jonas Berg", size: 44, status: "online");
      ui.column (gap: 4, width: fill) {
        ui.text("Jonas Berg", font: medium);
        ui.text("Engineer on the rendering team. Joined March 2024.",
          size: 13, color: text_secondary);
        ui.row (gap: 6, pad_top: 4, wrap: true) {
          ui.icon(calendar, 12, text_muted);
          ui.text("Usually replies within an hour",
            size: 12, color: text_muted);
        }
      }
    }
    ui.text("and due Friday.");
  }

  section(ui, "Confirm popover", "Ask right where the action is.");
  ui.row (gap: 12, wrap: true) {
    if (ui.button("Delete branch", icon: trash_2))
      ui.popover_open("confirm-delete");
    if (ui.confirm_popover("confirm-delete",
          title: "Delete feature/grid?",
          description: "The branch and its 12 commits are removed from "
                         "the remote.",
          confirm_label: "Delete branch", danger: true))
      deleted++;
    if (deleted) ui.muted("Branch deleted");
  }

  section(ui, "Expandable text",
          "Long text clamps to a few lines with a fade.");
  ui.expandable_text("about",
    "CUI is a component library for C. It draws everything itself, so an "
    "app looks the same on Windows, macOS and Linux, and it ships the parts "
    "most apps need: inputs, pickers, menus, dialogs, tables, charts and a "
    "command palette. Every component supports the keyboard, light and "
    "dark themes and reduced motion. The core is plain C99 with no "
    "dependencies, and it renders through OpenGL or a built-in software "
    "rasterizer, so it also runs in virtual machines and over remote "
    "desktop.",
    lines: 2);

  section(ui, "Expandable cards", "A header that opens a body with a spring.");
  ui.column (gap: 10) {
    ui.expandable_card ("Billing", card1,
        description: "Pro plan, renews on December 1",
        icon: credit_card, badge: "Active",
        badge_tone: success) {
      // Plain label and value pairs: a card inside the card would only add
      // edges.
      ui.row (gap: 40, wrap: true) {
        ui.column (gap: 2) {
          ui.muted("This month");
          ui.text("$84.00", font: display, size: 22,
                            tabular: true);
        }
        ui.column (gap: 2) {
          ui.muted("Seats");
          ui.text("7 of 10", font: display, size: 22,
                             tabular: true);
        }
      }
      ui.row (gap: 8, wrap: true) {
        ui.button("Change plan", size: sm);
        ui.button("Invoices", size: sm,
                              variant: ghost);
      }
    }
    ui.expandable_card ("Security", card2,
        description: "Two-factor authentication is on",
        icon: shield)
      ui.text("Recovery codes were generated 3 months ago.",
        color: text_secondary);
  }

  section(ui, "Countdown", "Digits roll as the time passes.");
  {
    static double target;
    if (target == 0)
      target = ui.time() + 2 * 86400 + 5 * 3600 + 42 * 60 + 18;
    ui.row (gap: 24, align: center) {
      ui.countdown("launch", target - ui.time());
      ui.countdown("sale", target - ui.time() - 86400 * 2,
        compact: true, hide_days: true);
    }
  }

  section(ui, "Onboarding checklist", "Progress, with the next step open.");
  ui.box (width: 460) {
    int a = ui.checklist("onboarding", steps,
      title: "Set up your workspace");
    if (a >= 0) {
      steps[a].done = true;
      ui.toast(steps[a].title, tone: success);
    }
  }

  section(ui, "Undo toast", "A draining line shows how long Undo stays.");
  if (ui.button("Archive 3 conversations", icon: archive))
    ui.toast("3 conversations archived", action: "Undo",
                                         show_timer: true);
}
