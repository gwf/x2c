/* Two member paths that differ only in non-identifier characters would
   give their statics one prefix. */
module {
  "module-block-prefix-collision/a_b.x",
  "module-block-prefix-collision/a/b.x",
}
