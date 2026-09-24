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
    finding is a `<violation>` or a review `<candidate>`, and the section of
    `agents/x2c-coding-style-guide.md` that owns it.
*/
typedef struct Rule:
  String code
  Symbol family, kind
  String section
Rule

/** One file under lint. `partner` maps each bracket or interpolated-string
    token to its match, or -1; `quoted` is 1 for a token inside a quoted
    Lisp form and 2 inside an interpolated string, where `${...}` and
    `@{...}` return to code, 0; and `first` maps each line to its first
    non-space token, or -1. `layout` is set for a unit in the indentation
    syntax, where rules about braces, semicolons, and wrapped statements do
    not apply. `edits` holds the replacements that fixable findings
    propose, as `(START END TEXT)` byte ranges of `text`.
*/
typedef struct Lint:
  String path, text
  struct Token *tokens
  int count, lines, layout
  int *partner, *first
  char *quoted
  Map selected
  Array findings, edits
*Lint

#pragma private

static const Rule rules[] = {
  {"forward-declaration", <language>, <violation>, "forward-declarations"},
  {"same-file-forward-declaration", <language>, <candidate>,
   "forward-declarations"},
  {"negated-is", <language>, <violation>, "control-flow"},
  {"src-forward-declaration", <style>, <violation>, "forward-declarations"},
  {"runtime-forward-declaration", <style>, <candidate>,
   "forward-declarations"},
  {"tab", <style>, <violation>, "indentation-width-and-text"},
  {"trailing-whitespace", <style>, <violation>, "indentation-width-and-text"},
  {"non-ascii", <style>, <violation>, "indentation-width-and-text"},
  {"operator-spacing", <style>, <violation>, "indentation-width-and-text"},
  {"over-width", <style>, <violation>, "indentation-width-and-text"},
  {"over-width-literal", <style>, <candidate>, "indentation-width-and-text"},
  {"over-width-table-row", <style>, <candidate>,
   "indentation-width-and-text"},
  {"blank-line-stack", <style>, <violation>, "vertical-space"},
  {"decorated-ruler", <style>, <candidate>, "vertical-space"},
  {"wrapped-opening-line", <style>, <violation>, "signatures-and-calls"},
  {"continuation-indent", <style>, <violation>, "signatures-and-calls"},
  {"standalone-closer", <style>, <violation>, "signatures-and-calls"},
  {"horizontal-form", <style>, <candidate>, "signatures-and-calls"},
  {"one-statement-braces", <style>, <violation>, "control-flow"},
  {"short-control-flow", <style>, <candidate>, "control-flow"},
  {"deferred-initialization", <style>, <violation>, "declarations"},
  {"repeated-accessor", <style>, <candidate>, "declarations"},
  {"subject-parameter-name", <style>, <violation>, "names-expose-ownership"},
  {"narration", <style>, <candidate>, "local-comments-explain-decisions"},
  {"prohibited-prose", <style>, <candidate>, "prose"},
  {"constant-output-run", <style>, <candidate>,
   "literals-strings-and-formatting"},
  {"member-arrow", <style>, <candidate>, "reach-members-with-"},
  {"contains-in", <style>, <candidate>, "let-x2c-carry-the-syntax"},
  {"expression-body", <style>, <candidate>, "let-x2c-carry-the-syntax"},
  {"plain-string", <style>, <candidate>, "trust-supported-conversions"},
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
           rule.kind.str(), rule.section)

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

/** Scans `text` and indexes its brackets, quoting, and lines. */
Lint Lint.new(String path, String text, Map selected):
  Tokenizer scanner = Tokenizer.new(text)
  scanner.scan()
  struct Token *all = (struct Token *) scanner.tokens
  int total = scanner.tokens.len() - 1
  Lint l = Scope.calloc(1, sizeof(struct Lint))
  l.path = path, l.text = text, l.selected = selected
  l.findings = [], l.edits = []
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

/** Reports a finding of `code` at `line` when the rule is selected. */
void Lint.add(Lint l, String code, int line, String message):
  if l.selected.contains(code): l.findings.push(%($line $code $message))

/** Reports a finding of `code` at `line` whose fix replaces the text from
    the start of the token at `from` to the end of the token at `to` with
    `replacement`. `from` past `to` inserts before `from`. */
void Lint.fix(Lint l, String code, int line, String message, int from,
              int to, String replacement):
  if !l.selected.contains(code): return
  l.add(code, line, message)
  int start = l.tokens[from].pos
  int end = to < from ? start : l.tokens[to].pos + l.tokens[to].len
  l.edits.push(%($start $end $replacement))

/** Returns the text from the start of the token at `from` to the end of
    the token at `to`. */
String Lint.source(Lint l, int from, int to) =>
  String.new_len(l.text + l.tokens[from].pos,
                 l.tokens[to].pos + l.tokens[to].len - l.tokens[from].pos)

/** Prints the findings in line order. */
void Lint.print(Lint l):
  l.findings.sort()
  foreach List finding in l.findings:
    Var (line, code, message) = finding
    const Rule *rule = Rule.find(code)
    printf("%s:%d: %s %s: %s\n", l.path, line.int(), rule.kind.str(),
           code, message)
