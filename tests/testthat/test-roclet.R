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

test_that("a bulleted composite @return generates field checks", {
  text <- "
    #' Report.
    #' @return (data.table) matches:
    #' - symbol (character) the pair.
    #' - score (numeric in [0, 1]) normalised score.
    #' @export
    report <- function() NULL
  "
  code <- unlist(roxygen2::roc_proc_text(contract_roclet(), text), use.names = FALSE)
  expect_true(any(grepl("^assert_return_report <- function\\(value\\)", code)))
  expect_true(any(grepl('assert_has_columns\\(value, c\\("symbol", "score"\\)\\)', code)))
  expect_true(any(grepl('assert_between\\(value\\[\\["score"\\]\\], lower = 0, upper = 1\\)', code)))
})

test_that("R6 methods generate <Class>__<method> helpers", {
  text <- "
    #' @title Store
    #' @description A store.
    Store <- R6::R6Class('Store',
      public = list(
        #' @description Get records.
        #' @param keys (character) keys to fetch.
        #' @param limit (scalar<integer in [1, Inf[>?) optional max rows.
        #' @return (data.table) the records.
        get = function(keys, limit = NULL) NULL,
        #' @description Count records.
        #' @return (scalar<integer in [0, Inf[>) the count.
        count = function() NULL
      )
    )
  "
  code <- unlist(roxygen2::roc_proc_text(contract_roclet(), text), use.names = FALSE)
  expect_true(any(grepl("^assert_args_Store__get <- function\\(keys, limit\\)", code)))
  expect_true(any(grepl("assert_character\\(keys\\)", code)))
  expect_true(any(grepl("assert_scalar_integer\\(limit\\)", code)))
  expect_true(any(grepl("^assert_return_Store__get <- function\\(value\\)", code)))
  expect_true(any(grepl("assert_data_table\\(value\\)", code)))
  # count() has no params -> no args helper, but a return helper
  expect_false(any(grepl("assert_args_Store__count", code)))
  expect_true(any(grepl("^assert_return_Store__count <- function\\(value\\)", code)))
})

test_that("annotation text + names are read from raw, not markdown-rewritten val", {
  # roxygen2 rewrites $val through markdown when enabled, mangling `<...>` into
  # `\if{html}{\out{<...>}}`; the roclet must read the pristine $raw instead.
  ptag <- list(raw = "qty (vector<numeric, 3>) sizes.", val = list(name = "qty", description = "MANGLED"))
  sp <- .ra_param_split(ptag)
  expect_equal(sp$names, "qty")
  expect_equal(sp$text, "(vector<numeric, 3>) sizes.")
  rtag <- list(raw = c("(data.table) acks:", "- id (character) the id."), val = "MANGLED")
  expect_equal(.ra_tag_text(rtag), "(data.table) acks:\n- id (character) the id.")
  # a multi-name @param with a space after the comma recovers BOTH names + text
  # (roxygen mangles $val$name to "a," here, so we must read from $raw)
  mtag <- list(raw = "a, b (scalar<numeric>) two.", val = list(name = "a,", description = "X"))
  sp2 <- .ra_param_split(mtag)
  expect_equal(sp2$names, "a, b")
  expect_equal(sp2$text, "(scalar<numeric>) two.")
})

test_that("a multi-name @param with a space ('a, b') validates both names", {
  text <- "
    #' F.
    #' @param a, b (scalar<numeric>) two values.
    #' @export
    f <- function(a, b) NULL
  "
  code <- unlist(roxygen2::roc_proc_text(contract_roclet(), text), use.names = FALSE)
  expect_true(any(grepl("^assert_args_f <- function\\(a, b\\)", code)))
  expect_true(any(grepl("assert_scalar_double\\(a\\)", code)))
  expect_true(any(grepl("assert_scalar_double\\(b\\)", code)))
})

test_that("a promise<T> @return generates a plain resolved-value validator", {
  text <- "
    #' Fetch bars.
    #' @param symbol (scalar<character>) the pair.
    #' @return (promise<data.table>) bars:
    #' - t (POSIXct) time.
    #' - close (numeric in [0, Inf[) price.
    #' @export
    get_bars <- function(symbol) NULL
  "
  code <- unlist(roxygen2::roc_proc_text(contract_roclet(), text), use.names = FALSE)
  expect_true(any(grepl("^assert_return_get_bars <- function\\(value\\)", code)))
  expect_true(any(grepl("assert_data_table\\(value\\)", code)))
  expect_true(any(grepl('assert_has_columns\\(value, c\\("t", "close"\\)\\)', code)))
  # roxyassert stays promise-agnostic: no then()/is.promise in the generated code
  expect_false(any(grepl("promises::then|is\\.promise", code)))
})

test_that("a promise<T> on @param is rejected (return-only)", {
  text <- "
    #' Bad.
    #' @param p (promise<data.table>) not allowed here.
    #' @export
    bad <- function(p) NULL
  "
  expect_error(roxygen2::roc_proc_text(contract_roclet(), text), "only valid on @return")
})
