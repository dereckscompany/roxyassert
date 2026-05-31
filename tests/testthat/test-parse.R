# Tests for the annotation parser (R/parse.R). parse_annotation() is internal.

test_that("a bare atomic parses as a vector", {
  a <- parse_annotation("(numeric) the value.")
  expect_equal(a$kind, "slot")
  expect_false(a$null_ok)
  t <- a$alternatives[[1]]
  expect_equal(t$kind, "atomic")
  expect_equal(t$base, "numeric")
  expect_equal(t$shape, "bare")
  expect_null(t$length)
})

test_that("scalar / vector shapes and length forms", {
  expect_equal(parse_annotation("(scalar<character>)")$alternatives[[1]]$shape, "scalar")
  v <- parse_annotation("(vector<numeric, 1..10>)")$alternatives[[1]]
  expect_equal(v$shape, "vector")
  expect_equal(v$length, list(min = 1L, max = 10L))
  expect_equal(parse_annotation("(vector<integer, 2..>)")$alternatives[[1]]$length, list(min = 2L, max = Inf))
  expect_equal(parse_annotation("(vector<numeric, 10>)")$alternatives[[1]]$length, list(min = 10L, max = 10L))
  expect_equal(parse_annotation("(vector<character, 0..>)")$alternatives[[1]]$length, list(min = 0L, max = Inf))
})

test_that("intervals: openness + bounds captured verbatim", {
  iv <- parse_annotation("(scalar<numeric in ]0, 1]>)")$alternatives[[1]]$interval
  expect_equal(iv$lo$text, "0")
  expect_true(iv$lo_open)
  expect_equal(iv$hi$text, "1")
  expect_false(iv$hi_open)

  expect_equal(parse_annotation("(scalar<numeric in ]0, Inf[>)")$alternatives[[1]]$interval$hi$sentinel, "Inf")
  expect_equal(parse_annotation("(scalar<numeric in ]-Inf, 0]>)")$alternatives[[1]]$interval$lo$sentinel, "-Inf")
  expect_equal(parse_annotation("(scalar<numeric in [-1.5, 2.5]>)")$alternatives[[1]]$interval$lo$text, "-1.5")
})

test_that("temporal interval bounds are R expressions, captured verbatim", {
  dv <- parse_annotation('(scalar<Date in [as.Date("2024-01-01"), Inf[>)')$alternatives[[1]]$interval
  expect_equal(dv$lo$text, 'as.Date("2024-01-01")')
  expect_equal(dv$hi$sentinel, "Inf")
  # a comma inside the bound expression is not the interval comma
  pv <- parse_annotation('(scalar<POSIXct in [as.POSIXct("2024-01-01", tz = "UTC"), Inf[>)')$alternatives[[1]]$interval
  expect_equal(pv$lo$text, 'as.POSIXct("2024-01-01", tz = "UTC")')
})

test_that("sets captured verbatim; the vector length comma is respected", {
  expect_equal(
    parse_annotation('(scalar<character in c("BUY", "SELL")>)')$alternatives[[1]]$set$text,
    'c("BUY", "SELL")'
  )
  v <- parse_annotation('(vector<character in c("a", "b"), 1..10>)')$alternatives[[1]]
  expect_equal(v$set$text, 'c("a", "b")')
  expect_equal(v$length, list(min = 1L, max = 10L))
  expect_equal(parse_annotation("(character in ORDER_SIDE)")$alternatives[[1]]$set$text, "ORDER_SIDE")
})

test_that("NA, nullability, and unions", {
  expect_true(parse_annotation("(scalar<numeric | NA>)")$alternatives[[1]]$na_ok)
  expect_true(parse_annotation("(numeric | NA)")$alternatives[[1]]$na_ok)
  expect_true(parse_annotation("(scalar<numeric>?)")$null_ok)
  expect_true(parse_annotation("(scalar<numeric> | NULL)")$null_ok)

  u <- parse_annotation("(numeric | character)")
  expect_equal(length(u$alternatives), 2L)
  expect_equal(u$alternatives[[2]]$base, "character")

  # `| NA` binds to the trailing atom of a union, not the whole slot
  u2 <- parse_annotation("(numeric | character | NA)")
  expect_equal(length(u2$alternatives), 2L)
  expect_false(u2$alternatives[[1]]$na_ok)
  expect_true(u2$alternatives[[2]]$na_ok)
})

