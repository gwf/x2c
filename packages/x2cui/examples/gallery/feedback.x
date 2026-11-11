#pragma once

/*  feedback.x -- the gallery's Feedback page */

#include "state.x"

void page_feedback(Ui ui, Gallery g) {
  section(ui, "Alerts", "Color only when something succeeded, needs "
                        "attention or failed.");
  $cui.column(ui, { .gap = 10 }) {
    ui.alert("A new version is available", {
      .description = "Restart to update to 1.1." });
    ui.alert("Payment received", {
      .description = "Your invoice was paid on November 5.",
      .tone = CUI_TONE_SUCCESS });
    ui.alert("Storage almost full", {
      .description = "You have used 92% of your plan.",
      .tone = CUI_TONE_WARNING, .dismissible = true });
    ui.alert("Build failed", {
      .description = "Missing symbol cui_frame in main.c line 42.",
      .tone = CUI_TONE_DANGER });
  }
  $cui.box(ui, { .dir = CUI_GRID, .columns = 2, .min_column_width = 260,
                 .gap = 16 }) {
    $cui.card(ui, { .gap = 18 }) {
      ui.heading("Progress", 4);
      ui.progress(0.68f, { .label = "Uploading assets",
                           .show_value = true });
      ui.progress(0.0f, { .label = "Indexing", .indeterminate = true });
      ui.meter("Storage", 18.4f, 20, "GB");
      $cui.row(ui, { .gap = 16, .wrap = true }) {
        ui.spinner(16);
        ui.spinner(22);
        ui.spinner(28);
      }
    }
    $cui.card(ui, { .gap = 14 }) {
      ui.heading("Loading", 4);
      $cui.row(ui, { .gap = 12, .wrap = true }) {
        ui.skeleton(CUI_PX(40), 40);
        $cui.column(ui, { .gap = 8, .width = CUI_FILL }) {
          ui.skeleton(CUI_PCT(70), 12);
          ui.skeleton(CUI_PCT(45), 12);
        }
      }
      ui.skeleton(CUI_FILL, 88);
      ui.skeleton(CUI_PCT(90), 12);
      ui.skeleton(CUI_PCT(60), 12);
    }
  }
  $cui.box(ui, { .dir = CUI_GRID, .columns = 2, .min_column_width = 260,
                 .gap = 16 }) {
    $cui.card(ui, { .gap = 14 }) {
      ui.heading("Activity", 4);
      ui.timeline_item("Deployed to production", {
        .time = "2m ago",
        .description = "Release 1.0.3 is live in all regions.",
        .icon = CUI_ICON_ROCKET, .tone = CUI_TONE_SUCCESS });
      ui.timeline_item("Review requested", {
        .time = "1h ago",
        .description = "Jonas asked you to review the theming changes.",
        .icon = CUI_ICON_MESSAGE_SQUARE, .tone = CUI_TONE_INFO });
      ui.timeline_item("Build failed", {
        .time = "3h ago", .icon = CUI_ICON_CIRCLE_ALERT,
        .tone = CUI_TONE_DANGER, .last = true });
    }
    $cui.card(ui, { .gap = 14 }) {
      ui.heading("Goals", 4);
      $cui.row(ui, { .gap = 24, .justify = CUI_JUSTIFY_AROUND }) {
        ui.progress_ring("Onboarding", 0.72f, 104);
        ui.progress_ring("Quota", 0.35f, 104);
      }
    }
  }
  section(ui, "Badges and avatars", NULL);
  $cui.card(ui, { .gap = 16 }) {
    $cui.row(ui, { .gap = 8, .wrap = true }) {
      ui.badge("Draft", {});
      ui.badge("Recommended", { .tone = CUI_TONE_ACCENT });
      ui.badge("Active", { .tone = CUI_TONE_SUCCESS, .dot = true });
      ui.badge("Pending", { .tone = CUI_TONE_WARNING, .dot = true });
      ui.badge("Overdue", { .tone = CUI_TONE_DANGER, .dot = true });
      ui.badge("Beta", { .tone = CUI_TONE_VIOLET });
      ui.badge("New", { .tone = CUI_TONE_INFO, .solid = true });
    }
    $cui.row(ui, { .gap = 16, .wrap = true }) {
      ui.avatar("Sam Whitfield", { .size = 40, .status = "online" });
      ui.avatar("Daniel Mensah", { .size = 40, .status = "busy" });
      ui.avatar("Rosa Delgado", { .size = 40, .square = true });
      ui.avatar_group(%("Kwame Asante" "Hana Novak" "Elif Kaya"
                        "Ben Carter" "Omar Haddad" "Felix Moreau"
                        "Iris Coleman"), 4, 32);
    }
  }
  $cui.card(ui, { .pad = 0 }) {
    if (ui.empty_state("No projects yet", {
          .icon = CUI_ICON_FOLDER_OPEN,
          .description = "A project holds your screens, their builds and "
                         "who can see them.",
          .action = "New project" }))
      ui.toast("Project created", { .tone = CUI_TONE_SUCCESS });
  }
}
