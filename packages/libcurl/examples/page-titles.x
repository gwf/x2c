/*  page-titles.x -- Fetch the titles from a small collection of web pages. */

import "libcurl" with CurlEasy, CurlResponse;

static String page_title(String html) {
  return html.split("<title>").last().string()
    .split("</title>").car();
}

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  String site = String.new(argv[1]);
  List pages = %("/guide" "/reference" "/source");

  CurlEasy curl = CurlEasy.new().timeouts(1000, 3000);
  defer curl.free();

  foreach(String page, pages) {
    CurlResponse response = curl.get(site + page);
    defer response.free();
    printf("%s: %s\n", page[1:], page_title(response.text()));
  }
  return 0;
}
