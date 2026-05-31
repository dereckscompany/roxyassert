# A small hand-rolled scanning parser for roxyassert type annotations.
#
# It turns the parenthesised `(slot)` token at the start of a @param / @return
# description into an abstract syntax tree (a nested list). The grammar is the
# bespoke one documented in `vignette("grammar")`; only its thin *structural*
# layer (`< > [ ] in | ? ..`) is hand-parsed here. The embedded R expressions —
# interval bounds and `c(...)` sets — are captured **verbatim** as strings and
# never re-parsed, honouring the language's "copy what the user wrote" rule.
#
# Internal. The roclet calls `parse_annotation()`. Errors are plain `stop()`s
# (the package keeps a lean dependency surface: assert + roxygen2 only).

# ---- base-type categories ---------------------------------------------------

.ra_ordered_num <- c("integer", "numeric")
.ra_temporal <- c("Date", "POSIXct")
.ra_enumerable <- c("character", "factor")
.ra_plain <- c("complex", "logical")
.ra_atomic <- c(.ra_ordered_num, .ra_temporal, .ra_enumerable, .ra_plain, "raw")
.ra_composite <- c("list", "data.table", "data.frame")

.ra_interval_ok <- c(.ra_ordered_num, .ra_temporal) # accept `in [..]`
.ra_set_ok <- c(.ra_ordered_num, .ra_temporal, .ra_enumerable) # accept `in c(..)`
.ra_na_ok <- c(.ra_ordered_num, .ra_temporal, .ra_enumerable, .ra_plain) # accept `| NA`

# ---- cursor over the annotation text ----------------------------------------

.ra_cursor <- function(s) {
  e <- new.env(parent = emptyenv())
  e$s <- s
  e$chars <- if (nchar(s) == 0L) character(0) else strsplit(s, "", fixed = TRUE)[[1]]
  e$n <- length(e$chars)
  e$pos <- 1L
  return(e)
}

.ra_eof <- function(p) p$pos > p$n
.ra_ch <- function(p) if (.ra_eof(p)) "" else p$chars[p$pos]
.ra_ch_at <- function(p, i) if (i < 1L || i > p$n) "" else p$chars[i]

.ra_ws <- function(p) {
  while (!.ra_eof(p) && p$chars[p$pos] %in% c(" ", "\t", "\n", "\r")) {
    p$pos <- p$pos + 1L
  }
  return(invisible(NULL))
}

.ra_err <- function(p, msg) {
  stop(
    "roxyassert: ",
    msg,
    "\n  annotation: (",
    p$s,
    ")\n  position:   ",
    p$pos,
    call. = FALSE
  )
}

.ra_expect <- function(p, ch) {
  .ra_ws(p)
  if (.ra_ch(p) != ch) {
    .ra_err(p, paste0("expected '", ch, "'"))
  }
  p$pos <- p$pos + 1L
  return(invisible(NULL))
}

# A word: a base type / keyword / identifier. Starts with a letter or `.`
# (so `data.table`, `data.frame` read as one token), continues with
# `[A-Za-z0-9._]`.
.ra_read_word <- function(p) {
  .ra_ws(p)
  start <- p$pos
  if (.ra_eof(p) || !grepl("[A-Za-z.]", p$chars[p$pos])) {
    return("")
  }
  while (!.ra_eof(p) && grepl("[A-Za-z0-9._]", p$chars[p$pos])) {
    p$pos <- p$pos + 1L
  }
  return(substr(p$s, start, p$pos - 1L))
}

.ra_peek_word <- function(p) {
  save <- p$pos
  w <- .ra_read_word(p)
  p$pos <- save
  return(w)
}

.ra_read_int <- function(p) {
  .ra_ws(p)
  start <- p$pos
  while (!.ra_eof(p) && grepl("[0-9]", p$chars[p$pos])) {
    p$pos <- p$pos + 1L
  }
  if (p$pos == start) {
    return(NA_integer_)
  }
  return(as.integer(substr(p$s, start, p$pos - 1L)))
}

