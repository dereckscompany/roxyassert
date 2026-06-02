# Changelog

## roxyassert 0.5.0

- New `count` type: a non-negative whole number that accepts both `20`
  and `20L` (lowering to `assert_scalar_count` / `assert_count`), unlike
  `integer` (strict `20L`) or `numeric` (strict double). It is
  interval-capable (`scalar<count in [1, Inf[>` is a positive count) but
  takes no set and no `| NA` — a count is non-negative and never NA. The
  vector form needs assert (\>= 0.0.8) for `assert_count()`.
- New `@noassert` tag: document a parameter’s type without generating
  its check, for parameters already enforced by a hand-written guard.
  `@noassert <names>` exempts the named parameters; a bare `@noassert`
  makes the whole function/method documented-only. Naming a parameter
  that is not documented is an error. Works for plain functions and R6
  methods.

## roxyassert 0.4.0

- New `class<Name>` type for asserting an object’s class, generating
  `assert_class(x, "Name")`. It works for any of R’s object systems (S3,
  S4, Reference Classes, R6, S7) and for any class you define yourself,
  and it matches subclasses, so `class<AbstractClock>` accepts a
  `RealClock`. `Name` is a single class (no `pkg::` qualifier — name the
  package in prose if useful).
- Breaking: the `R6<Class>` type is removed in favour of the more
  general `class<Class>` (identical generated check).
- Class names are not verified at `document()` time: a typo such as
  `class<Duraton>` generates without complaint and fails at runtime.

## roxyassert 0.3.1

- R6 contract generation now works on roxygen2 7.x as well as 8.x. The
  method detection no longer calls roxygen2’s internal `r6_tag_type()`
  (added in 8.0.0); it derives the same method-vs-class classification
  directly from the tag and class source lines, so packages pinned to
  roxygen2 7.3.x can generate R6 method contracts.

## roxyassert 0.3.0

- New `@type` tag: declare a reusable named type/shape once and
  reference it by name anywhere a type appears
  (`@return (promise<OrderAck>)`, `(Bps)`, `list<OrderAck>`), instead of
  repeating the annotation. Names resolve at `document()` time by inline
  expansion (no runtime cost); a `@type` may build on another, with
  cycles and unknown names reported as errors. Package-local. Use-site
  refinement of a named type (e.g. `(Price in [0, 1])`) is not supported
  in this version — see Known limitations in the README.

## roxyassert 0.2.0

- New `promise<T>` type (and the `T | promise<T>` union), most natural
  on `@return`, for functions whose result may be delivered
  synchronously **or** as a `promises::promise` that resolves to the
  same value (e.g. an exchange wrapper with an `async` switch).
  roxyassert generates a plain value-validator for the resolved type `T`
  and stays promise-agnostic — you compose the async yourself
  (`promises::then(impl, assert_return_fn)`, or your own sync/async
  helper).

## roxyassert 0.1.0

Initial release.

`roxyassert` is a roxygen2 roclet: at `document()` time it reads
structured type annotations in your `@param` / `@return` documentation
and writes per-function assertion helpers (calls to the
[`assert`](https://github.com/dereckscompany/assert) package) into
`R/contracts-generated.R`, so a function’s documented contract and its
runtime validation come from a single source.

### Features

- [`contract_roclet()`](https://dereckscompany.github.io/roxyassert/reference/contract_roclet.md)
  — register it in `DESCRIPTION`
  (`Roxygen: list(roclets = c("namespace", "rd", "roxyassert::contract_roclet"))`)
  to generate `assert_args_<fn>()` and `assert_return_<fn>()` for every
  documented function with a typed `(...)` annotation; untyped tags are
  left untouched, so adoption is incremental.
- A bespoke, self-contained annotation grammar (see
  [`vignette("grammar")`](https://dereckscompany.github.io/roxyassert/articles/grammar.md)):
  - bare atomics as vectors, `scalar<>` / `vector<..., length>` shapes,
    and the `any` wildcard;
  - `in [interval]` (ISO/Bourbaki open/closed brackets, `±Inf`
    sentinels) and `in c(set)` / bare-constant sets, with values copied
    **verbatim** — no coercion;
  - `| NA` (element-level) and `?` / `| NULL` (whole-argument)
    modifiers, and `|` type unions;
  - composite records and typed `data.table` / `data.frame` columns via
    nested `- name (type)` bullets, and homogeneous `list<T>`;
  - reference types `function` and `R6<Class>`.
- R6 method contracts: methods documented inline generate
  `assert_args_<Class>__<method>()` /
  `assert_return_<Class>__<method>()`.
- Annotation text is read from each tag’s raw source, so the grammar’s
  `<...>` and `[...]` survive roxygen2’s `markdown = TRUE` processing.

### Notes

- The generated helpers call `assert::*` by bare name; make `assert` an
  import of your package (see the README).
