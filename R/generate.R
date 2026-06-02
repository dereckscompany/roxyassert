# Lowering: turn an annotation AST (from R/parse.R) into the `assert_*()` calls
# that validate a value. `generate_checks()` returns a character vector of R
# statement lines; the roclet stitches these into R/contracts-generated.R.
#
# Every value the user wrote (interval bounds, set elements) is emitted verbatim.
# Internal.

# base type -> assert function name (the grammar's `numeric` is a double).
.rg_scalar_fn <- c(
  integer = "assert_scalar_integer",
  numeric = "assert_scalar_double",
  character = "assert_scalar_character",
  factor = "assert_scalar_factor",
  complex = "assert_scalar_complex",
  logical = "assert_scalar_logical",
  raw = "assert_scalar_raw",
  Date = "assert_scalar_date",
  POSIXct = "assert_scalar_datetime"
)
.rg_vector_fn <- c(
  integer = "assert_integer",
  numeric = "assert_double",
  character = "assert_character",
  factor = "assert_factor",
  complex = "assert_complex",
  logical = "assert_logical",
  raw = "assert_raw",
  Date = "assert_date",
  POSIXct = "assert_datetime"
)
.rg_composite_fn <- c(
  list = "assert_list",
  data.table = "assert_data_table",
  data.frame = "assert_data_frame"
)

#' Generate the assertion statements for an annotation
#'
#' @param ast A slot AST from [parse_annotation()].
#' @param expr A string: the R expression to validate (an argument name, or the
#'   return-value variable).
#' @return A character vector of R statement lines.
#' @keywords internal
#' @noRd
generate_checks <- function(ast, expr) {
  body <- .rg_alternatives(ast$alternatives, expr)
  # Nothing to check (e.g. `any` / `any?`): emit nothing, not an empty if-block.
  if (length(body) == 0L) {
    return(character())
  }
  if (isTRUE(ast$null_ok)) {
    body <- c(
      sprintf("if (!is.null(%s)) {", expr),
      paste0("  ", body),
      "}"
    )
  }
  return(body)
}

# A slot's alternatives: one type, or a union via assert_any_of().
.rg_alternatives <- function(alts, expr) {
  if (length(alts) == 1L) {
    return(.rg_type(alts[[1]], expr))
  }
  lines <- c("assert_any_of(", paste0("  ", expr, ","))
  for (i in seq_along(alts)) {
    stmts <- .rg_type(alts[[i]], ".x")
    closer <- if (i < length(alts)) "  }," else "  }"
    lines <- c(lines, "  function(.x) {", paste0("    ", stmts), closer)
  }
  lines <- c(lines, ")")
  return(lines)
}

.rg_type <- function(node, expr) {
  return(switch(
    node$kind,
    atomic = .rg_atomic(node, expr),
    wildcard = .rg_wildcard(node, expr),
    "function" = sprintf("assert_function(%s)", expr),
    # R's class system is flat: assert_class() checks the final segment. Any
    # `pkg::` qualifier in `class<pkg::Name>` is documentary and is dropped here.
    class = sprintf('assert_class(%s, "%s")', expr, sub("^.*::", "", node$class)),
    composite = .rg_composite(node, expr),
    # Defensive only: parse_annotation never yields a promise node here. promise<T>
    # is unwrapped (recursively) at slot and field level, rejected as a list
    # element, and rejected inside scalar<>/vector<>. Validate the resolved value,
    # never the promise wrapper, should that invariant ever change.
    promise = .rg_type(node$inner, expr),
    # A named type that reached generation unresolved: not a built-in and not a
    # registered @type. (The roclet resolves named types first; this is the path
    # for an undefined reference.)
    named = stop(
      "roxyassert: unknown type '",
      node$name,
      "' (not a built-in type; define it with @type)",
      call. = FALSE
    ),
    stop("roxyassert: cannot generate for node kind '", node$kind, "'", call. = FALSE)
  ))
}

.rg_atomic <- function(node, expr) {
  base <- node$base
  shape <- node$shape
  na_ok <- isTRUE(node$na_ok)
  checks <- character()

  if (shape == "scalar") {
    if (na_ok) {
      # scalar_* reject NA, so use the vector check + an explicit length 1.
      checks <- c(
        sprintf("%s(%s)", .rg_vector_fn[[base]], expr),
        sprintf("assert_length(%s, 1L)", expr)
      )
    } else {
      checks <- sprintf("%s(%s)", .rg_scalar_fn[[base]], expr)
    }
  } else {
    checks <- sprintf("%s(%s)", .rg_vector_fn[[base]], expr)
    if (!na_ok && base != "raw") {
      checks <- c(checks, sprintf("assert_no_missing_values(%s)", expr))
    }
    if (shape == "vector" && !is.null(node$length)) {
      checks <- c(checks, .rg_length(node$length, expr))
    }
  }

  if (!is.null(node$interval)) {
    checks <- c(checks, .rg_interval(node$interval, expr, na_ok))
  }
  if (!is.null(node$set)) {
    checks <- c(checks, .rg_set(node, expr, na_ok))
  }
  return(checks)
}

