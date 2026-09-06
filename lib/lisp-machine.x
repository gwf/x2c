/*  lisp-machine.x -- compile-time Lisp wordcode execution

    Copyright (c) 2026 Gary William Flake.

    Runs immutable programs prepared by the Lisp AUTO path. Each invocation
    has its own frames, operand values, and locals, and borrows its program,
    Lisp context, and optional statistics sink. Instructions call lisp.x for
    environment, call, quasiquote, and return behavior.
*/

#pragma once

#include "machine.x"

#pragma private

#include <assert.h>
#include <string.h>
#include "exception.x"
#include "lisp.x"

/* Initialize fresh caller-owned or session-owned Lisp machine storage. */
void LispMachine.open(LispMachine m) {
  memset(&m.program, 0, sizeof(MachineView));
  m.pc = 0;
  m.status = <idle>;
  m.running = 0;
  m.value = void;
  m.error = void;
  m.fp = 0;
  m.value_count = 0;
  m.local_count = 0;
  m.operand_base = 0;
  m.local_base = 0;
  m.lisp_context = NULL;
  m.stats = NULL;
}

static void LispMachine._error_value(LispMachine m, Var error) {
  m.fp = 0;
  for (int i = 0; i < m.value_count; i++) m.values[i] = (Var) { .u64 = 0 };
  for (int i = 0; i < m.local_count; i++) m.locals[i] = (Var) { .u64 = 0 };
  m.value_count = 0;
  m.local_count = 0;
  m.operand_base = 0;
  m.local_base = 0;
  m.error = error;
  m.status = <error>;
  m.running = 0;
}

static void LispMachine._error(LispMachine m, Symbol error) {
  m._error_value(error);
}

static int LispMachine._push_frame(LispMachine m) {
  if (m.fp + 1 >= MACHINE_FRAME_MAX) {
    m._error(<frame-max>);
    return 0;
  }
  LispFrame *frame = &m.frames[m.fp++];
  frame.return_pc = m.pc;
  frame.caller_operand_base = m.operand_base;
  frame.caller_local_base = m.local_base;
  frame.caller_value_count = m.value_count;
  frame.caller_local_count = m.local_count;
  frame.caller_value = m.value;
  frame.caller_program = m.program;
  if (m.stats) {
    m.stats.calls++;
    if (m.fp + 1 > m.stats.max_frames) m.stats.max_frames = m.fp + 1;
  }
  return 1;
}

static void LispMachine._pop_frame(LispMachine m) {
  assert(m.fp > 0);
  m.fp--;
  LispFrame *frame = &m.frames[m.fp];
  m.pc = frame.return_pc;
  m.program = frame.caller_program;
  m.operand_base = frame.caller_operand_base;
  m.local_base = frame.caller_local_base;
  m.value_count = frame.caller_value_count;
  m.local_count = frame.caller_local_count;
  m.value = frame.caller_value;
}
/* The decoder runs control flow, frames, and the operand and local stacks,
   and calls native code through Func.apply. Callee-program resolution and
   late global lookup go to lisp.x through the declarations above. */

static int LispMachine._push_value(LispMachine m, Var value) {
  if (m.value_count >= MACHINE_VALUE_MAX) {
    m._error(<value-max>);
    return 0;
  }
  m.values[m.value_count++] = value;
  return 1;
}

static void LispMachine._load(LispMachine m, const MachineWord *w) {
  const Var *consts = m.program.consts;
  Var value;
  if (w.op == MW_LLOCAL) {
    int slot = m.local_base + w.a;
    if (w.a < 0 || slot >= m.local_count) {
      m._error(<bad-local>);
      return;
    }
    value = m.locals[slot];
    if (m.stats) m.stats.local_loads++;
  }
  else if (w.op == MW_LGLOBAL) {
    Var name = consts[w.a];
    if (!Lisp.resolve(m.lisp_context, name, &value)) {
      Symbol code = <unbound>;
      m._error_value(%($code (name $name)));
      return;
    }
    if (m.stats) m.stats.global_loads++;
  }
  else {
    value = consts[w.a];
    if (m.stats && w.op == MW_LCAPTURE) m.stats.capture_loads++;
  }
  m._push_value(value);
}

/* A prepared lambda stays in the decoder when all three bounded stacks have
   room. Otherwise it crosses to the recursive evaluator; native Func values
   cross through Func.apply. A crossing can raise before stack cleanup. */
