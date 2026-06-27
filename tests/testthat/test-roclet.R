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
  code <- unlist(out$code, use.names = FALSE)

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
  expect_equal(length(out$code), 0L)
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
  code <- proc_code(text)
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
  code <- proc_code(text)
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
  code <- proc_code(text)
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
  code <- unlist(results$code, use.names = FALSE)

  expect_true(any(grepl("^assert_args_Store__get <- function\\(keys, limit\\)", code)))
  expect_true(any(grepl("assert_character\\(keys\\)", code)))
  expect_true(any(grepl("assert_scalar_integer\\(limit\\)", code)))
  expect_true(any(grepl("^assert_return_Store__get <- function\\(value\\)", code)))
  expect_true(any(grepl("assert_data_table\\(value\\)", code)))
  # count() has no params -> only a return helper, matching the method split.
  expect_false(any(grepl("assert_args_Store__count", code)))
  expect_true(any(grepl("^assert_return_Store__count <- function\\(value\\)", code)))
})

test_that("roclet_output repairs markdown-mangled type fragments in man/*.Rd", {
  # With markdown on, roxygen2 lowers a bare-word type fragment `<Name>` to
  # `\if{html}{\out{<Name>}}` (raw HTML a browser then eats). roclet_output must
  # rewrite those to a plain `<Name>` that renders, WITHOUT touching roxygen2's R6
  # layout tags (`\out{<hr>}`, `<div class=..>`, `</div>`), and WITHOUT disturbing
  # fragments that were never mangled (intervals, sets, comma-bearing vectors).
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "R"))
  writeLines(
    c(
      "Package: rdrepair",
      "Title: Rd repair fixture",
      "Version: 0.0.0",
      "Description: Test fixture.",
      "License: MIT + file LICENSE",
      "Encoding: UTF-8",
      'Roxygen: list(markdown = TRUE, roclets = c("namespace", "rd", "roxyassert::contract_roclet"))'
    ),
    file.path(dir, "DESCRIPTION")
  )
  writeLines(
    c(
      "#' Demo",
      "#' @param a (scalar<POSIXct>) bare atomic.",
      "#' @param b (list<class<Engine>>) nested generic.",
      "#' @param c (scalar<character>?) nullable; incidental foo<bar> and subclass<Widget> in prose.",
      "#' @param d (class<A> | class<B>) union.",
      "#' @param e (scalar<numeric in ]0, Inf[>) interval (never mangled).",
      "#' @param f (list<integer>) bare list (exercises the list branch directly).",
      "#' @param g (scalar<integer in [1, 100]>) closed interval (commonmark links it).",
      "#' @param h (scalar<numeric in [-1.5, Inf]>) closed interval, signed/Inf bounds.",
      "#' @return (promise<data.table>) result.",
      "#' @export",
      "demo <- function(a, b, c, d, e, f, g, h) NULL"
    ),
    file.path(dir, "R", "demo.R")
  )
  writeLines(
    c(
      "#' Eng",
      "#' @description An engine.",
      "#' @export",
      "Eng <- R6::R6Class('Eng', public = list(",
      "  #' @description A method.",
      "  #' @param x (scalar<POSIXct>) a time.",
      "  m = function(x) NULL))"
    ),
    file.path(dir, "R", "Eng.R")
  )
  suppressMessages(roxygen2::roxygenise(dir))

  demo <- paste(readLines(file.path(dir, "man", "demo.Rd")), collapse = "\n")
  # types render as plain <...>, with no surviving \out wrapper around them
  expect_match(demo, "(scalar<POSIXct>)", fixed = TRUE)
  expect_match(demo, "(list<class<Engine>>)", fixed = TRUE) # nested
  expect_match(demo, "(scalar<character>?)", fixed = TRUE) # nullable
  expect_match(demo, "(class<A> | class<B>)", fixed = TRUE) # union, both legs
  expect_match(demo, "(promise<data.table>)", fixed = TRUE) # @return
  expect_match(demo, "(scalar<numeric in ]0, Inf[>)", fixed = TRUE) # untouched
  expect_match(demo, "(list<integer>)", fixed = TRUE) # bare `list` branch
  # A fully-closed interval is lowered to a dangling `\link{low, high}`; the repair
  # restores the brackets and leaves no broken cross-reference behind.
  expect_match(demo, "(scalar<integer in [1, 100]>)", fixed = TRUE)
  expect_match(demo, "(scalar<numeric in [-1.5, Inf]>)", fixed = TRUE) # signed/Inf bounds
  expect_false(grepl("\\link{1, 100}", demo, fixed = TRUE))
  expect_false(grepl("\\link{-1.5, Inf}", demo, fixed = TRUE))
  expect_false(grepl("out{<POSIXct>", demo, fixed = TRUE))
  expect_false(grepl("out{<Engine>", demo, fixed = TRUE))
  # An incidental angle-bracket tag in prose must be left exactly as roxygen2 wrote
  # it. `foo` is not a category keyword; `subclass` merely ENDS in one (`class`) —
  # the `\b` left boundary means neither is rewritten (a category keyword is matched
  # only as a whole word, never as a suffix of a longer word).
  expect_match(demo, "foo\\if{html}{\\out{<bar>}}", fixed = TRUE)
  expect_match(demo, "subclass\\if{html}{\\out{<Widget>}}", fixed = TRUE)

  eng <- paste(readLines(file.path(dir, "man", "Eng.Rd")), collapse = "\n")
  expect_match(eng, "(scalar<POSIXct>)", fixed = TRUE) # method param repaired
  expect_match(eng, "\\out{<hr>}", fixed = TRUE) # R6 layout <hr> preserved
  expect_match(eng, '\\out{<div class="r">}', fixed = TRUE) # layout preserved
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
  code <- proc_code(text)
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
  code <- proc_code(text)
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
  code <- proc_code(text)
  expect_true(any(grepl("^assert_args_with_logging <- function\\(p\\)", code)))
  expect_true(any(grepl("assert_data_table\\(p\\)", code)))
  # promise-agnostic in @param position too: no then()/is.promise emitted
  expect_false(any(grepl("promises::then|is\\.promise", code)))
})

