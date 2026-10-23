/*  var-ledger.x -- the runtime tables projected from the Var tag ledger

    Copyright (c) 2025 Gary William Flake

    `var-tags.x` holds the ledger. This optional module is the one
    runtime unit that imports it. Other units include `var/var.x` without
    loading the ledger. This module defines the tag table, tag sets, numeric
    table, and decoder table that Var declares, and checks `TagId` in
    `lib/var/var.x` against the ledger.
*/

#include "var/var.x"
#include "meta.x"

#include "var-tags.x"

$var.tag.id.checks();

const VarTagInfo x2c_var_taginfo[] = $var.tag.info();
const SymbolSet x2c_var_tags = $var.tag.symbolset();
const SymbolSet x2c_var_numeric_tags = $var.tag.numeric.symbolset();
const X2CVarNumericInfo x2c_var_numerics[] = $var.tag.numeric();
const VarDecodeGroup x2c_var_decode_groups[] = $var.tag.decode.groups();