static void LispMachine._call(LispMachine m, int argc) {
  int callable_at = m.value_count - argc - 1;
  if (argc < 0 || callable_at < m.operand_base) {
    m._error(<call-stack>);
    return;
  }
  Var callable = m.values[callable_at];
  MachineView view;
  int params = 0;
  Var body = void;
  int prepared = Lisp.program(callable, &view, &params, &body);
  if (prepared) {
    if (argc != params) {
      Symbol code = <bad-arity>;
      m._error_value(
        %($code (expected $params) (actual $argc) (value $body)));
      return;
    }
    int old_locals = m.local_count;
    int room = old_locals + argc <= MACHINE_LOCAL_MAX &&
               m.fp + 1 < MACHINE_FRAME_MAX &&
               callable_at + MACHINE_CALL_RESERVE <= MACHINE_VALUE_MAX;
    if (room && m._push_frame()) {
      m.frames[m.fp - 1].caller_value_count = callable_at;
      for (int i = 0; i < argc; i++)
        m.locals[old_locals + i] = m.values[callable_at + 1 + i];
      for (int i = callable_at; i < m.value_count; i++)
        m.values[i] = (Var) { .u64 = 0 };
      m.value_count = callable_at;
      m.operand_base = callable_at;
      m.local_base = old_locals;
      m.local_count = old_locals + argc;
      Lisp.enter(m.lisp_context, callable, m.locals + old_locals, argc);
      m.program = view;
      m.pc = view.root;
      if (m.stats) m.stats.prepared_calls++;
      return;
    }
  }
  else if (callable is not <func>) {
    Symbol code = <not-call>;
    m._error_value(%($code (value $callable)));
    return;
  }
  /* A full frame or local stack does not determine the callee, so it
     crosses to the evaluator the same way MW_LPRECALL passes a macro or
     an unprepared lambda. The evaluator recurses in C and re-enters a
     nested machine below. Recursion deeper than MACHINE_FRAME_MAX works
     this way. */
  Var result;
  if (prepared)
    result = Lisp.apply_values(
      m.lisp_context, callable, m.values + callable_at + 1, argc);
  else {
    FuncArg arguments[MACHINE_VALUE_MAX];
    for (int i = 0; i < argc; i++)
      arguments[i] = FuncArg.value(m.values[callable_at + 1 + i]);
    result = ((Func) callable.pointer()).apply(argc, arguments);
    if (m.stats) m.stats.native_calls++;
  }
  for (int i = callable_at; i < m.value_count; i++)
    m.values[i] = (Var) { .u64 = 0 };
  m.value_count = callable_at;
  m._push_value(result);
}

/* A self-call in tail position reuses the frame it is standing in. The
   caller's locals and operands are dead, and its environment frame is
   replaced in place. Frames, locals, and values stay flat, so the loop runs
   in constant space and never reaches the crossing in `_call`. The lowering
   emits this only when the callee is the lambda being compiled. The
   environment frame it replaces holds the same parameters, and free-name
   resolution is unchanged. */
static void LispMachine._tail_call(LispMachine m, int argc) {
  int callable_at = m.value_count - argc - 1;
  if (argc < 0 || callable_at < m.operand_base) {
    m._error(<call-stack>);
    return;
  }
  Var callable = m.values[callable_at];
  MachineView view;
  int params = 0;
  Var body = void;
  if (!Lisp.program(callable, &view, &params, &body) ||
      view.code != m.program.code || argc != params) {
    m._call(argc);
    return;
  }
  for (int i = 0; i < argc; i++)
    m.locals[m.local_base + i] = m.values[callable_at + 1 + i];
  for (int i = m.operand_base; i < m.value_count; i++)
    m.values[i] = (Var) { .u64 = 0 };
  m.value_count = m.operand_base;
  m.local_count = m.local_base + argc;
  Lisp.retarget(m.lisp_context, callable, m.locals + m.local_base, argc);
  m.pc = m.program.root;
  if (m.stats) m.stats.prepared_calls++;
}

static void LispMachine._return(LispMachine m) {
  if (m.value_count <= m.operand_base) {
    m._error(<no-result>);
    return;
  }
  Var result = m.values[m.value_count - 1];
  for (int i = m.local_base; i < m.local_count; i++)
    m.locals[i] = (Var) { .u64 = 0 };
  if (m.stats) m.stats.lisp_returns++;
  if (!m.fp) {
    for (int i = 0; i < m.value_count; i++) m.values[i] = (Var) { .u64 = 0 };
    m.value_count = 0;
    m.local_count = 0;
    m.operand_base = 0;
    m.local_base = 0;
    m.value = result;
    m.status = <ok>;
    m.running = 0;
    return;
  }
  Lisp.leave(m.lisp_context);
  m._pop_frame();
  m._push_value(result);
}

/* Begin one prepared Lisp body in opened storage, borrowing the program and
   Lisp context and copying shallow argument values into root-frame locals.
   The caller has already evaluated those arguments. A dirty machine records
   <not-idle> and stops.

   Raises: `<bad-arity>` when argc is outside the local-frame domain. The
   machine stays clean and idle. */
