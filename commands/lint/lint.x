#pragma indent
/*  lint.x -- one source file under lint and the findings it collects

    A `Lint` holds a file's text and the tokens `Tokenizer.scan` reads from
    it, without the zero-width tokens the indentation syntax adds, so every
    token is written source. Rules read these tokens and the compiler's
    parse of the unit; none reads characters to recover syntax.

    The rule table is the whole configuration. Language rules hold for any
    x2c source and run by default; style rules state this repository's
    policy and run when selected.
*/
#include "frontend.x"
#include <ctype.h>
#include <stdio.h>
#include <string.h>

/** One rule: its code, its `<language>` or `<style>` family, whether a
    finding is a `<violation>` or a review `<candidate>`, and the rule ID in
    `agents/x2c-code-standard.md` that owns it.
*/
typedef struct Rule:
  String code
  Symbol family, kind
  String rule
Rule

/** One file under lint. `partner` maps each bracket or interpolated-string
    token to its match, or -1; `quoted` is 1 for a token inside a quoted
    Lisp form and 2 inside an interpolated string, where `${...}` and
    `@{...}` return to code, 0; and `first` maps each line to its first
    non-space token, or -1. `layout` is set for a unit in the indentation
    syntax, where rules about braces, semicolons, and wrapped statements do
    not apply. `edits` holds the replacements that fixable findings
    propose, as `(START END TEXT)` byte ranges of `text`, and `functions`
    the authored functions the compiler parsed, as `(NAME START BODY END)`
    token indexes, for a unit in brace syntax, whose compiler tokens are
    the tokens `Lint` scanned. `allowances` maps a source line to its
    `(CODE MATCHED)` Array, updated when that finding is suppressed.
    `unused` holds static definitions without bound references as
    `(NAME DISPLAY EMITTED LINE FIRST-LINE LAST-LINE)` for corpus review.
*/
typedef struct Lint:
  String path, text
  struct Token *tokens
  int count, lines, layout
  int *partner, *first
  char *quoted
  Map selected, allowances
  Array findings, edits, functions, unused
*Lint


