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

The `roclets` list **replaces** roxygen2's default set rather than
extending it, so re-list `collate`, `namespace` and `rd` alongside this
roclet. Dropping `collate` is the dangerous slip: an `@include`-using
package then stops having its DESCRIPTION `Collate:` field maintained,
and `R CMD INSTALL`/`R CMD check` fails with
`files in '.../R' missing from 'Collate' field` even though
`load_all()`/`test()` still pass locally.

List this roclet **after** `"rd"`. Besides generating the contract
helpers it repairs the `man/*.Rd` that `rd` writes (so typed
`@param`/`@return` annotations render under markdown); that repair is a
no-op unless `rd` has already run.
