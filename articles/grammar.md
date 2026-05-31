# The roxyassert annotation grammar — complete reference

The authoritative, exhaustive reference for the roxyassert annotation
language. Every construct and combination is written out so the language
can be audited against itself — it must agree with itself everywhere.

## 1. Design invariants

1.  **One home per concept.** The element type and its element-level
    modifiers (`in`, `| NA`) and a `vector`’s length live in `<>` (or
    attach to a bare atomic type); the whole-argument modifiers
    (`?`/`| NULL`, type unions) sit outside.
2.  **“Bare” means different things by category.** A bare *atomic* type
    is a vector of any length (`scalar<...>` is the only way to say
    length 1); a bare *reference* type (`function`/`R6<Class>`) is a
    single length-1 object; a bare *composite* is an unconstrained
    `list`/table (invariant 7, §2).
3.  **`NA` and `NULL` are reserved words, never type names** — this
    keeps `|` unambiguous.
4.  **Element-level binds tighter than slot-level.** `in` / `| NA` bind
    to the nearest atom on their left, before any slot-level `|` union
    or `?`.
5.  **The language is recursive.** A composite contains *full
    annotations* in its bullets, to any depth.
6.  **Sets are R; intervals are math.** A set is an R expression emitted
    verbatim (`c(...)` or a bare name); an interval is ISO/Bourbaki
    bracket notation. A bound or set element must evaluate to the **same
    type** as the atom it constrains — a static rule (S2), since `rexpr`
    is opaque.
7.  **A type may only carry what its category supports** (§2). The
    grammar makes structurally nonsensical combinations unrepresentable
    — an interval on `complex`, a set on `logical`/`raw`, a fractional
    bound on `integer`, a `vector` of `function`, `| NA` on `raw`. The
    few remaining element-level rules are stated as static rules (§4),
    not left implicit.

## 2. Type categories

Every base type sits in exactly one category, and the category alone (no
per-type exceptions) decides which modifiers are legal:

| Category | Types | `in [interval]` | `in c(set)` | `\| NA` | length / `vector<>` / bare | shape |
|----|----|:--:|:--:|:--:|:--:|----|
| **Ordered atomic** | `integer` `numeric` `Date` `POSIXct` | ✅ | ✅¹ | ✅ | ✅ | bare / `scalar<>` / `vector<>` |
| **Enumerable atomic** | `character` `factor` | ❌ | ✅² | ✅ | ✅ | bare / `scalar<>` / `vector<>` |
| **Plain atomic** | `complex` `logical` | ❌ | ❌ | ✅ | ✅ | bare / `scalar<>` / `vector<>` |
| **Byte atomic** | `raw` | ❌ | ❌ | ❌ | ✅ | bare / `scalar<>` / `vector<>` |
| **Reference** | `function` `R6<Class>` | ❌ | ❌ | ❌ | ❌ | **bare only** (length-1 by nature) |
| **Composite** | `list` `data.table` `data.frame` | ❌ | ❌ | ❌ | ❌ | bare, or refined by **nested bullets** |

