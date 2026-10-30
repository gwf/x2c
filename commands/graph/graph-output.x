#pragma once

/*  graph-output.x -- command help display */

macro Stmt $output.graph.usage(Expr $out, Expr $program) {
  $out.printf(
    "usage: %s snapshot OUTPUT [BUILD_OPTIONS] [FILE...]\n", $program);
  $out.printf("       %s status SNAPSHOT\n", $program);
  $out.printf("       %s query SNAPSHOT QUERY_FILE\n", $program);
  $out.printf("       %s serve SNAPSHOT\n", $program);
  $out.printf("       %s diff BEFORE AFTER\n", $program);
  $out.printf("       %s graph|digest [-I DIR] FILE...\n", $program);
  $out.printf("       %s clones [--min-size N] [-I DIR] FILE...\n", $program);
  $out.printf(
    "       %s datasets OUTPUT [-I DIR] SRC_FILE... -- LIB_FILE... "
    "[-- COMMAND_FILE...]\n",
    $program);
  $out.printf("       %s architecture [-I DIR] FILE...\n", $program);
  $out.printf("       %s structure UNIT [-I DIR] FILE...\n", $program);
  $out.printf("       %s between LEFT RIGHT [-I DIR] FILE...\n", $program);
  $out.printf("       %s focus NAME [-I DIR] FILE...\n", $program);
  $out.printf("       %s field TYPE FIELD [-I DIR] FILE...\n", $program);
  $out.printf("       %s field-sites TYPE FIELD [-I DIR] FILE...\n", $program);
  $out.printf("       %s sites NAME [-I DIR] FILE...\n", $program);
  $out.printf("       %s walks [-I DIR] FILE...\n", $program);
  $out.printf("       %s tail-calls [-I DIR] FILE...\n", $program);
  $out.printf(
    "       %s loop-allocations [--all] [-I DIR] FILE...\n", $program);
  $out.printf("       %s lifetime-escapes [-I DIR] FILE...\n", $program);
  $out.printf(
    "       %s certify --root NAME [--root NAME ...] "
    "[--contracts FILE] [-I DIR] FILE...\n", $program
  );
  $out.printf(
    "       %s allocation-returns NAME [-I DIR] FILE...\n", $program
  );
  $out.printf(
    "       %s flows PRODUCER CONSUMER [-I DIR] FILE...\n", $program);
  $out.printf(
    "       %s compare LEFT RIGHT TARGET... -- [-I DIR] FILE...\n",
    $program);
}
