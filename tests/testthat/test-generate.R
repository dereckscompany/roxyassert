# Tests for the lowering (R/generate.R): annotation AST -> assert_*() statements.

gen <- function(s) generate_checks(parse_annotation(paste0("(", s, ")")), "x")

test_that("class mapping (numeric -> double) and NA-rejection by default", {
  expect_equal(gen("scalar<numeric>"), "assert_scalar_double(x)")
  expect_equal(gen("scalar<character>"), "assert_scalar_character(x)")
  expect_equal(gen("numeric"), c("assert_double(x)", "assert_no_missing_values(x)"))
  expect_equal(gen("scalar<raw>"), "assert_scalar_raw(x)")
  expect_equal(gen("raw"), "assert_raw(x)") # raw has no NA, so no missing-value check
})

test_that("| NA toggles the missing-value handling", {
  expect_equal(gen("numeric | NA"), "assert_double(x)")
  expect_equal(gen("scalar<numeric | NA>"), c("assert_double(x)", "assert_length(x, 1L)"))
})

test_that("intervals lower to assert_between with the right flags / sentinels", {
  expect_equal(
    gen("scalar<numeric in [0, 1]>"),
    c("assert_scalar_double(x)", "assert_between(x, lower = 0, upper = 1)")
  )
  expect_equal(
    gen("scalar<numeric in ]0, 1]>"),
    c("assert_scalar_double(x)", "assert_between(x, lower = 0, lower_inclusive = FALSE, upper = 1)")
  )
  expect_equal(
    gen("scalar<numeric in ]0, Inf[>"),
    c(
      "assert_scalar_double(x)",
      "assert_between(x, lower = 0, lower_inclusive = FALSE, upper = Inf, upper_inclusive = FALSE)"
    )
  )
  expect_equal(
    gen('scalar<Date in [as.Date("2024-01-01"), Inf[>'),
    c("assert_scalar_date(x)", 'assert_between(x, lower = as.Date("2024-01-01"))')
  )
  # interval + | NA on a vector: na-aware between, no missing-value rejection
  g <- gen("numeric in [0, 1] | NA")
  expect_equal(g, c("assert_double(x)", "assert_between(x, lower = 0, upper = 1, na_ok = TRUE)"))
})

test_that("finiteness: an open bracket at a ±Inf sentinel excludes that infinity (numeric only)", {
  # open high at Inf -> x < Inf (finite above)
  expect_equal(
    gen("scalar<numeric in ]0, Inf[>"),
    c(
      "assert_scalar_double(x)",
      "assert_between(x, lower = 0, lower_inclusive = FALSE, upper = Inf, upper_inclusive = FALSE)"
    )
  )
  # open low at -Inf -> x > -Inf (finite below)
  expect_equal(
    gen("scalar<numeric in ]-Inf, 5]>"),
    c("assert_scalar_double(x)", "assert_between(x, lower = -Inf, lower_inclusive = FALSE, upper = 5)")
  )
  # both open sentinels -> any finite double
  expect_equal(
    gen("scalar<numeric in ]-Inf, Inf[>"),
    c(
      "assert_scalar_double(x)",
      "assert_between(x, lower = -Inf, lower_inclusive = FALSE, upper = Inf, upper_inclusive = FALSE)"
    )
  )
  # CLOSED sentinel still means "no bound that side": omit it
  expect_equal(
    gen("scalar<numeric in ]0, Inf]>"),
    c("assert_scalar_double(x)", "assert_between(x, lower = 0, lower_inclusive = FALSE)")
  )
  # integer/count can't be Inf: a sentinel is omitted regardless of bracket
  expect_equal(gen("scalar<integer in [1, Inf[>"), c("assert_scalar_integer(x)", "assert_between(x, lower = 1)"))
  expect_equal(gen("scalar<count in [0, Inf[>"), c("assert_scalar_count(x)", "assert_between(x, lower = 0)"))
})

