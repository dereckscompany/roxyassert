
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

## Key ideas

- **One source of truth.** The typed `@param`/`@return` you write for
  humans *is* what generates the runtime checks — they can never drift.
- **No magic, no coercion.** Value constraints (ranges, sets) are plain
  R expressions **copied verbatim** into the generated check. You write
  `as.POSIXct("2024-01-01", tz = "America/New_York")` and roxyassert
  pastes it — it never guesses a format, a constructor, or a time zone
  on your behalf.
- **An open *value* universe.** Interval bounds and set elements are
  arbitrary R, so you can range- or membership-check against *any* value
  type — `Date`, `POSIXct`,
  [`lubridate`](https://lubridate.tidyverse.org/), `bit64`, your own
  classes — without roxyassert having to “know about” it. (The set of
  *declared* types is fixed; `any` is the wildcard for a value you
  deliberately don’t constrain.)
- **Readable, debuggable output.** The generated helpers are ordinary
  `assert` calls in a committed file you can open, read, and step
  through.

## How it works

      R/*.R  (your code + typed roxygen tags)
         |
         |   devtools::document()   <- roxyassert runs here, as a roclet
         v
      R/contracts-generated.R       <- generated assert_args_* / assert_return_* helpers
         |
         |   you call them inside your functions, and commit the file
         v
      runtime validation via the `assert` package

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

This section is the working overview; the [complete grammar
reference](https://dereckscompany.github.io/roxyassert/articles/grammar.html)
(formal EBNF, type categories, precedence, and exhaustive demos) is the
authoritative specification.

**Default arity follows R: a bare *atomic* type is a *vector* of any
length.** A scalar (length 1) is declared explicitly with `scalar<...>`.
(Reference types — `function`/`R6` — are length-1, and a bare composite
is an unconstrained list/table.)

The `<>` generic wraps the **element type** (and, for `vector`, its
length); the whole-argument modifiers sit outside it:

- **Shape (`<>`):** `scalar<...>`, `vector<..., length>`, `R6<...>`. A
  **bare *atomic* type is already a vector**, so you only reach for `<>`
  when you need length 1 (`scalar`), an explicit length, or an R6 class.
- **Element constraints:** `in <interval-or-set>` and `| NA` attach to
  the *element type* — **bare or wrapped**. `(numeric in [0, Inf[)` is a
  non-negative numeric vector; `(scalar<numeric in [0, Inf[>)` is a
  single non-negative number.
- **Slot (whole argument):** a trailing `?` (may be `NULL`) and `|`
  type-unions.

The bracket / token reference:

- `< >` — generics: `scalar` / `vector` wrap the element type (+
  length), `R6` names a class.
- `[ ] / ] [` — a numeric **interval** (`[`/`]` closed, `]`/`[` open,
  ISO/Bourbaki).
- `in` — a value-constraint on the element type: an interval, or an R
  set.
- `c(...)` / a name — a **set** of allowed values (an enum).
- `,` — a vector **length** (inside `<>`).
- `| NA` — elements may be `NA` (bare or wrapped); default: **not**
  allowed.
- `?` / `| NULL` — the whole argument may be `NULL` (slot level).
- `| <type>` — a union with another type, e.g. `numeric | character`.

The `|` operator is read by what follows it: **`NA`** = elements may be
missing, **`NULL`** = the whole argument may be `NULL`, anything else =
a **type union**.

### Base types

The type token in an annotation or a column/field bullet (subject to the
per-category rules — `scalar<>`/`vector<>` wrap only atomics and `any`;
`function`/`R6`/`data.table`/`data.frame` are written bare; `list` is
written bare, refined by bullets, or parameterised as `list<T>`):

| Type | R meaning |
|----|----|
| `logical` | `TRUE`/`FALSE` vector |
| `integer` | integer vector |
| `numeric` | double vector |
| `complex` | complex vector |
| `character` | character vector |
| `raw` | raw vector |
| `factor` | factor |
| `Date` | `Date` vector |
| `POSIXct` | date-time vector |
| `any` | any R object — no type check (the wildcard) |
| `list` | list — bare = unconstrained; `list<T>` = homogeneous; + bullets = named record |
| `function` | a function/closure (a bare, length-1 reference) |
| `data.table` | a `data.table` (see composite form) |
| `data.frame` | a `data.frame` (see composite form) |
| `R6<Class>` | an R6 instance inheriting `Class` (a bare, length-1 reference) |

`function` and `R6<Class>` are **reference types**: written bare
(`(function)`, `(R6<Engine>)`), nullable as a slot (`(R6<Engine>?)`),
never wrapped in `scalar<>`/`vector<>` and never carrying
`in`/`| NA`/length. Intervals (`in [ , ]`) apply to the ordered types
(`integer`/`numeric`/`Date`/`POSIXct`); sets (`in c(...)`) apply to the
ordered and enumerable atomics
(`integer`/`numeric`/`Date`/`POSIXct`/`character`/`factor`) — `complex`,
`logical`, `raw`, and `any` take no set. `any` asserts nothing about
type (length/nullability only). See the [grammar
reference](https://dereckscompany.github.io/roxyassert/articles/grammar.html)
for the full per-category rules.

### Inline forms

- vector of any length (default) — `(character)`
- scalar (length 1) — `(scalar<character>)`
- exactly *n* — `(vector<numeric, 10>)`
- length range / at least *n* — `(vector<numeric, 1..10>)` /
  `(vector<numeric, 2..>)`
- between 1 and 5 (inclusive) — `(scalar<numeric in [1, 5]>)`
- greater than 0 — `(scalar<numeric in ]0, Inf[>)`
- at most 1 — `(scalar<numeric in ]-Inf, 1]>)`
- every element of a vector in a range — `(numeric in [1, 5])`
- enum, inline set (scalar) — `(scalar<character in c("BUY", "SELL")>)`
- enum, vector from a constant — `(character in ORDER_SIDE)`
- `NA` elements allowed — `(numeric | NA)`
- nullable slot — `(scalar<numeric>?)` ≡ `(scalar<numeric> | NULL)` (use
  one, not both)
- union of types — `(numeric | character)`
- R6 instance — `(R6<Engine>)`
- any (no type check) — `(any)`
- homogeneous list / list-column — `(list<character>)` / `(list<any>)`

Everything composes. For example `(vector<numeric in ]0, 1] | NA, 10>)`
means: a numeric vector of length 10, every element in `(0, 1]`, `NA`
allowed.

### Composite types — nested bullets

`list`, `data.table`, and `data.frame` describe their contents as a
**markdown bullet list** beneath the tag. Bullets nest arbitrarily, so
you can compose tables inside lists inside lists. Each bullet is
`- name (type) description`; a `:` after the `)` is tolerated but
optional, and **bold around the name is optional**
(`- **name** (type) ...` also works).

``` r
#' @return (list) the query result:
#' - ok (scalar<logical>) whether the query succeeded.
#' - rows (data.table) matched rows:
#'   - id (character) row identifier.
#'   - value (numeric in [0, Inf[) the (non-negative) value.
#' - meta (list) pagination metadata:
#'   - page (scalar<integer in [1, Inf[>) current page.
#'   - cursor (scalar<character>?) next-page cursor, or NULL at the end.
```

A column declared with an **atomic** type is checked for that type, so a
column declared `(numeric)` that actually holds a list **fails** — the
intended way to catch an accidental list-column. To declare one *on
purpose*, type it `list<T>` (each cell a `T`) or `list<any>` (arbitrary
cells). `list<T>` is also how you write any homogeneous list —
`list<function>` (callbacks), `list<R6<Model>>` (model objects):

``` r
#' @return (data.table) rows:
#' - id (character) identifier.
#' - tags (list<character>) a list-column; each cell a character vector.
#' - meta (list<any>) a list-column of arbitrary cells (unchecked).
```

## Quick example

``` r
#' Submit an order.
#'
#' @param symbol (scalar<character>) normalised `BASE/QUOTE` pair.
#' @param side (scalar<character in c("BUY", "SELL")>) order side.
#' @param quantity (scalar<numeric in ]0, Inf[>) order size (positive).
#' @param price_limit (scalar<numeric in ]0, Inf[>?) limit price; `NULL` for market orders.
#' @return (data.table) the accepted order:
#' - order_id (character) exchange order id.
#' - status (character) order status.
#' - quantity (numeric) accepted size.
#' - datetime (POSIXct) acceptance time.
#' @export
submit_order <- function(symbol, side, quantity, price_limit = NULL) {
  assert_args_submit_order(symbol, side, quantity, price_limit)   # generated
  result <- ...
  return(assert_return_submit_order(result))                      # generated
}
```

## Demos

### Deeply nested composition

``` r
#' Run a report.
#'
#' @param symbols (character) one or more `BASE/QUOTE` pairs.
#' @param top_n (scalar<integer in [1, Inf[>) how many rows to keep.
#' @return (list) the report:
#' - status (scalar<character in c("ok", "partial", "failed")>) outcome.
#' - result (list) the payload:
#'   - rows (data.table) ranked rows:
#'     - symbol (character) the pair.
#'     - score (numeric in [0, Inf[) rank score.
#'   - pagination (list) cursor state:
#'     - page (scalar<integer in [1, Inf[>) current page.
#'     - cursor (scalar<character>?) next cursor, or NULL at the end.
#' - diagnostics (list) run diagnostics:
#'   - warnings (character) messages (possibly length 0).
#'   - timings (list) millisecond timings:
#'     - parse_ms (scalar<numeric in [0, Inf[>) parse time.
#'     - run_ms (scalar<numeric in [0, Inf[>) run time.
#' @export
report <- function(symbols, top_n) {
  assert_args_report(symbols, top_n)
  result <- ...
  return(assert_return_report(result))
}
```

### A data.table with mixed column types

``` r
#' Open orders for a symbol.
#'
#' @param symbol (scalar<character>) the pair.
#' @param statuses (character in c("OPEN", "PARTIALLY_FILLED")) statuses to include.
#' @return (data.table) the open orders, newest first:
#' - order_id (character) exchange id.
#' - side (factor) BUY or SELL.
#' - quantity (numeric in ]0, Inf[) remaining size.
#' - reduce_only (logical) reduce-only flag.
#' - created_at (POSIXct) submission time.
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
  `return(assert_return_fn(x))` or keep your own `invisible()`.
- **`invisible()` is irrelevant** — generation depends only on a typed
  `@return`, not on how the value is returned.
- **R6 methods are scoped by class.** Method `submit` on class `Engine`
  generates `assert_args_Engine__submit` (double-underscore separator),
  so two classes sharing a method name never collide; clashes abort
  generation rather than overwrite.
- **Internal, undocumented, committed.** Generated helpers are not
  exported and carry no `.Rd`; they live in a single
  `R/contracts-generated.R` (with a do-not-edit banner) that you commit
  like `NAMESPACE`. Each package generates and uses its own.
- **Using them is optional.** The helpers are generated for you
  regardless; *calling* them is opt-in. Adopt them in one function, a
  few, or all — a function with no typed tags is simply left alone.

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

MIT © Dereck Mezquita. See [LICENSE](LICENSE) for details.

## Citation

``` r
citation("roxyassert")
```
