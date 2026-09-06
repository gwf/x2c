BEGIN {
  FS = ";"
  OFS = "\t"
  print "profile", "implementation", "entries", "operation",
    "ns_per_operation"
}

$1 == "N" {
  entries = $(NF - 1)
}

/^x2c (Var|pointer) / || /^16-char string-content / {
  split($0, parts, ":")
  description = parts[2]
  implementation = parts[3]

  if(description ~ /^Total time to insert/)
    operation = "insert_nonexisting"
  else if(description ~ /^Time to erase 1,000 existing/)
    operation = "erase_existing"
  else if(description ~ /^Time to replace/)
    operation = "replace_existing"
  else if(description ~ /^Time to erase 1,000 nonexisting/)
    operation = "erase_nonexisting"
  else if(description ~ /^Time to look up 1,000 existing/)
    operation = "lookup_existing"
  else if(description ~ /^Time to look up 1,000 nonexisting/)
    operation = "lookup_nonexisting"
  else if(description ~ /^Time to iterate/)
    operation = "iterate"
}

$1 == "Adjusted average" {
  value = $(NF - 1)
  if(operation == "insert_nonexisting")
    value = value * 1000 / entries
  else
    value = value / 1000

  print profile, implementation, entries, operation, value
}
