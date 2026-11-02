/*  defines.x -- package whose entry defines a C macro beside the
    declarations it publishes.
*/
#pragma once

#define DEFINES_LIMIT 8

typedef struct Room { int used; } Room;

int Room.left(Room room);


int Room.left(Room room) => DEFINES_LIMIT - room.used;
