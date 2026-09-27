# Literal head census

Regex `%(` followed by literal lowercase head only; references are first occurrences,
not proof of producer status. S/D field forms appear in grammar-fields.md.

| Head | Classification | Representative occurrences |
| --- | --- | --- |
| `adopt` | AST/nested grammar field form | src/protocol.x:119, src/protocol.x:120, src/protocol.x:126 |
| `ambiguous` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/expressions.x:1862, src/macros.x:516 |
| `api-definition` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/parse.x:1946, src/parse.x:1950, src/generate.x:734 |
| `api-source` | AST/nested grammar field form | src/parse.x:2102, src/parse.x:2479, src/macros.x:2720 |
| `append` | AST/nested grammar field form | src/expressions.x:2130, src/transform.x:3559, src/emit.x:1047 |
| `args` | AST/nested grammar field form | src/parse.x:2573, src/parse.x:2578, src/expressions.x:1225 |
| `array` | AST/nested grammar field form | src/expressions.x:2193 |
| `association` | AST/nested grammar field form | src/expressions.x:809, src/expressions.x:2171, src/expressions.x:2173 |
| `at` | AST/nested grammar field form | src/ast.x:178, src/parse.x:2738, src/parse.x:2742 |
| `attributes` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/generate.x:629 |
| `automatic` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/literals.x:882, src/literals.x:900, src/literals.x:1002 |
| `bad-arg` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/macros.x:1023 |
| `bad-state` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/macros.x:138, src/macros.x:214, src/macros.x:731 |
| `begin` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/macros.x:107 |
| `bind` | AST/nested grammar field form | src/parse.x:222, src/parse.x:223, src/parse.x:460 |
| `binding` | AST/nested grammar field form | src/ast.x:40, src/ast.x:48, src/parse.x:485 |
| `bindings` | AST/nested grammar field form | src/generate.x:323, src/generate.x:324, src/generate.x:393 |
| `block` | AST/nested grammar field form | src/parse.x:1586, src/parse.x:2889, src/parse.x:2904 |
| `break` | AST/nested grammar field form | src/statements.x:215, src/transform.x:2479, src/emit.x:1140 |
| `c-assert` | AST/nested grammar field form | src/parse.x:576, src/parse.x:585, src/parse.x:2580 |
| `cache` | AST/nested grammar field form | src/literals.x:192, src/emit.x:1082, src/cache.x:69 |
| `call` | AST/nested grammar field form | src/expressions.x:1755, src/expressions.x:1759, src/expressions.x:2319 |
| `call-stack` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/macros.x:2433 |
| `capture` | AST/nested grammar field form | src/expressions.x:1030, src/literals.x:909, src/literals.x:957 |
| `capture-field` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/transform.x:1395, src/transform.x:1493 |
| `case` | AST/nested grammar field form | src/parse.x:2750, src/parse.x:2752, src/statements.x:209 |
| `cast` | AST/nested grammar field form | src/expressions.x:2240, src/expressions.x:4035, src/transform.x:279 |
| `catchcases` | AST/nested grammar field form | src/parse.x:2828, src/parse.x:2847, src/statements.x:480 |
| `char` | Type/storage leaf List | src/expressions.x:3440, src/type.x:294 |
| `code` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/statements.x:452, src/statements.x:501, src/literals.x:529 |
| `commas` | AST/nested grammar field form | src/expressions.x:2181, src/expressions.x:2625, src/emit.x:912 |
| `completed` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/generate.x:350 |
| `completion` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/generate.x:348, src/protocol.x:1983 |
| `composite` | AST/nested grammar field form | src/expressions.x:2233, src/cache.x:119, src/cache.x:163 |
| `conditional` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/generate.x:574, src/generate.x:593, src/generate.x:672 |
| `conflict` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/protocol.x:1607 |
| `cons` | AST/nested grammar field form | src/expressions.x:2118, src/literals.x:207, src/literals.x:214 |
| `continue` | AST/nested grammar field form | src/statements.x:221, src/transform.x:2480, src/emit.x:1141 |
| `decl` | AST/nested grammar field form | src/expressions.x:791, src/expressions.x:937, src/expressions.x:1689 |
| `declaration-bundle` | AST/nested grammar field form | src/parse.x:2405, src/parse.x:2501, src/parse.x:2514 |
| `declaration-default` | AST/nested grammar field form | src/parse.x:2539, src/parse.x:2551, src/generate.x:632 |
| `declaration-forward` | AST/nested grammar field form | src/parse.x:2533 |
| `declaration-function` | AST/nested grammar field form | src/parse.x:2544, src/parse.x:2712 |
| `declaration-pending` | AST/nested grammar field form | src/parse.x:2525 |
| `declaration-recipe` | AST/nested grammar field form | src/parse.x:2522 |
| `declare` | AST/nested grammar field form | src/parse.x:455, src/parse.x:1120, src/parse.x:1145 |
| `default` | AST/nested grammar field form | src/parse.x:2536, src/statements.x:240 |
| `default-forward` | AST/nested grammar field form | src/parse.x:2531 |
| `defer` | AST/nested grammar field form | src/parse.x:1489, src/parse.x:2758, src/parse.x:2760 |
| `defer-ownr` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/transform.x:3815, src/transform.x:4151, src/emit.x:147 |
| `definition-span` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/generate.x:717 |
| `delegate` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/expressions.x:480, src/expressions.x:1874 |
| `dim` | AST/nested grammar field form | src/expressions.x:3175, src/expressions.x:3185, src/expressions.x:3196 |
| `do` | AST/nested grammar field form | src/parse.x:2762, src/parse.x:2764, src/statements.x:174 |
| `dotinit` | AST/nested grammar field form | src/expressions.x:2041, src/expressions.x:2042, src/expressions.x:3409 |
| `double` | Type/storage leaf List | src/literals.x:1227, src/type.x:287, src/type.x:451 |
| `dstrasgn` | AST/nested grammar field form | src/expressions.x:2153, src/transform.x:1102, src/transform.x:3052 |
| `dstrdecl` | AST/nested grammar field form | src/parse.x:1323, src/parse.x:2639, src/parse.x:2654 |
| `emitted` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/expressions.x:1404, src/expressions.x:1405, src/expressions.x:1413 |
| `empty` | AST/nested grammar field form | src/statements.x:434 |
| `enum` | AST/nested grammar field form | src/parse.x:550, src/parse.x:2185, src/parse.x:2186 |
| `enum-value` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/parse.x:510 |
| `expr` | AST/nested grammar field form | src/ast.x:196, src/ast.x:262, src/ast.x:267 |
| `expression` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/macros.x:3187 |
| `extern` | Type/storage leaf List | src/generate.x:415, src/generate.x:427 |
| `fadapt` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/transform.x:511 |
| `falias` | AST/nested grammar field form | src/parse.x:2389, src/parse.x:2588, src/macros.x:2613 |
| `fgetter` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/transform.x:716 |
| `fhandle` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/transform.x:659 |
| `field` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/expressions.x:378, src/expressions.x:410, src/expressions.x:415 |
| `fields` | AST/nested grammar field form | src/parse.x:546 |
| `findirect` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/transform.x:645 |
| `first` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/parse.x:503 |
| `float` | Type/storage leaf List | src/type.x:284, src/type.x:449 |
| `fnmod` | AST/nested grammar field form | src/parse.x:979, src/parse.x:2226, src/parse.x:2241 |
| `for` | AST/nested grammar field form | src/parse.x:2803, src/parse.x:2817, src/statements.x:167 |
| `fpointer-factory` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/transform.x:796 |
| `func` | AST/nested grammar field form | src/type.x:862 |
| `func-arg` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/expressions.x:1733 |
| `function` | AST/nested grammar field form | src/parse.x:1628, src/parse.x:1945, src/parse.x:1965 |
| `generated` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/transform.x:4027, src/transform.x:4142, src/protocol.x:1115 |
| `generic` | AST/nested grammar field form | src/expressions.x:812, src/expressions.x:2167, src/emit.x:1088 |
| `gensym` | AST/nested grammar field form | src/parse.x:2154 |
| `getindex` | AST/nested grammar field form | src/expressions.x:2149, src/transform.x:4172 |
| `goto` | AST/nested grammar field form | src/statements.x:228, src/transform.x:2481, src/emit.x:1183 |
| `group` | AST/nested grammar field form | src/parse.x:2906, src/parse.x:2911, src/statements.x:95 |
| `guarded` | AST/nested grammar field form | src/parse.x:2877, src/parse.x:2878, src/statements.x:373 |
| `iadapt` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/expressions.x:3791 |
| `ident` | AST/nested grammar field form | src/expressions.x:1040, src/expressions.x:1057, src/expressions.x:1971 |
| `if` | AST/nested grammar field form | src/parse.x:2777, src/parse.x:2786, src/parse.x:2788 |
| `import` | AST/nested grammar field form | src/parse.x:1774, src/generate.x:661 |
| `imported` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/macros.x:1431, src/macros.x:1573 |
| `index` | AST/nested grammar field form | src/expressions.x:2296, src/type.x:67, src/type.x:111 |
| `indexinit` | AST/nested grammar field form | src/expressions.x:2043, src/expressions.x:2044, src/expressions.x:3418 |
| `indirect-adapter` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/transform.x:639 |
| `initcode` | AST/nested grammar field form | src/emit.x:1057, src/cache.x:265 |
| `initval` | AST/nested grammar field form | src/ast.x:245, src/expressions.x:2213, src/emit.x:834 |
| `input` | AST/nested grammar field form | src/expressions.x:2223, src/expressions.x:4002, src/emit.x:414 |
| `int` | Type/storage leaf List | src/parse.x:559, src/expressions.x:1269, src/expressions.x:1306 |
| `io-fail` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/macros.x:1022 |
| `is-symbol` | AST/nested grammar field form | src/expressions.x:2273 |
| `is-type` | AST/nested grammar field form | src/expressions.x:2251 |
| `kind` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/macros.x:3171, src/macros.x:3171 |
| `known` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/expressions.x:1368, src/macros.x:422, src/macros.x:2773 |
| `label` | AST/nested grammar field form | src/statements.x:514, src/transform.x:1719, src/transform.x:1811 |
| `lambda` | AST/nested grammar field form | src/expressions.x:1028, src/expressions.x:1035, src/expressions.x:2199 |
| `lambda-capture` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/literals.x:964 |
| `lambda-cell` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/transform.x:998, src/transform.x:1339 |
| `lambda-depth` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/expressions.x:1032, src/expressions.x:1045, src/expressions.x:1409 |
| `lambda-order` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/literals.x:936, src/literals.x:1008, src/literals.x:1009 |
| `lambda-param` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/expressions.x:1043, src/literals.x:863, src/literals.x:881 |
| `lambda-scope` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/literals.x:926, src/literals.x:933, src/literals.x:953 |
| `lambda-snapshot` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/expressions.x:1457, src/literals.x:994, src/literals.x:1006 |
| `linkage` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/protocol.x:1588, src/protocol.x:1596 |
| `literal` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/expressions.x:2069, src/literals.x:131, src/literals.x:132 |
| `local-macro` | AST/nested grammar field form | src/macros.x:3970, src/macros.x:4011 |
| `local-macro-capture` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/expressions.x:1049, src/expressions.x:1403, src/expressions.x:2744 |
| `localinit` | AST/nested grammar field form | src/transform.x:1836, src/transform.x:2048, src/transform.x:2462 |
| `locals` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/macros.x:3449 |
| `long` | Type/storage leaf List | src/type.x:287, src/type.x:299, src/type.x:300 |
| `macro-bind` | AST/nested grammar field form | src/macros.x:2928, src/macros.x:3192, src/macros.x:3629 |
| `macro-invoke` | AST/nested grammar field form | src/parse.x:2470, src/expressions.x:2076, src/macros.x:3029 |
| `macro-param` | AST/nested grammar field form | src/macros.x:2897, src/macros.x:3090 |
| `macro-slot` | AST/nested grammar field form | src/parse.x:2474, src/expressions.x:2082, src/macros.x:2509 |
| `macrodef` | AST/nested grammar field form | src/macros.x:3373 |
| `malformed` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/expressions.x:3723, src/macros.x:721, src/macros.x:722 |
| `managed-init` | AST/nested grammar field form | src/parse.x:1424, src/expressions.x:2059, src/transform.x:4125 |
| `map` | AST/nested grammar field form | src/expressions.x:2091 |
| `map-entry` | AST/nested grammar field form | src/expressions.x:2449, src/expressions.x:2450, src/literals.x:672 |
| `match` | AST/nested grammar field form | src/parse.x:2861, src/parse.x:2886, src/statements.x:429 |
| `matchcases` | AST/nested grammar field form | src/transform.x:2495, src/transform.x:2496, src/transform.x:3088 |
| `meta-call` | AST/nested grammar field form | src/expressions.x:2071 |
| `meta-cap` | AST/nested grammar field form | src/expressions.x:2075 |
| `meta-later` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/macros.x:2401, src/macros.x:2430 |
| `meta-protocol` | AST/nested grammar field form | src/macros.x:546, src/protocol.x:388, src/protocol.x:389 |
| `method` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/parse.x:141, src/parse.x:2334, src/parse.x:2335 |
| `module` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/generate.x:844 |
| `named-type` | AST/nested grammar field form | src/parse.x:1093, src/parse.x:1127, src/parse.x:2491 |
| `native` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/generate.x:895, src/generate.x:902, src/generate.x:958 |
| `native-meta` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/macros.x:545, src/macros.x:1684 |
| `next` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/parse.x:511 |
| `nil` | AST/nested grammar field form | src/literals.x:149, src/literals.x:159, src/literals.x:241 |
| `no-symbol` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/macros.x:2088 |
| `no-value` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/expressions.x:1727 |
| `ntype` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/emit.x:230 |
| `op` | AST/nested grammar field form | src/parse.x:224, src/parse.x:225, src/parse.x:486 |
| `optional-reference-param` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/parse.x:892, src/expressions.x:1444 |
| `owner` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/protocol.x:1148, src/protocol.x:1585, src/protocol.x:1670 |
| `package-import` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/parse.x:1773 |
| `package-macro` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/macros.x:1595, src/macros.x:2231 |
| `param` | AST/nested grammar field form | src/parse.x:882, src/parse.x:2232, src/parse.x:2664 |
| `params` | AST/nested grammar field form | src/parse.x:978, src/expressions.x:3798, src/literals.x:892 |
| `parens` | AST/nested grammar field form | src/parse.x:1427, src/expressions.x:742, src/expressions.x:1754 |
| `pending` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/generate.x:496, src/generate.x:515, src/generate.x:616 |
| `postfix` | AST/nested grammar field form | src/expressions.x:2409, src/transform.x:1101, src/transform.x:1888 |
| `preproc` | AST/nested grammar field form | src/ast.x:118, src/parse.x:2732, src/transform.x:3998 |
| `proto-file` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/protocol.x:166 |
| `protocol` | AST/nested grammar field form | src/protocol.x:275, src/protocol.x:397, src/protocol.x:528 |
| `protocol-conformance` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/protocol.x:872, src/protocol.x:1080, src/protocol.x:1125 |
| `provisional` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/macros.x:2801, src/macros.x:2811, src/macros.x:3654 |
| `quote` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/macros.x:2315, src/macros.x:2316 |
| `raise` | AST/nested grammar field form | src/parse.x:2820, src/parse.x:2825, src/literals.x:564 |
| `reference-param` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/parse.x:889, src/expressions.x:1443, src/literals.x:1005 |
| `replcomp` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/expressions.x:651, src/expressions.x:667 |
| `return` | AST/nested grammar field form | src/parse.x:2744, src/parse.x:2746, src/statements.x:187 |
| `segexp` | AST/nested grammar field form | src/literals.x:792, src/literals.x:809 |
| `segments` | AST/nested grammar field form | src/expressions.x:2098, src/transform.x:3585 |
| `segvar` | AST/nested grammar field form | src/literals.x:802 |
| `self` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/parse.x:135, src/parse.x:184, src/parse.x:192 |
| `seq` | AST/nested grammar field form | src/parse.x:475, src/parse.x:617, src/parse.x:1417 |
| `setindex` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/transform.x:2868, src/transform.x:4188 |
| `short` | Type/storage leaf List | src/type.x:298 |
| `signed` | Type/storage leaf List | src/expressions.x:3440, src/type.x:293 |
| `size-limit` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/macros.x:1024 |
| `sizeof` | AST/nested grammar field form | src/expressions.x:2161, src/expressions.x:2164 |
| `slice` | AST/nested grammar field form | src/expressions.x:2139, src/expressions.x:2144, src/transform.x:4209 |
| `source` | AST/nested grammar field form | src/macros.x:970, src/macros.x:3185, src/macros.x:3473 |
| `source-spelling` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/macros.x:3941, src/macros.x:4075, src/generate.x:708 |
| `sourceinit` | AST/nested grammar field form | src/emit.x:1060, src/cache.x:468, src/cache.x:629 |
| `space` | emission/presentation output | src/generate.x:1150 |
| `splice` | AST/nested grammar field form | src/expressions.x:2190, src/literals.x:38, src/literals.x:43 |
| `src` | AST/nested grammar field form | src/parse.x:2476, src/macros.x:3784, src/macros.x:3794 |
| `src-at` | emission/presentation output | src/emit.x:1030 |
| `static` | Type/storage leaf List | src/transform.x:2392, src/macros.x:1653, src/generate.x:258 |
| `step` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/expressions.x:454 |
| `stmnt` | AST/nested grammar field form | src/ast.x:203, src/parse.x:1584, src/parse.x:2755 |
| `string` | AST/nested grammar field form | src/expressions.x:244, src/expressions.x:249, src/expressions.x:1981 |
| `struct` | AST/nested grammar field form | src/expressions.x:3192, src/macros.x:3294, src/macros.x:3830 |
| `switch` | AST/nested grammar field form | src/parse.x:2772, src/parse.x:2774, src/statements.x:234 |
| `syntax-recipe` | AST/nested grammar field form | src/parse.x:2518 |
| `tadapt` | AST/nested grammar field form | src/expressions.x:2420, src/transform.x:255 |
| `tag` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/macros.x:2798, src/macros.x:2810 |
| `tag-local` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/macros.x:2776, src/macros.x:3659, src/macros.x:3680 |
| `target` | AST/nested grammar field form | src/macros.x:2496, src/macros.x:2888, src/macros.x:3474 |
| `targets` | AST/nested grammar field form | src/expressions.x:2542, src/expressions.x:2552 |
| `tpl-call` | AST/nested grammar field form | src/expressions.x:2070 |
| `try` | AST/nested grammar field form | src/parse.x:2849, src/parse.x:2857, src/statements.x:490 |
| `type` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/parse.x:164, src/expressions.x:1420, src/literals.x:883 |
| `type-tag` | AST/nested grammar field form | src/expressions.x:2249 |
| `typedef` | AST/nested grammar field form | src/parse.x:1092, src/parse.x:1122, src/parse.x:1138 |
| `unit` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/generate.x:840 |
| `unknown` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/parse.x:553, src/parse.x:1342 |
| `unsigned` | Type/storage leaf List | src/expressions.x:3441, src/type.x:292, src/type.x:298 |
| `va-arg` | AST/nested grammar field form | src/expressions.x:793, src/expressions.x:2177, src/emit.x:1103 |
| `value` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/parse.x:508 |
| `var` | AST/nested grammar field form | src/literals.x:92, src/literals.x:135, src/literals.x:158 |
| `varray` | AST/nested grammar field form | src/transform.x:3535, src/emit.x:1033 |
| `vmap` | AST/nested grammar field form | src/transform.x:3551, src/emit.x:1035 |
| `void` | Type/storage leaf List | src/parse.x:1583, src/expressions.x:912, src/expressions.x:2261 |
| `volatile` | Type/storage leaf List | src/transform.x:2397 |
| `vpair` | AST/nested grammar field form | src/transform.x:3547, src/emit.x:1037 |
| `while` | AST/nested grammar field form | src/parse.x:2767, src/parse.x:2769, src/statements.x:141 |
| `with` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/expressions.x:2750, src/statements.x:604, src/statements.x:612 |
| `with-name` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/statements.x:535, src/statements.x:607, src/statements.x:608 |
| `x2c` | semantic registry, compiler result, dump or diagnostic metadata; not a program AST production | src/parse.x:556 |

215 detected head spellings. Dynamic `$tag` heads, String heads, empty
Lists and operator symbolic heads are outside this regex and accounted for
separately by owner grammar; head classification is bounded source review, not
mechanically complete validation. Regions and helper wire metadata are excluded.