¹ Sets compare with `==`/`%in%` and apply no normalisation:
**discouraged** on `numeric` (floating-point) and on `Date`/`POSIXct`
(double-based, time-zone- and precision-sensitive) — prefer intervals
there. Integer sets are exact and fine. Interval bounds for
`Date`/`POSIXct` are R expressions of the matching class
(e.g. `as.Date("2024-01-01")`); `integer` bounds are whole numbers (the
grammar rejects fractional integer bounds); see static rule S2. ² On
`character` and `factor` a set constrains the **realised values**
(`as.character(x) %in% set`), so the two behave identically; it does
**not** assert a factor’s declared
[`levels()`](https://rdrr.io/r/base/levels.html) — for that, use prose
(out of scope, §12).

`complex`/`logical`/`raw` take no set (degenerate or
floating-point-fragile), and `raw` has no `NA` representation in R, so
these are not value-constrained; use a bare/`scalar`/`vector` form.
`function`/`R6` are bare length-1 references; composites are refined
only by nested bullets. All of these are enforced by the grammar (§3);
the residual element-type rules are static (§4).

## 3. Formal context-free grammar (EBNF)

    annotation     ::= "(" slot ")" bullets?           (* bullets gated by S1 *)

    slot           ::= type ( "|" type )*  ( ( "|" "NULL" ) | "?" )?
                       (* a union of >=1 types; the whole argument may be NULL,
                          written EITHER as a "| NULL" alternative OR a trailing "?",
                          never both *)

    type           ::= atomic | reference | composite

    atomic         ::= atom
                     | "scalar" "<" atom ">"
                     | "vector" "<" atom ( "," length )? ">"
                       (* a bare atom is a vector of any length *)

    atom           ::= "integer"     ( "in" ( int_interval | set ) )?  ( "|" "NA" )?
                     | real_ordered  ( "in" ( interval | set ) )?      ( "|" "NA" )?
                     | enumerable    ( "in" set )?                     ( "|" "NA" )?
                     | plain                                           ( "|" "NA" )?
                     | "raw"

    real_ordered   ::= "numeric" | "Date" | "POSIXct"
    enumerable     ::= "character" | "factor"
    plain          ::= "complex" | "logical"

    reference      ::= "function" | "R6" "<" ident ">"
    composite      ::= "list" | "data.table" | "data.frame"

    int_interval   ::= low int_bound "," int_bound high
    interval       ::= low bound "," bound high
    low            ::= "["    (* closed *) | "]"   (* open *)
    high           ::= "]"    (* closed *) | "["   (* open *)
    int_bound      ::= "-"? digit+ | "Inf" | "-Inf"
    bound          ::= signed_number | "Inf" | "-Inf" | rexpr
                       (* signed_number for numeric; an R expr of the matching class
                          for Date/POSIXct, e.g. as.Date("2024-01-01"); see S2 *)

    set            ::= name_set | call_set
    name_set       ::= ident       (* a bare constant; a single maximal-munch token,
                                      terminated by | , ) or >; may NOT be a compound
                                      R expression *)
    call_set       ::= rexpr       (* a bracketed R expression such as c("a", "b") *)

    length         ::= int          (* exactly n *)
                     | int ".." int (* inclusive range *)
                     | int ".."     (* at least n *)

    bullets        ::= bullet+      (* siblings at one indentation depth *)
    bullet         ::= "- " name " (" slot ")" ":"? description bullets?
                       (* the trailing bullets are gated by S1 *)
    name           ::= ident | "**" ident "**"   (* bold optional, no semantic effect *)

    (* lexical terminals *)
    int            ::= digit+
    signed_number  ::= "-"? digit+ ( "." digit+ )?
    ident          ::= letter ( letter | digit | "." | "_" )*
    rexpr          ::= (* any valid R expression; opaque, emitted verbatim *)
    description    ::= (* free text to end of the bullet line *)

Tokenizing rules (so the grammar is deterministic in practice):

- **One scan order.** An `rexpr` region (a `call_set`, or a
  `Date`/`POSIXct` bound) is consumed **first**, by a string-aware,
  bracket-balanced R scan that skips string/character literals and
  balances `(` `[` `{`. Only **after** a bound/set is fully consumed
  does the next structural token count. Consequently any `,` `|` `>` `<`
  `[` `]` inside a balanced `rexpr` is invisible to the annotation
  tokenizer; only top-level structural tokens are seen.
- **One top-level comma per interval.** An `interval`/`int_interval` has
  exactly one *top-level* comma, between its two bounds; commas inside
  an `rexpr` bound are invisible (previous rule). The interval
  delimiters `[ ] ] [` are recognised only at the interval’s structural
  boundary (right after `in`, and right after the second bound) and are
  **not** counted by the `< >` / `( )` depth tracker, so an open
  interval `]0, Inf[` never unbalances anything.
