#pragma indent
/*  idioms.x -- rules that respell code in a form x2c translates the same

    Each rule proposes a replacement for its finding. The replacement is a
    candidate until `--fix` translates the unit before and after it and
    finds the generated C and header byte-identical, so a rule states where
    the idiom applies and the compiler decides whether the spelling means
    the same thing.
*/
#include "lint.x"
#include <string.h>

#pragma private

/* The token types of neighbors that bind no tighter than a relational
   operator, so an operand placed between them needs no parentheses. The
   `>` of `=>` is a neighbor before. */
static const SymbolSet loose_before =
  %<<"(" "[" "," "=" return "&&" "||" "?" ":" "==" "!=" if while>>
static const SymbolSet loose_after =
  %<<")" "]" "," ";" "&&" "||" "?" ":" "==" "!=">>

/* Operators that bind no tighter than `in`, which an operand of `in` must
   not contain outside brackets. */
static const SymbolSet relational =
  %<<"<" ">" "<=" ">=" "==" "!=" "^" "|" "&&" "||" "?" ":" in is>>

/* Whether the code tokens from `from` to `to` hold an operator of `in`'s
   precedence or lower outside brackets, or span lines. */
static int _loose(Lint l, int from, int to):
  if l.tokens[from].line != l.end_line(to): return 1
  for (int at = from; at <= to; at++):
    Token t = l.at(at)
    if l.partner[at] > at:
      at = l.partner[at]
      continue
    if t.type in relational || t.text == "&" && at > from: return 1
    if t.type == <","> || t.len > 1 && t.text[t.len - 1] == '=' &&
       t.text != "==" && t.text != "<=" && t.text != ">=" && t.text != "!=":
      return 1
  return 0

/* Returns the first token of the postfix chain that ends at `at`: names
   joined by `.` or `->`, calls, subscripts, and one bracketed or quoted
   primary. Returns -1 for any other operand. */
static int _chain_start(Lint l, int at):
  while at >= 0:
    Token t = l.at(at)
    if lint_closes(t) || t.text == "\"":
      if l.partner[at] < 0: return -1
      at = l.partner[at]
      int before = l.prev(at)
      if before < 0 || t.text == "\"": return at
      Token b = l.at(before)
      if b.type != <ident> && !lint_closes(b): return at
      at = before
    else if t.type == <ident> || lint_text(t):
      int before = l.prev(at)
      if before < 1 || l.tokens[before].text != "." &&
         l.tokens[before].text != "->":
        return at
      at = l.prev(before)
    else:
      return -1
  return -1

/* `c.contains(x)` where `x in c` needs no parentheses. A negated test
   keeps the call: `!(x in c)` emits different C. */
static void _contains_in(Lint l):
  for (int at = 2; at + 1 < l.count; at++):
    Token t = l.at(at)
    if t.text != "contains" || l.quoted[at] || l.tokens[at - 1].text != "." ||
       l.tokens[at + 1].type != <"(">:
      continue
    int open = at + 1, close = l.partner[open]
    int first = l.next(open), last = l.prev(close)
    if close < 0 || first >= close || _loose(l, first, last): continue
    int start = _chain_start(l, at - 2)
    if start < 0: continue
    int before = l.prev(start), after = l.next(close)
    if before < 0 || after >= l.count: continue
    Symbol left = l.tokens[before].type
    if left == <">"> && l.tokens[before - 1].text == "=": left = <return>
    if !(left in loose_before) || !(l.tokens[after].type in loose_after):
      continue
    String receiver = l.source(start, at - 2)
    if receiver.contains("\n"): continue
    l.fix("contains-in", t.line, "write the membership test with `in`",
          start, close, %"${l.source(first, last)} in $receiver")

/* A written `->`, which `.` reaches wherever x2c parsed the struct. */
static void _member_arrows(Lint l):
  for (int at = 1; at < l.count; at++):
    if l.tokens[at].text == "->" && !l.quoted[at]:
      l.fix("member-arrow", l.tokens[at].line, "reach the member with `.`",
            at, at, ".")

/* `%"text"` without interpolation or escapes, which a plain literal
   spells when its destination promotes it. */
static void _plain_strings(Lint l):
  for (int at = 0; at < l.count; at++):
    if l.tokens[at].text != "%\"" || l.quoted[at]: continue
    int close = l.partner[at]
    if close < 0: continue
    String body = close > at + 1 ? l.source(at + 1, close - 1) : ""
    if close > at + 2 || body && strpbrk(body, "\\\n$@"): continue
    l.fix("plain-string", l.tokens[at].line,
          "a plain literal needs no interpolation", at, close,
          %"\"$body\"")

/* A top-level `{ return e; }` body, which `=> e;` spells. Macros and meta
   functions produce no C of their own, so they are left alone. */
static void _expression_bodies(Lint l):
  int depth = 0
  for (int at = 0; at < l.count; at++):
    Token t = l.at(at)
    int close = l.partner[at]
    if t.type == <"}"> && close >= 0 && l.tokens[close].type == <"{"> &&
       !l.quoted[close]:
      depth--
    if t.type != <"{"> || l.quoted[at]: continue
    depth++
    int head = l.prev(at), ret = l.next(at)
    if depth != 1 || close < 0 || head < 0 ||
       l.tokens[head].type != <")"> || l.tokens[ret].type != <return>:
      continue
    int first = l.first[l.tokens[l.partner[head]].line]
    String lead = l.tokens[first].text
    if lead == "macro" || lead == "meta" || lead[0] == '$': continue
    int semi = l.next(ret)
    while semi < close && l.tokens[semi].type != <;> &&
          l.tokens[semi].type != <comment>:
      semi = l.partner[semi] > semi ? l.next(l.partner[semi]) : l.next(semi)
    if semi >= close || l.tokens[semi].type != <;> ||
       l.next(semi) != close || l.next(ret) == semi:
      continue
    String value = l.source(l.next(ret), l.prev(semi))
    int indent = l.indent(l.tokens[first].line) + 2
    if value.contains("\n") || indent + value.len() + 1 > 79: continue
    String text = %" =>\n${String.new_fill(' ', indent)}$value;"
    if l.tokens[head].col + 4 + value.len() + 1 <= 79:
      text = %" => $value;"
    l.fix("expression-body", t.line, "write the one returned value with `=>`",
          head + 1, close, text)

/** Runs the rules that respell code, each with a proposed fix. The
    expression-body rule reads braces and skips the indentation syntax.
*/
void Lint.idiom_rules(Lint l):
  _member_arrows(l)
  _contains_in(l)
  _plain_strings(l)
  if l.layout: return
  _expression_bodies(l)
