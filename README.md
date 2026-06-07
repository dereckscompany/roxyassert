
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

## Setup

Register the roclet in your package’s `DESCRIPTION`:

``` dcf
Roxygen: list(markdown = TRUE, roclets = c("namespace", "rd", "roxyassert::contract_roclet"))
```

The generated helpers call `assert::*` functions by their bare names, so
make `assert` an import of your package — add it to `Imports` and bring
its namespace in once (e.g. a package-level `#' @import assert`):

``` dcf
Imports: assert
```

``` r
#' @import assert
NULL
```

`devtools::document()` then runs `roxyassert` alongside the built-in
roclets and (re)writes `R/contracts-generated.R`.

> **Note — a harmless markdown warning.** With `markdown = TRUE`,
> roxygen2’s link resolver sees the `[ ]` of an interval (`[0, 1]`) or a
> `[[ ]]` subscript bound in a `@param`/`@return` description and
> reports a “could not resolve link” **warning** during `document()`. It
> is cosmetic: the `.Rd` still builds and the generated checks are
> unaffected — `roxyassert` reads each tag’s untouched **raw** text,
> never the markdown-rendered version. You can ignore the warning, or
> avoid it by escaping the bracket (`\[0, 1\]`) in the description if
> your help pages must be warning-clean.

> **Note — type rendering under markdown is handled for you.** With
> `markdown = TRUE`, roxygen2 lowers a bare-word type fragment such as
> `<POSIXct>` (in `scalar<POSIXct>`, `class<Duration>`, `promise<T>`, a
> nested generic, etc.) into raw inline HTML, which a browser would
> otherwise eat as an unknown tag — hiding the type so it shows as just
> `(scalar)`. `roxyassert` repairs the generated `man/*.Rd`
> automatically so the full type renders in your help pages and pkgdown
> site. Write the `<...>` type syntax exactly as documented here; no
> backticks or escaping needed for it. (The separate `[ ]`
> interval-bracket link warning above is unrelated to rendering — the
> interval type itself renders fine.)

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
(Reference types — `function`/`class<...>` — are length-1, and a bare
composite is an unconstrained list/table.)

The `<>` generic wraps the **element type** (and, for `vector`, its
length); the whole-argument modifiers sit outside it:

- **Shape (`<>`):** `scalar<...>` (length 1) and `vector<..., length>`
  wrap an atomic element. (`class<...>` also uses `<>` but is a
  *reference type*, not a shape — see Base types.) A **bare *atomic*
  type is already a vector**, so you only reach for `scalar`/`vector`
  when you need length 1 or an explicit length.
- **Element constraints:** `in <interval-or-set>` and `| NA` attach to
  the *element type* — **bare or wrapped**. `(numeric in [0, Inf[)` is a
  non-negative numeric vector; `(scalar<numeric in [0, Inf[>)` is a
  single non-negative number.
- **Slot (whole argument):** a trailing `?` (may be `NULL`) and `|`
  type-unions.

The bracket / token reference:

- `< >` — generics: `scalar` / `vector` wrap the element type (+
  length), `class` names a class.
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
`function`/`class<...>` are reference types written bare;
`list`/`data.table`/`data.frame` are composites written bare or refined
by nested bullets, and `list` additionally as `list<T>`):

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
| `count` | non-negative whole number(s), `20` or `20L` — `assert_scalar_count` / `assert_count` (no `NA`, no set; interval-capable) |
| `any` | any R object — no type check (the wildcard) |
| `list` | list — bare = unconstrained; `list<T>` = homogeneous; + bullets = named record |
| `function` | a function/closure (a bare, length-1 reference) |
| `data.table` | a `data.table` (see composite form) |
| `data.frame` | a `data.frame` (see composite form) |
| `class<Class>` | an object of class `Class` — any object system (S3/S4/RC/R6/S7), subclasses match (a bare, length-1 reference) |
| `promise<T>` | a result resolving to `T`, delivered sync or async (see **Asynchronous returns** below) |

