/*  service-health.x -- Report which services in a JSON file are unhealthy. */

import "yyjson" as json;

int main(void) {
  Scope.retain();
  defer Scope.release();

  Map config = json.Json.read_file(%"examples/services.json");
  Array services = config[%"services"];
  Array unhealthy = %[];

  printf("%s", %"region ${config[%"region"]}, ${services.len()} services\n");
  foreach(Map service, services) {
    String mark = service[%"healthy"].truthy() ? %"ok" : %"DOWN";
    printf("%s", %"  ${service[%"name"]}:${service[%"port"]} $mark\n");
    if (!service[%"healthy"].truthy()) unhealthy.push(service[%"name"]);
  }

  Var report = unhealthy;
  json.Json.write_file(report, %"/tmp/unhealthy.json");
  printf("%s", %"wrote ${report.json()} to /tmp/unhealthy.json\n");
  return 0;
}