static const Rule rules[] = {
  {"same-line-else", <style>, <violation>, "ST-1"},
  {"empty-constructor", <style>, <candidate>, "EX-1"},
  {"saved-local", <style>, <candidate>, "NM-4"},
  {"x2c-ident", <style>, <candidate>, "LI-2"},
  {"lisp-defun", <style>, <candidate>, "LI-1"},
  {"literal-report-error", <style>, <candidate>, "DG-1"},
  {"assignment-condition", <style>, <candidate>, "ST-4"},
  {"long-file", <style>, <candidate>, "FI-1"},
  {"long-section", <style>, <candidate>, "FI-5"},
  {"long-dispatch-arm", <style>, <candidate>, "FN-3"},
  {"uncalled-static-function", <style>, <candidate>, "FI-7"},
  {"bad-suppression", <language>, <violation>, "CM-2"},
  {"forward-declaration", <language>, <violation>, "FI-6"},
  {"same-file-forward-declaration", <language>, <candidate>, "FI-6"},
  {"negated-is", <language>, <violation>, "ST-5"},
  {"src-forward-declaration", <style>, <violation>, "FI-6"},
  {"runtime-forward-declaration", <style>, <candidate>, "FI-6"},
  {"tab", <style>, <violation>, "LY-1"},
  {"trailing-whitespace", <style>, <violation>, "LY-1"},
  {"non-ascii", <style>, <violation>, "LY-1"},
  {"operator-spacing", <style>, <violation>, "LY-5"},
  {"over-width", <style>, <violation>, "LY-2"},
  {"over-width-literal", <style>, <candidate>, "LY-2"},
  {"over-width-table-row", <style>, <candidate>, "LY-2"},
  {"blank-line-stack", <style>, <violation>, "LY-6"},
  {"decorated-ruler", <style>, <candidate>, "FI-5"},
  {"wrapped-opening-line", <style>, <violation>, "LY-3"},
  {"continuation-indent", <style>, <violation>, "LY-4"},
  {"standalone-closer", <style>, <violation>, "LY-4"},
  {"horizontal-form", <style>, <candidate>, "LY-3"},
  {"one-statement-braces", <style>, <violation>, "ST-1"},
  {"short-control-flow", <style>, <candidate>, "ST-2"},
  {"deferred-initialization", <style>, <violation>, "ST-7"},
  {"repeated-accessor", <style>, <candidate>, "ST-10"},
  {"subject-parameter-name", <style>, <violation>, "NM-2"},
  {"reference-parameter", <style>, <candidate>, "FN-8"},
  {"narration", <style>, <candidate>, "CM-2"},
  {"prohibited-prose", <style>, <candidate>, "CM-8"},
  {"constant-output-run", <style>, <candidate>, "EX-11"},
  {"member-arrow", <style>, <candidate>, "EX-6"},
  {"contains-in", <style>, <candidate>, "ST-11"},
  {"expression-body", <style>, <candidate>, "FN-7"},
  {"plain-string", <style>, <candidate>, "EX-3"},
  {"return-after-report-error", <style>, <violation>, "ER-4"},
  {"return-after-raise", <style>, <violation>, "ER-4"},
  {"fallback-shared-cause", <style>, <violation>, "ER-4"},
  {"fresh-literal-null-guard", <style>, <violation>, "ER-4"},
  {"growth-check", <style>, <violation>, "ER-4"},
  {"shape-diagnostics", <style>, <candidate>, "PR-4"},
  {"manual-shape-checks", <style>, <candidate>, "MA-7"},
  {"validator-diagnostics", <style>, <candidate>, "PR-4"},
  {"validator-shape", <style>, <candidate>, "PR-4"},
  {"recursive-validator", <style>, <candidate>, "FA-9"},
  {"validation-framework", <style>, <candidate>, "FA-9"},
  {"silent-shape-guard", <style>, <candidate>, "PR-4"},
  {"static-match-capture", <style>, <candidate>, "MA-7"},
  {"struct-copy", <style>, <candidate>, "FA-3"},
  {"manual-bookkeeping", <style>, <candidate>, "LT-1"},
  {"repeated-routes", <style>, <candidate>, "FA-5"},
  {"lifecycle-pair", <style>, <candidate>, "LT-1"},
  {"enum-table-switch", <style>, <candidate>, "FA-6"},
  {"internal-type", <style>, <candidate>, "FA-8"},
  {"duplicate-function-body", <style>, <candidate>, "FA-5"},
  {"long-function", <style>, <candidate>, "FN-2"},
  {"deep-nesting", <style>, <candidate>, "FN-5"},
  {"long-parameter-list", <style>, <candidate>, "FN-6"},
  {"long-name", <style>, <candidate>, "NM-3"},
  {"comment-history", <style>, <violation>, "CM-4"},
  {"comment-null-guard", <style>, <violation>, "CM-2"},
  {"section-label", <style>, <violation>, "FI-5"},
  {"catalog-label", <style>, <candidate>, "FI-5"},
  {"restates-name", <style>, <violation>, "CM-2"},
  {"restates-code", <style>, <violation>, "CM-2"},
  {"module-header-inventory", <style>, <candidate>, "FI-2"},
  {"doc-comment-tier", <style>, <violation>, "CM-5"},
  {"doc-boilerplate", <style>, <violation>, "CM-5"},
  {"doc-on-static", <style>, <violation>, "CM-5"},
  {"detached-doc", <style>, <violation>, "CM-5"},
  {"stacked-doc", <style>, <violation>, "CM-5"},
  {"repeated-prose", <style>, <candidate>, "CM-7"},
}

static const int rule_count = sizeof(rules) / sizeof(rules[0])

/** Returns the rule whose code is `code`, or NULL. */
const Rule *Rule.find(String code):
  for (int at = 0; at < rule_count; at++):
    if rules[at].code == code: return &rules[at]
  return NULL

/** Selects in `selected` the rules of `family`. */
void Rule.select_family(Map selected, Symbol family):
  for (int at = 0; at < rule_count; at++):
    if rules[at].family == family: selected[rules[at].code] = 1

/** Prints the rule table, one rule per line. */
void Rule.print_table(void):
  for (int at = 0; at < rule_count; at++):
    Rule rule = rules[at]
    printf("%-31s %-9s %-10s %s\n", rule.code, rule.family.str(),
           rule.kind.str(), rule.rule)

/** Whether `ch` continues a word: a letter, digit, or `_`. */
int lint_word_char(int ch) => isalnum(ch) || ch == '_'