# Skip a string/character literal (handles backslash escapes).
.ra_skip_string <- function(p) {
  q <- p$chars[p$pos]
  p$pos <- p$pos + 1L
  while (!.ra_eof(p)) {
    ch <- p$chars[p$pos]
    if (ch == "\\") {
      p$pos <- p$pos + 2L
      next
    }
    p$pos <- p$pos + 1L
    if (ch == q) {
      break
    }
  }
  return(invisible(NULL))
}

# Scan a verbatim span until a top-level character in `stops`. Always balances
# `()` and `{}` and skips string literals. `brackets = TRUE` additionally balances
# `[]` — use it ONLY in a rexpr context (an interval LOW bound, a call_set), where
# `[` opens a subscript; leave it FALSE for the structural annotation scan, where
# a top-level `[`/`]` is an interval delimiter and must pass through. The interval
# HIGH bound is scanned separately (.ra_scan_high), since there `[`/`]` double as
# the open/close delimiter.
.ra_scan <- function(p, stops, brackets = FALSE) {
  open <- if (brackets) c("(", "[", "{") else c("(", "{")
  close <- if (brackets) c(")", "]", "}") else c(")", "}")
  start <- p$pos
  depth <- 0L
  while (!.ra_eof(p)) {
    ch <- p$chars[p$pos]
    if (depth == 0L && ch %in% stops) {
      break
    }
    if (ch %in% c("\"", "'", "`")) {
      .ra_skip_string(p)
      next
    }
    if (ch %in% open) {
      depth <- depth + 1L
    } else if (ch %in% close) {
      if (depth == 0L) {
        break
      }
      depth <- depth - 1L
    }
    p$pos <- p$pos + 1L
  }
  return(trimws(substr(p$s, start, p$pos - 1L)))
}

# Scan an interval's HIGH bound, returning list(text=, open=). The closing
# delimiter is a top-level `]` (closed) or `[` (open); brackets WITHIN the bound
# (a subscript `df[["t"]]`, a call) are balanced first. A `[` at depth 0 closes an
# OPEN interval iff what follows it is a structural terminator rather than a
# subscript index (.ra_high_close_bracket). p stops ON the closing bracket.
.ra_scan_high <- function(p) {
  start <- p$pos
  depth <- 0L
  while (!.ra_eof(p)) {
    ch <- p$chars[p$pos]
    if (ch %in% c("\"", "'", "`")) {
      .ra_skip_string(p)
      next
    }
    if (depth == 0L && ch == "]") {
      return(list(text = trimws(substr(p$s, start, p$pos - 1L)), open = FALSE))
    }
    if (depth == 0L && ch == "[" && .ra_high_close_bracket(p)) {
      return(list(text = trimws(substr(p$s, start, p$pos - 1L)), open = TRUE))
    }
    if (ch %in% c("(", "[", "{")) {
      depth <- depth + 1L
    } else if (ch %in% c(")", "]", "}")) {
      depth <- depth - 1L
    }
    p$pos <- p$pos + 1L
  }
  return(.ra_err(p, "expected ']' or '[' to close the interval"))
}

# Is the `[` at p$pos the OPEN-interval close rather than a subscript opener? It
# is when the next non-space character is a structural terminator — a `|` (union),
# `>` (closing a scalar<>/vector<>), `,` (a vector length separator), or the end —
# none of which can begin a subscript's index expression. This bounds the decision
# to the current interval, so `]0, 1[ | numeric in ]2, 3]` does not see the later
# alternative's `]`. (A subscript bound like `df[["t"]]` is followed by `[`/index.)
.ra_high_close_bracket <- function(p) {
  i <- p$pos + 1L
  while (i <= p$n && p$chars[i] %in% c(" ", "\t", "\n", "\r")) {
    i <- i + 1L
  }
  if (i > p$n) {
    return(TRUE)
  }
  return(p$chars[i] %in% c("|", ">", ","))
}

