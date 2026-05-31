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
    c("assert_scalar_double(x)", "assert_between(x, lower = 0, lower_inclusive = FALSE)")
  )
  expect_equal(
    gen('scalar<Date in [as.Date("2024-01-01"), Inf[>'),
    c("assert_scalar_date(x)", 'assert_between(x, lower = as.Date("2024-01-01"))')
  )
  # interval + | NA on a vector: na-aware between, no missing-value rejection
  g <- gen("numeric in [0, 1] | NA")
  expect_equal(g, c("assert_double(x)", "assert_between(x, lower = 0, upper = 1, na_ok = TRUE)"))
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
  expect_equal(gen("R6<Engine>"), 'assert_class(x, "Engine")')
  expect_equal(gen("any"), character())
  expect_equal(gen("scalar<any>"), "assert_length(x, 1L)")
  expect_equal(gen("vector<any, 3>"), "assert_length(x, 3L)")
  expect_equal(gen("data.table"), "assert_data_table(x)")
  expect_equal(gen("list<character>"), c("assert_list(x)", 'assert_list_of(x, "character")'))
  expect_equal(gen("list<any>"), "assert_list(x)")
  # richer list element -> element-wise loop
  g <- gen("list<R6<Engine>>")
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