`function` and `class<Class>` are **reference types**: written bare
(`(function)`, `(class<Engine>)`), nullable as a slot
(`(class<Engine>?)`), never wrapped in `scalar<>`/`vector<>` and never
carrying `in`/`| NA`/length. `class<Class>` checks the value’s class
with `inherits()`, so it works for any object system (S3, S4, Reference
Classes, R6, S7) and matches subclasses (`class<AbstractClock>` accepts
a `RealClock`). `Class` names a single class, not a `pkg::Class`
reference — name the source package in prose if it helps. Intervals
(`in [ , ]`) apply to the ordered types
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
- greater than 0 and finite — `(scalar<numeric in ]0, Inf[>)` (an open
  bracket at a `±Inf` sentinel excludes that infinity; close it —
  `]0, Inf]` — to allow `Inf`)
- at most 1 and finite — `(scalar<numeric in ]-Inf, 1]>)`
- every element of a vector in a range — `(numeric in [1, 5])`
- enum, inline set (scalar) — `(scalar<character in c("BUY", "SELL")>)`
- enum, vector from a constant — `(character in ORDER_SIDE)`
- `NA` elements allowed — `(numeric | NA)`
- nullable slot — `(scalar<numeric>?)` ≡ `(scalar<numeric> | NULL)` (use
  one, not both)
- union of types — `(numeric | character)`
- a count, `20` or `20L` — `(scalar<count>)`; a positive count —
  `(scalar<count in [1, Inf[>)`
- object of a class — `(class<Engine>)`
- any (no type check) — `(any)`
- homogeneous list / list-column — `(list<character>)` / `(list<any>)`

Everything composes. For example `(vector<numeric in ]0, 1] | NA, 10>)`
means: a numeric vector of length 10, every element in `(0, 1]`, `NA`
allowed.

### Documenting a type without enforcing it — `@noassert`

A `(type)` both renders in the help page and generates a check. When a
parameter is already validated by a hand-written guard, add
**`@noassert`** so the type is still documented but no (redundant) check
is generated:

``` r
#' @param symbol (scalar<character>) a normalised BASE/QUOTE pair.
#' @noassert symbol
```

`@noassert <names>` exempts the named parameters; a bare `@noassert`
makes the whole function (or R6 method) documented-only. Exempted
parameters are still parsed and validated — only their code generation
is skipped — and naming an undocumented parameter is an error.

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
`list<function>` (callbacks), `list<class<Model>>` (model objects):

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

## Asynchronous returns — `promise<T>`