.ra_check_rexpr <- function(txt, p, what) {
  ok <- tryCatch(
    {
      parse(text = txt)
      TRUE
    },
    error = function(e) FALSE
  )
  if (!ok) {
    .ra_err(p, paste0(what, " is not a valid R expression: '", txt, "'"))
  }
  return(invisible(NULL))
}

# ---- entry point ------------------------------------------------------------

#' Parse a roxyassert annotation
#'
#' Reads the parenthesised `(slot)` token at the start of `text` and returns its
#' AST (a nested list). Returns `NULL` when `text` does not begin with `(`, so
#' an untyped tag is simply skipped.
#'
#' @param text A single string: the `@param` / `@return` description.
#' @return The annotation AST, or `NULL` if there is no leading `(...)` token.
#' @keywords internal
#' @noRd
parse_annotation <- function(text) {
  if (length(text) != 1L || is.na(text)) {
    return(NULL)
  }
  p <- .ra_cursor(text)
  .ra_ws(p)
  if (.ra_ch(p) != "(") {
    return(NULL)
  }
  p$pos <- p$pos + 1L
  inner <- .ra_scan(p, stops = ")")
  if (.ra_ch(p) != ")") {
    .ra_err(p, "unterminated '(' in annotation")
  }
  sp <- .ra_cursor(inner)
  ast <- .ra_parse_slot(sp)
  .ra_ws(sp)
  if (!.ra_eof(sp)) {
    .ra_err(sp, paste0("unexpected trailing input: '", substr(sp$s, sp$pos, sp$n), "'"))
  }
  ast <- .ra_normalize_promise(ast)
  # Everything after the closing ')' is free-text description, which may carry
  # nested `- name (slot)` field bullets (a composite record / typed columns, S1).
  rest <- if (p$pos < p$n) substr(p$s, p$pos + 1L, p$n) else ""
  # A nullability '?' belongs INSIDE the parens (slot tail); catch the misplaced
  # `(slot)?` form (a '?' immediately after ')') rather than silently dropping it
  # (which would read as non-null). A '?' later in the prose is just description.
  if (substr(rest, 1L, 1L) == "?") {
    .ra_err(p, "'?' must sit inside the parentheses: write (slot?), not (slot)?")
  }
  tree <- .ra_collect_bullets(rest)
  if (length(tree) > 0L) {
    ast <- .ra_attach_fields(ast, lapply(tree, .ra_finalize_bullet))
  }
  return(ast)
}

# ---- nested field bullets (S1 / S3) -----------------------------------------

# Gather the `- ` bullet lines of a description into an indentation tree. Each
# node is list(content = <text after "- ">, children = list(...)); non-bullet
# lines (the inline description, wrapped prose) are ignored.
.ra_collect_bullets <- function(text) {
  if (!nzchar(trimws(text))) {
    return(list())
  }
  lines <- strsplit(text, "\n", fixed = TRUE)[[1]]
  items <- list()
  for (ln in lines) {
    m <- regmatches(ln, regexec("^([ \t]*)-[ \t]+(.*)$", ln))[[1]]
    if (length(m) == 3L) {
      items[[length(items) + 1L]] <- list(indent = nchar(m[[2]]), content = trimws(m[[3]]))
    }
  }
  if (length(items) == 0L) {
    return(list())
  }
  return(.ra_nest_bullets(items, 1L, -1L)$nodes)
}

# Turn the flat (indent, content) list into a tree: an item is a child of the
# nearest preceding item with strictly smaller indentation.
.ra_nest_bullets <- function(items, i, min_indent) {
  nodes <- list()
  while (i <= length(items)) {
    it <- items[[i]]
    if (it$indent <= min_indent) {
      break
    }
    i <- i + 1L
    sub <- .ra_nest_bullets(items, i, it$indent)
    nodes[[length(nodes) + 1L]] <- list(content = it$content, children = sub$nodes)
    i <- sub$pos
  }
  return(list(nodes = nodes, pos = i))
}

