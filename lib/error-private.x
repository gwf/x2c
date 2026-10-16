/*  error-private.x -- private layouts for Error transfer state
*/

#pragma once

macro Field $error.private.region.fields() {
    Scope values;
    Pool pool;
}

macro Field $error.private.record.fields() {
    struct ErrorRegion region;
    List entry;
}

macro Field $error.private.handler.fields() {
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
}

macro Unit $error.private.types() {
  static typedef struct $x2c_ident("ErrorRegion") {
    $error.private.region.fields();
  } $x2c_ident("ErrorRegion");

  static typedef struct $x2c_ident("ErrorRecord") {
    $error.private.record.fields();
  } $x2c_ident("ErrorRecord");

  static struct $x2c_ident("ErrorHandler") {
    $error.private.handler.fields();
  };
}
