/* macro-prefix-member.x -- the member of macro-prefix.x. C expands the
   macro; the functions after it keep their written spans and lines. */
#define PREFIX_STEP(value) ((value) + 1)

int prefix_step(int value);
// step the prefix
int prefix_step(int value) => PREFIX_STEP(value);

int Prefix.parse_expression(Prefix p, int token, int depth, int more) =>
  token + depth + more;

int Prefix.parse(Prefix written_prefix, int depth) {
  return written_prefix.parse_expression(
    written_prefix.token, depth + 1, written_prefix.state_depth);
}

int prefix_empty(Var value) => !(value is <list>);