# One bullet -> list(name=, ast=): its `name (slot)` head, plus its own children
# attached as fields when the slot is a bare composite.
.ra_finalize_bullet <- function(node) {
  bp <- .ra_cursor(node$content)
  name <- .ra_read_bullet_name(bp)
  .ra_expect(bp, "(")
  inner <- .ra_scan(bp, stops = ")")
  if (.ra_ch(bp) != ")") {
    .ra_err(bp, "unterminated '(' in field bullet")
  }
  bp$pos <- bp$pos + 1L # consume ')'
  # the same misplaced-`?` guard as the top level (a '?' right after ')')
  if (.ra_ch(bp) == "?") {
    .ra_err(bp, "'?' must sit inside the parentheses: write (slot?), not (slot)?")
  }
  sp <- .ra_cursor(inner)
  ast <- .ra_parse_slot(sp)
  .ra_ws(sp)
  if (!.ra_eof(sp)) {
    .ra_err(sp, paste0("unexpected trailing input in field slot: '", substr(sp$s, sp$pos, sp$n), "'"))
  }
  if (length(node$children) > 0L) {
    ast <- .ra_attach_fields(ast, lapply(node$children, .ra_finalize_bullet))
  }
  return(list(name = name, ast = ast))
}

# The field name: the single token before the slot's `(`, with optional **bold**.
.ra_read_bullet_name <- function(p) {
  nm <- trimws(.ra_scan(p, stops = "("))
  nm <- trimws(gsub("^\\*\\*|\\*\\*$", "", nm))
  if (nm == "") {
    .ra_err(p, "field bullet needs a name before its '(type)'")
  }
  return(nm)
}

# S1: attach field bullets to a slot, which must be a single bare composite.
.ra_attach_fields <- function(ast, fields) {
  reject <- function(reason) {
    stop(
      "roxyassert: nested field bullets require a single bare composite ",
      "(list / data.table / data.frame); ",
      reason,
      call. = FALSE
    )
  }
  if (length(ast$alternatives) != 1L) {
    reject("the slot is a union of several types")
  }
  node <- ast$alternatives[[1]]
  if (!identical(node$kind, "composite")) {
    kind <- if (identical(node$kind, "atomic")) node$base else node$kind
    reject(paste0("the slot is a '", kind, "'"))
  }
  if (!is.null(node$element)) {
    reject("a list<T> is a leaf and takes no bullets")
  }
  node$fields <- fields
  ast$alternatives[[1]] <- node
  return(ast)
}

# ---- slot: type ( "|" type )* ( ( "|" NULL ) | "?" )? ------------------------

.ra_parse_slot <- function(p) {
  alts <- list(.ra_parse_type(p))
  null_ok <- FALSE
  repeat {
    .ra_ws(p)
    ch <- .ra_ch(p)
    if (ch == "?") {
      p$pos <- p$pos + 1L
      null_ok <- TRUE
      .ra_ws(p)
      if (!.ra_eof(p)) {
        .ra_err(p, "nothing may follow '?'")
      }
      break
    } else if (ch == "|") {
      save <- p$pos
      p$pos <- p$pos + 1L
      w <- .ra_peek_word(p)
      if (w == "NULL") {
        .ra_read_word(p)
        null_ok <- TRUE
        .ra_ws(p)
        if (!.ra_eof(p)) {
          .ra_err(p, "nothing may follow '| NULL'")
        }
        break
      } else if (w == "NA") {
        .ra_err(p, "'| NA' must sit inside the element (e.g. scalar<numeric | NA>), not after a closed type")
      } else {
        p$pos <- save + 1L
        alts[[length(alts) + 1L]] <- .ra_parse_type(p)
      }
    } else {
      break
    }
  }
  return(list(kind = "slot", alternatives = alts, null_ok = null_ok, async = FALSE))
}

