/* Exact, line-based Myers diff. No source is evaluated. */
(function (root) {
  "use strict";
  function lines(source) {
    if (!source) return [];
    const result = source.replace(/\r\n/g, "\n").split("\n");
    if (result[result.length - 1] === "") result.pop();
    return result;
  }

  function compare(before, after) {
    const a = lines(before), b = lines(after);
    // Compare a missing final newline explicitly, without adding a phantom line.
    const key = (values, source, i) => values[i] + (i === values.length - 1 && !source.endsWith("\n") ? "\u0000" : "");
    return compareSequence(a, b, (x, y) => key(a, before, x) === key(b, after, y));
  }

  function compareSequence(a, b, equal) {
    const frontier = new Map([[1, 0]]), trace = [];
    for (let depth = 0; depth <= a.length + b.length; depth++) {
      trace.push(new Map(frontier));
      for (let diagonal = -depth; diagonal <= depth; diagonal += 2) {
        let x = diagonal === -depth || (diagonal !== depth && frontier.get(diagonal - 1) < frontier.get(diagonal + 1))
          ? frontier.get(diagonal + 1) : frontier.get(diagonal - 1) + 1;
        let y = x - diagonal;
        while (x < a.length && y < b.length && equal(x, y)) { x++; y++; }
        frontier.set(diagonal, x);
        if (x >= a.length && y >= b.length) return backtrack(trace, a, b);
      }
    }
  }

  function backtrack(trace, a, b) {
    let x = a.length, y = b.length;
    const result = [];
    for (let depth = trace.length - 1; depth >= 0; depth--) {
      const frontier = trace[depth], diagonal = x - y;
      const previousDiagonal = diagonal === -depth || (diagonal !== depth && frontier.get(diagonal - 1) < frontier.get(diagonal + 1))
        ? diagonal + 1 : diagonal - 1;
      const previousX = frontier.get(previousDiagonal), previousY = previousX - previousDiagonal;
      while (x > previousX && y > previousY) result.push({ type: "equal", text: a[--x], old: x + 1, new: y-- });
      if (!depth) break;
      if (x === previousX) result.push({ type: "add", text: b[--y], new: y + 1 });
      else result.push({ type: "remove", text: a[--x], old: x + 1 });
    }
    return result.reverse();
  }

  function intraline(before, after) {
    // Keep punctuation operators as tokens, including the C field arrow.
    const tokens = (text) => text.match(/"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[A-Za-z_$][\w$]*|\d+(?:\.\d+)?|\s+|->|[^\s]/g) || [];
    const a = tokens(before), b = tokens(after);
    const edits = compareSequence(a, b, (x, y) => a[x] === b[y]);
    return {
      before: edits.filter((edit) => edit.type !== "add").map((edit) => ({ text: edit.text, changed: edit.type === "remove" })),
      after: edits.filter((edit) => edit.type !== "remove").map((edit) => ({ text: edit.text, changed: edit.type === "add" }))
    };
  }

  function stripComments(source) {
    source = source.replace(/\r\n/g, "\n");
    let result = "", line = "", state = "code", quote = "", escaped = false;
    let hadComment = false, gap = false;
    const flush = (newline) => {
      const text = quote ? line : line.replace(/[\t ]+$/, "");
      if (!hadComment || text.trim()) result += text + (newline ? "\n" : "");
      line = ""; gap = false;
    };
    for (let i = 0; i < source.length; i++) {
      const ch = source[i], next = source[i + 1];
      if (ch === "\n") {
        flush(true);
        if (state === "line" && source[i - 1] !== "\\") state = "code";
        hadComment = state !== "code";
        escaped = false;
        continue;
      }
      if (state === "line") continue;
      if (state === "block") {
        if (ch === "*" && next === "/") { state = "code"; i++; gap = true; }
        continue;
      }
      if (!quote && ch === "/" && (next === "/" || next === "*")) {
        state = next === "/" ? "line" : "block";
        hadComment = true; i++; continue;
      }
      if (gap) {
        if (line && !/\s$/.test(line) && !/\s/.test(ch)) line += " ";
        gap = false;
      }
      line += ch;
      if (quote) {
        if (escaped) escaped = false;
        else if (ch === "\\") escaped = true;
        else if (ch === quote) quote = "";
      } else if (ch === '"' || ch === "'") quote = ch;
    }
    if (line || hadComment) flush(false);
    return result;
  }

  const api = { lines, compare, intraline, stripComments };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.SourceDiff = api;
})(typeof window !== "undefined" ? window : globalThis);
