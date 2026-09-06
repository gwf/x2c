/*  page-rank.x -- Rank a link graph by power iteration on BLIS matrices. */

import "blis" with Blis, BlisObject;

int main(void) {
  Scope.retain();
  defer Scope.release();

  List pages = %("index" "guide" "reference" "download" "blog");

  /*  links[i][j] is page j's share of its outbound links that reach i. */
  BlisObject links = BlisObject.copy_rows(
    %((0.00 0.50 0.50 0.50 0.00)
      (0.50 0.00 0.50 0.00 0.50)
      (0.25 0.50 0.00 0.50 0.50)
      (0.25 0.00 0.00 0.00 0.00)
      (0.00 0.00 0.00 0.00 0.00)),
    BLIS_DOUBLE
  );
  defer links.free();

  /*  Rank owns its buffer across rounds. Each round releases its operator
      temporaries after copying the next rank into that owned buffer. */
  BlisObject rank = BlisObject.copy_vector(
    %(0.2 0.2 0.2 0.2 0.2), BLIS_DOUBLE
  );
  defer rank.free();
  BlisObject ones = BlisObject.copy_vector(
    %(1.0 1.0 1.0 1.0 1.0), BLIS_DOUBLE
  );
  defer ones.free();

  double shift = 1.0;
  int round = 0;
  for (; shift > 1e-15 && round < 100; round++) {
    Scope.retain();
    {
      defer Scope.release();
      BlisObject next = links * rank;
      next = next.scale(1.0 / next.dotv(ones));
      shift = (next - rank).normfv();
      rank.copy_from(next);
    }
  }
  printf("converged after %d rounds, shift %.1e\n", round, shift);

  Array scores = rank.to_values();
  for (int place = 0; place < scores.len(); place++) {
    int best = 0;
    for (int index = 1; index < scores.len(); index++)
      if (scores[index].double() > scores[best].double()) best = index;
    printf("  %-10s %.4f\n", pages[best].string(), scores[best].double());
    scores[best] = -1.0;
  }
  return 0;
}
