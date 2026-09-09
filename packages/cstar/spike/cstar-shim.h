/* cstar-shim.h -- the pinned C* 0.5.7 surface used by the milestone 1
   probe, declared in plain C so x2c parses it directly. */
#ifndef CSTAR_SHIM_H
#define CSTAR_SHIM_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct hol_term { void *inner; } term;
typedef struct hol_theorem { void *inner; } thm;
typedef term *term_list;
typedef void *partial_program;
typedef void *expression;
typedef void *ctype;
typedef struct { int line; int column; } location;
typedef struct {
  location start;
  location end;
  const char *filename;
} cst_range;

enum bin_op { BINOP_MULTIPLY, BINOP_DIVIDE, BINOP_MODULO, BINOP_ADD,
  BINOP_SUBTRACT, BINOP_LEFT_SHIFT, BINOP_RIGHT_SHIFT, BINOP_BITWISE_AND,
  BINOP_BITWISE_XOR, BINOP_BITWISE_OR, BINOP_LESS, BINOP_GREATER,
  BINOP_LESS_EQUAL, BINOP_GREATER_EQUAL, BINOP_EQUAL, BINOP_NOT_EQUAL,
  BINOP_LOGICAL_AND, BINOP_LOGICAL_OR };
enum unary_op { UNOP_ADDRESS, UNOP_DEREF, UNOP_PLUS, UNOP_MINUS,
  UNOP_BITWISE_NOT, UNOP_LOGICAL_NOT };

term parse_term(const char *s);
thm int_arith_rule(term tm);
char *string_of_thm(thm th);
term_list term_list_n(size_t size, ...);

void cst_set_debug(bool debug);
void cst_main_entry(bool restore_server_on_exit);
void cst_main_exit(void);
void cst_feed_program_segment_with_loc(partial_program prog, cst_range ran);
void cst_exit_on_error(void);
const char *cst_print_vc(void);

ctype make_int_type(void);
expression make_var_expr(const char *name, ctype type);
expression make_unary_expr(int op, expression expr, ctype result_type);
expression make_binary_expr(int op, expression left, expression right,
                            ctype result_type);
expression make_const_expr(int64_t constant, ctype type);
partial_program make_function_start(const char *name, ctype ret,
                                    ctype params[], const char *names[],
                                    int length);
partial_program make_function_end(void);
partial_program make_var_def_init(const char *name, ctype type,
                                  expression init);
partial_program make_if_condition(expression expr);
partial_program make_else(void);
partial_program make_return_expr(expression expr);
partial_program make_block_end(void);
partial_program make_block_begin(void);
partial_program make_cst_require(term arg);
partial_program make_cst_ensure(term arg);
#endif
