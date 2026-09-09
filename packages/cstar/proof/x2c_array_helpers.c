#include "x2c_array_helpers.h"

/* The loop assumptions imply the source-list bound in both the integer and
   natural-number index domains.  Keep this bridge in one place: opening the
   cell and advancing the functional cursor need exactly the same fact. */
PROOF static thm x2c_int_index_bound(
    const term index_var, const term length_var, const term xs) {
  return rewrite_rule(
      THM_LIST(assume_rule(
          `${length_var:int} = &(LENGTH ${xs:(int)list})`)),
      assume_rule(`${index_var:int} < ${length_var:int}`));
}

PROOF static thm x2c_num_index_bound(
    const term index_var, const term length_var, const term xs) {
  return num_of_int_lt_length_rule(
      index_var, xs,
      assume_rule(`0i <= ${index_var:int}`),
      x2c_int_index_bound(index_var, length_var, xs));
}

PROOF void x2c_fill_entry(
    const term array_at, const term length_addr,
    const term length_var, const term xs, const term value) {
  add_data_at_range_st(length_addr, `Tint`, length_var);
  thm n_nonnegative = int_eq_length_nonnegative_rule(
      length_var, xs,
      assume_rule(
          `${length_var:int} = &(LENGTH ${xs:(int)list})`));
  add_fact_st(conj_rule(int_arith_rule(`0i <= 0i`), n_nonnegative));

  thm initial_shape = apply_conversion(rewrite_conv(THM_LIST(
      get_theorem_by_name("NUM_OF_INT_OF_NUM"),
      get_theorem_by_name("REPLICATE"),
      LIST_DROP_DEF,
      get_theorem_by_name("APPEND"))),
      `APPEND (REPLICATE (num_of_int 0i) ${value:int})
              (list_drop (num_of_int 0i) ${xs:(int)list})`);
  apply_hconv_st(eq2ent(sym_rule(
      ap_term_rule(array_at, initial_shape))));
}

PROOF void x2c_fill_index_bound(
    const term index_var, const term length_var,
    const term xs, const term value) {
  thm hlt_original = x2c_int_index_bound(index_var, length_var, xs);
  thm hnatural_lt = x2c_num_index_bound(index_var, length_var, xs);
  thm hlength = mp_rule(
      specl_rule(TERM_LIST(`num_of_int ${index_var:int}`, value, xs),
                 LENGTH_FILL_CURSOR),
      match_mp_rule(
          get_theorem_by_name("LT_IMP_LE"), hnatural_lt));
  thm hint_length = ap_term_rule(`int_of_num`, hlength);
  add_fact_st(conv_rule(
      rewrite_conv(THM_LIST(sym_rule(hint_length))),
      hlt_original));
}

PROOF void x2c_fill_advance(
    const term index_var, const term length_var,
    const term xs, const term value) {
  thm step = mp_rule(
      specl_rule(TERM_LIST(`num_of_int ${index_var:int}`, value, xs),
                 LIST_UPDATE_REPLICATE_DROP_STEP),
      x2c_num_index_bound(index_var, length_var, xs));
  thm successor = num_of_int_suc_rule(
      index_var, assume_rule(`0i <= ${index_var:int}`));
  step = conv_rule(
      rewrite_conv(THM_LIST(sym_rule(successor))), step);
  substitute_st(step);
  add_fact_st(int_arith_rule(`
    0i <= ${index_var:int} ==>
    ${index_var:int} <= ${length_var:int} ==>
    ${index_var:int} < ${length_var:int} ==>
    0i <= ${index_var:int} + 1i &&
    ${index_var:int} + 1i <= ${length_var:int}
  `));
}

PROOF void x2c_fill_exit(
    const term index_var, const term length_var,
    const term xs, const term value) {
  thm hieq = match_mp_rule(
      int_arith_rule(`
        ${index_var:int} <= ${length_var:int} ==>
        ${index_var:int} >= ${length_var:int} ==>
        ${index_var:int} = ${length_var:int}
      `),
      assume_rule(`${index_var:int} <= ${length_var:int}`));
  hieq = match_mp_rule(
      hieq, assume_rule(`${index_var:int} >= ${length_var:int}`));
  thm hi_length = trans_rule(
      hieq,
      assume_rule(
          `${length_var:int} = &(LENGTH ${xs:(int)list})`));
  thm hnum_length = num_of_int_eq_length_rule(
      index_var, xs, hi_length);
  thm finished_shape = apply_conversion(rewrite_conv(THM_LIST(
      hnum_length,
      LIST_DROP_LENGTH,
      get_theorem_by_name("APPEND_NIL"))),
      `APPEND (REPLICATE (num_of_int ${index_var:int}) ${value:int})
              (list_drop (num_of_int ${index_var:int}) ${xs:(int)list})`);
  substitute_st(finished_shape);
}

/*
 * Open and close are the only element-type-specific steps.  They are
 * separate C proof functions, so one `elem` term selects between them.
 */
PROOF static void x2c_open_cell(
    const term elem, const term p_pre, const term index_var) {
  if (equals_term(elem, `Tchar`)) {
    open_char_array(p_pre, index_var);
    return;
  }
  open_int_array(p_pre, index_var);
}

PROOF static void x2c_close_cell_write(
    const term elem, const term p_pre, const term index_var) {
  if (equals_term(elem, `Tchar`)) {
    close_char_array_write(p_pre, index_var);
    return;
  }
  close_int_array_write(p_pre, index_var);
}

PROOF void x2c_fill_before_store(
    const term elem, const term p_pre, const term index_var,
    const term length_var, const term xs, const term value) {
  x2c_fill_index_bound(index_var, length_var, xs, value);
  x2c_open_cell(elem, p_pre, index_var);
}

PROOF void x2c_fill_after_store(
    const term elem, const term p_pre, const term index_var,
    const term length_var, const term xs, const term value) {
  x2c_close_cell_write(elem, p_pre, index_var);
  x2c_fill_advance(index_var, length_var, xs, value);
}