test_that("@noassert documents a param's type but generates no check (plain fn)", {
  text <- "
    #' F.
    #' @param a (scalar<character>) one.
    #' @param b (scalar<numeric>) two.
    #' @noassert a
    #' @export
    f <- function(a, b) NULL
  "
  code <- proc_code(text)
  expect_true(any(grepl("^assert_args_f <- function\\(b\\)", code)))
  expect_true(any(grepl("assert_scalar_double\\(b\\)", code)))
  expect_false(any(grepl("assert_scalar_character", code))) # a's check is skipped
})

test_that("a bare @noassert makes the whole function documented-only", {
  text <- "
    #' F.
    #' @param a (scalar<character>) one.
    #' @noassert
    #' @export
    f <- function(a) NULL
  "
  expect_length(proc_code(text), 0L)
})

test_that("@noassert naming an undocumented param is an error", {
  text <- "
    #' F.
    #' @param a (scalar<character>) one.
    #' @noassert zzz
    #' @export
    f <- function(a) NULL
  "
  expect_error(roxygen2::roc_proc_text(contract_roclet(), text), "not documented")
})

test_that("@noassert works on an R6 method param", {
  text <- "
    #' @title Store
    #' @description A store.
    Store <- R6::R6Class('Store',
      public = list(
        #' @description Get.
        #' @param keys (character) keys.
        #' @param limit (scalar<count in [1, Inf[>?) max rows.
        #' @noassert keys
        get = function(keys, limit = NULL) NULL
      )
    )
  "
  code <- proc_code(text)
  expect_true(any(grepl("^assert_args_Store__get <- function\\(limit\\)", code)))
  expect_true(any(grepl("assert_scalar_count\\(limit\\)", code)))
  expect_false(any(grepl("assert_character\\(keys\\)", code))) # keys skipped
})
