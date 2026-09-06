BEGIN {
  FS = "\t"
}

NR == 1 {
  next
}

{
  key = $2 FS $3
  result = $4 FS $5

  if(!(key in expected)) {
    expected[key] = result
    owner[key] = $1
  }
  else if(expected[key] != result) {
    printf "udb3 mismatch at %s: %s has %s, expected %s from %s\n",
      key,
      $1,
      result,
      expected[key],
      owner[key] > "/dev/stderr"
    failed = 1
  }
}

END {
  if(failed)
    exit 1
}