test_that("references, wildcard, list<T> and composites", {
  expect_equal(parse_annotation("(function)")$alternatives[[1]]$kind, "function")
  expect_equal(parse_annotation("(function?)")$null_ok, TRUE)
  expect_equal(parse_annotation("(R6<Engine>)")$alternatives[[1]]$class, "Engine")
  expect_equal(parse_annotation("(any)")$alternatives[[1]]$kind, "wildcard")
  expect_equal(parse_annotation("(scalar<any>)")$alternatives[[1]]$shape, "scalar")

  lt <- parse_annotation("(list<character>)")$alternatives[[1]]
  expect_equal(lt$kind, "composite")
  expect_equal(lt$element$base, "character")
  expect_null(parse_annotation("(data.table)")$alternatives[[1]]$element)
  expect_equal(parse_annotation("(list<R6<Engine>>)")$alternatives[[1]]$element$kind, "r6")
  expect_equal(parse_annotation("(R6<Reader> | R6<Writer>)")$alternatives[[2]]$class, "Writer")
})

test_that("scalar<raw> / vector<raw> / bare factor", {
  expect_equal(parse_annotation("(scalar<raw>)")$alternatives[[1]]$base, "raw")
  expect_equal(parse_annotation("(vector<raw, 32>)")$alternatives[[1]]$length, list(min = 32L, max = 32L))
  expect_equal(parse_annotation("(factor)")$alternatives[[1]]$base, "factor")
})

test_that("the everything-at-once form", {
  a <- parse_annotation("(vector<numeric in ]0, 1] | NA, 1..100>?)")
  expect_true(a$null_ok)
  t <- a$alternatives[[1]]
  expect_equal(t$shape, "vector")
  expect_equal(t$length, list(min = 1L, max = 100L))
  expect_true(t$na_ok)
  expect_true(t$interval$lo_open)
  expect_false(t$interval$hi_open)
})

test_that("no leading paren returns NULL (untyped tag is skipped)", {
  expect_null(parse_annotation("just a free-text description"))
  expect_null(parse_annotation(""))
  expect_null(parse_annotation(NA_character_))
})

test_that("invalid annotations are rejected with clear errors", {
  expect_error(parse_annotation("(complex in [0, 1])"), "interval not allowed")
  expect_error(parse_annotation("(character in [0, 1])"), "interval not allowed")
  expect_error(parse_annotation("(logical in c(TRUE, FALSE))"), "set not allowed")
  expect_error(parse_annotation("(raw in OPCODES)"), "set not allowed")
  expect_error(parse_annotation("(raw | NA)"), "not allowed on 'raw'")
  expect_error(parse_annotation("(integer in [0.5, 2.5])"), "whole number")
  expect_error(parse_annotation("(Date in [0, 1])"), "class-matching expression")
  expect_error(parse_annotation("(numeric in [Inf, 0])"), "only be the high")
  expect_error(parse_annotation("(numeric in ]-Inf, 0])"), NA) # valid: -Inf low
  expect_error(parse_annotation("(numeric in ]1, 1[)"), "empty")
  expect_error(parse_annotation("(scalar<numeric> | NA)"), "must sit inside")
  expect_error(parse_annotation("(numeric | NULL?)"), "nothing may follow")
  expect_error(parse_annotation("(R6)"), "must name a class")
  expect_error(parse_annotation("(scalar<numeric, 1>)"), "expected '>'")
  expect_error(parse_annotation("(frobnicate)"), "unknown type")
})

# ---- nested field bullets (S1 / S3) -----------------------------------------

