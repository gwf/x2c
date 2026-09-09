/*  endpoint-report.x -- Survey a service's endpoints, then fetch its file. */

import "libcurl" with CurlBatch, CurlEasy, CurlHeader, CurlResponse,
  CurlResponseBlock;

/*  A survey answers two questions per request: what came back, and did it
    come back inside the latency budget.
*/
static const long BUDGET_US = 3000000;

static void count_chunk(Bytes chunk, Var data) {
  Array count = data.array();
  count[0] = count[0].integer() + chunk.block().length;
}

static void summarize(CurlResponse response) {
  long code = response.response_code(), sent = response.upload_size();
  size_t received = response.body_size();
  String timing = response.elapsed_us() < BUDGET_US ? %"in budget" : %"late";
  printf("%s", %"  $code ${response.effective_url()}\n");
  printf("%s", %"  $received bytes in, $sent out, $timing\n");
}

static void survey(CurlBatch batch, int index, String path) {
  printf("%s", %"GET $path\n");
  try {
    CurlResponse response = batch.response(index);
    summarize(response);
    int number = 0;
    foreach(CurlResponseBlock block, response.blocks()) {
      printf("%s", %"  block $number: ${block.status_line()}\n");
      foreach(CurlHeader header, block.headers())
        printf("%s", %"    ${header.line()}\n");
      number++;
    }
  }
  catch %(size-limit *detail): {
    String channel = detail.assoc(<channel>);
    long limit = detail.assoc(<limit>).integer();
    printf("%s", %"  refused: $channel over $limit bytes\n");
  }
  catch %(io-fail *detail): {
    long code = detail.assoc(<code>).integer();
    printf("%s", %"  failed: libcurl code $code\n");
  }
}

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  String base = String.new(argv[1]);
  String artifact = %"/tmp/x2c-endpoint-report.bin";
  List paths = %("/ok" "/redirect" "/empty" "/missing" "/large" "/close");

  CurlEasy easy = CurlEasy.new()
    .timeouts(1000, 3000)
    .follow_redirects(3)
    .max_body(32)
    .user_agent(%"x2c-endpoint-report/1");
  defer easy.free();

  List urls = paths.map(%!(String path) => base + path);
  CurlBatch batch = easy.get_all(urls, 3);
  defer batch.free();
  for (int i = 0; i < batch.len(); i++) survey(batch, i, paths[i]);

  /*  A HEAD asks a large endpoint's size without moving its body. */
  CurlResponse head = easy.request(%"HEAD", base + %"/download");
  defer head.free();
  printf("HEAD /download\n");
  summarize(head);

  /*  Submitting a job: one body with its content type, answered in JSON.
      The reply no longer fits the survey's deliberately tiny body limit.
  */
  easy.max_body(64 * 1024);
  String job = %"{\"artifact\":\"release-7\",\"format\":\"tar\"}";
  CurlResponse accepted = easy.body(%"application/json", job)
    .request(%"POST", base + %"/echo");
  defer accepted.free();
  printf("%s", %"POST /echo\n");
  printf("%s", %"  ${accepted.text()}\n");
  summarize(accepted);

  /*  The signing key needs credentials, which libcurl offers up front. */
  CurlResponse key = easy.basic_auth(%"user", %"s3cret")
    .get(base + %"/secret");
  defer key.free();
  printf("%s", %"GET /secret\n");
  printf("%s", %"  ${key.response_code()} ${key.text()}\n");

  /*  A search term with a space, an ampersand, and a slash in it only
      survives the round trip percent-encoded.
  */
  String term = %"x2c & friends/100%";
  CurlResponse found = easy.get(
    base + %"/search?q=" + CurlEasy.escape(term)
  );
  defer found.free();
  printf("%s", %"GET /search\n");
  printf("%s", %"  ${found.text()}\n");

  /*  The callback receives copied chunks and ordinary x2c state. It never
      owns a native buffer, and the response still retains status and headers.
  */
  Array streamed = %[0];
  CurlResponse observed = easy.max_body(32)
    .stream(base + %"/download", streamed, count_chunk);
  defer observed.free();
  printf("%s", %"GET /download stream\n");
  printf("%s", %"  ${streamed[0]} bytes passed to callback\n");

  /*  The artifact goes straight to disk as it arrives, so the survey's body
      limit does not apply and nothing large is ever held in memory.
  */
  CurlResponse fetched = easy.max_body(32)
    .download(base + %"/download", artifact);
  defer fetched.free();
  printf("%s", %"GET /download\n");
  printf("%s", %"  ${fetched.body_size()} bytes written to $artifact\n");
  return 0;
}