# A promise<T> denotes the resolved type T plus an async marker; a union mixing
# promise<X> with a bare X (the "sync-or-async delivery" pattern) collapses to a
# single X. roxyassert validates only the resolved value and emits no promise
# code (the caller wires the async); this just records `async = TRUE` and reduces
# the slot to its resolved type, so generation and field bullets see plain T.
.ra_normalize_promise <- function(ast) {
  has_promise <- any(vapply(ast$alternatives, function(a) identical(a$kind, "promise"), logical(1)))
  if (!has_promise) {
    return(ast)
  }
  resolved <- lapply(ast$alternatives, function(a) if (identical(a$kind, "promise")) a$inner else a)
  first <- resolved[[1]]
  if (!all(vapply(resolved, function(a) identical(a, first), logical(1)))) {
    stop(
      "roxyassert: a union with a promise must resolve to a single type ",
      "(e.g. (T | promise<T>)); its alternatives differ.",
      call. = FALSE
    )
  }
  ast$alternatives <- list(first)
  ast$async <- TRUE
  return(ast)
}

# ---- type --------------------------------------------------------------------

.ra_parse_type <- function(p) {
  w <- .ra_read_word(p)
  if (w == "") {
    .ra_err(p, "expected a type")
  }

  if (w == "scalar" || w == "vector") {
    .ra_expect(p, "<")
    node <- .ra_parse_wrapped(p)
    length <- NULL
    if (w == "vector") {
      .ra_expect(p, ",")
      length <- .ra_parse_length(p)
    }
    .ra_expect(p, ">")
    node$shape <- w
    node$length <- length
    return(node)
  }

  if (w == "any") {
    return(list(kind = "wildcard", shape = "bare", length = NULL))
  }
  if (w == "function") {
    return(list(kind = "function"))
  }
  if (w == "R6") {
    .ra_ws(p)
    if (.ra_ch(p) != "<") {
      .ra_err(p, "R6 must name a class: R6<Class>")
    }
    p$pos <- p$pos + 1L
    cls <- .ra_read_word(p)
    if (cls == "") {
      .ra_err(p, "R6 must name a class: R6<Class>")
    }
    .ra_expect(p, ">")
    return(list(kind = "r6", class = cls))
  }
  if (w == "promise") {
    .ra_ws(p)
    if (.ra_ch(p) != "<") {
      .ra_err(p, "promise must name its resolved type: promise<T>")
    }
    p$pos <- p$pos + 1L
    inner <- .ra_parse_type(p)
    .ra_expect(p, ">")
    return(list(kind = "promise", inner = inner))
  }
  if (w %in% .ra_composite) {
    element <- NULL
    .ra_ws(p)
    if (w == "list" && .ra_ch(p) == "<") {
      p$pos <- p$pos + 1L
      element <- .ra_parse_type(p)
      .ra_expect(p, ">")
    }
    return(list(kind = "composite", base = w, element = element, fields = NULL))
  }
  if (w %in% .ra_atomic) {
    node <- .ra_parse_atom_rest(p, w)
    node$shape <- "bare"
    node$length <- NULL
    return(node)
  }
  return(.ra_err(p, paste0("unknown type '", w, "'")))
}

# Inside scalar<...> / vector<...>: an atom or the `any` wildcard.
.ra_parse_wrapped <- function(p) {
  w <- .ra_read_word(p)
  if (w == "any") {
    return(list(kind = "wildcard"))
  }
  if (w %in% .ra_atomic) {
    return(.ra_parse_atom_rest(p, w))
  }
  return(.ra_err(p, paste0("scalar<>/vector<> may only wrap an atomic type or 'any', not '", w, "'")))
}

