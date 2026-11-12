#pragma once

/*  capture.x -- the gallery's Capture page */

#include "state.x"

void page_capture(Ui ui, Gallery g) {
  static cui_texture avatar;
  static String last;
  section(ui, "Dropzone", "Drop files from your desktop, or click to browse.");
  int n = ui.dropzone("files",
    description: "PNG, JPG or PDF, up to 25 MB",
    accept: "png;jpg;jpeg;pdf");
  if (n > 0) last = ui.dropped_file(0);
  ui.row (gap: 12, wrap: true) {
    ui.box (width: fill)
      ui.dropzone("compact", compact: true, title: "Attach a file",
                             description: "Any type");
    ui.box (width: fill)
      ui.dropzone("images", compact: true, title: "Add images",
                            description: "PNG or JPG",
                            icon: image,
                            accept: "png;jpg;jpeg");
  }
  if (last) ui.muted(last);

  section(ui, "Avatar upload", "Drop an image on the avatar.");
  ui.row (gap: 20, align: center) {
    ui.avatar_upload("avatar", "Maya Okafor", avatar, 88);
    ui.column (gap: 4) {
      ui.label("Profile photo");
      ui.secondary("At least 256 by 256 pixels.");
    }
  }

  section(ui, "Signature",
          "Draw with the mouse or a pen. Faster strokes are thinner, like "
          "ink.");
  ui.box (width: 520)
    ui.signature_pad("signature", height: 180);
}
