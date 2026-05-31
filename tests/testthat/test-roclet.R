# End-to-end tests for the contract roclet, via roxygen2::roc_proc_text().

test_that("the roclet generates arg + return helpers for a typed function", {
  text <- "
    #' Submit.
    #' @param symbol (scalar<character>) the pair.
    #' @param n (scalar<integer in [1, Inf[>) the count.
    #' @param opt (scalar<numeric>?) optional value.
    #' @return (data.table) the result.
    #' @export
    submit <- function(symbol, n, opt = NULL) NULL
  "
  out <- roxygen2::roc_proc_text(contract_roclet(), text)
  code <- unlist(out, use.names = FALSE)

  expect_true(any(grepl("^assert_args_submit <- function\\(symbol, n, opt\\) \\{", code)))
  expect_true(any(grepl("assert_scalar_character\\(symbol\\)", code)))
  expect_true(any(grepl("assert_scalar_integer\\(n\\)", code)))
  expect_true(any(grepl("assert_between\\(n, lower = 1\\)", code)))
  expect_true(any(grepl("if \\(!is.null\\(opt\\)\\)", code)))
  expect_true(any(grepl("^assert_return_submit <- function\\(value\\) \\{", code)))
  expect_true(any(grepl("assert_data_table\\(value\\)", code)))
  expect_true(any(grepl("return\\(value\\)", code)))
})

test_that("a function with no typed tags produces no helpers", {
  text <- "
    #' Plain.
    #' @param x just a description, no type.
    #' @return some value.
    #' @export
    g <- function(x) NULL
  "
  out <- roxygen2::roc_proc_text(contract_roclet(), text)
  expect_equal(length(out), 0L)
})

test_that("only annotated params enter the args helper; return-only is allowed", {
  text <- "
    #' Mixed.
    #' @param a (scalar<character>) typed.
    #' @param b untyped, skipped.
    #' @return (scalar<logical>) ok.
    #' @export
    h <- function(a, b) NULL
  "
  code <- unlist(roxygen2::roc_proc_text(contract_roclet(), text), use.names = FALSE)
  expect_true(any(grepl("^assert_args_h <- function\\(a\\) \\{", code)))
  expect_false(any(grepl("assert_args_h <- function\\(a, b\\)", code)))
  expect_true(any(grepl("^assert_return_h <- function\\(value\\)", code)))
})
