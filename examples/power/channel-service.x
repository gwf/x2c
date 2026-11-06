/*  channel-service.x -- a service and its clients share one batch lifetime */

#include "task.x"

static void _service(int tasks) {
  Channel requests = auto Channel.new(2);
  Channel first_reply = auto Channel.new();
  Channel second_reply = auto Channel.new();
  Array answers = auto [];
  Array jobs = auto [];
  int remaining_clients = 2;

  jobs.push(%!(void) => {
    foreach (List request in requests) {
      String text = request[0];
      Channel reply = request[1];
      reply.send(text.upper());
    }
    return <service>;
  });

  jobs.push(%!(void) => {
    requests.send($("first", first_reply));
    return first_reply.receive();
  });
  jobs.push(%!(void) => {
    requests.send($("second", second_reply));
    return second_reply.receive();
  });

  Func completed = %!(Var completed) using &remaining_clients => {
    if (completed is <string>) {
      answers.push(completed);
      if (--remaining_clients == 0) requests.close();
    }
  };
  if (tasks) Task.run(jobs, completed);
  else Thread.run(jobs, completed);

  foreach (String answer in answers.sort()) puts(answer);
}

int main(void) {
  _service(0);
  _service(1);
  return 0;
}