void LispMachine.begin(
  LispMachine m, MachineView program, void *lisp_context, const Var *args,
  int argc) {
  if (m.running || m.fp || m.value_count || m.local_count) {
    m._error(<not-idle>);
    return;
  }
  if (argc < 0 || argc > MACHINE_LOCAL_MAX)
    raise %(bad-arity (owner "LispMachine.begin") (actual $argc));
  m.program = program;
  m.pc = program.root;
  m.status = <running>;
  m.running = 1;
  m.value = void;
  m.error = void;
  m.lisp_context = lisp_context;
  for (int i = 0; i < argc; i++) m.locals[i] = args[i];
  m.local_count = argc;
  m.local_base = 0;
  m.value_count = 0;
  m.operand_base = 0;
  if (m.stats) {
    m.stats.calls++;
    if (m.stats.max_frames < 1) m.stats.max_frames = 1;
  }
}

/* Execute one Lisp word and report whether another word remains. Fetch
   advances pc before dispatch, so calls save the following word and branches
   replace it. Machine failures store an error and clear active stacks. Lisp
   callbacks and native calls can raise out while the machine remains marked
   running. */
int LispMachine.step(LispMachine m) {
  if (!m.running) return 0;
  MachineView *p = &m.program;
  const MachineWord *w = &p.code[m.pc++];
  switch (w.op) {
    case MW_JUMP: m.pc = w.target;
      break;

    case MW_LCONST:
    case MW_LLOCAL:
    case MW_LCAPTURE:
    case MW_LGLOBAL:
      m._load(w);
      break;

    case MW_LBR_NIL: {
      if (m.value_count <= m.operand_base) {
        m._error(<no-operand>);
        break;
      }
      Var condition = m.values[m.value_count - 1];
      if (m.stats) m.stats.nil_edges++;
      if (condition.is_nil()) {
        m.values[--m.value_count] = (Var) { .u64 = 0 };
        if (m.stats) m.stats.nil_taken++;
        m.pc = w.target;
      }
      break;
    }

    case MW_LPRECALL: {
      if (m.value_count <= m.operand_base) {
        m._error(<no-operand>);
        break;
      }
      Var callable = m.values[m.value_count - 1], result = void;
      if (!Lisp.precall(m.lisp_context, callable, p.consts[w.a], &result))
        break;
      m.values[m.value_count - 1] = result;
      m.pc = w.target;
      break;
    }

    case MW_LCALL: m._call(w.b);
      break;

    case MW_LTAILCALL: m._tail_call(w.b);
      break;

    case MW_LQQ_WRAP: {
      if (m.value_count <= m.operand_base) {
        m._error(<no-operand>);
        break;
      }
      Var value = m.values[m.value_count - 1];
      m.values[m.value_count - 1] = cons(value, NULL);
      break;
    }

    case MW_LQQ_APPEND: {
      if (m.value_count - m.operand_base < 2) {
        m._error(<no-operand>);
        break;
      }
      Var left = m.values[m.value_count - 2];
      Var right = m.values[m.value_count - 1];
      if (left is not <list>) {
        Symbol code = <bad-types>, actual = left.kind();
        m._error_value(%($code (actual $actual)));
        break;
      }
      if (right is not <list>) {
        m._error(<quasi-tail>);
        break;
      }
      List a = left, b = right, result = a.append(b);
      m.values[m.value_count - 2] = result;
      m.values[--m.value_count] = (Var) { .u64 = 0 };
      break;
    }

    case MW_LDROP:
      if (m.value_count <= m.operand_base) {
        m._error(<no-operand>);
        break;
      }
      m.values[--m.value_count] = (Var) { .u64 = 0 };
      break;

    case MW_LRETURN: m._return();
      break;
    default: m._error(<bad-word>);
  }
  return m.running;
}

/* Execute Lisp words until a value or stored machine error stops the run.
   Callback error transfers leave cleanup to the Lisp session's unwind path. */
void LispMachine.run(LispMachine m) {
  while (m.step()) {}
}

/* Return a stopped invocation to idle and clear all borrowed execution state.
   The optional stats pointer remains installed for session reuse.

   Raises: `<bad-state>` when execution is still running. */
void LispMachine.finish(LispMachine m) {
  if (m.running) raise %(bad-state (owner "LispMachine.finish"));

  for (int i = 0; i < m.value_count; i++) m.values[i] = (Var) { .u64 = 0 };
  for (int i = 0; i < m.local_count; i++) m.locals[i] = (Var) { .u64 = 0 };
  m.value_count = 0;
  m.local_count = 0;
  m.operand_base = 0;
  m.local_base = 0;
  m.lisp_context = NULL;
  m.fp = 0;
  m.pc = 0;
  m.value = void;
  m.error = void;
  m.status = <idle>;
  memset(&m.program, 0, sizeof(MachineView));
  m.running = 0;
}

/* Report whether the observable Lisp invocation state is idle and cleared.
   The optional stats pointer does not affect the answer. */
int LispMachine.clean(LispMachine m) {
  if (m.running || m.program.code || m.fp || m.value_count ||
      m.local_count || m.operand_base || m.local_base || m.lisp_context)
    return 0;
  return m.status == <idle> && m.error is void;
}
