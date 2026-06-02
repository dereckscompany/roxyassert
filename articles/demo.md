# Getting started with roxyassert

## What roxyassert does

R is dynamically typed, so a function can be handed the wrong type or
hand back the wrong shape with no complaint. `roxyassert` reads the
structured type annotations in your roxygen2 docs and, at `document()`
time, generates per-function argument and return assertion helpers —
calls to the [`assert`](https://github.com/dereckscompany/assert)
package — so a function’s documented contract and its runtime validation
come from one source.

See the [README](https://github.com/dereckscompany/roxyassert) for the
complete annotation grammar; this vignette is a short tour plus the
pattern we use most.

## Setup

Register the roclet in `DESCRIPTION`:

``` dcf
Roxygen: list(markdown = TRUE, roclets = c("namespace", "rd", "roxyassert::contract_roclet"))
```

## Annotate a function

A type annotation is a parenthesised token at the start of a `@param` or
`@return` description. A bare type is a vector; a scalar is declared
explicitly.

``` r

#' Submit an order.
#'
#' @param symbol (scalar<character>) normalised `BASE/QUOTE` pair.
#' @param side (scalar<character in c("BUY", "SELL")>) order side.
#' @param quantity (scalar<numeric in ]0, Inf[>) order size (positive).
#' @param price_limit (scalar<numeric>?) limit price; `NULL` for market orders.
#' @return (data.table) the accepted order:
#' - order_id (character) exchange order id.
#' - quantity (numeric) accepted size.
#' - datetime (POSIXct) acceptance time.
#' @export
submit_order <- function(symbol, side, quantity, price_limit = NULL) {
  assert_args_submit_order(symbol, side, quantity, price_limit)   # generated
  result <- ...
  return(assert_return_submit_order(result))                      # generated
}
```

`devtools::document()` (re)writes `R/contracts-generated.R` with
`assert_args_submit_order()` and `assert_return_submit_order()`,
committed alongside `NAMESPACE`.

## The pattern: an abstract class that enforces its own contract

A common use is an abstract base class whose public methods define a
uniform interface. Document each method’s inputs and outputs once, and
let `roxyassert` generate the checks — every concrete subclass then
inherits a contract that is validated at runtime, on both the way in and
the way out.

``` r

#' @title AbstractStore
#' @description A key-value store contract. Subclasses implement `.impl_*`;
#'   the public methods validate inputs and returns from the documented types.
AbstractStore <- R6::R6Class(
  "AbstractStore",
  public = list(
    #' @description Fetch records by key.
    #' @param keys (character) one or more keys to fetch.
    #' @param limit (scalar<integer>?) optional max rows.
    #' @return (data.table) the matched records:
    #' - key (character) the record key.
    #' - value (numeric) the stored value.
    #' - updated_at (POSIXct) last-write time.
    get = function(keys, limit = NULL) {
      assert_args_AbstractStore__get(keys, limit)       # generated
      result <- private$.impl_get(keys, limit)
      return(assert_return_AbstractStore__get(result))  # generated
    },

    #' @description Write one record.
    #' @param key (scalar<character>) the record key.
    #' @param value (scalar<numeric>) the value to store.
    #' @return (class<AbstractStore>) self, invisibly (for chaining).
    put = function(key, value) {
      assert_args_AbstractStore__put(key, value)        # generated
      private$.impl_put(key, value)
      return(invisible(assert_return_AbstractStore__put(self)))
    }
  ),
  private = list(
    .impl_get = function(keys, limit) stop("not implemented"),
    .impl_put = function(key, value) stop("not implemented")
  )
)
```

Because the method names are scoped by class
(`assert_args_AbstractStore__get`), two classes can share a method name
without colliding. A subclass that overrides
[`get()`](https://rdrr.io/r/base/get.html) re-uses the same documented
contract simply by calling the same generated helpers.

## Using the checks is optional

The helpers are generated whether or not you call them. Adopt them in
one method, a few, or all of them; a method with no typed tags is left
untouched. You never hand-write a validation function again — even for
the methods where you choose not to call one.
