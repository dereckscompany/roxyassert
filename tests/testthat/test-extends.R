# Tests for @type record DERIVATION: `extends` (single / multiple inheritance),
# override-by-redeclaration, and pick / omit projection — both as named @type
# definitions and inline in @param / @return. End-to-end via the roclet
# (proc_code), with a few parse/resolve unit checks.

rt <- function(text) proc_code(text)
err <- function(text) tryCatch(rt(text), error = function(e) conditionMessage(e))
noref <- "#' F.\n#' @export\nf <- function() NULL"

# A base record reused across cases.
order <- "#' @type Order (data.table):\n#' - id (character) the id.\n#' - status (character) the state.\n"

# ---- inherit + add ----------------------------------------------------------

test_that("extends inherits the base columns and appends new ones, in order", {
  text <- paste0(
    order,
    "NULL\n",
    "#' @type OrderMod (extends Order):\n#' - old (character) prior id.\n#' - new (character) new id.\nNULL\n",
    "#' F.\n#' @return (OrderMod) x.\n#' @export\nf <- function() NULL"
  )
  code <- rt(text)
  expect_true(any(grepl('assert_data_table\\(value\\)', code)))
  expect_true(any(grepl('assert_has_columns\\(value, c\\("id", "status", "old", "new"\\)\\)', code)))
  # an inherited column keeps its own check
  expect_true(any(grepl('assert_character\\(value\\[\\["id"\\]\\]\\)', code)))
  # a new column is checked too
  expect_true(any(grepl('assert_character\\(value\\[\\["new"\\]\\]\\)', code)))
})

test_that("a bare extends (no new columns) is an alias for the base", {
  text <- paste0(order, "NULL\n", "#' @type OrderCopy (extends Order)\nNULL\n",
    "#' F.\n#' @return (OrderCopy) x.\n#' @export\nf <- function() NULL")
  code <- rt(text)
  expect_true(any(grepl('assert_has_columns\\(value, c\\("id", "status"\\)\\)', code)))
})

# ---- override ---------------------------------------------------------------

test_that("redeclaring a column overrides it in place (position kept, type changed)", {
  text <- paste0(
    order, "NULL\n",
    "#' @type OrderI (extends Order):\n#' - status (integer) numeric state.\nNULL\n",
    "#' F.\n#' @return (OrderI) x.\n#' @export\nf <- function() NULL"
  )
  code <- rt(text)
  # still two columns, status still in second position
  expect_true(any(grepl('assert_has_columns\\(value, c\\("id", "status"\\)\\)', code)))
  # status now lowers to the integer check, not character
  expect_true(any(grepl('assert_integer\\(value\\[\\["status"\\]\\]\\)', code)))
  expect_false(any(grepl('assert_character\\(value\\[\\["status"\\]\\]\\)', code)))
})

# ---- multiple inheritance ---------------------------------------------------

test_that("extends merges columns from several bases", {
  text <- paste0(
    "#' @type A (data.table):\n#' - a (character) x.\nNULL\n",
    "#' @type B (data.table):\n#' - b (numeric) y.\nNULL\n",
    "#' @type C (extends A, B):\n#' - c (logical) z.\nNULL\n",
    "#' F.\n#' @return (C) x.\n#' @export\nf <- function() NULL"
  )
  code <- rt(text)
  expect_true(any(grepl('assert_has_columns\\(value, c\\("a", "b", "c"\\)\\)', code)))
})

test_that("a column shared by two bases errors unless the child redeclares it", {
  defs <- paste0(
    "#' @type A (data.table):\n#' - x (character) ax.\nNULL\n",
    "#' @type B (data.table):\n#' - x (numeric) bx.\nNULL\n"
  )
  # unresolved collision
  bad <- paste0(defs, "#' @type C (extends A, B)\nNULL\n", noref)
  expect_match(err(bad), "defined by more than one base")
  # resolved by an override in the child
  good <- paste0(defs, "#' @type C (extends A, B):\n#' - x (logical) cx.\nNULL\n",
    "#' F.\n#' @return (C) x.\n#' @export\nf <- function() NULL")
  code <- rt(good)
  expect_true(any(grepl('assert_logical\\(value\\[\\["x"\\]\\]\\)', code)))
})

test_that("bases of different kinds error", {
  defs <- paste0(
    "#' @type L (list):\n#' - a (character) x.\nNULL\n",
    "#' @type T (data.table):\n#' - b (numeric) y.\nNULL\n"
  )
  expect_match(err(paste0(defs, "#' @type X (extends L, T)\nNULL\n", noref)), "mixed kinds")
})

# ---- pick / omit ------------------------------------------------------------

