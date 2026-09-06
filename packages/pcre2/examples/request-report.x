/*  request-report.x -- Analyze and redact a small HTTP access-log batch. */

import "pcre2" with Regexp, RegexpCapture, RegexpMatch;

int main(void) {
  Regexp request = Regexp.compile(
    %"^(?<method>[A-Z]+) (?<path>[^ ]+) HTTP/[0-9.]+ (?<status>[0-9]{3})$$",
    PCRE2_UTF | PCRE2_UCP
  );
  defer request.free();

  Regexp api_path = Regexp.compile(%"^/api/", PCRE2_UTF | PCRE2_UCP);
  defer api_path.free();
  Regexp parameter = Regexp.compile(
    %"(?:[?&])(?<name>[^=&]+)=(?<value>[^&]*)",
    PCRE2_UTF | PCRE2_UCP
  );
  defer parameter.free();
  Regexp token = Regexp.compile(%"token=[^& ]+", PCRE2_UTF | PCRE2_UCP);
  defer token.free();

  List lines = %(
    "GET /docs?lang=en HTTP/1.1 200"
    "POST /api/releases?channel=stable&token=abc123 HTTP/1.1 201"
    "GET /api/releases?channel=beta HTTP/1.1 503"
    "not a request"
  );
  Map methods = %{};
  int api_requests = 0;

  foreach(String line, lines) {
    RegexpMatch parsed = request.match(line);
    if (!parsed) {
      printf("%s", %"ignored: $line\n");
      continue;
    }

    String method = parsed[<method>], path = parsed[<path>];
    Var old = 0;
    methods.try_get(method, &old);
    methods[method] = old + 1;
    if (api_path.match(path)) api_requests++;

    printf("%s", %"$method ${parsed[2]} -> ${parsed[<status>]}\n");
    foreach(RegexpCapture capture, parsed) {
      if (capture.matched() && capture.name())
        printf("%s", %"  ${capture.name()}=${capture.text()}\n");
    }
    foreach(RegexpMatch field, parameter.find_all(path))
      printf("%s", %"  query ${field[<name>]}=${field[2]}\n");

    String safe = token.replace_all(line, %"token=[redacted]");
    printf("%s", %"  safe $safe\n");
  }

  printf("%s", %"api requests: $api_requests\n");
  foreach(Var (method, count), methods)
    printf("%s", %"$method requests: $count\n");
  return 0;
}
