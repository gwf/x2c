import { markdownToHtml } from "satteri";
import { wordmark } from "../../wordmark.mjs";

export const inlineMarkdown = async (source: string) => {
  const { html } = await markdownToHtml(source, {
    mdastPlugins: [wordmark]
  });
  return html.replace(/^<p>/, "").replace(/<\/p>\n?$/, "");
};