/** Whether lower-case `text` contains `phrase` as whole words. */
int lint_phrase(String text, String phrase):
  for (int at = text.find(phrase); at >= 0;
       at = text.find_within(phrase, at + 1, -1)):
    int end = at + phrase.len()
    if (!at || !lint_word_char((unsigned char) text[at - 1])) &&
       !lint_word_char((unsigned char) text[end]):
      return 1
  return 0

/** Whether `t` is written string text: a literal, a segment, or a quote. */
int lint_string(Token t) =>
  t.type == <lit-char*> || t.type == <segment> || t.text == "\"" ||
  t.text == "%\""

/** Whether `t` is quoted text, a string or a character literal. */
int lint_text(Token t) => lint_string(t) || t.type == <lit-char>

/** Whether `t` is code: not space, a comment, a directive, or a literal
    such as a string, number, Symbol, or Lisp atom. */
int lint_code(Token t) =>
  t.type != <space> && t.type != <comment> && t.type != <preproc> &&
  !lint_string(t) && !t.type.str().startswith("lit-")

/** Whether `t` is an identifier or keyword, which may name a member. */
int lint_word(Token t) =>
  lint_code(t) && (isalpha((unsigned char) t.text[0]) || t.text[0] == '_')

/** Whether `t` begins a control header whose body may be one statement. */
int lint_control(Token t) =>
  t.text == "if" || t.text == "for" || t.text == "foreach" ||
  t.text == "while"

/** Whether `t` opens a bracket: `(`, `[`, `{`, or a prefixed form such as
    `%(`, `${`, or `%[`. */
int lint_opens(Token t) => lint_code(t) && strchr("([{", t.text[t.len - 1])

/** Whether `t` closes a bracket. */
int lint_closes(Token t) =>
  t.type == <")"> || t.type == <"]"> || t.type == <"}">

/* The quoting a bracket opens: 1 for a quoted Lisp form, 0 for code, and
   `outer` for a bracket that keeps the enclosing state. */
static int _quoting(Lint l, int at, int outer):
  String text = l.tokens[at].text
  int after_at = at && l.tokens[at - 1].text == "@"
  if text == "%(" || text == "$(" || text == "(" && after_at: return 1
  if text == "${" || text == "{" && after_at: return 0
  return outer

/* Invalid directives remain visible even when another rule is selected. */
static void _bad_suppression(Lint l, int line, String message):
  l.findings.push(%($line "bad-suppression" $message))

/* Only standalone line-comment tokens can qualify the next source line. */
static void _allowances(Lint l):
  for (int at = 0; at < l.count; at++):
    Token t = l.at(at)
    if t.type != <comment> || !t.text.startswith("//"): continue
    String text = t.text[2:].strip(" \t\r\n")
    if !text.startswith("lint:"): continue
    String directive = text[5:].strip(" \t\r\n")
    String (header, colon, reason) = directive.partition(":")
    Array words = []
    foreach String word in header.words(): words.push(word)
    const Rule *rule = words.len() == 3 ? Rule.find(words[1]) : NULL
    if l.first[t.line] != at || l.line_end(at) != at ||
       !colon || !reason.strip(" \t\r\n") || !rule ||
       words[0] != "allow" || words[2] != rule.rule ||
       words[1] == "bad-suppression":
      _bad_suppression(l, t.line,
        "expected // lint: allow CODE RULE-ID: non-empty reason")
      continue
    l.allowances[t.line + 1] = [words[1], 0]

