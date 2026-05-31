# Shared test helpers.

# Lower a FULL annotation (with its parentheses) to its generated assert_* lines.
genf <- function(annotation) {
  return(generate_checks(parse_annotation(annotation), "x"))
}
