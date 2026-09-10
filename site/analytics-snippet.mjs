// Use the site-specific script URL from Plausible's installation settings.
// https://plausible.io/docs/plausible-script
export function analyticsSnippet(env = process.env, development = false) {
  if (development || env.SITE_ANALYTICS !== "production" ||
      !env.PLAUSIBLE_SCRIPT_URL) return "";

  const scriptUrl = env.PLAUSIBLE_SCRIPT_URL
    .replaceAll("&", "&amp;")
    .replaceAll('"', "&quot;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");

  return `<script async src="${scriptUrl}"></script>
<script>
window.plausible=window.plausible||function(){(plausible.q=plausible.q||[]).push(arguments)},plausible.init=plausible.init||function(i){plausible.o=i||{}};
plausible.init({outboundLinks:false,fileDownloads:false,formSubmissions:false});
</script>`;
}
