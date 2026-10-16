/*  literals.x -- x2c literal parsing

    Each literal parses to a typed expression. A `List` cell or `String`
    segment with no dynamic reference enters the compiler cache and is built
    once; `runtime_literals` builds every one at run time instead. Lambda
    literals parse in `lambdas.x`.
*/
#pragma once
#include "private-keywords.x"
#include "compiler.x"
#include "grammar.x"
#include "parse.x"
#include "type.x"
#include "expressions.x"
#include "transform.x"
#include "lambdas.x"
#include <stdint.h>
#include <string.h>

module {
  "literals/quotation.x",
  "literals/payloads.x",
  "literals/collections.x",
  "literals/strings.x",
  "literals/atoms.x",
}