test_that("pick keeps only the named columns; omit drops them", {
  text <- paste0(
    order, "NULL\n",
    "#' @type OnlyId (extends Order pick id)\nNULL\n",
    "#' @type NoStatus (extends Order omit status)\nNULL\n",
    "#' F.\n#' @param a (OnlyId) one.\n#' @return (NoStatus) two.\n#' @export\nf <- function(a) NULL"
  )
  code <- rt(text)
  expect_true(any(grepl('assert_has_columns\\(a, c\\("id"\\)\\)', code)))
  expect_true(any(grepl('assert_has_columns\\(value, c\\("id"\\)\\)', code)))
})

test_that("pick/omit error on an unknown column or when used together", {
  base <- paste0(order, "NULL\n")
  expect_match(err(paste0(base, "#' @type P (extends Order pick nope)\nNULL\n", noref)), "pick.*not in the base")
  expect_match(err(paste0(base, "#' @type O (extends Order omit nope)\nNULL\n", noref)), "omit.*not in the base")
  # pick and omit on one head -> dedicated error (you cannot use both).
  both <- paste0(base, "#' @type PO (extends Order pick id omit status)\nNULL\n", noref)
  expect_match(err(both), "cannot both be used")
})

# ---- errors: unknown base, cycle, non-composite -----------------------------

test_that("extends errors: unknown base, cycle, non-record base", {
  expect_match(err(paste0("#' @type D (extends Nope)\nNULL\n", noref)), "unknown type")
  expect_match(err(paste0(
    "#' @type A (extends B):\n#' - a (character) x.\nNULL\n",
    "#' @type B (extends A):\n#' - b (character) y.\nNULL\n", noref
  )), "cyclic")
  expect_match(err(paste0(
    "#' @type Sc (scalar<numeric>)\nNULL\n",
    "#' @type D (extends Sc)\nNULL\n", noref
  )), "must be a record type")
})

# ---- transitive -------------------------------------------------------------

test_that("a derived type can itself be extended (transitive)", {
  text <- paste0(
    order, "NULL\n",
    "#' @type A (extends Order):\n#' - a (character) x.\nNULL\n",
    "#' @type B (extends A):\n#' - b (character) y.\nNULL\n",
    "#' F.\n#' @return (B) x.\n#' @export\nf <- function() NULL"
  )
  code <- rt(text)
  expect_true(any(grepl('assert_has_columns\\(value, c\\("id", "status", "a", "b"\\)\\)', code)))
})

# ---- inline derivation ------------------------------------------------------

test_that("extends works inline in @return and @param (no name needed)", {
  text <- paste0(
    order, "NULL\n",
    "#' F.\n",
    "#' @param legs (extends Order pick id) the legs.\n",
    "#' @return (extends Order):\n#' - extra (character) bonus.\n",
    "#' @export\nf <- function(legs) NULL"
  )
  code <- rt(text)
  expect_true(any(grepl('assert_has_columns\\(legs, c\\("id"\\)\\)', code)))
  expect_true(any(grepl('assert_has_columns\\(value, c\\("id", "status", "extra"\\)\\)', code)))
})

# ---- @genassert on a derived type -------------------------------------------

test_that("@genassert builds a standalone validator for a derived @type", {
  text <- paste0(
    order, "NULL\n",
    "#' @type OrderMod (extends Order):\n#' - old (character) prior.\n#' @genassert\nNULL"
  )
  code <- rt(text)
  expect_true(any(grepl('^assert_type_OrderMod <- function\\(value\\)', code)))
  expect_true(any(grepl('assert_has_columns\\(value, c\\("id", "status", "old"\\)\\)', code)))
})

# ---- parse-level units ------------------------------------------------------

test_that("parse_annotation captures extends, pick and omit", {
  d <- parse_annotation("(extends Order)")$alternatives[[1]]
  expect_equal(d$kind, "composite")
  expect_equal(d$extends, "Order")
  expect_equal(parse_annotation("(extends A, B)")$alternatives[[1]]$extends, c("A", "B"))
  expect_equal(parse_annotation("(extends Order pick id, status)")$alternatives[[1]]$pick, c("id", "status"))
  expect_equal(parse_annotation("(extends Order omit status)")$alternatives[[1]]$omit, "status")
})

# ---- pick/omit vs multi-base collisions -------------------------------------

test_that("pick/omit can resolve a multi-base collision; an unresolved one still errors", {
  defs <- paste0(
    "#' @type A (data.table):\n#' - x (character) ax.\n#' - y (character) ay.\nNULL\n",
    "#' @type B (data.table):\n#' - x (numeric) bx.\n#' - z (numeric) bz.\nNULL\n"
  )
  ret <- "#' F.\n#' @return (C) v.\n#' @export\nf <- function() NULL"
  # omit the colliding column -> succeeds with the rest
  expect_true(any(grepl(
    'assert_has_columns\\(value, c\\("y", "z"\\)\\)',
    rt(paste0(defs, "#' @type C (extends A, B omit x)\nNULL\n", ret))
  )))
  # pick a non-colliding subset -> succeeds
  expect_true(any(grepl(
    'assert_has_columns\\(value, c\\("y", "z"\\)\\)',
    rt(paste0(defs, "#' @type C (extends A, B pick y, z)\nNULL\n", ret))
  )))
  # a collision NOT removed by the projection still errors
  expect_match(err(paste0(defs, "#' @type C (extends A, B pick x, y)\nNULL\n", noref)), "more than one base")
})

