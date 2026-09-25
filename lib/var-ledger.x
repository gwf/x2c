/*  var-ledger.x -- the runtime tables projected from the Var tag ledger

    Copyright (c) 2025 Gary William Flake

    `var-tags.xmacro` holds the ledger. This optional module is the one
    runtime unit that imports it, so other units include `var.x` and
    `varconvert.x` without loading the ledger. It defines the tag table, the
    tag sets, the numeric table, and the decoder table those modules
    declare, and checks `TagId` in `lib/var.x` against the ledger.
*/

#include "var.x"
#include "varconvert.x"
#include "meta.x"

$(import "var-tags.xmacro")

$var.tag.id.checks();

const VarTagInfo x2c_var_taginfo[] = $var.tag.info();
const SymbolSet x2c_var_tags = $var.tag.symbolset();
const SymbolSet x2c_var_numeric_tags = $var.tag.numeric.symbolset();
const X2CVarNumericInfo x2c_var_numerics[] = $var.tag.numeric();
const VarDecodeGroup x2c_var_decode_groups[] = $var.tag.decode.groups();
