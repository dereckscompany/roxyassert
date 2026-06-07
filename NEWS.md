# roxyassert 0.9.0

* **Record-type derivation for `@type`** — build one record shape from another
  instead of copying columns, the same idea as TypeScript's `extends` / `Pick` /
  `Omit`. Inside the parentheses (the kind is inherited from the base, never
  restated):

  * **`extends Base`** — inherit the base's columns, then add new ones as bullets:
    `@type OrderModifyResult (extends Order):` plus the modify-only columns.
  * **Override** — redeclaring an inherited column by name replaces it in place
    (a trusted full replacement; roxyassert has no subtype lattice, so it is not
    checked for being a narrowing).
  * **Multiple inheritance** — `(extends A, B)`; a column defined by more than one
    base is an error unless the derived type redeclares it.
  * **`pick` / `omit`** — `(extends Order pick id, status)` /
    `(extends Order omit secret)`; mutually exclusive, names must exist in a base.

  Works both as a named `@type` and **inline** in a `@param`/`@return`
  (`@return (extends Order):` + bullets). Pure `document()`-time column splicing —
  it reuses the existing `@type` registry, cycle / unknown-base detection, and
  lowering, with no runtime cost and no change to generated code. Column *renaming*
  and *generic / parameterized* types remain out of scope (see the grammar
  vignette's *Non-goals*).

# roxyassert 0.8.0

* New tag **`@genassert`**: on a block that defines one or more `@type`, emit a
  standalone, callable `assert_type_<Name>(value)` for *every* `@type` in that
  block — even when no function references the type. Previously a `@type` only
  materialised as inlined checks inside a referencing `@param`/`@return`, so a type
  used by no function (or one built internally and never passed as an argument)
  had no callable validator.

* New tag **`@exportassert`**: export the assert helpers generated *from that
  block* — the `assert_type_*` of a `@genassert` block, and/or the
  `assert_args_*` / `assert_return_*` of a function or R6 method — so downstream
  packages can call them. Distinct from roxygen2's `@export` (which exports the
  documented object, not its assert helpers). The roclet appends a managed
  `export(...)` block to the package `NAMESPACE` *and* writes a documenting Rd
  (`man/roxyassert-generated-asserts.Rd`, `\keyword{internal}`, `\usage` recovered
  from the generated signatures) — R requires exported objects to be documented,
  so this keeps `R CMD check` clean. Both are re-written deterministically on each
  `document()`; the Rd carries roxyassert's own banner (not roxygen2's), so the
  `rd` roclet never purges it.

* `@genassert` and `@exportassert` are **bare, whole-block flags** — they are not
  selective like `@noassert` (which exempts named *parameters* of one function): a
  `@type` is its own definition, so per-type control comes from putting a `@type`
  in its own block. A stray name list on either tag is an error, not silently
  ignored. The exported helper names are roxyassert-generated (including R6
  `assert_args_<Class>__<method>`): they are public, though hidden from the help
  index via `\keyword{internal}`.

* `roclet_process()` now returns a structured `list(code=, exports=)` rather than
  a bare list of code blocks — a behaviour change to the return value of an
  exported S3 method, affecting any direct caller (e.g. `roc_proc_text()`).

# roxyassert 0.7.0

* Type annotations now render correctly in the generated documentation when the
  package enables markdown. roxygen2's markdown pass lowers a bare-word type
  fragment such as `<POSIXct>` (in `scalar<POSIXct>`, `class<Duration>`,
  `promise<T>`, `list<T>`, a nested generic, a nullable `?`, or a union) into raw
  inline HTML (`\if{html}{\out{<POSIXct>}}`), which a browser then parses as an
  unknown tag and silently drops — so the type previously showed as just
  `(scalar)`. `roclet_output` now repairs the generated `man/*.Rd`, rewriting
  those fragments back to a plain `<Name>` that renders across html/latex/text. No
  annotation change is needed — types keep their existing `<...>` syntax. The
  repair targets exactly a bare identifier glued, as a whole word, to one of the
  category keywords `scalar`/`class`/`promise`/`list`, so roxygen2's own R6 layout
  tags (`\out{<hr>}`, `<div ...>`, `</div>`) and never-mangled fragments
  (`<numeric in ]0, Inf[>`, comma-bearing vectors) are left untouched. The same
  shape written in ordinary prose is likewise restored to visible text rather than
  a dropped tag, which is never harmful.

# roxyassert 0.6.0

* Finiteness via interval brackets: on a `numeric`, an **open** bracket at a
  `±Inf` sentinel now *excludes* that infinity. `scalar<numeric in ]0, Inf[>` is
  "finite and > 0" (lowering to `assert_between(x, lower = 0, lower_inclusive =
  FALSE, upper = Inf, upper_inclusive = FALSE)`), and `]-Inf, Inf[` is "any finite
  double". A **closed** sentinel still means "no bound that side" and is omitted,
  so `]0, Inf]` is unchanged. This is `numeric`-only — `integer`/`count` cannot be
  `Inf` and a `Date`/`POSIXct` `Inf` bound would be a type mismatch, so for those
  a sentinel is omitted regardless of bracket (no behaviour change).
