/*  semantic-tokens.x -- lexical tokens in LSP UTF-16 coordinates

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "analysis.x"
#include "tokenizer.x"

static typedef struct SemanticTokens {
  String text;
  Array data;
  int at, line, column, previous_line, previous_column;
} SemanticTokens;

/** Declares the token indices returned by the lexical token stream. */
Array lsp_token_types(void) =>
  ["comment", "string", "number", "keyword", "operator", "variable", "macro"];

/** Scans the current document without requiring successful compiler analysis. */
Array LspWorkspace.semantic_tokens(LspWorkspace w, String path) {
  Context request = auto Context.open_isolated_named("language server tokens");
  SemanticTokens out = {.text = w.document(path), .data = []};
  Tokenizer tokenizer = Tokenizer.new(out.text, <x2c>);
  tokenizer.scan();
  for (Token token = tokenizer.tokens; token.type != <eof>; token++) {
    if (!token.len) continue;
    lsp_advance(out.text, token.pos, out.at, out.line, out.column);
    int type = _semantic_type(token);
    if (type < 0)
      lsp_advance(out.text, token.pos + token.len, out.at, out.line, out.column);
    else _semantic_parts(out, token.pos + token.len, type);
  }
  return request.export(out.data);
}

static int _semantic_type(Token token) {
  switch (token.type) {
    case <space>: case <error>: return -1;
    case <comment>: return 0;
    case <lit-char*>: case <lit-char>: case <segment>:
    case <lit-atom>: case <lit-symbol>: case <"%\"">: case <"\"">: return 1;
    case <lit-int>: case <lit-float>: return 2;
    case <ident>: return 5;
    case <preproc>: case <$>: case <@>: return 6;
    default: return scan_keyword_type(token.text, token.len) ? 3 : 4;
  }
}

/* Split physical lines because LSP clients need not accept multiline tokens.
   One forward cursor visits the complete source, including skipped trivia. */
static void _semantic_parts(SemanticTokens &out, int end, int type) {
  while (out.at < end) {
    int line = out.line, column = out.column, finish = out.at;
    while (finish < end && out.text[finish] != '\r' && out.text[finish] != '\n')
      finish++;
    lsp_advance(out.text, finish, out.at, out.line, out.column);
    int length = out.column - column;
    if (length) {
      out.data.push(line - out.previous_line);
      out.data.push(line == out.previous_line ? column - out.previous_column : column);
      out.data.push(length);
      out.data.push(type);
      out.data.push(0);
      out.previous_line = line;
      out.previous_column = column;
    }
    if (out.at < end) {
      // Line comments and directives can end between the two bytes of CRLF.
      int width = out.text[out.at] == '\r' && out.at + 1 < out.text.len() &&
                  out.text[out.at + 1] == '\n' ? 2 : 1;
      lsp_advance(out.text, out.at + width, out.at, out.line, out.column);
    }
  }
}