Many APIs return a result either **synchronously** (the value) or
**asynchronously** (a
[`promises::promise`](https://rstudio.github.io/promises/) that resolves
to the *same* value). roxyassert supports this with two forms:

- `promise<T>` — the function always returns a promise resolving to `T`.
- `T | promise<T>` — the function returns `T` directly **or** a promise
  resolving to `T` (e.g. a client with a per-instance `async` switch).

**The key idea: roxyassert stays promise-agnostic.** It generates a
*plain value-validator* for the resolved type `T` —
`assert_return_fn(value)` validates a `T` and returns it. It never emits
`then()` or `is.promise()`. **You** decide how to apply that validator
to your promise; because the helper is a `function(value) value`, it is
*exactly* the callback `promises::then()` wants.

> **Note:** `promise<T>` is most natural on `@return`, but roxyassert
> doesn’t police it — it’s allowed anywhere. A helper that takes a
> promise *input* (say, to attach a callback) is a fine use case; you
> just apply the generated validator to the resolved value yourself
> (e.g. inside your own `promises::then(p, ...)`).

### Always-async (`promise<T>`)

``` r
#' Fetch OHLCV bars.
#'
#' @param symbol (scalar<character>) the pair.
#' @return (promise<data.table>) bars:
#' - timestamp (POSIXct) candle open time.
#' - close (numeric in ]0, Inf[) close price.
#' @export
ohlcv = function(symbol) {
  assert_args_ohlcv(symbol)
  # validator is a then()-callback: validates on resolution, rejects on failure
  return(promises::then(private$.impl_ohlcv(symbol), assert_return_ohlcv))
}
```

The generated `assert_return_ohlcv()` is just the `data.table` + column
checks (no promise code). Dropped into `then()`, it validates the
resolved table and passes it through; a failing check rejects the
returned promise — it never blocks.

### Sync-or-async (`T | promise<T>`)

When the same method can return either shape, document the union and
branch on the mode you already know (a constructor flag, here
`private$.is_async`):

``` r
#' @return (data.table | promise<data.table>) bars:
#' - timestamp (POSIXct) candle open time.
#' - close (numeric in ]0, Inf[) close price.
ohlcv = function(symbol) {
  assert_args_ohlcv(symbol)
  result <- private$.impl_ohlcv(symbol)      # a data.table OR a promise of one
  if (private$.is_async) {
    return(promises::then(result, assert_return_ohlcv))  # async: validate on resolve
  }
  return(assert_return_ohlcv(result))                    # sync: validate now
}
```

A tidy way to capture that branch once is a tiny helper (drop it in your
package):

``` r
then_or_now <- function(x, fn, is_async) {
  if (is_async) return(promises::then(x, fn))
  return(fn(x))
}

ohlcv = function(symbol) {
  assert_args_ohlcv(symbol)
  return(then_or_now(private$.impl_ohlcv(symbol), assert_return_ohlcv, private$.is_async))
}
```

If you don’t track the mode explicitly, branch on the value instead —
`if (promises::is.promise(result)) promises::then(result, assert_return_ohlcv) else assert_return_ohlcv(result)`.

In all cases the generated validator is identical; only *your* one-line
wiring differs. (See **Known limitations** for `list<promise<T>>`.)

## Reusable types — `@type`

Repeating the same shape across many functions is tedious and drifts.
Declare it once with `@type` and reference it by name anywhere a type
appears.

Define (anywhere — e.g. `R/types.R`):

``` r
#' @type OrderAck (data.table) an order acknowledgement:
#' - order_id (character) the exchange id.
#' - status (scalar<character in c("FILLED", "REJECTED")>) outcome.
NULL

#' @type Bps (scalar<numeric in [0, Inf[>)
NULL
```

Use anywhere a type goes:

``` r
#' @param ack (OrderAck) the ack.
#' @param slippage (Bps) allowed slippage.
#' @return (promise<OrderAck>) the ack, async.
#' @return (list<OrderAck>) a batch.
```

A `@type` resolves at `document()` time by **inline expansion** — the
generated checks are identical to writing the shape out, with no runtime
cost. A `@type` may build on another
(`@type Row (data.table) - score (Score) ...`); cycles, unknown names,
and duplicate definitions are reported as errors.

Rules: a `@type` defines a *single type* — add `?` / `| NULL` / unions
at the **use site**, not the definition; references work bare, nullable,
in a union, and inside `list<…>` / `promise<…>`, but not inside
`scalar<>` / `vector<>` (define a scalar alias directly, like `Bps`).
Types are package-local.

### Deriving one type from another — `extends`, override, `pick` / `omit`

A record type can be **built from another** instead of being copied —
the same idea as TypeScript’s `interface B extends A` and `Pick` /
`Omit`.

> **One rule for the parentheses:** the parentheses always mean *“this
> is a type.”* `extends` lives **inside** them, and the kind
> (`data.table` / `list` / `data.frame`) is **inherited from the base**
> — never restated. There is no second syntax to remember.

**Inherit and add columns** — write `extends Base`, then list only the
*new* columns as bullets:

``` r
#' @type Order (data.table):
#' - order_id (character) the exchange id.
#' - status (character in unlist(ORDER_STATUS)) lifecycle state.
#' ... (defined once)

#' @type OrderModifyResult (extends Order):
#' - order_id_old (character) the id before the change.
#' - order_id_new (character) the id after the change.
```

`OrderModifyResult` is every `Order` column **plus** the two new ones,
in order — with no duplicated definition to drift.

**Override a column** — redeclare it by name; the redeclaration replaces
the inherited one *in place* (its position is kept). This is a trusted
full replacement: roxyassert is a generator, not a type checker, so it
does not verify the new type is a narrowing of the old.

``` r
#' @type ClosedOrder (extends Order):
#' - status (character in unlist(c("FILLED", "CANCELLED", "EXPIRED")))
```

**Multiple inheritance** — list several bases (all must be the same
kind). A column defined by more than one base is an **error unless the
derived type redeclares it** (the override then resolves the tie):

``` r
#' @type MarginOrder (extends Order, MarginFields):
```

**Subset with `pick` / `omit`** (mutually exclusive; every named column
must exist in a base):

``` r
#' @type OrderSummary (extends Order pick order_id, status):
#' @type PublicOrder  (extends Order omit order_id_client):
```

All of this works **inline** too — define the shape right in a `@param`
/ `@return`, no name needed:

``` r
#' @param legs (extends Order pick order_id, status) the legs.
#' @return (extends Order):
#' - order_id_old (character) prior id.
#' - order_id_new (character) new id.
```

Derivation is pure `document()`-time list algebra over the resolved
columns: it reuses the existing `@type` registry, cycle / unknown-base
detection, and lowering, with no runtime cost. Two derivations are
deliberately **out of scope** for now (each is a separate, larger
feature): *renaming* a column (use `omit` + re-add) and *generic /
parameterized* types (`Paged<T>`).

## Standalone, exportable asserts — `@genassert` / `@exportassert`

By default a `@type` only materialises as **inlined** checks inside a
`@param`/`@return` that references it — so a shape used by no function
(or one built internally and never passed as an argument) has no
callable validator. Two tags lift that:

- **`@genassert`** — on a block defining one or more `@type`, emit a
  standalone `assert_type_<Name>(value)` for *every* `@type` in that
  block, even if nothing references it.
- **`@exportassert`** — export the asserts generated **from that block**
  so other packages can call them. Works on a function or R6 method
  block too (exporting its `assert_args_*` / `assert_return_*`).
  Distinct from roxygen2’s `@export`, which exports the documented
  object, not its assert helpers.

``` r
#' @type OrderAck (data.table) an order acknowledgement:
#' - order_id (character) the exchange id.
#' - status (scalar<character in c("FILLED", "REJECTED")>) outcome.
#' @genassert      # also emit a callable assert_type_OrderAck()
#' @exportassert   # ...and export it for downstream packages
#' @name shapes
NULL
```

Both are **bare, whole-block flags**. They are deliberately *not*
selective like `@noassert` (which exempts named *parameters* of one
function): a `@type` is its own definition, so for per-type control put
a `@type` in its own block — a stray name list on either tag is an
error, not silently ignored.

`@exportassert` appends a managed `export(...)` block to the package
`NAMESPACE` **and** writes a `\keyword{internal}` Rd documenting the
exported helpers (R requires exported objects to be documented, so this
keeps `R CMD check` clean). Both are rewritten deterministically on each
`document()`. Note the exported names are roxyassert-generated
(including R6 `assert_args_<Class>__<method>`): they become part of your
package’s public namespace, though `\keyword{internal}` keeps them out
of the help index.

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

## Known limitations

Things deliberately not supported yet — each is rejected with a clear
error, and we’ll revisit any of them if there’s demand. (The grammar
reference’s *Non-goals* section is the full formal list.)

- **A list of un-resolved promises** (`list<promise<T>>`) — each element
  would be an unresolved promise that can’t be checked synchronously,
  and roxyassert never emits per-element `then()` wiring. Await them
  (e.g. `promises::promise_all`) and annotate the result as
  `promise<list<T>>`.
- **Refining a named type at the use site** — once
  `@type Price (scalar<numeric>)` is defined you can’t write
  `(Price in [0, 1])`; the refinement must live in the definition
  (define a second `@type`, or write the refined type inline). Named
  types are also package-local (no cross-package reuse yet).
- **A named type shows as its bare name in rendered docs** — `@type` is
  resolved only for the generated checks, so a help page / pkgdown site
  shows `(OrderAck)` verbatim, not its expanded shape, with no
  auto-generated topic or link. To give a type a help page, document its
  `@type` block like any object (add a title/description and `@name`);
  reference it as a markdown link (`[OrderAck]`) for a clickable
  cross-reference. (Auto-generated type pages and links may come later.)
- **A `class<Name>` name is not verified at `document()` time** —
  roxyassert emits `assert_class(x, "Name")` blindly, so a typo such as
  `class<Duraton>` generates without complaint and fails only at
  runtime.
- **An `extends` override is not checked for compatibility** —
  redeclaring an inherited column replaces it with whatever you write;
  roxyassert has no subtype lattice, so it does not verify the override
  narrows the base column (it trusts the author). Column *renaming* and
  *generic / parameterized* types (`Paged<T>`) are likewise not
  supported yet.

## Status

Early development — the annotation grammar and generation conventions
documented here are the design under active implementation.

## License

MIT © Dereck Mezquita. See [LICENSE](LICENSE) for details.

## Citation

``` r
citation("roxyassert")
```
