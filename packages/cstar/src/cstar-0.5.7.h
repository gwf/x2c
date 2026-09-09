/*  cstar-0.5.7.h -- the pinned C* 0.5.7 surface, declared in plain C.

    x2c parses included C headers itself, and the upstream headers reach a
    C++ `constexpr` region in `hol_prover_client.h` that it cannot parse.
    This shim therefore restates the declarations the package uses, copied
    from the pinned release's `symexec.h`, `proof_kernel.h`,
    `proof_runtime.h`, and `hol_prover_client.h`, and from the MIT proof
    sources under `share/cstar_examples/`.

    One upstream name is renamed: `range` collides with an x2c name, so the
    location record is `cst_range`.  Every other spelling, order, and
    qualifier matches upstream.
*/
#ifndef CSTAR_0_5_7_H
#define CSTAR_0_5_7_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* proof_kernel.h / hol_prover_client.h */
typedef struct hol_term { void *inner; } term;
typedef struct hol_theorem { void *inner; } thm;
typedef struct hol_type { void *inner; } type;
typedef struct hol_conversion { void *inner; } conv;
typedef term *term_list;
typedef thm *thm_list;
typedef char *cstr;
typedef const char *const_cstr;

/* symexec.h */
typedef void *partial_program;
typedef void *expression;
typedef void *ctype;
typedef struct { int line; int column; } location;
typedef struct {
  location start;
  location end;
  const char *filename;
} cst_range;

enum bin_op {
  BINOP_MULTIPLY, BINOP_DIVIDE, BINOP_MODULO, BINOP_ADD, BINOP_SUBTRACT,
  BINOP_LEFT_SHIFT, BINOP_RIGHT_SHIFT, BINOP_BITWISE_AND, BINOP_BITWISE_XOR,
  BINOP_BITWISE_OR, BINOP_LESS, BINOP_GREATER, BINOP_LESS_EQUAL,
  BINOP_GREATER_EQUAL, BINOP_EQUAL, BINOP_NOT_EQUAL, BINOP_LOGICAL_AND,
  BINOP_LOGICAL_OR
};

enum assign_op {
  ASSIGNOP_ASSIGN, ASSIGNOP_MUL_ASSIGN, ASSIGNOP_DIV_ASSIGN,
  ASSIGNOP_MOD_ASSIGN, ASSIGNOP_ADD_ASSIGN, ASSIGNOP_SUB_ASSIGN,
  ASSIGNOP_LEFT_SHIFT_ASSIGN, ASSIGNOP_RIGHT_SHIFT_ASSIGN,
  ASSIGNOP_AND_ASSIGN, ASSIGNOP_XOR_ASSIGN, ASSIGNOP_OR_ASSIGN
};

enum unary_op {
  UNOP_ADDRESS, UNOP_DEREF, UNOP_PLUS, UNOP_MINUS, UNOP_BITWISE_NOT,
  UNOP_LOGICAL_NOT
};

enum incdec_op {
  INCDEC_INCREMENT_PRE, INCDEC_DECREMENT_PRE, INCDEC_INCREMENT_POST,
  INCDEC_DECREMENT_POST
};

/* Session, feeding, and reporting. */
void cst_set_debug(bool debug);
void cst_main_entry(bool restore_server_on_exit);
void cst_main_exit(void);
void cst_feed_program_segment_with_loc(partial_program prog, cst_range ran);
void cst_exit_on_error(void);
void cst_exit_on_error_with_loc(cst_range ran);
const char *cst_print_vc(void);
term cst_get_symbolic_state(void);
void cst_set_symbolic_state(thm th);

/* Types. */
ctype make_void_type(void);
ctype make_char_type(void);
ctype make_int_type(void);
ctype make_unsigned_char_type(void);
ctype make_unsigned_int_type(void);
ctype make_pointer_type(ctype pointee);
ctype make_function_type(ctype ret, ctype params[], int length);

/* Expressions. */
expression make_var_expr(const char *name, ctype type);
expression make_unary_expr(int op, expression expr, ctype result_type);
expression make_binary_expr(int op, expression left, expression right,
                            ctype result_type);
