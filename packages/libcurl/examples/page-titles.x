/*  page-titles.x -- Fetch the titles from a small collection of web pages. */

import "libcurl" with CurlBatch, CurlEasy;

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

  List urls = pages.map(%!(String page) => site + page);
  CurlBatch batch = curl.get_all(urls, 3);
  defer batch.free();
  for (int i = 0; i < batch.len(); i++)
    printf("%s: %s\n", pages[i].string()[1:],
      page_title(batch.response(i).text()));
  return 0;
}
