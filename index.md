# roxyassert

> Write the contract once — in your roxygen2 docs — and generate the
> runtime checks.

`roxyassert` turns **structured type annotations** in your roxygen2
documentation into **per-function assertion helpers**. At `document()`
time it parses your `@param`/`@return` tags and generates argument and
return checks — plain calls to the
[`assert`](https://github.com/dereckscompany/assert) package — into a
committed source file you can read and debug.

R is **dynamically typed**: nothing stops a caller from passing a
character where you expected a number, or a function from returning the
wrong shape. The usual fix is to hand-write a validation function —
which repeats, in code, the types you already wrote in your docs, and
then drifts from them. `roxyassert` makes the **documentation the single
source of truth**: the same annotations render for humans *and* generate
the checks, so they cannot disagree.

## How it works

``` R
  R/*.R  (your code + typed roxygen tags)
     |
     |   devtools::document()   <- roxyassert runs here, as a roclet
     v
  R/contracts-generated.R       <- generated assert_args_* / assert_return_* helpers
     |
     |   you call them inside your functions, and commit the file
     v
  runtime validation via the `assert` package
```

`roxyassert` is a **roxygen2 roclet** — it runs in the documentation
step (the one that writes `NAMESPACE` and `man/*.Rd`), never during
`R CMD build`/`check`. It parses tag *text* only; it never executes your
code.

| Layer | Package | Role |
|----|----|----|
| Vocabulary | [`assert`](https://github.com/dereckscompany/assert) | Runtime primitives (`assert_scalar_character()`, `assert_data_table()`, …). |
| Generator | **`roxyassert`** | Parses typed docs -\> emits helpers that *call* `assert`. |

`assert` does not depend on `roxyassert` and stays lightweight;
`roxyassert` depends on `assert` + `roxygen2`.

## Installation

``` r

renv::install("dereckscompany/roxyassert")
# or: remotes::install_github("dereckscompany/roxyassert")
```

## Setup (one line)

Register the roclet in your package’s `DESCRIPTION`:

``` dcf
Roxygen: list(markdown = TRUE, roclets = c("namespace", "rd", "roxyassert::contract_roclet"))
```

`devtools::document()` then runs `roxyassert` alongside the built-in
roclets and (re)writes `R/contracts-generated.R`.

## The annotation grammar

A type annotation is a parenthesised token at the **start** of a
`@param` or `@return` description. Tags without a leading `(...)` token
are ignored, so adoption is incremental and opt-in.

**Default arity follows R: a bare type is a *vector* of any length.** A
scalar (length 1) is declared explicitly.

### Base types

Every type below is valid wherever a `<type>` appears (inline or in a
column/field bullet):

| Type         | R meaning                           |
|--------------|-------------------------------------|
| `logical`    | `TRUE`/`FALSE` vector               |
| `integer`    | integer vector                      |
| `numeric`    | double vector                       |
| `complex`    | complex vector                      |
| `character`  | character vector                    |
| `raw`        | raw vector                          |
| `factor`     | factor                              |
| `Date`       | `Date` vector                       |
| `POSIXct`    | date-time vector                    |
| `list`       | list (see composite form)           |
| `function`   | a function/closure                  |
| `data.table` | a `data.table` (see composite form) |
| `data.frame` | a `data.frame` (see composite form) |
| `R6<Class>`  | an R6 instance inheriting `Class`   |

### Inline forms (generics)

| Intent | Annotation |
|----|----|
| vector of any length (default) | `(character)` |
| scalar — length 1 | `(scalar<character>)` |
| exactly *n* | `(vector<numeric, 10>)` |
| length range | `(vector<numeric, 1..10>)` |
| length at least *n* | `(vector<numeric, 2..>)` |
| nullable / optional (`NULL` or missing passes) | `(numeric?)` |
| enum — inline literals | `(enum<character, "BUY" \| "SELL">)` |
| enum — from a constant/object | `(enum<character, ORDER_SIDE>)` |
| R6 instance | `(R6<Engine>)` |

The generic style is the explicit, uniform spelling: everything is
`kind<type, ...>` (the same shape as C++ templates or TypeScript’s
`Array<T>`). The `?` modifier composes, e.g. `(scalar<numeric>?)`.

### Composite types — nested bullets

`list`, `data.table`, and `data.frame` describe their contents as a
**markdown bullet list** beneath the tag. Bullets nest arbitrarily, so
you can compose tables inside lists inside lists. Each bullet is
`- name (type): description`; **bold around the name is optional**
(`- **name** (type): ...` also works).

``` r

#' @return (list) the query result:
#' - ok (scalar<logical>): whether the query succeeded.
#' - rows (data.table): matched rows:
#'   - id (character): row identifier.
#'   - value (numeric): the value.
#' - meta (list): pagination metadata:
#'   - page (scalar<integer>): current page.
#'   - cursor (character?): next-page cursor, or NULL at the end.
```

Because each leaf is checked for an atomic type, **list-columns are
rejected by construction** — a column declared `(numeric)` that holds a
list fails.

## Quick example

``` r

#' Submit an order.
#'
#' @param symbol (scalar<character>) normalised `BASE/QUOTE` pair.
#' @param side (enum<character, "BUY" | "SELL">) order side.
#' @param quantity (scalar<numeric>) order size in the base asset.
#' @param price_limit (scalar<numeric>?) limit price; `NULL` for market orders.
#' @return (data.table) the accepted order:
#' - order_id (character): exchange order id.
#' - status (character): order status.
#' - quantity (numeric): accepted size.
#' - datetime (POSIXct): acceptance time.
#' @export
submit_order <- function(symbol, side, quantity, price_limit = NULL) {
  assert_args_submit_order(symbol, side, quantity, price_limit)   # generated
  result <- ...
  return(assert_return_submit_order(result))                      # generated
}
```

## Demos

### Composed list with a nested table

``` r

#' Run a screen and return results plus diagnostics.
#'
#' @param symbols (character) one or more `BASE/QUOTE` pairs.
#' @param top_n (scalar<integer>) how many rows to keep.
#' @param weights (vector<numeric, 1..>?) optional per-symbol weights.
#' @return (list) the screen output:
#' - matched (data.table): ranked matches:
#'   - symbol (character): the pair.
#'   - score (numeric): rank score.
#'   - tags (character): label(s) on the match.
#' - summary (list): run summary:
#'   - n_in (scalar<integer>): symbols screened.
#'   - n_out (scalar<integer>): rows returned.
#'   - ran_at (scalar<POSIXct>): run timestamp.
#' @export
screen <- function(symbols, top_n, weights = NULL) {
  assert_args_screen(symbols, top_n, weights)
  result <- ...
  return(assert_return_screen(result))
}
```

### A data.table with mixed column types

``` r

#' Open orders for a symbol.
#'
#' @param symbol (scalar<character>) the pair.
#' @param statuses (enum<character, "OPEN" | "PARTIALLY_FILLED">) statuses to include.
#' @return (data.table) the open orders, newest first:
#' - order_id (character): exchange id.
#' - side (factor): BUY or SELL.
#' - quantity (numeric): remaining size.
#' - reduce_only (logical): reduce-only flag.
#' - created_at (POSIXct): submission time.
#' @export
open_orders <- function(symbol, statuses) {
  assert_args_open_orders(symbol, statuses)
  result <- ...
  return(assert_return_open_orders(result))
}
```

See the [Getting started
vignette](https://dereckscompany.github.io/roxyassert/articles/demo.html)
for a fuller pattern: an abstract class whose every method enforces its
inputs and outputs from the docs.

## Generated functions — conventions

- **Two helpers, each optional.** `assert_args_<fn>` is emitted only if
  the function has at least one typed `@param`; `assert_return_<fn>`
  only if `@return` carries a parseable type.
- **Explicit arguments.** `assert_args_<fn>(arg1, arg2, ...)` takes the
  documented parameters by name, in declaration order, so the contract
  is visible at the call site.
- **Returns are passed through.** `assert_return_<fn>(value)` validates
  and returns `value` unchanged, so you can write
  `return(assert_return_fn(x))` or keep your own
  [`invisible()`](https://rdrr.io/r/base/invisible.html).
- **[`invisible()`](https://rdrr.io/r/base/invisible.html) is
  irrelevant** — generation depends only on a typed `@return`, not on
  how the value is returned.
- **R6 methods are scoped by class.** Method `submit` on class `Engine`
  generates `assert_args_Engine__submit` (double-underscore separator),
  so two classes sharing a method name never collide; clashes abort
  generation rather than overwrite.
- **Internal, undocumented, committed.** Generated helpers are not
  exported and carry no `.Rd`; they live in a single
  `R/contracts-generated.R` (with a do-not-edit banner) that you commit
  like `NAMESPACE`. Each package generates and uses its own.
- **Using them is optional.** The helpers are generated for you
  regardless; *calling* them is opt-in. You can adopt them in one
  function, a few, or all — and a function with no typed tags is simply
  left alone.

## Why annotations, not in-code types

Packages like [`typed`](https://github.com/moodymudskipper/typed)
declare types inside the function body with a custom operator. That
works and checks at runtime, but it changes how every function is
written. `roxyassert` keeps your R code exactly as it is and treats the
documentation you already write as the contract — and because the checks
are generated *for* you, you never write a validation function by hand
again, even if you choose not to call every one.

## Status

Early development — the annotation grammar and generation conventions
documented here are the design under active implementation.

## License

MIT © Dereck Mezquita. See
[LICENSE](https://dereckscompany.github.io/roxyassert/LICENSE) for
details.

## Citation

``` r

citation("roxyassert")
```
