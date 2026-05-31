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

# Scan a verbatim span until a top-level character in `stops`. Tracks `()`/`{}`
# nesting and skips string literals; `[`/`]` are NOT counted as nesting, so a
# top-level `[`/`]` can act as an interval delimiter (the documented limitation:
# an interval bound may not contain a top-level subscript — wrap it in a call).
.ra_scan <- function(p, stops) {
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
    if (ch %in% c("(", "{")) {
      depth <- depth + 1L
    } else if (ch %in% c(")", "}")) {
      if (depth == 0L) {
        break
      }
      depth <- depth - 1L
    }
    p$pos <- p$pos + 1L
  }
  return(trimws(substr(p$s, start, p$pos - 1L)))
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
  return(list(kind = "slot", alternatives = alts, null_ok = null_ok))
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
      set <- .ra_parse_set(p)
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
  lo_txt <- .ra_scan(p, stops = ",")
  .ra_expect(p, ",")
  hi_txt <- .ra_scan(p, stops = c("]", "["))
  hb <- .ra_ch(p)
  if (!(hb %in% c("]", "["))) {
    .ra_err(p, "expected ']' or '[' to close the interval")
  }
  hi_open <- (hb == "[")
  p$pos <- p$pos + 1L

  lo <- .ra_classify_bound(lo_txt, base, "low", p)
  hi <- .ra_classify_bound(hi_txt, base, "high", p)

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
      .ra_err(p, paste0("integer bound must be a whole number or '±Inf', got '", txt, "'"))
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

.ra_parse_set <- function(p) {
  txt <- .ra_scan(p, stops = c(",", "|", ">", ")", "?"))
  if (txt == "") {
    .ra_err(p, "empty set after 'in'")
  }
  # A bare name (name_set) or a call/expression (call_set); both emitted verbatim.
  if (grepl("[^A-Za-z0-9._]", txt)) {
    .ra_check_rexpr(txt, p, "set")
  }
  return(list(text = txt))
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
