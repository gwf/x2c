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

#pragma private

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
void SourceView.set(
  SourceView sources, String path, String text, int changed) {
  sources.overlays[Path.absolute(path)] = text;
  if (changed) sources.dirty_paths[Path.absolute(path)] = 1;
}

/** Returns whether this logical file has an unsaved overlay. */
int SourceView.is_changed(SourceView sources, String path) =>
  sources && sources.dirty_paths.contains(Path.absolute(path));

/** Returns readable-file presence, including unsaved new files. */
int SourceView.exists(SourceView sources, String path) {
  if (sources && sources.overlays.contains(Path.absolute(path))) return 1;
  struct stat info;
  return !access(path, R_OK) && !stat(path, &info) &&
         S_ISREG(info.st_mode);
}

/** Reads through the request overlay, falling back to a regular disk file.
    The return value distinguishes an empty file from a failed read. Disk
    text belongs to the calling unit; configured snapshots remain borrowed.
*/
int SourceView.read(
  SourceView sources, String path, String volatile *text) {
  Var value;
  if (sources && sources.overlays.try_get(Path.absolute(path), &value)) {
    *text = value.string();
    return 1;
  }
  struct stat info;
  File file = fopen(path, "r");
  if (!file) return 0;
  if (file.stat(&info) || !S_ISREG(info.st_mode)) {
    file.close();
    return 0;
  }
  try *text = file.string_close();
  catch %(io-fail *): return 0;
  return 1;
}
