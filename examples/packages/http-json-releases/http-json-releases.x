/*  releases.x -- Fetch and summarize a JSON release catalog. */

import "libcurl" with CurlEasy, CurlResponse;
import "yyjson" with Json;

int main(int argc, char **argv) {
  Scope.retain();
  defer Scope.release();

  String url = argc > 1 ? String.new(argv[1]) :
    %"https://api.github.com/repos/PCRE2Project/pcre2/releases?per_page=5";
  CurlEasy curl = CurlEasy.new()
    .timeouts(3000, 10000)
    .follow_redirects(5)
    .max_body(2 * 1024 * 1024)
    .user_agent(%"x2c-release-report/1")
    .header(%"Accept: application/vnd.github+json");
  defer curl.free();

  CurlResponse response = curl.get(url);
  defer response.free();
  if (response.response_code() != 200) {
    Stderr.printf("HTTP %ld from %s\n", response.response_code(), url);
    return 1;
  }

  Array releases = Json.parse(response.text());
  Map channels = %{};
  int assets = 0;

  printf("%s", %"${releases.len()} releases\n");
  foreach(Map release, releases) {
    String channel = Json.boolean(release[%"prerelease"])
      ? %"preview" : %"stable";
    Var count = 0;
    channels.try_get(channel, &count);
    channels[channel] = count + 1;

    Array files = release[%"assets"];
    assets += files.len();
    String tag = release[%"tag_name"];
    printf("%s", %"  $tag  $channel  ${files.len()} assets\n");
  }

  Var stable = 0, preview = 0;
  channels.try_get(%"stable", &stable);
  channels.try_get(%"preview", &preview);
  printf("%s", %"stable: $stable; preview: $preview; assets: $assets\n");

  /*  The catalog the report just summarized goes back as one JSON document,
      which is the other half of the composition: libcurl fetches the bytes
      and yyjson decides what they mean.
  */
  Var summary = %{ "stable": $stable, "preview": $preview,
                   "assets": $assets };
  CurlResponse posted = curl.body(%"application/json", summary.json())
    .request(%"POST", url + %"/summary");
  defer posted.free();
  Map echoed = Json.parse(posted.text());
  printf("%s", %"posted ${echoed[%"length"]} bytes as ${echoed[%"type"]}\n");
  return 0;
}
