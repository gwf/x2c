/*  repl-ledgers.x -- the book's API ledgers, embedded when the REPL is built

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "meta.x"

meta static String _ledger(Source path) => x2c_embed_text(path);
macro Expression $repl.ledger(Literal $path) => $_ledger($path);

/** Returns `docs/library-manifest.txt` as of the REPL build. */
String repl_library_manifest(void) =>
  $repl.ledger("../../docs/library-manifest.txt");

/** Returns `docs/library-api-tiers.txt` as of the REPL build. */
String repl_library_api_tiers(void) =>
  $repl.ledger("../../docs/library-api-tiers.txt");