/** Scans `text` and indexes its brackets, quoting, and lines. */
Lint Lint.new(String path, String text, Map selected):
  Tokenizer scanner = Tokenizer.new(text, <x2c>)
  scanner.scan()
  struct Token *all = (struct Token *) scanner.tokens
  int total = scanner.tokens.len() - 1
  Lint l = Scope.calloc(1, sizeof(struct Lint))
  l.path = path, l.text = text, l.selected = selected
  l.findings = [], l.edits = [], l.functions = [], l.unused = []
  l.allowances = {}
  l.layout = scanner.layout || path.endswith(".xp")
  l.tokens = Scope.calloc(total + 1, sizeof(struct Token))
  for (int at = 0; at < total; at++):
    if all[at].len: l.tokens[l.count++] = all[at]
  l.lines = 1
  for (char *ch = text; ch && *ch; ch++):
    if *ch == '\n' && ch[1]: l.lines++
  l.partner = Scope.calloc(l.count + 1, sizeof(int))
  l.quoted = Scope.calloc(l.count + 1, 1)
  l.first = Scope.calloc(l.lines + 2, sizeof(int))
  for (int line = 0; line <= l.lines + 1; line++): l.first[line] = -1
  Array open = [], states = []
  int quoted = 0
  for (int at = 0; at < l.count; at++):
    Token t = l.at(at)
    String type = t.type
    l.partner[at] = -1
    l.quoted[at] = quoted
    if t.type != <space> && t.line <= l.lines && l.first[t.line] < 0:
      l.first[t.line] = at
    if lint_opens(t) || type == "%\"":
      open.push(at)
      states.push(quoted)
      quoted = type == "%\"" ? 2 : _quoting(l, at, quoted)
    else if (lint_closes(t) || type == "\"") && open.len():
      int match = open.take_last().int()
      l.partner[match] = at, l.partner[at] = match
      quoted = states.take_last().int()
  _allowances(l)
  return l

/** Returns the token at index `at`. */
Token Lint.at(Lint l, int at) => &l.tokens[at]

/** Returns the index of the first non-space token after `at`, or
    `l.count`. */
int Lint.next(Lint l, int at):
  for (at++; at < l.count && l.tokens[at].type == <space>; at++) {}
  return at

/** Returns the index of the last non-space token before `at`, or -1. */
int Lint.prev(Lint l, int at):
  for (at--; at >= 0 && l.tokens[at].type == <space>; at--) {}
  return at

/** Returns the index of the last non-space token that starts on the line
    of the token at `at`. */
int Lint.line_end(Lint l, int at):
  int line = l.tokens[at].line
  for (int next = l.next(at); next < l.count && l.tokens[next].line == line;
       next = l.next(next)):
    at = next
  return at

/** Returns whether a token exists at index `at` with text `text`. */
int Lint.token_is(Lint l, int at, String text) =>
  at >= 0 && at < l.count && l.tokens[at].text == text

/** Returns the line on which the token at `at` ends. */
int Lint.end_line(Lint l, int at):
  Token t = l.at(at)
  int line = t.line
  for (int offset = 0; offset < t.len - 1; offset++):
    if l.text[t.pos + offset] == '\n': line++
  return line

/** Returns the width of the indentation before the first token on
    `line`, or -1 for a line with no token. */
int Lint.indent(Lint l, int line) =>
  l.first[line] < 0 ? -1 : l.tokens[l.first[line]].col - 1

/** Reports a selected, unsuppressed finding and returns 1, otherwise 0. */
int Lint.add(Lint l, String code, int line, String message):
  if !(code in l.selected): return 0
  Array allowance = l.allowances[line]
  if allowance && allowance[0] == code:
    allowance[1] = 1
    return 0
  l.findings.push(%($line $code $message))
  return 1

/** Reports allowances for selected codes with no matching finding. */
void Lint.suppression_rules(Lint l):
  foreach Var line in l.allowances.keys():
    Array allowance = l.allowances[line]
    if allowance[0] in l.selected && !allowance[1]:
      _bad_suppression(l, line.int() - 1,
        "suppression code has no matching finding on the next line")

/** Reports a finding of `code` at `line` whose fix replaces the text from
    the start of the token at `from` to the end of the token at `to` with
    `replacement`. `from` past `to` inserts before `from`. */
void Lint.fix(Lint l, String code, int line, String message, int from,
              int to, String replacement):
  if !l.add(code, line, message): return
  int start = l.tokens[from].pos
  int end = to < from ? start : l.tokens[to].pos + l.tokens[to].len
  l.edits.push(%($start $end $replacement))

/** Returns the text from the start of the token at `from` to the end of
    the token at `to`. */
String Lint.source(Lint l, int from, int to) =>
  String.new_len(l.text + l.tokens[from].pos,
                 l.tokens[to].pos + l.tokens[to].len - l.tokens[from].pos)

/** Returns the name of a `Lint.functions` row. */
String lint_name(List function) => function.car()

/** Prints the findings in line order. */
void Lint.print(Lint l):
  l.findings.sort()
  foreach List finding in l.findings:
    Var (line, code, message) = finding
    const Rule *rule = Rule.find(code)
    printf("%s:%d: %s %s %s: %s\n", l.path, line.int(), rule.kind.str(),
           code, rule.rule, message)
