#pragma once
#include "after.x"

typedef struct Tracked { int value; } Tracked;
void Tracked.cleanup(Tracked value);

macro Declaration $tracked_initialization(Name $name, Expr $value) {
  Tracked $name = $value;
}

$after_initialization($tracked_initialization)
meta Code managed_binding(Code declaration) {
  match (declaration) case $tracked_initialization(?name, ?value):
    return $!{ defer $name.cleanup(); };
  return NULL;
}
