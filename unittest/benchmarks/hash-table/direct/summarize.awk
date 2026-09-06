BEGIN {
  FS = ","
  OFS = ","
  operation_names = "grow-insert reserved-insert replace-hit update-add-hit"
  operation_names = operation_names " lookup-hit"
  operation_names = operation_names " lookup-miss erase-miss iterate erase-hit"
  operation_count = split(operation_names, operations, " ")
}

NR == 1 {
  next
}

{
  sample = $1
  implementation = $2
  count = $3
  operation = $5
  value = $7 + 0
  checksum = $8

  count_key = count ""
  if (!count_seen[count_key]++) counts[++count_count] = count_key

  series = implementation SUBSEP count_key SUBSEP operation
  values[series, ++series_count[series]] = value
  checksums[implementation, sample, count_key, operation] = checksum
  samples[sample] = 1
}

function numeric_sort(series, count, destination,  i, j, value) {
  for (i = 1; i <= count; i++) {
    value = values[series, i]
    j = i - 1
    while (j >= 1 && destination[j] > value) {
      destination[j + 1] = destination[j]
      j--
    }
    destination[j + 1] = value
  }
}

function trimmed_mean(series, count,  sorted, drop, i, total, kept) {
  delete sorted
  numeric_sort(series, count, sorted)
  drop = count >= 8 ? 2 : 0
  total = 0
  kept = 0
  for (i = drop + 1; i <= count - drop; i++) {
    total += sorted[i]
    kept++
  }
  return total / kept
}

function series_mean(implementation, count, operation, expected,  series, n) {
  series = implementation SUBSEP count SUBSEP operation
  n = series_count[series]
  if (n != expected || n == 0) {
    print \
      "sample count mismatch: implementation=" implementation \
      " count=" count " operation=" operation > "/dev/stderr"
    exit 2
  }
  return trimmed_mean(series, n)
}

END {
  failed = 0
  pair_names = "x2c:khashl x2c:x2c-khashl x2c-typed:khashl-typed"
  pair_names = pair_names " x2c-typed:x2c-flat x2c-typed:x2c-wide"
  pair_names = pair_names " x2c-typed:x2c-meta"
  pair_count = split(pair_names, pairs, " ")
  for (sample in samples) {
    for (ci = 1; ci <= count_count; ci++) {
      count = counts[ci]
      for (oi = 1; oi <= operation_count; oi++) {
        operation = operations[oi]
        for (pi = 1; pi <= pair_count; pi++) {
          split(pairs[pi], pair, ":")
          left = checksums[pair[1], sample, count, operation]
          right = checksums[pair[2], sample, count, operation]
          if (left != right) {
            print \
              "checksum mismatch: pair=" pairs[pi] \
              " sample=" sample \
              " count=" count \
              " operation=" operation > "/dev/stderr"
            failed = 1
          }
        }
      }
    }
  }
  if (failed) exit 2

  print \
    "count", "operation", "x2c_trimmed_ns", "khashl_trimmed_ns", \
    "x2c_over_khashl", "x2c_khashl_trimmed_ns", "x2c_over_x2c_khashl", \
    "x2c_typed_trimmed_ns", "khashl_typed_trimmed_ns", \
    "x2c_typed_over_khashl_typed", "x2c_over_x2c_typed", \
    "x2c_flat_trimmed_ns", "x2c_typed_over_x2c_flat", \
    "x2c_flat_over_khashl_typed", "x2c_wide_trimmed_ns", \
    "x2c_typed_over_x2c_wide", "x2c_wide_over_khashl_typed", \
    "x2c_meta_trimmed_ns", "x2c_typed_over_x2c_meta", \
    "x2c_meta_over_khashl_typed"
  for (ci = 1; ci <= count_count; ci++) {
    count = counts[ci]
    for (oi = 1; oi <= operation_count; oi++) {
      operation = operations[oi]
      expected = series_count["x2c" SUBSEP count SUBSEP operation]
      x2c_mean = series_mean("x2c", count, operation, expected)
      reference_mean = series_mean("khashl", count, operation, expected)
      backend_mean = series_mean("x2c-khashl", count, operation, expected)
      typed_mean = series_mean("x2c-typed", count, operation, expected)
      native_mean = series_mean("khashl-typed", count, operation, expected)
      flat_mean = series_mean("x2c-flat", count, operation, expected)
      wide_mean = series_mean("x2c-wide", count, operation, expected)
      meta_mean = series_mean("x2c-meta", count, operation, expected)
      printf \
        "%s,%s,%.6f,%.6f,%.4f,%.6f,%.4f,%.6f,%.6f,%.4f,%.4f,%.6f,%.4f,%.4f,%.6f,%.4f,%.4f,%.6f,%.4f,%.4f\n", \
        count, operation, x2c_mean, reference_mean, \
        x2c_mean / reference_mean, backend_mean, x2c_mean / backend_mean, \
        typed_mean, native_mean, \
        typed_mean / native_mean, x2c_mean / typed_mean, \
        flat_mean, typed_mean / flat_mean, flat_mean / native_mean, \
        wide_mean, typed_mean / wide_mean, wide_mean / native_mean, \
        meta_mean, typed_mean / meta_mean, meta_mean / native_mean
    }
  }
}
