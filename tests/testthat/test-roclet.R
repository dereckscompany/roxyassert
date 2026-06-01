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

test_that("R6 method contracts generate through the real on-disk document() path", {
  # The roc_proc_text() path above parses in-memory text, where the tag's file
  # is "<text>" but the method's file is a tempfile. roxygen2 8.0.0 special-cases
  # "<text>" in find_method_for_tag(); 7.3.x does not, so that path cannot
  # exercise 7.x faithfully. A real package documents files on disk, where the
  # tag and the method share the same source file -- the path that matters in
  # production. This parses an on-disk package and runs the contract roclet over
  # it, so the R6 method-tag association is tested end to end on whatever
  # roxygen2 is installed (the original crash and the silent-empty failure both
  # live here, not in the isolated .ra_r6_is_method_tag unit test).
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "R"))
  writeLines(
    c(
      "Package: r6ondisk",
      "Title: On-disk R6 generation fixture",
      "Version: 0.0.0",
      "Description: Test fixture.",
      "License: MIT + file LICENSE",
      "Encoding: UTF-8"
    ),
    file.path(dir, "DESCRIPTION")
  )
  writeLines(
    c(
      "#' @title Store",
      "#' @description A store of records.",
      "Store <- R6::R6Class('Store',",
      "  public = list(",
      "    #' @description Get records by key.",
      "    #' @param keys (character) keys to fetch.",
      "    #' @param limit (scalar<integer in [1, Inf[>?) optional max rows.",
      "    #' @return (data.table) the records.",
      "    get = function(keys, limit = NULL) NULL,",
      "    #' @description Count records.",
      "    #' @return (scalar<integer in [0, Inf[>) the count.",
      "    count = function() NULL",
      "  )",
      ")"
    ),
    file.path(dir, "R", "Store.R")
  )

  # parse_package() reads the files from disk, so tags and methods carry the
  # real source path (not "<text>"). roclet_process() for the contract roclet
  # does not use `env`, so a dummy is fine.
  blocks <- suppressMessages(roxygen2::parse_package(dir))
  results <- roxygen2::roclet_process(contract_roclet(), blocks, env = NULL, base_path = dir)
  code <- unlist(results, use.names = FALSE)

  expect_true(any(grepl("^assert_args_Store__get <- function\\(keys, limit\\)", code)))
  expect_true(any(grepl("assert_character\\(keys\\)", code)))
  expect_true(any(grepl("assert_scalar_integer\\(limit\\)", code)))
  expect_true(any(grepl("^assert_return_Store__get <- function\\(value\\)", code)))
  expect_true(any(grepl("assert_data_table\\(value\\)", code)))
  # count() has no params -> only a return helper, matching the method split.
  expect_false(any(grepl("assert_args_Store__count", code)))
  expect_true(any(grepl("^assert_return_Store__count <- function\\(value\\)", code)))
})

test_that(".ra_r6_is_method_tag classifies method vs class tags across roxygen2 versions", {
  # An explicit r6method binding (roxygen2 >= 8.0.0) is always a method tag.
  expect_true(.ra_r6_is_method_tag(list(r6method = "get", line = 1L), list(line = 99L)))
  # Otherwise the rule is positional: a tag inline in the class body (at or below
  # the class's definition line) documents a method; one above documents the
  # class / constructor. This is computed directly, so it holds on roxygen2 7.x
  # (which lacks the `r6_tag_type` internal) as well as 8.x.
  expect_true(.ra_r6_is_method_tag(list(line = 12L), list(line = 10L)))
  expect_true(.ra_r6_is_method_tag(list(line = 10L), list(line = 10L)))
  expect_false(.ra_r6_is_method_tag(list(line = 4L), list(line = 10L)))
  # Degenerate inputs never misfire as a method tag, and never error: a missing
  # or NA line on either the tag or the class returns FALSE rather than tripping
  # the comparison (note `is.na(NULL)` is logical(0), which would break an `if`).
  expect_false(.ra_r6_is_method_tag(list(line = NA_integer_), list(line = 10L)))
  expect_false(.ra_r6_is_method_tag(list(line = 5L), list(line = NA_integer_)))
  expect_false(.ra_r6_is_method_tag(list(line = 5L), list()))
  expect_false(.ra_r6_is_method_tag(list(), list(line = 10L)))
  expect_false(.ra_r6_is_method_tag(list(), list()))
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

test_that("a promise<T> @param is allowed — it lowers to the resolved-type check", {
  # a helper that takes a promise input is valid; roxyassert generates the
  # resolved-value validator and the user applies it however they like.
  text <- "
    #' Add a callback.
    #' @param p (promise<data.table>) the bars promise.
    #' @export
    with_logging <- function(p) NULL
  "
  code <- unlist(roxygen2::roc_proc_text(contract_roclet(), text), use.names = FALSE)
  expect_true(any(grepl("^assert_args_with_logging <- function\\(p\\)", code)))
  expect_true(any(grepl("assert_data_table\\(p\\)", code)))
  # promise-agnostic in @param position too: no then()/is.promise emitted
  expect_false(any(grepl("promises::then|is\\.promise", code)))
})
