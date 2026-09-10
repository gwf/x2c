/*  verify-ops.x -- prints one line per checked operator for
    tests/verify-ops.py, which recomputes each value in the pinned Python
    torch and compares. Every line is `<name> <value>`; a value is the sum of
    the result unless the name says otherwise.
*/

import "torch" with Torch, Tensor;

static void show(String name, double value) {
  printf("%s %.17g\n", name, value);
}

int main(void) {
  Tensor a = Tensor.of(%((1 2 3) (4 5 6)), %(2 3), XT_FLOAT64);
  Tensor mask = a.gt(3);

  show("softmax_first", a.softmax(1).to_values()[0].double());
  show("cumsum_last", a.cumsum(1, -1).to_values()[5].double());
  show("clamp_sum", a.clamp(2, 5).sum().item().double());
  show("clamp_min_only_sum", a.clamp(2, Var.null()).sum().item().double());
  show("clamp_max_float_sum", a.clamp(Var.null(), 2.5).sum().item().double());
  show("maximum_sum", a.maximum(a.flip(%(1))).sum().item().double());
  show("flip_first", a.flip(%(1)).to_values()[0].double());
  show("argmax_dim_sum", a.argmax(1, 1).to_dtype(XT_FLOAT64).sum().item().double());
  show("argmax_flat", a.reshape(%(6)).argmax(0, 0).to_dtype(XT_FLOAT64).item().double());
  show("amax_sum", a.amax(%(1), 0).sum().item().double());
  show("prod_all", a.prod(-1).item().double());
  show("logsumexp_first", a.logsumexp(%(1), 0).to_values()[0].double());
  show("narrow_sum", a.narrow(1, 0, 2).sum().item().double());
  show("topk_values_sum", a.topk(2, 1, 1, 1)[0].tensor().sum().item().double());
  show("sort_desc_first",
       a.sort(1, 1)[0].tensor().to_values()[0].double());
  show("split_second_sum", a.split(1, 0)[1].tensor().sum().item().double());
  show("chunk_third_sum", a.chunk(3, 1)[2].tensor().sum().item().double());
  show("cat_sum", Tensor.cat(%($a $a), 0).sum().item().double());
  show("stack_rank", (double) Tensor.stack(%($a $a), 0).rank());
  show("linspace_sum", Torch.linspace(0, 1, 5, XT_FLOAT64, NULL)
                            .sum().item().double());
  show("eye_sum", Torch.eye(3, XT_FLOAT64, NULL).sum().item().double());
  show("where_sum",
       mask.where(a, Tensor.zeros(%(2 3), XT_FLOAT64)).sum().item().double());
  show("masked_select_sum", a.masked_select(mask).sum().item().double());
  return 0;
}
