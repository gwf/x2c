/*  package-define-surface.x -- an import replays the package's surface
    past the directive events its entry records.
*/
#pragma once

import "defines" as d;

int room_left(int used);


int room_left(int used) {
  d.Room room = { used };
  return room.left();
}