test_that("a bulleted composite attaches its fields", {
  txt <- paste(
    "(data.table) ranked matches:",
    "- symbol (character) the pair.",
    "- score (numeric in [0, 1]) score.",
    sep = "\n"
  )
  node <- parse_annotation(txt)$alternatives[[1]]
  expect_equal(node$kind, "composite")
  expect_equal(node$base, "data.table")
  expect_equal(length(node$fields), 2L)
  expect_equal(node$fields[[1]]$name, "symbol")
  expect_equal(node$fields[[1]]$ast$alternatives[[1]]$base, "character")
  expect_equal(node$fields[[2]]$name, "score")
  expect_equal(node$fields[[2]]$ast$alternatives[[1]]$interval$hi$text, "1")
})

test_that("bullets nest by indentation, recursively", {
  txt <- paste(
    "(list) the report:",
    "- status (scalar<character>) outcome.",
    "- rows (data.table | NULL) the page:",
    "  - id (character) identifier.",
    "  - amount (numeric in ]0, Inf[ | NA) amount.",
    sep = "\n"
  )
  node <- parse_annotation(txt)$alternatives[[1]]
  expect_equal(length(node$fields), 2L)
  rows <- node$fields[[2]]
  expect_equal(rows$name, "rows")
  expect_true(rows$ast$null_ok)
  inner <- rows$ast$alternatives[[1]]
  expect_equal(inner$base, "data.table")
  expect_equal(length(inner$fields), 2L)
  expect_equal(inner$fields[[2]]$name, "amount")
  expect_true(inner$fields[[2]]$ast$alternatives[[1]]$na_ok)
})

test_that("a **bold** field name is stripped", {
  node <- parse_annotation("(list)\n- **status** (scalar<character>) outcome.")$alternatives[[1]]
  expect_equal(node$fields[[1]]$name, "status")
})

test_that("S1: bullets require a single bare composite", {
  expect_error(parse_annotation("(scalar<numeric>)\n- a (character) x."), "single bare composite")
  expect_error(parse_annotation("(data.table | data.frame)\n- a (character) x."), "union of several types")
  expect_error(parse_annotation("(list<numeric>)\n- a (character) x."), "list<T> is a leaf")
})

test_that("a composite with no bullets keeps fields NULL", {
  expect_null(parse_annotation("(data.table) just a table.")$alternatives[[1]]$fields)
})

# ---- conformance review regressions -----------------------------------------

test_that("interval bounds and call_sets balance square brackets (rexpr scan)", {
  # the grammar's own worked example: a high bound ending in a subscript
  iv <- parse_annotation('(scalar<numeric in [0, df[["t"]]]>)')$alternatives[[1]]$interval
  expect_equal(iv$lo$text, "0")
  expect_equal(iv$hi$text, 'df[["t"]]')
  expect_false(iv$hi_open)
  # a low bound containing a comma'd subscript
  iv2 <- parse_annotation("(scalar<numeric in [x[1, 2], 5]>)")$alternatives[[1]]$interval
  expect_equal(iv2$lo$text, "x[1, 2]")
  expect_equal(iv2$hi$text, "5")
  # a call_set with an operator inside a subscript
  expect_equal(parse_annotation("(numeric in VALUES[VALUES > 0])")$alternatives[[1]]$set$text, "VALUES[VALUES > 0]")
  expect_equal(parse_annotation("(integer in M[1, 2])")$alternatives[[1]]$set$text, "M[1, 2]")
  # open intervals are unaffected
  expect_true(parse_annotation("(scalar<numeric in ]0, Inf[>)")$alternatives[[1]]$interval$hi_open)
})

test_that("a nullability '?' after the closing ')' is rejected, not dropped", {
  expect_error(parse_annotation("(character)?"), "must sit inside")
  expect_error(parse_annotation("(numeric in [0, 1] | NA | character)?"), "must sit inside")
  # the in-paren form is the canonical one and works
  expect_true(parse_annotation("(character?)")$null_ok)
})

test_that("S2: inline set element types are checked (no coercion); opaque sets trusted", {
  expect_error(parse_annotation("(integer in c(1, 2, 3))"), "L")
  expect_silent(parse_annotation("(integer in c(1L, 2L, 3L))"))
  expect_error(parse_annotation("(character in c(1, 2))"), "string literal")
  expect_silent(parse_annotation('(character in c("a", "b"))'))
  expect_error(parse_annotation("(Date in c(1, 2))"), "class-matching")
  # a bare name_set / namespaced constant / index is opaque and trusted
  expect_silent(parse_annotation("(character in ORDER_SIDE)"))
  expect_silent(parse_annotation("(integer in pkg::CODES)"))
})

