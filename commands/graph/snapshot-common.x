/*  snapshot-common.x -- portable analysis values

    Copyright (c) 2026 Gary William Flake
*/

#pragma once
#include "datum.x"
#include "json.x"

/** Writes an owned analysis value using the existing tagged datum grammar. */
String snapshot_text(Var value) {
  Buffer out = auto Buffer.new(0);
  if (!datum_write(out, value, 1))
    raise %(bad-types (operation "graph snapshot") (value $value));
  return out;
}

/** Reads exactly one stored value or structural pattern, without evaluation. */
Var snapshot_value(String text) {
  unsigned cursor = 0;
  Var value = void, extra = void;
  if (!datum_read(text, cursor, value) || datum_read(text, cursor, extra))
    raise %(malformed (operation "graph snapshot datum"));
  return value;
}

String x2c_embedded_identity(void);

/** Loads a snapshot produced by this exact compiler build. */
Map graph_snapshot_read(Path directory) {
  Var value = snapshot_value(directory.join("snapshot.datum").read_text());
  if (value is not <map>) raise %(malformed (snapshot $directory));
  Map snapshot = value;
  if (snapshot["version"] != 1 ||
      snapshot["compiler"] != x2c_embedded_identity())
    raise %(bad-state (snapshot $directory)
            (reason "incompatible snapshot; rebuild with this compiler"));
  return snapshot;
}
