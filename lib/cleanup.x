#pragma once

// Cleanup adoption for handles released by one method.
// Import this file to use it: $(import "cleanup.x")

/* Adopts `Cleanup` for `$type` by calling its `$release` method, so `$auto`
   can name the handle's lifetime. The release method may be defined later
   in the unit. */
macro Unit $cleanup.by(Type $type, Name $release) {
  /** Ends the owned lifetime when a managed local leaves its block. */
  void $type.cleanup($type value) { value.$release(); }
  protocol Cleanup($type);
}