- **The `vector` length comma.** Inside `vector<...>` the element `atom`
  — with its `in (...)` and `| NA` — is consumed first; the atom/length
  comma is the first top-level comma that remains. `scalar<...>`
  likewise admits **no top-level comma** (a comma inside an interval or
  set is fine); `scalar<T, n>` fails because no length slot follows the
  atom.
- **Bare-name set.** A `name_set` is a single `ident` (maximal munch
  over `letter|digit|.|_`); the next `|`, `,`, `)`, or `>` ends it. A
  bare name may not itself be a compound R expression (`FOO | NA` reads
  as the set `FOO` plus an atom-level `| NA`); use a `call_set` `c(...)`
  when operators are needed.
- **`>`** closes the innermost open generic (depth-aware); `vector<...>`
  and `R6<...>` each close one level. `R6` must be followed by
  `<ident>`; a bare `R6` is a parse error.
- **`..` is one maximal-munch token**, valid only in a `length`; a lone
  `.` is a decimal point, valid only inside a numeric bound. `..` in a
  bound position and a lone `.` in a length position are lexical errors.
- **Bullet anatomy.** The `name` is the single token before the first
  `(` at the bullet’s top level; the `slot` is the balanced-parenthesis
  group opened by that `(`, found with the same string-aware scan as
  `annotation`; everything after its matching `)` (optionally a leading
  `:`) is free-text `description`. Names contain no spaces.
- **Reference types are bare** — `function`/`R6<Class>` never appear in
  `scalar<>`/`vector<>` and never carry `in`/`| NA`/length.
- **Union `| NA`.** Each union member is parsed as a full `atom`, so a
  trailing `| NA` is consumed by that member’s `atom` before the slot
  union resumes; since `NA` is reserved it can never be a `type`, so
  `( "|" type )*` never swallows it. Thus in
  `(numeric | character | NA)` the `| NA` belongs to `character`.
- **Nesting** of bullets is by **indentation depth**; the trailing `:`
  is optional and carries no grammatical force.

## 4. Static rules (beyond the context-free grammar)

These context-sensitive constraints are checked by the generator; they
are *specified rules*, not stylistic suggestions.

- **S1 — composite nesting.** Nested `bullets` may follow an
  `annotation` or a `bullet` only when its slot has exactly one non-NULL
  alternative and that alternative is a composite
  (`list`/`data.table`/`data.frame`). Any other slot is a leaf and takes
  no children; `(data.table | data.frame)` with bullets is rejected
  (which field-set would they describe?).
- **S2 — bound/set element type.** Interval bounds and set elements must
  evaluate to the constrained atom’s type: `signed_number`/`±Inf` for
  `numeric`; whole numbers/`±Inf` for `integer` (also enforced by the
  grammar via `int_bound`); class-matching R expressions for
  `Date`/`POSIXct` (e.g. `as.Date(...)`, never a character literal); the
  literal element type for `character`/`factor`/`integer` sets.
- **S3 — named composite fields.** A bulleted
  `list`/`data.table`/`data.frame` asserts the presence of the **named**
  fields/columns listed (`all(<names> %in% names(x))`, and the
  per-column type for tables). Positional or unnamed lists are out of
  scope (§12).

## 5. Binding & precedence (why `|` is never ambiguous)

After an `atom`/type, the next `|` is resolved by its operand:

| What follows `\|` | Reads as | Level |
|----|----|----|
| `NA` | elements may be missing | element (part of an atom) |
| `NULL` | the whole argument may be `NULL` | slot |
| a type (`atomic` / `reference` / `composite`) | a union alternative | slot |

`NA`/`NULL` are reserved and can never start a type, so each `|`
resolves by look-ahead. `| NA` is valid **only after an atom** (never
after a closed `scalar<>`/`vector<>`, never on `raw`, reference, or
composite), and binds to the **immediately preceding atom** — the
nearest type to its left, at most one per atom. Thus:

- `(scalar<numeric> | NA)` is **invalid**; write
  `(scalar<numeric | NA>)`.
