#!/usr/bin/env -S x2c script
/*  parallel-jobs.x -- run commands at most three at a time and report each */

static String describe(String name, Job job) {
  int status = job.status();
  String output = status ? NULL : job.output(), errors = job.errors();
  String out = output ? output.strip("\n") : "-";
  String err = errors ? errors.strip("\n") : "-";
  return %"$name status $status out $out err $err";
}

List queue = %(
  (sh -c "sleep 0.05; echo alpha")
  (echo bravo)
  (sh -c "sleep 0.02; echo charlie >&2; exit 3")
  (sh -c "sleep 0.03; echo delta")
  (false)
  (echo echo)
);
int limit = 3, peak = 0, started = 0;
Array running = %[], results = %[];
Map names = %{};

foreach (List command, queue) {
  if (running.len() == limit) {
    Job done = Job.wait_any(running);
    results.push(describe(names[done], done));
  }
  Job job = command.job().options(%{stderr: capture}).start();
  names[job] = %"job ${++started}";
  running.push(job);
  if (running.len() > peak) peak = running.len();
}
while (running.len()) {
  Job done = Job.wait_any(running);
  results.push(describe(names[done], done));
}

foreach (String line, results.sort()) printf("%s\n", line);
printf("peak %d of %d\n", peak, limit);

try %(sh -c "echo broken >&2; exit 4").job().options(%{stderr: capture})
  .run();
catch %(cmd-fail *detail):
  printf("run raised status %ld: %s", detail.assoc(<status>).integer(),
         detail.assoc(<errors>).string());
