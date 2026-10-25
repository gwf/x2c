#pragma once

macro Expression $embed.definition() =>
  $x2c_embed_text("macro-embed-text-data.txt");

macro Expression $embed.caller(Literal $path) =>
  $x2c_embed_text($path);

macro Expression $embed.empty() =>
  $x2c_embed_text("macro-embed-text-empty.txt");
