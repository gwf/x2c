---
section: packages
tab: yyjson
title: Turn JSON into a service report.
---

<!-- ignore: source excerpt; the complete example requires its optional package and setup. -->
```x2c,ignore
import "yyjson" as json;

Scope.retain();
defer Scope.release();
Map config = json.Json.read_file(
  %"examples/services.json"
);
Array services = config[%"services"];
Array unhealthy = %[];

foreach(Map service, services) {
  String mark = service[%"healthy"].truthy()
    ? %"ok" : %"DOWN";
  printf("%s", %"  ${service[%"name"]}:"
    + %"${service[%"port"]} $mark\n");
  if (!service[%"healthy"].truthy())
    unhealthy.push(service[%"name"]);
}

Var report = unhealthy;
json.Json.write_file(
  report, %"/tmp/unhealthy.json"
);
```

Read a JSON file into ordinary Maps and Arrays, then use the same
indexing and iteration as any other x2c collection. Each service supplies
a name, port, and health flag; the report marks it `ok` or `DOWN`.

Collect the unhealthy names in a new Array and write it back as JSON.
Here, only `release-worker` needs attention. The saved file contains that
single name, ready for another program to read.

Full example output:

```text
region us-west, 3 services
  artifact-api:8080 ok
  release-worker:9100 DOWN
  docs-site:443 ok
wrote ["release-worker"] to /tmp/unhealthy.json
```

[Full example](https://github.com/gwf/x2c/blob/main/packages/yyjson/examples/service-health.x) / [Package guide](https://github.com/gwf/x2c/blob/main/packages/yyjson/README.md)
