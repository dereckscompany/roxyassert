# roxyassert contract roclet

Register this roclet in your package `DESCRIPTION` so
`devtools::document()` generates argument and return assertion helpers
from your typed `@param` / `@return` documentation:

## Usage

``` r
contract_roclet()
```

## Value

A roxygen2 roclet object.

## Details

List this roclet **after** `"rd"`. Besides generating the contract
helpers it repairs the `man/*.Rd` that `rd` writes (so typed
`@param`/`@return` annotations render under markdown); that repair is a
no-op unless `rd` has already run.
