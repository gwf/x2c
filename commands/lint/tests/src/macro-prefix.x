/* macro-prefix.x -- a module entry whose member writes functions after a
   C macro. Findings map from the spliced unit to each file and line. */
typedef struct Prefix { int token, depth, state_depth; } *Prefix;

module {
  "macro-prefix-member.x",
}

int prefix_total(Prefix p);
int prefix_total(Prefix p) => p.depth + p.token;
