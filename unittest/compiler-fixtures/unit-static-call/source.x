// A static function above the private boundary is still unit-private, and
// the one below it is dropped from what the file publishes.
static int above_boundary(int value) => value + 1;
int shared_value(int value) => above_boundary(value) + below_boundary(value);

#pragma private
static int below_boundary(int value) => value + 2;