# After the base word: optional `in (interval | set)` then optional `| NA`.
.ra_parse_atom_rest <- function(p, base) {
  interval <- NULL
  set <- NULL
  na_ok <- FALSE

  if (.ra_peek_word(p) == "in") {
    .ra_read_word(p)
    .ra_ws(p)
    ch <- .ra_ch(p)
    if (ch == "[" || ch == "]") {
      if (!(base %in% .ra_interval_ok)) {
        .ra_err(p, paste0("interval not allowed on '", base, "' (only integer/numeric/Date/POSIXct)"))
      }
      interval <- .ra_parse_interval(p, base)
    } else {
      if (!(base %in% .ra_set_ok)) {
        .ra_err(p, paste0("set not allowed on '", base, "' (only ordered + enumerable atomics)"))
      }
      set <- .ra_parse_set(p, base)
    }
  }

  .ra_ws(p)
  if (.ra_ch(p) == "|") {
    save <- p$pos
    p$pos <- p$pos + 1L
    if (.ra_peek_word(p) == "NA") {
      .ra_read_word(p)
      if (!(base %in% .ra_na_ok)) {
        .ra_err(p, paste0("'| NA' not allowed on '", base, "' (raw has no NA representation)"))
      }
      na_ok <- TRUE
    } else {
      p$pos <- save # a slot-level union `|`, not `| NA`
    }
  }

  return(list(kind = "atomic", base = base, interval = interval, set = set, na_ok = na_ok))
}

# ---- interval ----------------------------------------------------------------

.ra_parse_interval <- function(p, base) {
  lo_open <- (.ra_ch(p) == "]")
  p$pos <- p$pos + 1L
  lo_txt <- .ra_scan(p, stops = ",", brackets = TRUE)
  .ra_expect(p, ",")
  hi_scan <- .ra_scan_high(p)
  hi_txt <- hi_scan$text
  hi_open <- hi_scan$open
  p$pos <- p$pos + 1L # consume the closing ']' / '['

  lo <- .ra_classify_bound(lo_txt, base, "low", p)
  hi <- .ra_classify_bound(hi_txt, base, "high", p)

  # A both-sentinel interval imposes no bound and would lower to a bound-less
  # assert_between() that aborts at runtime; reject it here instead.
  if (!is.na(lo$sentinel) && !is.na(hi$sentinel)) {
    .ra_err(p, "degenerate interval ]-Inf, Inf[: both ends are sentinels, so it bounds nothing; drop the 'in [..]'")
  }

  # S4: reject an empty / reversed interval for literal numeric bounds.
  if (is.na(lo$sentinel) && is.na(hi$sentinel) && grepl("^-?[0-9.]+$", lo$text) && grepl("^-?[0-9.]+$", hi$text)) {
    lov <- suppressWarnings(as.numeric(lo$text))
    hiv <- suppressWarnings(as.numeric(hi$text))
    if (!is.na(lov) && !is.na(hiv) && (lov > hiv || (lov == hiv && (lo_open || hi_open)))) {
      .ra_err(
        p,
        paste0(
          "empty / reversed interval: ",
          if (lo_open) "]" else "[",
          lo$text,
          ", ",
          hi$text,
          if (hi_open) "[" else "]"
        )
      )
    }
  }

  return(list(lo = lo, hi = hi, lo_open = lo_open, hi_open = hi_open))
}

# Classify a bound: a side-gated `Inf`/`-Inf` sentinel, or a verbatim value.
.ra_classify_bound <- function(txt, base, side, p) {
  if (txt == "") {
    .ra_err(p, "empty interval bound")
  }
  if (txt == "Inf") {
    if (side != "high") {
      .ra_err(p, "'Inf' may only be the high bound (use '-Inf' for the low)")
    }
    return(list(text = "Inf", sentinel = "Inf"))
  }
  if (txt == "-Inf") {
    if (side != "low") {
      .ra_err(p, "'-Inf' may only be the low bound (use 'Inf' for the high)")
    }
    return(list(text = "-Inf", sentinel = "-Inf"))
  }
  if (base == "integer") {
    if (!grepl("^-?[0-9]+$", txt)) {
      .ra_err(p, paste0("integer bound must be a whole number or -Inf/Inf, got '", txt, "'"))
    }
  } else if (base %in% .ra_temporal) {
    if (grepl("^-?[0-9]+(\\.[0-9]+)?$", txt)) {
      .ra_err(
        p,
        paste0("'", base, "' bound must be a class-matching expression ", "(e.g. as.Date(\"...\")), not a bare number")
      )
    }
    .ra_check_rexpr(txt, p, paste0(base, " bound"))
  } else {
    # numeric: a signed number, or any verbatim R expression.
    if (!grepl("^-?[0-9]+(\\.[0-9]+)?$", txt)) {
      .ra_check_rexpr(txt, p, "numeric bound")
    }
  }
  return(list(text = txt, sentinel = NA_character_))
}

