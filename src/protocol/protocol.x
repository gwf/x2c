/*  protocol.x -- protocols from declaration to conform forms

    Copyright (c) 2025 Gary William Flake.

    This module owns the protocol feature: it parses protocol and adoption
    declarations, keeps their rows in per-unit registries, resolves each
    adoption into a conformance, answers member and operator lookups, and
    presents each conformance as native aliases or a `conform` form, from which
    `src/components/protocol-adapters.x` writes the adapters. Registries are
    rebuilt per translation unit; a static row is visible only in the unit of
    its canonical source path. The unit that declares an external adoption
    resolves it and records the conformance in its interface, which an
    including unit reuses.
*/
#pragma once
#include "compiler/compiler.x"
#include "grammar.x"
#include "adapter-memo.x"

#include <string.h>
#include "collect/collect.x"
#include "expressions/expressions.x"
#include "parse/parse.x"
#include "meta.x"

// operators

/* operator-ledger.x defines these methods outside the shared include graph. */
// lint: allow src-forward-declaration FI-6: leaf ledger binding
Symbol Compiler.operator_member(Symbol op);

// lint: allow src-forward-declaration FI-6: leaf ledger binding
Symbol Compiler.derived_member(Symbol op);

module {
  "registry.x",
  "declarations.x",
  "resolution.x",
  "lookup.x",
  "call-helpers.x",
  "adapters.x",
}
