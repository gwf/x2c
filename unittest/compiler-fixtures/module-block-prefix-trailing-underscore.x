/* Member paths that differ only in trailing non-identifier characters
   share a static prefix, so `_n` in one and `n` in the other cannot meet
   in one generated name unreported. */
module {
  "module-block-prefix-trailing-underscore/foo.x",
  "module-block-prefix-trailing-underscore/foo-.x",
}
