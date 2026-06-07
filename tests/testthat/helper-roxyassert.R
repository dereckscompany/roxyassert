# Shared test helpers.

# Lower a FULL annotation (with its parentheses) to its generated assert_* lines.
genf <- function(annotation) {
  return(generate_checks(parse_annotation(annotation), "x"))
}

# Run the contract roclet on inline package source and return the flattened
# generated code lines (the `$code` field of the roclet's structured result).
proc_code <- function(text) {
  return(unlist(roxygen2::roc_proc_text(contract_roclet(), text)$code, use.names = FALSE))
}