test_that("S: a both-sentinel interval is rejected (it bounds nothing)", {
  expect_error(parse_annotation("(scalar<numeric in ]-Inf, Inf[>)"), "degenerate|bounds nothing")
})

# ---- re-review regressions (round 2) -----------------------------------------

test_that("unions of open intervals parse (high-bound close is interval-scoped)", {
  a <- parse_annotation("(numeric in ]0, 1[ | numeric in ]2, 3])")
  expect_equal(length(a$alternatives), 2L)
  expect_equal(a$alternatives[[1]]$interval$hi$text, "1")
  expect_true(a$alternatives[[1]]$interval$hi_open)
  expect_equal(a$alternatives[[2]]$interval$hi$text, "3")
  expect_false(a$alternatives[[2]]$interval$hi_open)
  # three-way, and a subscript whose index contains '>' as a high bound
  expect_silent(parse_annotation("(numeric in ]0, 1[ | numeric in ]2, 3[ | numeric in ]4, 5[)"))
  expect_equal(parse_annotation("(scalar<numeric in [0, m[i > 0]]>)")$alternatives[[1]]$interval$hi$text, "m[i > 0]")
})

test_that("misplaced '?' is rejected inside a field bullet too, not just at top level", {
  expect_error(parse_annotation("(list)\n- cur (scalar<character>)? next."), "must sit inside")
  expect_true(parse_annotation("(list)\n- cur (scalar<character>?) next.")$alternatives[[1]]$fields[[1]]$ast$null_ok)
})

test_that("a free-text description beginning with '?' is allowed (only adjacent '?' is rejected)", {
  expect_silent(parse_annotation("(numeric) ? semantics still unknown"))
  expect_error(parse_annotation("(numeric)?"), "must sit inside")
})

test_that("a trailing-comma inline set does not raise a misleading empty-element error", {
  expect_silent(parse_annotation("(integer in c(1L,))"))
  expect_error(parse_annotation("(integer in c(1, ))"), "L") # still requires L suffix
})

# ---- promise<T> (sync-or-async returns) -------------------------------------

test_that("promise<T> records async and collapses to its resolved type", {
  a <- parse_annotation("(promise<data.table>)")
  expect_true(a$async)
  expect_equal(length(a$alternatives), 1L)
  expect_equal(a$alternatives[[1]]$kind, "composite")
  expect_equal(a$alternatives[[1]]$base, "data.table")
  b <- parse_annotation("(promise<scalar<numeric>>)")
  expect_true(b$async)
  expect_equal(b$alternatives[[1]]$shape, "scalar")
  expect_equal(b$alternatives[[1]]$base, "numeric")
})

test_that("the T | promise<T> union collapses to a single resolved T (async)", {
  a <- parse_annotation("(data.table | promise<data.table>)")
  expect_true(a$async)
  expect_equal(length(a$alternatives), 1L)
  expect_equal(a$alternatives[[1]]$base, "data.table")
  b <- parse_annotation("(promise<data.table> | data.table)")
  expect_true(b$async)
  expect_equal(length(b$alternatives), 1L)
})

test_that("promise<T> carries field bullets into the resolved composite", {
  node <- parse_annotation("(promise<data.table>)\n- id (character) i.\n- score (numeric in [0, 1]) s.")$alternatives[[
    1
  ]]
  expect_equal(node$base, "data.table")
  expect_equal(length(node$fields), 2L)
  expect_equal(node$fields[[2]]$name, "score")
})

test_that("a non-async slot has async = FALSE", {
  expect_false(parse_annotation("(scalar<numeric>)")$async)
  expect_false(parse_annotation("(data.table | NULL)")$async)
})

test_that("promise<T> needs <T>, and a heterogeneous promise union is rejected", {
  expect_error(parse_annotation("(promise)"), "resolved type")
  expect_error(parse_annotation("(numeric | promise<character>)"), "single type")
})