- in `(numeric | character | NA)` the `| NA` binds to `character` only —
  a numeric vector, **or** a character vector whose elements may be
  `NA`.
- in `(numeric in [0, 1] | NA)` the `in` and `| NA` both attach to
  `numeric`.

## 6. Base types

| Type | Category | R meaning |
|----|----|----|
| `integer` | ordered atomic | integer vector |
| `numeric` | ordered atomic | double vector |
| `Date` | ordered atomic | `Date` vector |
| `POSIXct` | ordered atomic | date-time vector |
| `character` | enumerable atomic | character vector |
| `factor` | enumerable atomic | factor |
| `complex` | plain atomic | complex vector |
| `logical` | plain atomic | `TRUE`/`FALSE` vector |
| `raw` | byte atomic | raw vector (no `NA`) |
| `function` | reference | a function/closure (length 1) |
| `R6<Class>` | reference | an R6 instance inheriting `Class` (length 1) |
| `list` | composite | a list (a named record when refined by bullets, S3) |
| `data.table` | composite | a `data.table` (typed columns when refined, S3) |
| `data.frame` | composite | a `data.frame` (typed columns when refined, S3) |

A `list`/`data.table`/`data.frame` **with** nested bullets is a fixed
named-field structure; **without** bullets it is an unconstrained
list/table.

## 7. Every construct, with examples

``` r
# --- bare atomic = vector (any length) ---
(character)                       # character vector, length >= 1
(integer)                         # integer vector
(logical)                         # logical vector
(complex)                         # complex vector
(raw)                             # raw vector
(Date)                            # Date vector

# --- scalar (length 1) ---
(scalar<character>)
(scalar<numeric>)
(scalar<complex>)
(scalar<logical | NA>)            # tri-state flag: TRUE / FALSE / NA

# --- reference types: bare, length-1 by nature ---
(function)                        # a single function/closure
(function?)                       # a function, or NULL
(R6<Engine>)                      # a single R6 instance inheriting Engine
(R6<Engine> | NULL)               # an Engine, or NULL

# --- vector with explicit length (every atom type) ---
(vector<numeric, 10>)             # exactly 10
(vector<numeric, 1..10>)          # 1 to 10 inclusive
(vector<integer, 2..>)            # at least 2
(vector<character, 0..>)          # any length, including 0
(vector<logical, 3>)              # three flags
(vector<factor in c("a", "b"), 2..>)               # set + open length
(vector<Date in [as.Date("2024-01-01"), as.Date("2024-12-31")], 1..7>)  # rexpr-comma vs length-comma

# --- intervals (ordered atomics only) ---
(scalar<numeric in [0, 1]>)       # 0 <= x <= 1
(scalar<numeric in ]0, 1[>)       # 0 <  x <  1
(scalar<numeric in ]0, 1]>)       # 0 <  x <= 1
(scalar<numeric in [-1.5, 2.5]>)  # fractional, signed bounds
(scalar<numeric in ]0, Inf[>)     # x > 0
(scalar<numeric in ]-Inf, 0]>)    # x <= 0  (-Inf lower sentinel)
(scalar<integer in [1, Inf[>)     # x >= 1  (integer bounds are whole numbers)
(numeric in [0, 1])               # every element in [0, 1]
(scalar<Date in [as.Date("2024-01-01"), as.Date("2024-12-31")]>)        # date range
(scalar<POSIXct in [as.POSIXct("2024-01-01 00:00:00", tz = "UTC"), as.POSIXct("2024-12-31 23:59:59", tz = "UTC")]>)

# --- sets / enums (ordered + enumerable atomics) ---
(scalar<character in c("BUY", "SELL")>)   # inline set, scalar
(character in c("BUY", "SELL"))           # vector, every element in the set
(scalar<character in ORDER_SIDE>)         # set from a bare constant name
(integer in c(1L, 2L, 3L))                # exact integer enum
(factor in c("low", "med", "high"))       # constrains realised values (S2/footnote 2)
(numeric in c(0.25, 0.5, 1.0))            # discouraged: floating-point ==

# --- NA permission (atomics except raw; default: NA not allowed) ---
(numeric | NA)                    # numeric vector, NAs allowed
(scalar<numeric | NA>)            # one numeric or NA
(vector<numeric | NA, 10>)        # 10 numerics, NAs allowed
(numeric in [0, 1] | NA)          # constrained + NA-allowed
(factor in c("low", "med", "high") | NA)   # missing-category factor

# --- nullable slot (whole argument) ---
(scalar<numeric>?)                # one numeric, or NULL
(scalar<numeric> | NULL)          # identical to the above (use one, not both)
(character?)                      # character vector, or NULL

# --- type unions (slot level) ---
(numeric | character)             # a numeric vector OR a character vector
(numeric | character | NA)        # numeric, OR character with NAs allowed
(R6<Reader> | R6<Writer>)         # either R6 class
(data.table | NULL)               # a data.table or NULL

# --- everything at once ---
(vector<numeric in ]0, 1] | NA, 1..100>?)
# NULL, OR a numeric vector of length 1..100 whose elements lie in (0,1] and may be NA
```

