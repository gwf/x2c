import { defineMdastPlugin } from "satteri";

export const wordmarkHtml = '<span class="x2c-wordmark">x2c</span>';

export function wordmarkParts(value) {
  return value.split(/(\bx2c\b)/g);
}

export const wordmark = defineMdastPlugin({
  name: "x2c-wordmark",
  text(node, context) {
    const parts = wordmarkParts(node.value);
    if (parts.length === 1) return;

    context.insertBefore(
      node,
      parts.filter(Boolean).map((value) =>
        value === "x2c"
          ? {
              type: "html",
              value: wordmarkHtml
            }
          : { type: "text", value }
      )
    );
    context.removeNode(node);
  }
});
