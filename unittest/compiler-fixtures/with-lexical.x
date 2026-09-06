#include "x2c.x"

typedef struct Point {
  int x, y, z;
} Point;

typedef struct Box {
  Point point;
  Point points[2];
  Point *pointer;
} Box;

typedef struct Named {
  int with;
} Named;

static int call_count;
static int index_count;
static int with_count;

static Point *counted(Point *point) {
  call_count++;
  return point;
}

static int next_index(void) {
  index_count++;
  return 0;
}

static int with(int with) {
  with_count++;
  return with + 1;
}

static void helper(Point *point) {
  with point as value {
    value->z = 70;
  }
}

static void contextual_as(Point *as) {
  with as {
    _->y += 1;
  }
}

macro Statement $fixture.set_x(Expr $target, Expr $value) => {
  with $target {
    _.x = $value;
  }
}

macro Statement $fixture.assign(Expr $target, Expr $value) => {
  $target = $value;
}

macro Statement $fixture.template_shadow(Expr $target) => {
  Point _ = { 0 };
  with $target {
    _.x += 1;
    {
      Point _ = { 0 };
      _.x = 2;
    }
    _.y += 1;
  }
  _.z = 3;
}

macro Expression $fixture.keyword_value() => (99)
keyword point $fixture.keyword_value;

int main(void) {
  Box box = { 0 };
  box.pointer = &box.points[0];

  with box.point {
    _.x = 1;
    _.y = 2;
    _.z = 3;
  }
  with box.points[next_index()] {
    _.x = 10;
    _.x += 1;
  }
  with *box.pointer {
    _.y = 20;
  }
  with counted(&box.point) {
    _->x += 1;
    _->y += 1;
  }
  with counted(&box.point) {
    ;
  }

  int scaled = 0;
  with 1 + 2 {
    scaled = _ * 3;
  }
  if (scaled == 9) with box.point {
    _.z += 1;
  }

  Point _ = { 30, 0, 0 };
  int shadow_local = 0;
  with box.point {
    _.x += 1;
    Point _ = { 40, 0, 0 };
    _.x += 2;
    shadow_local = _.x;
  }

  with box.point {
    _.x += 1;
    with box.points[0] {
      _.y += 1;
    }
    _.y += 1;
  }
  with box.point as item {
    item.z += 1;
    with box.points[0] as item {
      item.z = 30;
    }
    item.z += 1;
  }
  with box.point as outer {
    with box.points[1] {
      _.x = outer.x + 1;
    }
  }

  $fixture.set_x(box.points[1], 6);
  with box.points[1] {
    $fixture.assign(_.z, 50);
  }
  helper(&box.points[0]);
  contextual_as(&box.points[1]);
  $fixture.template_shadow(box.points[1]);

  with box.point as point {
    point.x += 1;
  }
  int keyword = point();
  Named named = { 7 };
  int answer = with(41);
  (with)(1);

  printf(
    "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
    box.point.x, box.point.y, box.point.z,
    box.points[0].x, box.points[0].y, box.points[0].z,
    box.points[1].x, box.points[1].y, box.points[1].z,
    call_count, index_count, scaled, _.x, shadow_local, keyword,
    named.with, answer, with_count
  );
  return box.point.x == 5 && box.point.y == 4 && box.point.z == 6 &&
         box.points[0].x == 11 && box.points[0].y == 21 &&
         box.points[0].z == 70 && box.points[1].x == 7 &&
         box.points[1].y == 2 &&
         box.points[1].z == 50 &&
         call_count == 2 && index_count == 2 && scaled == 9 &&
         _.x == 30 && shadow_local == 42 && keyword == 99 &&
         named.with == 7 && answer == 42 && with_count == 2 ? 0 : 1;
}
