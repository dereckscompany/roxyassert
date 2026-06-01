# Tests for the @type tag: reusable named types resolved (inline) at document()
# time. End-to-end via roxygen2::roc_proc_text(); the resolver is also unit-tested.

rt <- function(text) unlist(roxygen2::roc_proc_text(contract_roclet(), text), use.names = FALSE)

test_that("a @type expands inline wherever it is referenced", {
  text <- "
    #' @type OrderAck (data.table) an ack:
    #' - order_id (character) the id.
    #' - status (scalar<character in c('FILLED', 'REJECTED')>) outcome.
    NULL

    #' @type Bps (scalar<numeric in [0, Inf[>)
    NULL

    #' Submit.
    #' @param ack (OrderAck) the ack.
    #' @param slippage (Bps) allowed slippage.
    #' @param maybe (OrderAck?) optional ack.
    #' @return (promise<OrderAck>) async ack.
    #' @export
    submit <- function(ack, slippage, maybe) NULL
  "
  code <- rt(text)
  # the record shape expands (table + columns)
  expect_true(any(grepl('assert_has_columns\\(ack, c\\("order_id", "status"\\)\\)', code)))
  expect_true(any(grepl('assert_value_in_set\\(ack\\[\\["status"\\]\\], c\\(.FILLED., .REJECTED.\\)\\)', code)))
  # the scalar alias expands
  expect_true(any(grepl("assert_scalar_double\\(slippage\\)", code)))
  expect_true(any(grepl("assert_between\\(slippage, lower = 0", code)))
  # nullable use site wraps the expansion
  expect_true(any(grepl("if \\(!is.null\\(maybe\\)\\)", code)))
  # promise<OrderAck> return validates the resolved data.table
  expect_true(any(grepl("^assert_return_submit <- function\\(value\\)", code)))
  expect_true(any(grepl("assert_data_table\\(value\\)", code)))
  # the @type blocks themselves generate nothing
  expect_false(any(grepl("assert_(args|return)_(OrderAck|Bps)", code)))
})

test_that("a @type may build on another (transitive), and inside list<>", {
  text <- "
    #' @type Score (scalar<numeric in [0, 1]>)
    NULL
    #' @type Row (data.table) a row:
    #' - score (Score) the score.
    NULL
    #' F.
    #' @param rows (list<Row>) the rows.
    #' @return (Row) one row.
    #' @export
    f <- function(rows) NULL
  "
  code <- rt(text)
  # list<Row>: each element validated as the resolved Row table
  expect_true(any(grepl("assert_list\\(rows\\)", code)))
  expect_true(any(grepl("for \\(.x in rows\\)", code)))
  expect_true(any(grepl("assert_data_table\\(.x\\)", code)))
  # transitive: Row.score uses Score's scalar double + interval
  expect_true(any(grepl('assert_scalar_double\\(value\\[\\["score"\\]\\]\\)', code)))
  expect_true(any(grepl('assert_between\\(value\\[\\["score"\\]\\], lower = 0, upper = 1\\)', code)))
})

test_that("@type errors: unknown, duplicate, shadow, non-single-type, cycle", {
  err <- function(text) tryCatch(rt(text), error = function(e) conditionMessage(e))
  use_a <- "#' F.\n#' @return (A) x.\n#' @export\nf <- function() NULL"
  expect_match(err("#' F.\n#' @return (Nope) x.\n#' @export\nf <- function() NULL"), "unknown type")
  expect_match(err(paste0("#' @type A (numeric)\nNULL\n#' @type A (character)\nNULL\n", use_a)), "duplicate @type")
  expect_match(err("#' @type numeric (character)\nNULL\n#' F.\n#' @export\nf <- function() NULL"), "shadow")
  expect_match(err(paste0("#' @type A (numeric | character)\nNULL\n", use_a)), "single type")
  expect_match(err(paste0("#' @type A (numeric?)\nNULL\n", use_a)), "single type")
  expect_match(err(paste0("#' @type A (B)\nNULL\n#' @type B (A)\nNULL\n", use_a)), "cyclic")
})

test_that("a named type cannot sit inside scalar<>/vector<>", {
  err <- function(text) tryCatch(rt(text), error = function(e) conditionMessage(e))
  def_a <- "#' @type A (numeric)\nNULL\n"
  use <- "#' F.\n#' @param x (scalar<A>) y.\n#' @export\nf <- function(x) NULL"
  expect_match(err(paste0(def_a, use)), "atomic type or 'any'")
})

test_that("the resolver substitutes named nodes (unit level)", {
  registry <- list(Price = parse_annotation("(scalar<numeric in [0, Inf[>)")$alternatives[[1]])
  ast <- parse_annotation("(Price)")
  expect_equal(ast$alternatives[[1]]$kind, "named")
  resolved <- .ra_resolve_slot(ast, registry)
  expect_equal(resolved$alternatives[[1]]$base, "numeric")
  expect_equal(resolved$alternatives[[1]]$shape, "scalar")
  # an unknown name errors
  expect_error(.ra_resolve_slot(parse_annotation("(Missing)"), registry), "unknown type")
})