test_that("vector lengths", {
  expect_true(any(grepl("assert_length\\(x, 10L\\)", gen("vector<numeric, 10>"))))
  expect_true(any(grepl("assert_length_between\\(x, 1L, 10L\\)", gen("vector<numeric, 1..10>"))))
  expect_true(any(grepl("assert_minimum_length\\(x, 2L\\)", gen("vector<integer, 2..>"))))
})

test_that("sets: character verbatim, factor via as.character, NA-aware", {
  expect_true(any(grepl('assert_values_in_set\\(x, c\\("a", "b"\\)\\)', gen('character in c("a", "b")'))))
  expect_true(any(grepl("assert_values_in_set\\(as.character\\(x\\)", gen('factor in c("a", "b")'))))
  expect_true(any(grepl("c\\(ORDER_SIDE, NA\\)", gen("character in ORDER_SIDE | NA"))))
  expect_true(any(grepl("^assert_value_in_set\\(", gen('scalar<character in c("a", "b")>'))))
})

test_that("references, wildcard, composites", {
  expect_equal(gen("function"), "assert_function(x)")
  expect_equal(gen("class<Engine>"), 'assert_class(x, "Engine")')
  # a dotted S3 class name is emitted verbatim
  expect_equal(gen("class<my.Class>"), 'assert_class(x, "my.Class")')
  expect_equal(gen("any"), character())
  expect_equal(gen("scalar<any>"), "assert_length(x, 1L)")
  expect_equal(gen("vector<any, 3>"), "assert_length(x, 3L)")
  expect_equal(gen("data.table"), "assert_data_table(x)")
  expect_equal(gen("list<character>"), c("assert_list(x)", 'assert_list_of(x, "character")'))
  expect_equal(gen("list<any>"), "assert_list(x)")
  # richer list element -> element-wise loop
  g <- gen("list<class<Engine>>")
  expect_equal(g[1], "assert_list(x)")
  expect_true(any(grepl("for \\(.x in x\\)", g)))
  expect_true(any(grepl('assert_class\\(.x, "Engine"\\)', g)))
})

test_that("unions lower to assert_any_of with one thunk per alternative", {
  g <- gen("numeric | character")
  expect_equal(g[1], "assert_any_of(")
  expect_true(any(grepl("assert_double\\(.x\\)", g)))
  expect_true(any(grepl("assert_character\\(.x\\)", g)))
  expect_equal(g[length(g)], ")")
})

test_that("nullable slot wraps the checks in if (!is.null(...))", {
  g <- gen("scalar<numeric>?")
  expect_equal(g[1], "if (!is.null(x)) {")
  expect_true(any(grepl("assert_scalar_double\\(x\\)", g)))
  expect_equal(g[length(g)], "}")
})

test_that("composite fields lower to a names check + per-field checks", {
  txt <- paste(
    "(data.table) matches:",
    "- symbol (character) the pair.",
    "- score (numeric in [0, 1]) score.",
    sep = "\n"
  )
  g <- generate_checks(parse_annotation(txt), "value")
  expect_true(any(grepl('assert_has_columns\\(value, c\\("symbol", "score"\\)\\)', g)))
  expect_true(any(grepl('assert_character\\(value\\[\\["symbol"\\]\\]\\)', g)))
  expect_true(any(grepl('assert_between\\(value\\[\\["score"\\]\\], lower = 0, upper = 1\\)', g)))
})

test_that("a list record uses assert_has_names; nesting threads [[...]]", {
  txt <- paste(
    "(list)",
    "- page (scalar<integer in [1, Inf[>) page.",
    "- rows (data.table | NULL) the page:",
    "  - id (character) id.",
    sep = "\n"
  )
  g <- generate_checks(parse_annotation(txt), "value")
  expect_true(any(grepl('assert_has_names\\(value, c\\("page", "rows"\\)\\)', g)))
  expect_true(any(grepl('if \\(!is.null\\(value\\[\\["rows"\\]\\]\\)\\)', g)))
  expect_true(any(grepl('assert_character\\(value\\[\\["rows"\\]\\]\\[\\["id"\\]\\]\\)', g)))
})

