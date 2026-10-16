/*  error-private.x -- private layouts for Error transfer state
*/

#pragma once

macro Unit $error.private.types() {
  static typedef struct $x2c_ident("ErrorRegion") {
    Scope values;
    Pool pool;
  } $x2c_ident("ErrorRegion");

  static typedef struct $x2c_ident("ErrorRecord") {
    struct ErrorRegion region;
    List entry;
  } $x2c_ident("ErrorRecord");

  static struct $x2c_ident("ErrorHandler") {
    struct ErrorHandler *prev;
    struct ErrorHandler *running;
    struct ErrorRegion view;
    ErrorHandlerFn fn;
    Var data;
    int watermark;
    ErrorCatchSite *site;
    Block plans;
    void *target;
    int selected;
    Block capture_values;
    Block retained;
    int detached;
  };
}