# ---- set & length ------------------------------------------------------------

.ra_parse_set <- function(p, base) {
  txt <- .ra_scan(p, stops = c(",", "|", ">", ")", "?"), brackets = TRUE)
  if (txt == "") {
    .ra_err(p, "empty set after 'in'")
  }
  # A bare name (name_set) or a call/expression (call_set); both emitted verbatim.
  if (grepl("[^A-Za-z0-9._]", txt)) {
    .ra_check_rexpr(txt, p, "set")
  }
  .ra_check_set_elements(txt, base, p)
  return(list(text = txt))
}

# S2: an INLINE `c(...)` literal set must have elements of the atom's type, with
# no coercion. An opaque name_set / rexpr (ORDER_SIDE, pkg::CONST, VALUES[...])
# is trusted and left unchecked.
.ra_check_set_elements <- function(txt, base, p) {
  elems <- .ra_inline_set_elements(txt)
  if (is.null(elems)) {
    return(invisible(NULL))
  }
  for (e in elems) {
    .ra_check_set_element(e, base, p)
  }
  return(invisible(NULL))
}

# The deparsed elements of a literal `c(...)` call, or NULL if `txt` is anything
# else (a bare name, a `::`, an index, ...).
.ra_inline_set_elements <- function(txt) {
  expr <- tryCatch(parse(text = txt)[[1]], error = function(e) NULL)
  if (is.null(expr) || !is.call(expr) || !identical(expr[[1]], as.name("c"))) {
    return(NULL)
  }
  args <- as.list(expr)[-1]
  elems <- vapply(args, function(a) paste(deparse(a), collapse = ""), character(1))
  return(elems[nzchar(elems)]) # drop a trailing-comma empty arg, e.g. c(1L,)
}

.ra_check_set_element <- function(e, base, p) {
  is_num <- grepl("^-?[0-9]+(\\.[0-9]+)?$", e)
  is_int_l <- grepl("^-?[0-9]+L$", e)
  is_str <- grepl("^[\"']", e)
  if (base == "integer") {
    if (is_num) {
      .ra_err(
        p,
        paste0("integer set element '", e, "' needs the 'L' suffix (c(1L, 2L, 3L)); a bare number is not coerced")
      )
    }
    if (!is_int_l) {
      .ra_err(p, paste0("integer set element must be an integer literal like 2L, got '", e, "'"))
    }
  } else if (base %in% .ra_enumerable) {
    if (!is_str) {
      .ra_err(p, paste0("'", base, "' set element must be a string literal, got '", e, "'"))
    }
  } else if (base == "numeric") {
    if (is_str || is_int_l) {
      .ra_err(p, paste0("numeric set element must be a number, got '", e, "'"))
    }
  } else if (base %in% .ra_temporal) {
    if (is_num || is_int_l) {
      .ra_err(
        p,
        paste0(
          "'",
          base,
          "' set element must be a class-matching expression (e.g. as.Date(\"...\")), not a bare number"
        )
      )
    }
  }
  return(invisible(NULL))
}

.ra_parse_length <- function(p) {
  lo <- .ra_read_int(p)
  if (is.na(lo)) {
    .ra_err(p, "expected a length")
  }
  .ra_ws(p)
  if (.ra_ch(p) == "." && .ra_ch_at(p, p$pos + 1L) == ".") {
    p$pos <- p$pos + 2L # consume ".."
    hi <- .ra_read_int(p)
    return(list(min = lo, max = if (is.na(hi)) Inf else hi))
  }
  if (.ra_ch(p) == ".") {
    .ra_err(p, "a single '.' is not a length; use '..' for a range")
  }
  return(list(min = lo, max = lo))
}
