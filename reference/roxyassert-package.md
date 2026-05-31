# roxyassert: Generate Runtime Assertions from roxygen2 Documentation

A roxygen2 roclet that turns structured type annotations in '@param' and
'@return' documentation into per-function argument and return assertion
helpers, generated at 'document()' time. The generated checks are calls
to the 'assert' package, so a function's documented contract and its
runtime validation come from a single source and cannot drift apart.

## See also

Useful links:

- <https://dereckscompany.github.io/roxyassert>

- <https://github.com/dereckscompany/roxyassert>

- Report bugs at <https://github.com/dereckscompany/roxyassert/issues>

## Author

**Maintainer**: Dereck Mezquita <dereck@mezquita.io>
([ORCID](https://orcid.org/0000-0002-9307-6762))

Authors:

- Dereck Mezquita <dereck@mezquita.io>
  ([ORCID](https://orcid.org/0000-0002-9307-6762))
