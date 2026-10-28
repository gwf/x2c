/*  symbols.x -- authored definitions from analyzed source units

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "analysis.x"

/** Lists authored definitions physically contained in the document. */
Array LspWorkspace.document_symbols(LspWorkspace w, String path) {
  (void) w.diagnostics(path);
  Array symbols = [];
  Var cached = w.analyses[path];
  if (cached is not <map>) return symbols;
  foreach (Map row, cached.map()["definitions"].array()) {
    if (row["file"].str() != path) continue;
    symbols.push({name: row["display"], kind: row["kind"],
      range: row["range"], selectionRange: row["selectionRange"]});
  }
  return symbols;
}

/** Searches only exported definitions of documents already analyzed. */
Array LspWorkspace.workspace_symbols(LspWorkspace w, String query) {
  Array symbols = [];
  Map seen = {};
  foreach ((String path, Map analysis) in w.analyses)
    foreach (Map row, analysis["definitions"].array()) {
      String name = row["display"];
      if (query && !strstr(name, query)) continue;
      Map location = {uri: lsp_uri(row["file"]), range: row["selectionRange"]};
      String key = Var.json([name, row["kind"], location]);
      if (key in seen) continue;
      seen[key] = 1;
      symbols.push({name: name, kind: row["kind"], location: location});
    }
  return symbols;
}