expression make_const_expr(int64_t constant, ctype type);
expression make_call_expr(expression func, expression args[], int length,
                          ctype result_type);
expression make_deref_expr(expression expr, ctype result_type);
expression make_addrof_expr(expression expr, ctype result_type);
expression make_cast_expr(expression expr, ctype type);
expression make_index_expr(expression array, expression index,
                           ctype result_type);

/* Statements and declarations. */
partial_program make_function_decl(const char *name, ctype ret, ctype params[],
                                   const char *names[], int length);
partial_program make_function_start(const char *name, ctype ret,
                                    ctype params[], const char *names[],
                                    int length);
partial_program make_function_end(void);
partial_program make_var_def(const char *name, ctype type);
partial_program make_var_def_init(const char *name, ctype type,
                                  expression init);
partial_program make_assign(expression left, expression right, int op);
partial_program make_while_condition(expression expr);
partial_program make_if_condition(expression expr);
partial_program make_else(void);
partial_program make_return_expr(expression expr);
partial_program make_return(void);
partial_program make_block_begin(void);
partial_program make_block_end(void);
partial_program make_compute(expression expr);
partial_program make_inc_dec(expression expr, int op);

/* Contracts and annotations. */
partial_program make_cst_param(type types[], int num_types, term args[],
                               int length);
partial_program make_cst_require(term arg);
partial_program make_cst_ensure(term arg);
partial_program make_cst_invariant(term arg, int partial);
partial_program make_cst_assert(term arg, int partial);

/* HOL client operations the proof surface and helpers use. */
term parse_term(const_cstr s);
type parse_type(const_cstr s);
cstr string_of_term(term tm);
cstr string_of_thm(thm th);
thm arith_rule(term tm);
thm int_arith_rule(term tm);
thm sym_rule(thm th);
conv rewrite_conv(thm_list ths);
thm apply_conversion(conv c, term tm);
term_list term_list_n(size_t size, ...);
thm_list thm_list_n(size_t size, ...);

/* proof/proof_sl.h */
thm eq2ent(thm eq);

/* userlib/qcp/veriftime.h */
term Hconj(term_list hconjs);
term ExHconj(term_list exs, term_list hconjs);
term bool_calls_for_qcp(term raw_assertion);
term return_int(term value);
term get_symbolic_state(void);
void set_symbolic_state(thm symst_ent);

/* userlib/operational/operational.h */
void apply_hconv_st(thm theorem);
void add_fact_st(thm fact_theorem);
void rewrite_st(thm_list rules);

/* tutorial/common.h */
term mk_simple_invariant(term inv);

/* array/lib/array.h -- the concrete int-list and array vocabulary. Install
   it once, after every pure theory is loaded. */
int install_array_qcp_interface(void);

/* proof/x2c_array_helpers.h -- this package's own C* proof library, the
   reusable steps of a left-to-right array fill. `elem` selects `Tint` or
   `Tchar`; every list-level step is shared between them. */
void x2c_fill_entry(term array_at, term length_addr, term length_var,
                    term xs, term value);
void x2c_fill_before_store(term elem, term p_pre, term index_var,
                           term length_var, term xs, term value);
void x2c_fill_after_store(term elem, term p_pre, term index_var,
                          term length_var, term xs, term value);
void x2c_fill_index_bound(term index_var, term length_var, term xs,
                          term value);
void x2c_fill_advance(term index_var, term length_var, term xs, term value);
void x2c_fill_exit(term index_var, term length_var, term xs, term value);

/* Library initializers emitted by `cstarc --cl` for the linked proof
   objects, called in this order before any feeding. */
void _cst_proof_proof_user_init(void);
void _cst_proof_proof_sl_init(void);
void _cst_proof_proof_backward_init(void);
void _cst_proof_proof_backward_sl_init(void);
void _cst_proof_proof_symexec_init(void);
void _cst_userlib_qcp_veriftime_init(void);
void _cst_tutorial_common_init(void);
void _cst_userlib_operational_operational_init(void);
void _cst_array_lib_list_init(void);
void _cst_array_lib_array_core_init(void);
void _cst_array_lib_index_init(void);
void _cst_array_lib_array_init(void);
void _cst_x2c_array_helpers_init(void);

#endif