## 8. Demo 1 — every inline form on one function

``` r

#' Place a batch of orders.
#'
#' @param symbol (scalar<character>) the `BASE/QUOTE` pair.
#' @param sides (character in c("BUY", "SELL")) one side per order.
#' @param quantities (vector<numeric in ]0, Inf[, 1..500>) positive sizes, up to 500.
#' @param limits (vector<numeric in ]0, Inf[ | NA, 1..500>) limit prices; NA = market.
#' @param leverage (scalar<integer in [1, 125]>?) leverage, or NULL for spot.
#' @param tags (vector<character, 0..>) free-form labels (possibly none).
#' @param tag (scalar<character> | NULL) optional client tag.
#' @param venue (scalar<character in VENUES>) a known venue id.
#' @param tier (scalar<factor in c("retail", "vip")>) account tier.
#' @param dry_run (scalar<logical | NA>) simulate only; NA = use account default.
#' @param not_before (scalar<POSIXct>?) earliest send time, or NULL.
#' @param on_fill (function?) optional fill callback.
#' @return (data.table) the acknowledgements (see Demo 2 for nested returns).
#' @export
place_batch <- function(symbol, sides, quantities, limits, leverage = NULL,
                        tags = character(), tag = NULL, venue, tier, dry_run,
                        not_before = NULL, on_fill = NULL) {
  assert_args_place_batch(symbol, sides, quantities, limits, leverage,
                          tags, tag, venue, tier, dry_run, not_before, on_fill)
  result <- ...
  return(assert_return_place_batch(result))
}
```

## 9. Demo 2 — the kitchen sink: a deeply nested composite return

``` r

#' Run a full report.
#'
#' @param symbols (character) one or more `BASE/QUOTE` pairs.
#' @param top_n (scalar<integer in [1, Inf[>) rows to keep per section.
#' @return (list) the report:
#' - **status** (scalar<character in c("ok", "partial", "failed")>): overall outcome.
#' - generated_at (scalar<POSIXct>): when the report was produced.
#' - window (scalar<Date in [as.Date("2000-01-01"), as.Date("2100-01-01")]>): as-of date.
#' - sections (list): one entry per requested view:
#'   - matches (data.table): ranked matches:
#'     - symbol (character): the pair.
#'     - score (numeric in [0, 1]): normalised rank score.
#'     - drawdown (numeric in ]-Inf, 0]): worst observed drawdown.
#'     - side (factor in c("BUY", "SELL")): order side.
#'     - flags (character | NA): label(s), NA where none apply.
#'   - rejected (data.table | NULL): rows dropped, or NULL if none:
#'     - symbol (character): the pair.
#'     - reason (scalar<character in c("liquidity", "filter", "error")>): why.
#'   - cursor (scalar<character>?): next-page cursor, or NULL at the end.
#' - audit (data.frame): a flat audit log:
#'   - at (POSIXct): event time.
#'   - level (factor in c("info", "warn", "error")): severity.
#'   - message (character): the message.
#' - diagnostics (list): run diagnostics:
#'   - warnings (vector<character, 0..>): messages (possibly none).
#'   - retries (scalar<integer in [0, Inf[>): retry count.
#'   - timings (list): millisecond timings:
#'     - parse_ms (scalar<numeric in [0, Inf[>): parse time.
#'     - run_ms (scalar<numeric in [0, Inf[>): run time.
#'     - per_source (data.table): a row per source:
#'       - source (character): source id.
#'       - ms (numeric in [0, Inf[): time for that source.
#' @export
report <- function(symbols, top_n) {
  assert_args_report(symbols, top_n)
  result <- ...
  return(assert_return_report(result))
}
```

