#pragma once
#include <stdio.h>

macro Decorator $loud.switch(Stmt $body, Expr $subject) {
  printf("hooked\n");
  switch ($subject) $body
}

static hook switch $loud.switch;

/* Hooked here: the hook is visible in its own file. */
int inside(int n) {
  switch (n) { case 1: return 1; }
  return 0;
}
