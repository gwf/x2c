/* A small expedition log, from native values to language extension. */

#include <assert.h>
#include "typed-array.x"
#include "typed-map.x"
#include "typed-list.x"

class Stop struct { String name; int miles; } *;

String Stop.describe(Stop stop) => %"${stop.name} (${stop.miles} mi)";

/* A macro keeps one repeated source-level action in one place. */
macro Statement $announce(Expr $message) {
  printf("%s\n", $message);
}

/* The same native function can be called by ordinary x2c and by Lisp. */
int pace(int miles) => miles * 2;

/* Workers receive a copy of plain C input and return a dynamic result. */
static Var survey(const void *input, size_t bytes) {
  const int *miles = input;
  return bytes == sizeof(int) ? *miles * 2 : 0;
}

static void check_water(Map supplies, int hikers) {
  if (supplies[<water>].int() < hikers)
    raise %(lowwater (item water));
}

int main(void) {
  $scope() {
    /* 1. C values stay native; String and Var add richer values. */
    int day = 1;
    String trail = "Pine Loop";
    Var weather = "clear";
    $announce(%"day $day: $trail ($weather)");

    /* 2. Symbol names a state; SymbolSet owns the closed vocabulary. */
    SymbolSet states = %<<planned walking done>>;
    Symbol state = <planned>;
    assert(states.contains(state));
    printf("state %s has index %d\n", state.str(), states.index(state));

    /* 3. List is persistent: the new route shares the old tail. */
    List route = %(lake ridge camp);
    List detour = cons(<lookout>, route);
    assert(detour.cdr() == route);
    printf("route: %s\n", detour.str());

    /* 4. Array is a mutable, indexed work queue. */
    Array stops = [Stop.new("lake", 2), Stop.new("ridge", 5)];
    stops.push(Stop.new("camp", 3));
    Stop next = stops[1];
    printf("next: %s; stops: %zu\n", next.describe(), stops.len());

    /* 5. Map associates names and values; absence is explicit. */
    Map supplies = {water: 3, snacks: 2};
    supplies[<water>] += 1;
    Var missing;
    assert(!supplies.try_get(<tent>, &missing));
    printf("water: %d; tent: %s\n", supplies[<water>].int(),
           supplies.getdefault(<tent>, "none"));

    /* Errors cross a helper; the caller chooses the recovery. */
    try check_water(supplies, 5);
    catch %(lowwater (item ?item)):
      printf("pack more %s\n", item);

    /* 6. Typed families store native elements without boxing. */
    ArrayInt legs = [2, 5, 3];
    MapStringInt visits = {"lake": 1, "ridge": 1};
    visits["lake"] += 1;
    ListInt milestones = %(2 7 10);
    printf("miles: %d; lake visits: %d; finish: %d\n",
           legs[0] + legs[1] + legs[2], visits["lake"],
           milestones.last());

    /* 7. A lambda captures a native value for a collection operation. */
    int bonus = 1;
    List adjusted = milestones.map(%!(mile) => mile + bonus);
    printf("adjusted: %s\n", adjusted.str());

    /* 8. Iter streams a pipeline; match reads a structured message. */
    int long_legs = legs.iter().filter(%!(mile) => mile >= 3).count();
    List event = %(arrived ridge 5);
    match (event) {
      case %(arrived ?place ?distance):
        printf("arrived: %s after %d miles; long legs: %d\n",
               place, distance.int(), long_legs);
    }

    /* 9. Buffer grows text; File and $auto own temporary resources. */
    Buffer report = $auto(Buffer.new(0));
    foreach (Var item, stops) {
      Stop stop = item;
      report.write(stop.describe());
      report.write("\n");
    }
    File log = $auto(tmpfile());
    log.puts(report.str());
    log.rewind();
    printf("log: %s", log.string());

    /* 10. Runtime Lisp can use an ordinary typed native function. */
    Lisp lisp = $auto(Lisp.new());
    $lisp.bind(lisp, "pace", pace);
    int hours = lisp.eval(%(pace 5));
    /* The Lisp expression below runs during translation. */
    int daylight = $(+ 4 2);
    printf("estimated hours: %d; daylight: %d\n", hours, daylight);

    /* 11. Native workers own isolated x2c state until joined. */
    int west = legs[0], east = legs[2];
    Thread first = Thread.start(survey, &west, sizeof(west));
    Thread second = Thread.start(survey, &east, sizeof(east));
    int survey_hours = first.join() + second.join();
    first.free();
    second.free();
    printf("survey hours: %d\n", survey_hours);
    $announce("Expedition complete.");
  }
  return 0;
}
