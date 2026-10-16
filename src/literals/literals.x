/*  literals.x -- x2c literal parsing

    Each literal parses to a typed expression. A `List` cell or `String`
    segment with no dynamic reference enters the compiler cache and is built
    once; `runtime_literals` builds every one at run time instead. Lambda
    literals parse in `lambdas.x`.
*/
#pragma once
#include "private-keywords.x"
#include "compiler/compiler.x"
#include "grammar.x"
#include "parse/parse.x"
#include "type.x"
#include "expressions/expressions.x"
#include "transform/transform.x"
#include "lambdas.x"
#include <stdint.h>
#include <string.h>

module {
  "quotation.x",
  "payloads.x",
  "collections.x",
  "strings.x",
  "atoms.x",
}