test_that("override resolving a collision keeps the inherited position", {
  defs <- paste0(
    "#' @type A (data.table):\n#' - x (character) ax.\n#' - y (character) ay.\nNULL\n",
    "#' @type B (data.table):\n#' - x (numeric) bx.\n#' - z (numeric) bz.\nNULL\n"
  )
  code <- rt(paste0(defs, "#' @type C (extends A, B):\n#' - x (logical) cx.\nNULL\n",
    "#' F.\n#' @return (C) v.\n#' @export\nf <- function() NULL"))
  # x keeps first (A's) position; columns x, y, z; x now logical
  expect_true(any(grepl('assert_has_columns\\(value, c\\("x", "y", "z"\\)\\)', code)))
  expect_true(any(grepl('assert_logical\\(value\\[\\["x"\\]\\]\\)', code)))
})

# ---- richer column types in derived records ---------------------------------

test_that("a derived record can inherit/add list<T> and nullable columns", {
  text <- paste0(
    "#' @type Base (data.table):\n#' - id (character) id.\n#' - note (character | NULL) optional.\nNULL\n",
    "#' @type Tagged (extends Base):\n#' - tags (list<character>) a list-column.\nNULL\n",
    "#' F.\n#' @return (Tagged | NULL) maybe.\n#' @export\nf <- function() NULL"
  )
  code <- rt(text)
  expect_true(any(grepl('assert_has_columns\\(value, c\\("id", "note", "tags"\\)\\)', code)))
  expect_true(any(grepl('assert_list_of\\(value\\[\\["tags"\\]\\], "character"\\)', code)))
  # nullable derived return wraps the whole expansion
  expect_true(any(grepl('if \\(!is.null\\(value\\)\\)', code)))
  # the inherited nullable column wraps its own check
  expect_true(any(grepl('if \\(!is.null\\(value\\[\\["note"\\]\\]\\)\\)', code)))
})

test_that("a derived type works inside list<> and promise<>", {
  text <- paste0(
    order, "NULL\n",
    "#' @type Mod (extends Order):\n#' - old (character) prior.\nNULL\n",
    "#' F.\n#' @param xs (list<Mod>) many.\n#' @return (promise<Mod>) async one.\n#' @export\nf <- function(xs) NULL"
  )
  code <- rt(text)
  expect_true(any(grepl('assert_list\\(xs\\)', code)))
  expect_true(any(grepl('for \\(.x in xs\\)', code)))
  # promise<Mod> validates the resolved record
  expect_true(any(grepl('assert_has_columns\\(value, c\\("id", "status", "old"\\)\\)', code)))
})

test_that("extends works inline in an R6 method @return", {
  text <- paste0(order, "NULL\n", "
    #' @title Engine
    #' @description An engine.
    Engine <- R6::R6Class('Engine',
      public = list(
        #' @description Modify an order.
        #' @return (extends Order):
        #' - extra (character) bonus.
        modify = function() NULL
      )
    )
  ")
  code <- rt(text)
  expect_true(any(grepl('^assert_return_Engine__modify <- function\\(value\\)', code)))
  expect_true(any(grepl('assert_has_columns\\(value, c\\("id", "status", "extra"\\)\\)', code)))
})

# ---- more error paths -------------------------------------------------------

test_that("derivation rejects malformed forms with clear errors", {
  base <- paste0(order, "NULL\n")
  # duplicate base
  expect_match(err(paste0(base, "#' @type D (extends Order, Order)\nNULL\n", noref)), "more than once")
  # duplicate local column
  expect_match(err(paste0(base,
    "#' @type D (extends Order):\n#' - new (character) a.\n#' - new (integer) b.\nNULL\n", noref)), "more than once")
  # restating the inherited kind
  expect_match(err(paste0(base, "#' @type D (data.table extends Order)\nNULL\n", noref)), "inherited from the base")
  # redeclaring a column that pick/omit removed
  expect_match(err(paste0(base,
    "#' @type D (extends Order omit status):\n#' - status (integer) s.\nNULL\n", noref)), "excluded by pick/omit")
  # a derivation keyword cannot be a @type name
  expect_match(err(paste0("#' @type extends (data.table):\n#' - a (character) x.\nNULL\n", noref)), "shadow")
})

test_that("@noassert suppresses a derived-typed parameter's check", {
  text <- paste0(
    order, "NULL\n",
    "#' @type Mod (extends Order):\n#' - old (character) prior.\nNULL\n",
    "#' F.\n#' @param m (Mod) the mod.\n#' @noassert m\n#' @export\nf <- function(m) NULL"
  )
  code <- rt(text)
  expect_false(any(grepl('assert_has_columns\\(m,', code)))
})
