#pragma once

/*  json-api.x -- yyjson API names by family

    yyjson spells each operation once per tree: `yyjson_` for immutable
    documents and `yyjson_mut_` for mutable ones. The project meta build
    compiles a meta function defined in yyjson.x with that unit's header
    includes but not the package's C include directories, so it lives here.
*/

/* Calls the yyjson operation `name` of the API family `prefix`. The callee
   is a plain source identifier, which binds to the native declaration. */
meta List _json_call(String prefix, String name, List argument) {
  String spelling = %"$prefix$name";
  List callee = x2c_expr_ident(%($spelling));
  return $!( $callee($argument) );
}
