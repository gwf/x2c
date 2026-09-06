/* release-catalog.x -- inspect, patch, and publish lossless JSON data. */

import "yyjson" as json;

int main(void) {
  Scope.retain();
  defer Scope.release();

  String source = %"".join(%(
    "{\"service\":{\"name\":\"artifact-api\",\"active\":true},"
    "\"labels\":{\"region\":\"us-west\",\"region\":\"fallback\","
    "\"tier\":\"edge\"},\"releases\":["
    "{\"version\":\"2.3.0\",\"channel\":\"stable\","
    "\"downloads\":1400},"
    "{\"version\":\"2.4.0-rc1\",\"channel\":\"preview\","
    "\"downloads\":320},"
    "{\"version\":\"2.2.7\",\"channel\":\"stable\","
    "\"downloads\":870}]}"
  ));
  json.JsonDocument catalog = json.JsonDocument.parse(source);
  defer catalog.free();

  json.JsonObject root = catalog.root().object();
  json.JsonObject service = root[%"service"].object();
  json.JsonArray releases = root[%"releases"].array();
  Map downloads = %{};

  printf("%s", %"service: ${service[%"name"].string()}\n");
  foreach(json.JsonValue item, releases) {
    json.JsonObject release = item.object();
    String version = release[%"version"].string();
    String channel = release[%"channel"].string();
    unsigned long long total = release[%"downloads"].uint();
    Var count = 0;
    downloads.try_get(channel, &count);
    downloads[channel] = count + total;
    printf("%s", %"  $version ($channel) $total downloads\n");
  }

  json.JsonObject labels = root[%"labels"].object();
  foreach(json.JsonMember member, labels)
    printf("%s", %"label ${member.key()}=${member.value().string()}\n");
  printf("%s", %"region entries: ${labels.all(%"region").len()}\n");

  Array operations = %[
    {
      "op": "replace",
      "path": "/service/name",
      "value": "edge-api"
    },
    {
      "op": "add",
      "path": "/release-count",
      "value": ${releases.len()}
    }
  ];
  json.JsonDocument published = catalog.patch(operations);
  defer published.free();

  json.JsonObject published_root = published.root().object();
  String name = published_root[%"service"].object()[%"name"].string();
  printf("%s", %"published service: $name\n");
  printf("%s", %"stable downloads: ${downloads[%"stable"]}\n");
  puts(published.pretty_json());
  return 0;
}
