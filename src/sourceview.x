/*  sourceview.x -- request-owned source overlays

    Copyright (c) 2026 Gary William Flake

    Logical paths keep their identity when an editor supplies unsaved text.
    Configure this view before opening a frontend unit; its immutable values
    and Map must outlive every compiler borrowing it.
*/

#pragma once
#include "path.x"

/** Owns configured immutable overlays in the request's active Context.
    A frontend and its units borrow this view. Text read from disk belongs
    to the reading unit, so the view never caches that shorter-lived text.
*/
class SourceView struct {
  Map overlays, dirty_paths;
} *;

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/** Initializes empty overlays in the current request lifetime. */
void SourceView.init(SourceView sources) {
  sources.overlays = {};
  sources.dirty_paths = {};
}

/** Stores an immutable snapshot under its logical source path. Empty text
    is a present snapshot, not a request to fall back to the disk file.
*/
void SourceView.set(SourceView s, String path, String text, int changed) {
  path = Path.absolute(path);
  s.overlays[path] = text;
  if (changed) s.dirty_paths[path] = 1;
  else s.dirty_paths.del(path);
}

/** Removes a closed document so subsequent reads use the disk file. */
void SourceView.unset(SourceView s, String path) {
  path = Path.absolute(path);
  s.overlays.del(path);
  s.dirty_paths.del(path);
}

/** Returns whether this logical file has an unsaved overlay. */
int SourceView.is_changed(SourceView sources, String path) =>
  sources && Path.absolute(path) in sources.dirty_paths;

/** Returns readable-file presence, including unsaved new files. */
int SourceView.exists(SourceView sources, String path) {
  if (sources && Path.absolute(path) in sources.overlays) return 1;
  struct stat info;
  return !access(path, R_OK) && !stat(path, &info) && S_ISREG(info.st_mode);
}

/** Returns the text at `path` through the request overlay, falling back to
    a regular disk file. An empty file is NULL. Disk text belongs to the
    calling unit; configured snapshots remain borrowed.
    Raises: `<not-found>` or `<io-fail>` when the file cannot be opened or
    read, `<io-fail>` with a `reason` when it is not a regular file,
    `<bad-arg>` when it holds a NUL byte, or `<size-limit>` when it is too
    large for a `String`.
*/
String SourceView.read_text(SourceView s, String path) {
  Var value;
  if (s && s.overlays.try_get(Path.absolute(path), value)) return value;
  File file = auto path.open("r");
  struct stat info;
  if (file.stat(&info) || !S_ISREG(info.st_mode))
    raise %(io-fail (operation "SourceView.read_text") (path $path)
      (reason "not a regular file"));
  return file.string();
}

/** Reads like `SourceView.read_text`, returning 0 instead of raising. The
    return value distinguishes an empty file from a failed read.
*/
int SourceView.read(SourceView sources, String path, String volatile &text) {
  try text = sources.read_text(path);
  catch %((!or not-found io-fail bad-arg size-limit) *): return 0;
  return 1;
}
