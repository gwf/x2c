#pragma once

macro Expression $fixture.location() =>
  $x2c_ident("location_values")(
    $x2c_invocation_file(),
    $x2c_invocation_line(),
    $x2c_invocation_column()
  );

macro Expression $fixture.nested_location() => $fixture.location();
