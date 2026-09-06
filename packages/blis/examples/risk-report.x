/*  risk-report.x -- Center named observations and report feature risk. */

import "blis" with Blis, BlisObject;

static List numerical_rows(List batches, List features) {
  List rows = NULL;
  foreach(List batch, batches) {
    List values = NULL;
    foreach(Var feature, features) values = cons(batch.get(feature), values);
    rows = cons(values.reverse(), rows);
  }
  return rows.reverse();
}

int main(void) {
  List batches = %(
    ((name "north") (return 0.123456789) (volume 1.0) (liquidity 5.0))
    ((name "south") (return 0.223456789) (volume 3.0) (liquidity 5.0))
    ((name "east") (return -0.076543211) (volume 5.0) (liquidity 5.0))
    ((name "west") (return 0.323456789) (volume 7.0) (liquidity 5.0))
  );
  List features = %(return volume liquidity), first_batch = batches[0];
  double source_return = first_batch.get(<return>).double();

  BlisObject observations = BlisObject.copy_rows(
    numerical_rows(batches, features), BLIS_FLOAT
  );
  defer observations.free();
  BlisObject ones = BlisObject.copy_vector(%(1.0 1.0 1.0 1.0), BLIS_FLOAT);
  defer ones.free();

  printf("BLIS %s risk report\n", Blis.version());
  printf(
    "observations: %d x %d, storage %s\n",
    observations.rows(), observations.columns(),
    observations.storage_precision()
  );
  printf(
    "rounding boundary: %.9f -> %.9f\n",
    source_return, observations.at(0, 0)
  );

  for (int index = 0; index < observations.columns(); index++) {
    BlisObject column = observations.column(index);
    double mean = column.dotv(ones) / column.length();
    column.axpyv(-mean, ones);
    double deviation = column.normfv();
    String name = features[index].symbol();
    if (deviation == 0.0) printf("%s: no variation after centering\n", name);
    else printf("%s: centered norm %.6f\n", name, deviation);
  }

  BlisObject transposed = observations.transpose_view();
  BlisObject risk = BlisObject.new(BLIS_DOUBLE, 3, 3);
  defer risk.free();
  risk.fill(0.25);
  risk.set_computation_precision(BLIS_DOUBLE_PREC);

  double alpha = 1.0 / (observations.rows() - 1), beta = 0.5;
  risk.gemm(alpha, transposed, observations, beta);
  printf(
    "gemm: C := %.1f*C + %.6f*A*X, computation %s\n",
    beta, alpha, risk.computation_precision()
  );
  foreach(Array row, risk.to_rows()) {
    printf("  ");
    foreach(Var value, row) printf("%10.6f", value.double());
    printf("\n");
  }
  return 0;
}
