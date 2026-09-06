#pragma once

typedef struct Part { int value; } Part;

typedef struct Box {
  delegate Part part;
} Box;

int Part.read(Part value);

#pragma private

int Part.read(Part value) {
  return value.value;
}

static int Part.hidden(Part value) {
  return value.value;
}
