# Getting started with roxyassert

## What roxyassert does

`roxyassert` reads structured type annotations in your roxygen2
documentation and, at `document()` time, generates per-function argument
and return assertion helpers. The generated checks are calls to the
[`assert`](https://github.com/dereckscompany/assert) package, so a
function’s documented contract and its runtime validation come from one
source.

See the [README](https://github.com/dereckscompany/roxyassert) for the
full annotation grammar; this vignette is a short tour.

## Setup

Register the roclet in `DESCRIPTION`:

``` dcf
Roxygen: list(markdown = TRUE, roclets = c("namespace", "rd", "roxyassert::contract_roclet"))
```

## Annotate a function

A type annotation is a parenthesised token at the start of a `@param` or
`@return` description:

``` r

#' Submit an order.
#'
#' @param symbol (scalar<character>) normalised `BASE/QUOTE` pair.
#' @param quantity (scalar<numeric>) order size.
#' @param price_limit (scalar<numeric>?) limit price; `NULL` for market orders.
#' @return (data.table) the accepted order:
#' - **order_id** (character): exchange order id.
#' - **quantity** (numeric): accepted size.
#' - **datetime** (POSIXct): acceptance time.
#' @export
submit_order <- function(symbol, quantity, price_limit = NULL) {
  assert_args_submit_order(symbol, quantity, price_limit)   # generated
  result <- ...
  return(assert_return_submit_order(result))                # generated
}
```

## Generate the checks

``` r

devtools::document()
```

This (re)writes `R/contracts-generated.R` with
`assert_args_submit_order()` and `assert_return_submit_order()` —
committed alongside `NAMESPACE`. Edit the docs, re-document, and the
checks stay in sync.
