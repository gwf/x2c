#pragma indent
/*  lifetime.x -- shared declaration auto when acquired bindings stay fixed

    Parsing expands managed initializers into separate declarations. Their
    recorded token indexes recover the authored comma group; bound writes
    and reference access decide whether cleanup can use the final bindings.
*/
#include "lint.x"
#include "ast.x"
#include "grammar.x"

static void _changed(Map changed, List target):
  List binding = Ast.lvalue_binding(target)
  if binding: changed[binding] = 1

static Map _changed_bindings(List ast):
  Map changed = {}
  List node
  $ast.walk(ast, node):
    match node:
      case %(op & ?target):
        _changed(changed, target)
      case %(dstrasgn (targets *targets) ?):
        foreach List target in targets: _changed(changed, target)
      case $Macro.call_content($called,
          %(expr ?callee_type ?), %(*arguments)):
        List parameters = NULL
        if !Type.function_parts(callee_type, parameters, NULL): continue
        for (; parameters && arguments;
             parameters = parameters.cdr(), arguments = arguments.cdr()):
          Type parameter = parameters.car()
          if parameter.is_reference(): _changed(changed, arguments.car())
      default: _changed(changed, Ast.written_operand(node))
  return changed

static int _written(Token token) =>
  token.type != <space> && token.type != <comment> &&
  token.type != <preproc>

static int _next(struct Token *tokens, int count, int at):
  at++
  while at < count && !_written(tokens + at): at++
  return at

/* Skip one initializer using the compiler's balanced tokens, including
   indentation's inserted delimiters. A comma inside a literal is not a
   declaration separator. */
static int _end(struct Token *tokens, int count, int at):
  int depth = 0
  for (; at < count; at++):
    Token token = tokens + at
    if !depth && (token.type == <,> || token.type == <;>): return at
    if lint_opens(token): depth++
    else if lint_closes(token):
      if !depth: return count
      depth--
  return count

static int _group(Compiler c, Map bindings, Map changed, int at):
  struct Token *tokens = c.tokenizer.tokens
  int count = c.tokenizer.tokens.len(), size = 0
  for (;;):
    Var binding
    if !bindings.try_get(at, binding) || binding in changed: return 0
    at = _next(tokens, count, at)
    if at == count || tokens[at].type != <=>: return 0
    at = _next(tokens, count, at)
    if at == count || tokens[at].text != "auto": return 0
    at = _end(tokens, count, _next(tokens, count, at))
    if at == count: return 0
    size++
    if tokens[at].type == <;>: return size
    at = _next(tokens, count, at)

/** Reports compound groups whose managed initializers can share one auto.
    Only plain, explicitly typed declarators qualify. Mixed cleanup groups,
    writes, address escapes, and reference arguments keep initializer auto.
*/
void Lint.lifetime_rules(Lint l, Compiler c, List ast):
  if !("compound-auto" in l.selected): return
  auto Map bindings = {}, changed = _changed_bindings(ast)
  foreach List hit in ast.search(%(bind ?binding ())):
    List binding = hit.assoc(<?binding>)
    Var at
    if c.init_tokens.try_get(binding, at): bindings[at.int()] = binding
  struct Token *tokens = c.tokenizer.tokens
  foreach Var index in bindings.keys():
    int at = index.int(), before = at - 1
    while before >= 0 && !_written(tokens + before): before--
    // A later declarator follows a comma; only a group head follows a type.
    if before < 0 || !lint_word(tokens + before): continue
    if _group(c, bindings, changed, at) < 2: continue
    int position = tokens[at].pos
    String path = c.text_source(position, position)
    if Path.resolved_absolute(path) != Path.resolved_absolute(l.path):
      continue
    l.add("compound-auto", tokens[at].line,
          "use one leading auto for this compound declaration; " +
          "its bindings keep their acquired values")