.rg_wildcard <- function(node, expr) {
  shape <- node$shape
  if (shape == "scalar") {
    return(sprintf("assert_length(%s, 1L)", expr))
  }
  if (shape == "vector" && !is.null(node$length)) {
    return(.rg_length(node$length, expr))
  }
  return(character()) # bare `any`: no check at all
}

.rg_composite <- function(node, expr) {
  checks <- sprintf("%s(%s)", .rg_composite_fn[[node$base]], expr)
  if (node$base == "list" && !is.null(node$element)) {
    el <- node$element
    if (identical(el$kind, "wildcard")) {
      return(checks) # list<any> == bare list at runtime
    }
    flat_atomic <- identical(el$kind, "atomic") &&
      identical(el$shape, "bare") &&
      is.null(el$interval) &&
      is.null(el$set) &&
      !isTRUE(el$na_ok)
    if (flat_atomic) {
      # `numeric` means double everywhere else; assert_list_of's is.numeric would
      # otherwise wave through integer cells, so lower it to the strict "double".
      el_type <- if (identical(el$base, "numeric")) "double" else el$base
      checks <- c(checks, sprintf('assert_list_of(%s, "%s")', expr, el_type))
    } else {
      # richer element type: check each element in turn.
      inner <- .rg_type(el, ".x")
      checks <- c(checks, sprintf("for (.x in %s) {", expr), paste0("  ", inner), "}")
    }
  }
  if (!is.null(node$fields) && length(node$fields) > 0L) {
    checks <- c(checks, .rg_fields(node, expr))
  }
  return(checks)
}

# Named-record / typed-column fields (S3): assert the names/columns are present,
# then check each field's own annotation against `expr[["field"]]` (recursively).
.rg_fields <- function(node, expr) {
  names <- vapply(node$fields, function(f) f$name, character(1))
  set <- paste0("c(", paste(sprintf('"%s"', names), collapse = ", "), ")")
  has <- if (node$base == "list") "assert_has_names" else "assert_has_columns"
  checks <- sprintf("%s(%s, %s)", has, expr, set)
  for (f in node$fields) {
    checks <- c(checks, generate_checks(f$ast, sprintf('%s[["%s"]]', expr, f$name)))
  }
  return(checks)
}

.rg_length <- function(length, expr) {
  # `0..` (min 0, no max) is no constraint at all — emit nothing.
  if (length$min == 0L && is.infinite(length$max)) {
    return(character())
  }
  if (is.finite(length$max) && length$min == length$max) {
    return(sprintf("assert_length(%s, %dL)", expr, length$min))
  }
  if (is.infinite(length$max)) {
    return(sprintf("assert_minimum_length(%s, %dL)", expr, length$min))
  }
  return(sprintf("assert_length_between(%s, %dL, %dL)", expr, length$min, length$max))
}

.rg_interval <- function(interval, expr, na_ok) {
  args <- expr
  if (is.na(interval$lo$sentinel)) {
    args <- c(args, sprintf("lower = %s", interval$lo$text))
    if (isTRUE(interval$lo_open)) {
      args <- c(args, "lower_inclusive = FALSE")
    }
  }
  if (is.na(interval$hi$sentinel)) {
    args <- c(args, sprintf("upper = %s", interval$hi$text))
    if (isTRUE(interval$hi_open)) {
      args <- c(args, "upper_inclusive = FALSE")
    }
  }
  if (isTRUE(na_ok)) {
    args <- c(args, "na_ok = TRUE")
  }
  return(sprintf("assert_between(%s)", paste(args, collapse = ", ")))
}

.rg_set <- function(node, expr, na_ok) {
  allowed <- if (isTRUE(na_ok)) sprintf("c(%s, NA)", node$set$text) else node$set$text
  # on a factor the set constrains the realised values (as.character), per footnote 2.
  target <- if (identical(node$base, "factor")) sprintf("as.character(%s)", expr) else expr
  fn <- if (identical(node$shape, "scalar")) "assert_value_in_set" else "assert_values_in_set"
  return(sprintf("%s(%s, %s)", fn, target, allowed))
}