* As a consequence, the only degenerate both-`±Inf`-sentinel intervals rejected at
  parse time are now those that bound nothing: both brackets closed (`[-Inf, Inf]`,
  any type) or a non-`numeric` with open brackets (`integer in ]-Inf, Inf[`).
  `numeric in ]-Inf, Inf[` is now valid ("any finite double").

# roxyassert 0.5.0

* New `count` type: a non-negative whole number that accepts both `20` and `20L`
  (lowering to `assert_scalar_count` / `assert_count`), unlike `integer` (strict
  `20L`) or `numeric` (strict double). It is interval-capable
  (`scalar<count in [1, Inf[>` is a positive count) but takes no set and no
  `| NA` — a count is non-negative and never NA. The vector form needs
  assert (>= 0.0.8) for `assert_count()`.
* New `@noassert` tag: document a parameter's type without generating its check,
  for parameters already enforced by a hand-written guard. `@noassert <names>`
  exempts the named parameters; a bare `@noassert` makes the whole
  function/method documented-only. Naming a parameter that is not documented is
  an error. Works for plain functions and R6 methods.

# roxyassert 0.4.0

* New `class<Name>` type for asserting an object's class, generating
  `assert_class(x, "Name")`. It works for any of R's object systems (S3, S4,
  Reference Classes, R6, S7) and for any class you define yourself, and it
  matches subclasses, so `class<AbstractClock>` accepts a `RealClock`. `Name` is
  a single class (no `pkg::` qualifier — name the package in prose if useful).
* Breaking: the `R6<Class>` type is removed in favour of the more general
  `class<Class>` (identical generated check).
* Class names are not verified at `document()` time: a typo such as
  `class<Duraton>` generates without complaint and fails at runtime.

# roxyassert 0.3.1

* R6 contract generation now works on roxygen2 7.x as well as 8.x. The method
  detection no longer calls roxygen2's internal `r6_tag_type()` (added in
  8.0.0); it derives the same method-vs-class classification directly from the
  tag and class source lines, so packages pinned to roxygen2 7.3.x can
  generate R6 method contracts.

# roxyassert 0.3.0

* New `@type` tag: declare a reusable named type/shape once and reference it by
  name anywhere a type appears (`@return (promise<OrderAck>)`, `(Bps)`,
  `list<OrderAck>`), instead of repeating the annotation. Names resolve at
  `document()` time by inline expansion (no runtime cost); a `@type` may build on
  another, with cycles and unknown names reported as errors. Package-local.
  Use-site refinement of a named type (e.g. `(Price in [0, 1])`) is not supported
  in this version — see Known limitations in the README.

# roxyassert 0.2.0

* New `promise<T>` type (and the `T | promise<T>` union), most natural on
  `@return`, for functions whose result may be delivered synchronously **or** as
  a `promises::promise`
  that resolves to the same value (e.g. an exchange wrapper with an `async`
  switch). roxyassert generates a plain value-validator for the resolved type
  `T` and stays promise-agnostic — you compose the async yourself
  (`promises::then(impl, assert_return_fn)`, or your own sync/async helper).

# roxyassert 0.1.0

Initial release.

`roxyassert` is a roxygen2 roclet: at `document()` time it reads structured type
annotations in your `@param` / `@return` documentation and writes per-function
assertion helpers (calls to the [`assert`](https://github.com/dereckscompany/assert)
package) into `R/contracts-generated.R`, so a function's documented contract and
its runtime validation come from a single source.

## Features

* `contract_roclet()` — register it in `DESCRIPTION`
  (`Roxygen: list(roclets = c("namespace", "rd", "roxyassert::contract_roclet"))`)
  to generate `assert_args_<fn>()` and `assert_return_<fn>()` for every documented
  function with a typed `(...)` annotation; untyped tags are left untouched, so
  adoption is incremental.
* A bespoke, self-contained annotation grammar (see `vignette("grammar")`):
  - bare atomics as vectors, `scalar<>` / `vector<..., length>` shapes, and the
    `any` wildcard;
  - `in [interval]` (ISO/Bourbaki open/closed brackets, `±Inf` sentinels) and
    `in c(set)` / bare-constant sets, with values copied **verbatim** — no coercion;
  - `| NA` (element-level) and `?` / `| NULL` (whole-argument) modifiers, and
    `|` type unions;
  - composite records and typed `data.table` / `data.frame` columns via nested
    `- name (type)` bullets, and homogeneous `list<T>`;
  - reference types `function` and `R6<Class>`.
* R6 method contracts: methods documented inline generate
  `assert_args_<Class>__<method>()` / `assert_return_<Class>__<method>()`.
* Annotation text is read from each tag's raw source, so the grammar's `<...>`
  and `[...]` survive roxygen2's `markdown = TRUE` processing.

## Notes

* The generated helpers call `assert::*` by bare name; make `assert` an import of
  your package (see the README).
