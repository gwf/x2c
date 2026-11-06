#!/usr/bin/env -S x2c script
/* script.x -- a script unit, whose generated entry points lie past its
   tokens */

static void fail(String message) {
  Stderr.printf("%s\n", message);
}

if (args.len() > 1) fail("no arguments");
return 0;
