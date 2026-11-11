#pragma once

/*  capture.x -- the gallery's Capture page */

#include "state.x"

void page_capture(Ui ui, Gallery g) {
  static cui_texture avatar;
  static String last;
  section(ui, "Dropzone", "Drop files from your desktop, or click to browse.");
  int n = ui.dropzone("files", {
    .description = "PNG, JPG or PDF, up to 25 MB",
    .accept = "png;jpg;jpeg;pdf" });
  if (n > 0) last = ui.dropped_file(0);
  $cui.row(ui, { .gap = 12, .wrap = true }) {
    $cui.box(ui, { .width = CUI_FILL })
      ui.dropzone("compact", { .compact = true, .title = "Attach a file",
                               .description = "Any type" });
    $cui.box(ui, { .width = CUI_FILL })
      ui.dropzone("images", { .compact = true, .title = "Add images",
                              .description = "PNG or JPG",
                              .icon = CUI_ICON_IMAGE,
                              .accept = "png;jpg;jpeg" });
  }
  if (last) ui.muted(last);

  section(ui, "Avatar upload", "Drop an image on the avatar.");
  $cui.row(ui, { .gap = 20, .align = CUI_ALIGN_CENTER }) {
    ui.avatar_upload("avatar", "Maya Okafor", avatar, 88);
    $cui.column(ui, { .gap = 4 }) {
      ui.label("Profile photo");
      ui.secondary("At least 256 by 256 pixels.");
    }
  }

  section(ui, "Signature",
          "Draw with the mouse or a pen. Faster strokes are thinner, like "
          "ink.");
  $cui.box(ui, { .width = CUI_PX(520) })
    ui.signature_pad("signature", { .height = 180 });
}
