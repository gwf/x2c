import { absoluteSiteUrl } from "./site-config.mjs";

export function releaseDestination(env = process.env) {
  const sourceRef = env.SITE_SOURCE_REF || "main";
  const staging = env.SITE_RELEASE_CHANNEL === "staging";
  const candidate = env.SITE_CANDIDATE_ID || "";
  if (sourceRef !== "main" && !/^[a-f0-9]{40}$/.test(sourceRef)) {
    throw new Error("SITE_SOURCE_REF must be a full source SHA");
  }
  if (staging && (sourceRef === "main" ||
      !new RegExp(`^candidate-${sourceRef}-[0-9]+-[0-9]+$`).test(candidate))) {
    throw new Error("staging requires a source SHA and SITE_CANDIDATE_ID");
  }
  return { sourceRef, staging, candidate };
}

export const destination = releaseDestination();

export function installExample(original, config = destination) {
  if (!config.staging) return original;
  return `export X2C_PREFIX="$(mktemp -d)/x2c"
curl -fsSL ${absoluteSiteUrl("/install.sh")} | sh
export PATH="$X2C_PREFIX/bin:$PATH"
x2c run "$X2C_PREFIX/examples/foreach.x"
x2c install pcre2 --index ${absoluteSiteUrl("/packages/index.txt")}`;
}

function escapeHtml(value) {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;").replaceAll('"', "&quot;");
}

// Apply once after both Astro and mdBook have emitted their complete output.
// This also covers links authored in Markdown and slide frontmatter.
export function finalizeDestination(html, config = destination) {
  if (config.sourceRef !== "main") {
    html = html.replaceAll("https://github.com/gwf/x2c/blob/main/",
      `https://github.com/gwf/x2c/blob/${config.sourceRef}/`)
      .replaceAll("https://github.com/gwf/x2c/tree/main/",
        `https://github.com/gwf/x2c/tree/${config.sourceRef}/`)
      .replaceAll("https://github.com/gwf/x2c/archive/refs/heads/main.zip",
        `https://github.com/gwf/x2c/archive/${config.sourceRef}.zip`);
  }
  if (config.staging) {
    const metadata = `<meta name="x2c-release-channel" content="staging">` +
      `<meta name="x2c-candidate" content="${escapeHtml(config.candidate)}">`;
    html = html.replace(/(<head\b[^>]*>)/i, `$1${metadata}`);
  }
  return html;
}
