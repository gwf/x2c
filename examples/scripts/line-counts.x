#!/usr/bin/env -S x2c script
/*  line-counts.x -- count lines with parallel commands and write a report */

static void write_sources(Path root) {
  Map sources = {
    "src/main.x": "int main(void) {\n  return run();\n}\n",
    "src/run.x": "int run(void) {\n  int total = 0;\n  return total;\n}\n",
    "lib/text.x": "String greeting(void) => \"hello\";\n",
    "docs/notes.md": "not source\n"
  };
  foreach (Var (name, text), sources) {
    Path path = root.join(name.str());
    path.dirname().make_dirs();
    path.write_text(text.str());
  }
}

Path root = Path.temp_dir();
write_sources(root);

Array running = [], counts = [];
foreach (Path unit, root.join("**/*.x").glob()) {
  if (running.len() == 2) counts.push(Job.wait_any(running).output());
  running.push(%(wc -l $unit).job().start());
}
while (running.len()) counts.push(Job.wait_any(running).output());

Array lines = [];
foreach (String count, counts) {
  List fields = count.strip(" \n").split(" ").filter(%!(word) => word);
  String path = fields.cadr().str();
  lines.push(%"${fields.car()} ${path[root.len() + 1:]}");
}
Path report = root.join("report/lines.txt");
report.dirname().make_dirs();
report.write_text(%"${String.join("\n", lines.sort().list_free())}\n");

printf("%s", report.read_text());
printf("total %s", %((cat $report) (awk "{ s += \$1 } END { print s }"))
  .job().output());
printf("markdown files %ld\n",
       (long) root.walk().filter(%!(path) => path.str().endswith(".md"))
         .count());
root.remove_tree();
printf("cleaned %s\n", root.exists() ? "no" : "yes");