## 10. Demo 3 — an abstract R6 class enforcing every return kind

``` r

#' @title AbstractStore
#' @description A store contract; subclasses implement `.impl_*`. Each public
#'   method validates its inputs and its return from the documented types.
AbstractStore <- R6::R6Class(
  "AbstractStore",
  public = list(
    #' @description Fetch records by key.
    #' @param keys (character) keys to fetch.
    #' @param limit (scalar<integer in [1, Inf[>?) optional max rows.
    #' @return (data.table) the records:
    #' - key (character): the key.
    #' - value (numeric | NA): the value, NA if unset.
    #' - updated_at (POSIXct): last write time.
    get = function(keys, limit = NULL) {
      assert_args_AbstractStore__get(keys, limit)
      return(assert_return_AbstractStore__get(private$.impl_get(keys, limit)))
    },

    #' @description Count records.
    #' @return (scalar<integer in [0, Inf[>) the count.
    count = function() {
      return(assert_return_AbstractStore__count(private$.impl_count()))
    },

    #' @description Write one record; returns self for chaining.
    #' @param key (scalar<character>) the key.
    #' @param value (scalar<numeric> | NULL) the value, or NULL to clear it.
    #' @return (R6<AbstractStore>) self.
    put = function(key, value) {
      assert_args_AbstractStore__put(key, value)
      private$.impl_put(key, value)
      return(invisible(assert_return_AbstractStore__put(self)))
    },

    #' @description Fetch one record, or NULL if absent.
    #' @param key (scalar<character>) the key.
    #' @return (list | NULL) the record, or NULL:
    #' - key (scalar<character>): the key.
    #' - value (scalar<numeric | NA>): the value.
    find = function(key) {
      assert_args_AbstractStore__find(key)
      return(assert_return_AbstractStore__find(private$.impl_find(key)))
    }
  ),
  private = list(
    .impl_get = function(keys, limit) stop("not implemented"),
    .impl_count = function() stop("not implemented"),
    .impl_put = function(key, value) stop("not implemented"),
    .impl_find = function(key) stop("not implemented")
  )
)
```

## 11. Demo 4 — corner cases and tricky combinations

