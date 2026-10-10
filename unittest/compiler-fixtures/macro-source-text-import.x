#pragma once

macro Expression $imported.source(Expr $syntax) =>
  $(x2c.literal.string (Code.source_text $syntax));
