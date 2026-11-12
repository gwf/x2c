// Markdown marks compile-only scaffold lines with ~. A hidden main wrapper
// contributes indentation to the full program, but not to its excerpt.
export function x2cExcerpt(source) {
  const result = [];
  let body = null;
  const appendBody = () => {
    const indents = body.filter(line => line.trim()).map(line => line.match(/^ */)[0].length);
    const indent = indents.length ? Math.min(...indents) : 0;
    result.push(...body.map(line => line.slice(indent)));
    body = null;
  };
  for (const line of source.split("\n")) {
    if (/^~int main\([^\n]*\)\s*\{/.test(line)) {
      body = [];
    } else if (body && /^~}\s*$/.test(line)) {
      appendBody();
    } else if (!line.trimStart().startsWith("~")) {
      (body ?? result).push(line);
    }
  }
  if (body) appendBody();
  return result.join("\n").replace(/^\n+|\n+$/g, "");
}
