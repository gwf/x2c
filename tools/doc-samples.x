#pragma indent
/*  doc-samples.x -- the fenced x2c samples of a Markdown page

    `check-doc-examples` compiles and runs the samples, and
    `check-gallery-examples` compares a slide's sample with its standalone
    example. A fence opens with a line of backticks and an info string and
    closes at the next line that repeats the opening indent before its
    backticks. An unterminated opening line is ordinary text.
*/
#include "path.x"
#include "regex.x"

/** One checked sample: `(where code expected runs status)`. `where` is
    `page:line`, `code` has its indent and hidden-line markers removed, and a
    nonzero `runs` means the sample is built and run, printing `expected`
    and exiting with `status`.
*/
typedef List Sample

/** Reports whether `sample` is built and run. */
int Sample.runs(Sample sample):
  (String where, String code, String expected, int runs) = sample
  return runs

/** Returns each fence of `text` as `(indent info body line start stop)`:
    `line` is the one-based line of the opening fence, and `start` and `stop`
    are the byte offsets of the opening line and of the end of the closing
    fence.
*/
List Sample.fences(String text):
  Regex opening = Regex.compile("^(?<indent>[ \\t]*)```(?<info>.*)$")
  Array lines = text.split("\n"), offsets = [], fences = []
  int offset = 0
  foreach String line, lines:
    offsets.push(offset)
    offset += line.len() + 1
  for int at = 0; at + 1 < lines.len(); at++:
    RegexMatch found = opening.match(lines[at])
    if (!found) continue
    String indent = found["indent"], close = %"$indent```"
    for int end = at + 1; end < lines.len(); end++:
      String line = lines[end]
      if (!line.startswith(close) || line[close.len():].strip(" \t"))
        continue
      Array body = []
      for (int inner = at + 1; inner < end; inner++) body.push(lines[inner])
      String text_body = body.len() ?
        String.join("\n", body.list_free()) + "\n" : NULL
      int stop = offsets[end].integer() + line.len()
      fences.push(%($indent ${found["info"]} $text_body ${at + 1}
                    ${offsets[at]} $stop))
      at = end
      break
  return fences.list_free()

/** Returns the language word of a fence's info string. */
String Sample.language(String info) =>
  info ? Regex.compile("^[^\\s,]*").match(info)[0] : NULL

static String _dedent(String body, String indent):
  if (!indent) return body
  Array lines = []
  foreach (String line, body.split_lines(0))
    lines.push(line.startswith(indent) ? line[indent.len():] : line)
  return String.join("\n", lines.list_free()) + "\n"

/* Drops the `~` prefix that book.toml hides from readers. */
static String _reveal_hidden(String code):
  Array lines = []
  foreach String line, code.split_lines(0):
    String stripped = line.lstrip(NULL)
    if (stripped.startswith("~"))
      lines.push(line[:line.len() - stripped.len()] + stripped[1:])
    else lines.push(line)
  return String.join("\n", lines.list_free()) + "\n"

/** Returns the samples of the page at `path`, adding each malformed fence
    to `errors`. Locations are relative to `root`.
*/
List Sample.collect(Path root, Path path, Array errors):
  String text = path.read_text(), relative = path
  relative = relative[root.len() + 1:]
  Regex sample_info = Regex.compile("^x2c(,ignore)?$")
  Regex output_info = Regex.compile("^text(,status=(?<status>\\d+))?$")
  Regex reason = Regex.compile("(?s)<!--\\s*ignore:\\s*\\S+.*?-->")
  Array fences = Sample.fences(text), samples = []
  for int at = 0; at < fences.len(); at++:
    (String indent, String raw, String body, int line, int start, int stop) =
      fences[at].list()
    String info = raw.strip(NULL)
    if (Sample.language(info) != "x2c") continue
    String where = %"$relative:$line"
    RegexMatch sample = sample_info.match(info)
    if !sample:
      errors.push(%"$where: unrecognized fence `$info`; " +
                  "use `x2c` or `x2c,ignore`")
      continue
    String code = _reveal_hidden(_dedent(body, indent))
    if sample[1]:
      String prior = text[start > 400 ? start - 400 : 0:start]
      if (!prior || !reason.match(prior))
        errors.push(%"$where: `x2c,ignore` needs an " +
                    "<!-- ignore: reason --> comment above the fence")
      continue
    if (!code.strip(NULL)) continue
    String expected = NULL
    int runs = 0, status = 0
    if at + 1 < fences.len():
      (String next_indent, String next_raw, String next_body, int next_line,
       int next_start) = fences[at + 1].list()
      String shown = next_raw.strip(NULL)
      if Sample.language(shown) == "text" &&
          !text[stop:next_start].strip(NULL):
        RegexMatch fence = output_info.match(shown)
        if !fence:
          errors.push(%"$where: unrecognized output fence `$shown`; " +
                      "use `text` or `text,status=N`")
          continue
        expected = _dedent(next_body, next_indent)
        runs = 1
        status = fence["status"] ? atoi(fence["status"]) : 0
    samples.push(%($where $code $expected $runs $status))
  return samples.list_free()