test_that("an atomic-typed column rejects list-cells; list<T> column is allowed", {
  g <- generate_checks(parse_annotation("(data.table)\n- blob (list<any>) a list-column."), "value")
  expect_true(any(grepl('assert_list\\(value\\[\\["blob"\\]\\]\\)', g)))
  # an atomic column lowers to an atomic assert, which rejects a list at runtime
  g2 <- generate_checks(parse_annotation("(data.table)\n- id (character) id."), "value")
  expect_true(any(grepl('assert_character\\(value\\[\\["id"\\]\\]\\)', g2)))
})

test_that("list<numeric> lowers to assert_list_of with the strict \"double\" type", {
  expect_equal(gen("list<numeric>"), c("assert_list(x)", 'assert_list_of(x, "double")'))
  # other element bases pass through unchanged
  expect_equal(gen("list<character>"), c("assert_list(x)", 'assert_list_of(x, "character")'))
  expect_equal(gen("list<integer>"), c("assert_list(x)", 'assert_list_of(x, "integer")'))
})

# ---- optional record keys ----------------------------------------------------

# Evaluate the generated checks for an annotation against a concrete value. The
# generated lines call assert::* by bare name (they are meant to run inside a
# package that imports assert), so the function is closed over assert's
# namespace.
run_checks <- function(annotation, value) {
  skip_if_not_installed("assert")
  lines <- generate_checks(parse_annotation(annotation), "x")
  fn <- eval(
    parse(text = paste(c("function(x) {", lines, "}"), collapse = "\n"), keep.source = FALSE),
    envir = new.env(parent = asNamespace("assert"))
  )
  fn(value)
  return(invisible(value))
}

test_that("optional fields skip the presence assertion; required fields keep it", {
  g <- genf("(list)\n- a (scalar<character>) x.\n- c? (scalar<character>) y.")
  expect_equal(
    g,
    c(
      "assert_list(x)",
      'assert_has_names(x, c("a"))',
      'assert_scalar_character(x[["a"]])',
      'if ("c" %in% names(x)) {',
      '  assert_scalar_character(x[["c"]])',
      "}"
    )
  )
  # tables use assert_has_columns for the required columns only
  g2 <- genf("(data.table)\n- id (character) i.\n- note? (character) n.")
  expect_true(any(grepl('assert_has_columns\\(x, c\\("id"\\)\\)', g2)))
  expect_true(any(grepl('if \\("note" %in% names\\(x\\)\\) \\{', g2)))
})

test_that("an all-optional record emits no has_names/has_columns call", {
  g <- genf("(list)\n- c? (scalar<character>) y.\n- d? (scalar<numeric>) z.")
  expect_false(any(grepl("assert_has_names|assert_has_columns", g)))
  expect_true(any(grepl('if \\("c" %in% names\\(x\\)\\) \\{', g)))
  expect_true(any(grepl('if \\("d" %in% names\\(x\\)\\) \\{', g)))
})

test_that("an optional + nullable field nests the !is.null guard inside the presence guard", {
  g <- genf("(list)\n- d? (scalar<character> | NULL) y.")
  expect_equal(
    g,
    c(
      "assert_list(x)",
      'if ("d" %in% names(x)) {',
      '  if (!is.null(x[["d"]])) {',
      '    assert_scalar_character(x[["d"]])',
      "  }",
      "}"
    )
  )
})

test_that("optional record keys behave at runtime (the tri-state)", {
  ann <- "(list)\n- a (scalar<character>) required.\n- c? (scalar<character>) optional."
  # (a) an absent optional key passes
  expect_silent(run_checks(ann, list(a = "x")))
  # (b) a present optional key with the wrong type fails
  expect_error(run_checks(ann, list(a = "x", c = 1)))
  # (f) the tri-state: present-NA on a non-`| NA` type FAILS (absent != present-NA)
  expect_error(run_checks(ann, list(a = "x", c = NA_character_)))
  # (d) a required key is still enforced by assert_has_names
  expect_error(run_checks(ann, list(c = "x")))
  # (c) optional + `| NULL`: a present-NULL key passes
  expect_silent(run_checks("(list)\n- d? (scalar<character> | NULL) y.", list(d = NULL)))
})