``` r
# union mixing a constrained vector, NA permission, and NULL
(numeric in [0, 1] | NA | character)?
# read: NULL, OR (a numeric vector in [0,1], NAs allowed) OR (a character vector)

# scalar union, nullable
(scalar<integer in [1, 6]> | scalar<character in c("d6")>)?

# length-pinned, NA-allowed, range-constrained, nullable
(vector<numeric in [-1, 1] | NA, 3>?)

# set from a bare constant, as a vector
(character in CURRENCIES)

# reference types, nullable / unioned
(function?)                       # a function, or NULL
(R6<Engine> | NULL)               # an Engine, or NULL
(R6<Reader> | R6<Writer>)         # either class

# nested list whose only field is a nullable nested table
(list)
# - page (scalar<integer in [1, Inf[>): page number.
# - rows (data.table | NULL): the page, or NULL when empty:
#   - id (character): identifier.
#   - amount (numeric in ]0, Inf[ | NA): positive amount, NA if pending.

# --- intentionally INVALID ---
# (scalar<numeric, 1>)            # scalar takes no length
# (scalar<numeric> | NA)          # | NA must be inside <>: use (scalar<numeric | NA>)
# (numeric | NULL?)               # pick one nullability marker, not both
# (complex in [0, 1])             # interval on a non-ordered type
# (character in [0, 1])           # interval on a non-ordered type (use a set)
# (integer in [0.5, 2.5])         # fractional bounds on integer
# (logical in c(TRUE, FALSE))     # logical takes no set (degenerate)
# (complex in c(0+0i, 1+0i))      # complex takes no set
# (raw in OPCODES)                # raw takes no set
# (raw | NA)                      # raw has no NA representation
# (scalar<function>)              # function is bare: write (function)
# (vector<function, 3>)           # function is a length-1 reference (scope choice, §12)
# (R6 | NULL)                     # R6 must name a class: R6<Class>
# (data.table | NA)               # | NA is element-level; not valid on a composite
# (data.table | data.frame): ...  # S1: bullets need a single composite alternative
```

## 12. Non-goals (deliberately inexpressible)

Out of scope for the current grammar — express these in prose or a
hand-written check, anchored on a bare `(list)`/`(data.table)` plus a
sentence. They are listed so the “every combination” claim is honest;
forbidding `vector<function>` is a scope choice, **not** a claim that a
list of functions is un-R-like.

- **Element-typed / homogeneous collections** — `list<scalar<numeric>>`,
  “a list of callbacks”, “a column of model objects”. A `list` with
  bullets is a named record, not a homogeneous collection.
- **Composite cardinality** — “a `data.table` with 1..N rows”, “a list
  of exactly 3 elements”. Length applies only to atomic `vector<>`.
- **A vector of reference types** — `vector<function>` /
  `vector<R6<...>>`.
- **A factor’s declared
  [`levels()`](https://rdrr.io/r/base/levels.html)** — a set checks
  realised values, not the level schema (footnote 2).

## 13. Self-consistency checklist

Every base type sits in exactly one category (§2); every modifier it
carries is a ✅ in that category’s row — no per-type exceptions.

`in [interval]` appears only on `integer`/`numeric`/`Date`/`POSIXct`;
integer bounds are whole numbers (`int_bound`).

`in c(set)` appears only on ordered + enumerable atomics; never on
`complex`/`logical`/`raw`; discouraged on `numeric`/`Date`/`POSIXct`
(`==`); on `factor`/`character` it constrains realised values, not
levels (S2).

interval/set bound types match the atom (S2).

`| NA` appears only after an atom (bare or inside `<>`), never on `raw`,
reference, or composite; binds to the nearest atom on its left; never
after a closed `scalar<>`/`vector<>`.

`?` and `| NULL` mean the same thing and never appear together.

`|` is followed only by `NA` (element), `NULL` (slot), or a type
(union); a union member carries its own `| NA`.

intervals use `[ ]` / `] [` only; one top-level comma; brackets/commas
inside an `rexpr` bound are invisible to the tokenizer.

sets are a bare `name_set` (single token) or a bracketed `call_set`;
never [`{ }`](https://rdrr.io/r/base/Paren.html); `enum` is not a
construct (the word appears only as prose).

a length (`,` n / a..b / a..) appears only inside `vector<>`;
`scalar<T, n>` is rejected (no top-level comma); `..` is one token,
valid only in length position.

`function`/`R6<Class>` appear only as bare reference types; `R6` always
names a class.

`list`/`data.table`/`data.frame` carry no `in`/`| NA`/length/`vector<>`;
refined only by nested bullets (S1); bulleted ⇒ named fields (S3).

nested bullets appear only under a slot with exactly one non-NULL
composite alternative (S1); every bullet leaf is itself a valid `slot`.

generated names are `assert_args_<fn>` / `assert_return_<fn>`, and
`assert_args_<Class>__<method>` for R6 (double underscore). \`\`\`
