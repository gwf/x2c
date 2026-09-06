#include "protocol-static-owner.x"

double static_consumer_reading(StaticFeet value) {
  return value.magnitude();
}
