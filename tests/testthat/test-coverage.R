# Exhaustive coverage: every grammar construct, paired with its exact generated
# `assert_*()` lowering. Read this file as the human-checkable "annotation ->
# generated code" record; each expectation is the verified output of the package.
# `genf()` (helper-roxyassert.R) lowers a full `(annotation)` to its check lines.

test_that("bare atomic = vector, NA rejected by default (raw is exempt)", {
  expect_equal(genf("(character)"), c("assert_character(x)", "assert_no_missing_values(x)"))
  expect_equal(genf("(numeric)"), c("assert_double(x)", "assert_no_missing_values(x)"))
  expect_equal(genf("(integer)"), c("assert_integer(x)", "assert_no_missing_values(x)"))
  expect_equal(genf("(logical)"), c("assert_logical(x)", "assert_no_missing_values(x)"))
  expect_equal(genf("(complex)"), c("assert_complex(x)", "assert_no_missing_values(x)"))
  expect_equal(genf("(raw)"), "assert_raw(x)")
  expect_equal(genf("(Date)"), c("assert_date(x)", "assert_no_missing_values(x)"))
  expect_equal(genf("(POSIXct)"), c("assert_datetime(x)", "assert_no_missing_values(x)"))
  expect_equal(genf("(factor)"), c("assert_factor(x)", "assert_no_missing_values(x)"))
})

test_that("wildcard `any` asserts only length / nullability", {
  expect_equal(genf("(any)"), character())
  expect_equal(genf("(any?)"), character())
  expect_equal(genf("(scalar<any>)"), "assert_length(x, 1L)")
  expect_equal(genf("(vector<any, 3>)"), "assert_length(x, 3L)")
  expect_equal(genf("(vector<any, 1..>)"), "assert_minimum_length(x, 1L)")
})

test_that("scalar shapes (length 1)", {
  expect_equal(genf("(scalar<character>)"), "assert_scalar_character(x)")
  expect_equal(genf("(scalar<numeric>)"), "assert_scalar_double(x)")
  expect_equal(genf("(scalar<complex>)"), "assert_scalar_complex(x)")
  expect_equal(genf("(scalar<raw>)"), "assert_scalar_raw(x)")
  expect_equal(genf("(scalar<logical | NA>)"), c("assert_logical(x)", "assert_length(x, 1L)"))
})

test_that("reference types are bare, length-1", {
  expect_equal(genf("(function)"), "assert_function(x)")
  expect_equal(genf("(function?)"), c("if (!is.null(x)) {", "  assert_function(x)", "}"))
  expect_equal(genf("(R6<Engine>)"), 'assert_class(x, "Engine")')
  expect_equal(genf("(R6<Engine> | NULL)"), c("if (!is.null(x)) {", '  assert_class(x, "Engine")', "}"))
})

test_that("homogeneous list<T>: flat -> assert_list_of, rich -> element loop", {
  expect_equal(genf("(list<character>)"), c("assert_list(x)", 'assert_list_of(x, "character")'))
  expect_equal(genf("(list<numeric>)"), c("assert_list(x)", 'assert_list_of(x, "double")'))
  expect_equal(genf("(list<any>)"), "assert_list(x)")
  expect_equal(
    genf("(list<scalar<numeric>>)"),
    c("assert_list(x)", "for (.x in x) {", "  assert_scalar_double(.x)", "}")
  )
  expect_equal(genf("(list<R6<Engine>>)"), c("assert_list(x)", "for (.x in x) {", '  assert_class(.x, "Engine")', "}"))
  expect_equal(genf("(list<function>)"), c("assert_list(x)", "for (.x in x) {", "  assert_function(.x)", "}"))
  expect_equal(genf("(list<data.table>)"), c("assert_list(x)", "for (.x in x) {", "  assert_data_table(.x)", "}"))
})

test_that("vector lengths: exact, range, minimum; 0.. is no constraint", {
  expect_equal(
    genf("(vector<numeric, 10>)"),
    c("assert_double(x)", "assert_no_missing_values(x)", "assert_length(x, 10L)")
  )
  expect_equal(
    genf("(vector<numeric, 1..10>)"),
    c("assert_double(x)", "assert_no_missing_values(x)", "assert_length_between(x, 1L, 10L)")
  )
  expect_equal(
    genf("(vector<integer, 2..>)"),
    c("assert_integer(x)", "assert_no_missing_values(x)", "assert_minimum_length(x, 2L)")
  )
  expect_equal(genf("(vector<character, 0..>)"), c("assert_character(x)", "assert_no_missing_values(x)"))
  expect_equal(
    genf("(vector<logical, 3>)"),
    c("assert_logical(x)", "assert_no_missing_values(x)", "assert_length(x, 3L)")
  )
  expect_equal(genf("(vector<raw, 32>)"), c("assert_raw(x)", "assert_length(x, 32L)"))
})

test_that("vector with an element set / interval, plus length", {
  expect_equal(
    genf('(vector<factor in c("a", "b"), 2..>)'),
    c(
      "assert_factor(x)",
      "assert_no_missing_values(x)",
      "assert_minimum_length(x, 2L)",
      'assert_values_in_set(as.character(x), c("a", "b"))'
    )
  )
  expect_equal(
    genf("(vector<numeric in [0, 1], 1..>)"),
    c(
      "assert_double(x)",
      "assert_no_missing_values(x)",
      "assert_minimum_length(x, 1L)",
      "assert_between(x, lower = 0, upper = 1)"
    )
  )
  expect_equal(
    genf('(vector<Date in [as.Date("2024-01-01"), as.Date("2024-12-31")], 1..7>)'),
    c(
      "assert_date(x)",
      "assert_no_missing_values(x)",
      "assert_length_between(x, 1L, 7L)",
      'assert_between(x, lower = as.Date("2024-01-01"), upper = as.Date("2024-12-31"))'
    )
  )
})

test_that("interval openness, sentinels, and bound types (verbatim)", {
  expect_equal(
    genf("(scalar<numeric in [0, 1]>)"),
    c("assert_scalar_double(x)", "assert_between(x, lower = 0, upper = 1)")
  )
  expect_equal(
    genf("(scalar<numeric in ]0, 1[>)"),
    c(
      "assert_scalar_double(x)",
      "assert_between(x, lower = 0, lower_inclusive = FALSE, upper = 1, upper_inclusive = FALSE)"
    )
  )
  expect_equal(
    genf("(scalar<numeric in ]0, 1]>)"),
    c("assert_scalar_double(x)", "assert_between(x, lower = 0, lower_inclusive = FALSE, upper = 1)")
  )
  expect_equal(
    genf("(scalar<numeric in [-1.5, 2.5]>)"),
    c("assert_scalar_double(x)", "assert_between(x, lower = -1.5, upper = 2.5)")
  )
  expect_equal(
    genf("(scalar<numeric in ]0, Inf[>)"),
    c("assert_scalar_double(x)", "assert_between(x, lower = 0, lower_inclusive = FALSE)")
  )
  expect_equal(genf("(scalar<numeric in ]-Inf, 0]>)"), c("assert_scalar_double(x)", "assert_between(x, upper = 0)"))
  expect_equal(genf("(scalar<integer in [1, Inf[>)"), c("assert_scalar_integer(x)", "assert_between(x, lower = 1)"))
  expect_equal(genf("(scalar<integer in ]-Inf, 0]>)"), c("assert_scalar_integer(x)", "assert_between(x, upper = 0)"))
  expect_equal(
    genf("(numeric in [0, 1])"),
    c("assert_double(x)", "assert_no_missing_values(x)", "assert_between(x, lower = 0, upper = 1)")
  )
  expect_equal(
    genf('(scalar<Date in [as.Date("2024-01-01"), as.Date("2026-12-31")]>)'),
    c("assert_scalar_date(x)", 'assert_between(x, lower = as.Date("2024-01-01"), upper = as.Date("2026-12-31"))')
  )
  expect_equal(
    genf('(scalar<Date in [as.Date("2024-01-01"), Inf[>)'),
    c("assert_scalar_date(x)", 'assert_between(x, lower = as.Date("2024-01-01"))')
  )
  expect_equal(
    genf('(scalar<Date in ]-Inf, as.Date("2024-12-31")]>)'),
    c("assert_scalar_date(x)", 'assert_between(x, upper = as.Date("2024-12-31"))')
  )
  expect_equal(
    genf('(scalar<POSIXct in [as.POSIXct("2024-01-01 00:00", tz = "America/New_York"), Inf[>)'),
    c("assert_scalar_datetime(x)", 'assert_between(x, lower = as.POSIXct("2024-01-01 00:00", tz = "America/New_York"))')
  )
  # a high bound containing a [[ ]] subscript (bracket-balanced rexpr scan)
  expect_equal(
    genf('(scalar<numeric in [0, df[["t"]]]>)'),
    c("assert_scalar_double(x)", 'assert_between(x, lower = 0, upper = df[["t"]])')
  )
})

test_that("sets: scalar vs vector, factor via as.character, name/call sets", {
  expect_equal(
    genf('(scalar<character in c("BUY", "SELL")>)'),
    c("assert_scalar_character(x)", 'assert_value_in_set(x, c("BUY", "SELL"))')
  )
  expect_equal(
    genf('(character in c("BUY", "SELL"))'),
    c("assert_character(x)", "assert_no_missing_values(x)", 'assert_values_in_set(x, c("BUY", "SELL"))')
  )
  expect_equal(
    genf("(scalar<character in ORDER_SIDE>)"),
    c("assert_scalar_character(x)", "assert_value_in_set(x, ORDER_SIDE)")
  )
  expect_equal(
    genf("(integer in c(1L, 2L, 3L))"),
    c("assert_integer(x)", "assert_no_missing_values(x)", "assert_values_in_set(x, c(1L, 2L, 3L))")
  )
  expect_equal(
    genf("(scalar<integer in c(1L, 2L, 3L)>)"),
    c("assert_scalar_integer(x)", "assert_value_in_set(x, c(1L, 2L, 3L))")
  )
  expect_equal(
    genf('(factor in c("low", "med", "high"))'),
    c(
      "assert_factor(x)",
      "assert_no_missing_values(x)",
      'assert_values_in_set(as.character(x), c("low", "med", "high"))'
    )
  )
  expect_equal(
    genf('(Date in c(as.Date("2024-01-01"), as.Date("2024-06-30")))'),
    c(
      "assert_date(x)",
      "assert_no_missing_values(x)",
      'assert_values_in_set(x, c(as.Date("2024-01-01"), as.Date("2024-06-30")))'
    )
  )
  expect_equal(
    genf("(numeric in c(0.25, 0.5, 1.0))"),
    c("assert_double(x)", "assert_no_missing_values(x)", "assert_values_in_set(x, c(0.25, 0.5, 1.0))")
  )
  expect_equal(
    genf("(numeric in VALUES[VALUES > 0])"),
    c("assert_double(x)", "assert_no_missing_values(x)", "assert_values_in_set(x, VALUES[VALUES > 0])")
  )
})

test_that("| NA toggles missing-value handling; binds to its atom", {
  expect_equal(genf("(numeric | NA)"), "assert_double(x)")
  expect_equal(genf("(scalar<numeric | NA>)"), c("assert_double(x)", "assert_length(x, 1L)"))
  expect_equal(genf("(scalar<integer | NA>)"), c("assert_integer(x)", "assert_length(x, 1L)"))
  expect_equal(genf("(scalar<POSIXct | NA>)"), c("assert_datetime(x)", "assert_length(x, 1L)"))
  expect_equal(genf("(complex | NA)"), "assert_complex(x)")
  expect_equal(genf("(vector<numeric | NA, 10>)"), c("assert_double(x)", "assert_length(x, 10L)"))
  expect_equal(
    genf("(numeric in [0, 1] | NA)"),
    c("assert_double(x)", "assert_between(x, lower = 0, upper = 1, na_ok = TRUE)")
  )
  expect_equal(
    genf('(factor in c("low", "med", "high") | NA)'),
    c("assert_factor(x)", 'assert_values_in_set(as.character(x), c(c("low", "med", "high"), NA))')
  )
})

test_that("nullable slot wraps checks in if (!is.null(...))", {
  expect_equal(genf("(scalar<numeric>?)"), c("if (!is.null(x)) {", "  assert_scalar_double(x)", "}"))
  expect_equal(genf("(scalar<numeric> | NULL)"), c("if (!is.null(x)) {", "  assert_scalar_double(x)", "}"))
  expect_equal(
    genf("(character?)"),
    c("if (!is.null(x)) {", "  assert_character(x)", "  assert_no_missing_values(x)", "}")
  )
})

test_that("type unions lower to assert_any_of, one thunk per alternative", {
  expect_equal(
    genf("(numeric | character)"),
    c(
      "assert_any_of(",
      "  x,",
      "  function(.x) {",
      "    assert_double(.x)",
      "    assert_no_missing_values(.x)",
      "  },",
      "  function(.x) {",
      "    assert_character(.x)",
      "    assert_no_missing_values(.x)",
      "  }",
      ")"
    )
  )
  # | NA binds to character only -> its thunk omits the missing-value check
  expect_equal(
    genf("(numeric | character | NA)"),
    c(
      "assert_any_of(",
      "  x,",
      "  function(.x) {",
      "    assert_double(.x)",
      "    assert_no_missing_values(.x)",
      "  },",
      "  function(.x) {",
      "    assert_character(.x)",
      "  }",
      ")"
    )
  )
  expect_equal(
    genf("(R6<Reader> | R6<Writer>)"),
    c(
      "assert_any_of(",
      "  x,",
      "  function(.x) {",
      '    assert_class(.x, "Reader")',
      "  },",
      "  function(.x) {",
      '    assert_class(.x, "Writer")',
      "  }",
      ")"
    )
  )
  expect_equal(genf("(data.table | NULL)"), c("if (!is.null(x)) {", "  assert_data_table(x)", "}"))
})

test_that("union of open intervals (regression) and everything-at-once", {
  expect_equal(
    genf("(numeric in ]0, 1[ | numeric in ]2, 3])"),
    c(
      "assert_any_of(",
      "  x,",
      "  function(.x) {",
      "    assert_double(.x)",
      "    assert_no_missing_values(.x)",
      "    assert_between(.x, lower = 0, lower_inclusive = FALSE, upper = 1, upper_inclusive = FALSE)",
      "  },",
      "  function(.x) {",
      "    assert_double(.x)",
      "    assert_no_missing_values(.x)",
      "    assert_between(.x, lower = 2, lower_inclusive = FALSE, upper = 3)",
      "  }",
      ")"
    )
  )
  expect_equal(
    genf("(vector<numeric in ]0, 1] | NA, 1..100>?)"),
    c(
      "if (!is.null(x)) {",
      "  assert_double(x)",
      "  assert_length_between(x, 1L, 100L)",
      "  assert_between(x, lower = 0, lower_inclusive = FALSE, upper = 1, na_ok = TRUE)",
      "}"
    )
  )
})

test_that("composite records, typed columns, list-columns, nullable nesting", {
  expect_equal(
    genf("(list)\n- a (scalar<character>) x.\n- b (numeric in [0, 1]) y."),
    c(
      "assert_list(x)",
      'assert_has_names(x, c("a", "b"))',
      'assert_scalar_character(x[["a"]])',
      'assert_double(x[["b"]])',
      'assert_no_missing_values(x[["b"]])',
      'assert_between(x[["b"]], lower = 0, upper = 1)'
    )
  )
  expect_equal(
    genf("(data.frame)\n- id (character) i.\n- blob (list<any>) c."),
    c(
      "assert_data_frame(x)",
      'assert_has_columns(x, c("id", "blob"))',
      'assert_character(x[["id"]])',
      'assert_no_missing_values(x[["id"]])',
      'assert_list(x[["blob"]])'
    )
  )
  expect_equal(
    genf("(data.table | NULL)\n- id (character) i.\n- amount (numeric in ]0, Inf[ | NA) a."),
    c(
      "if (!is.null(x)) {",
      "  assert_data_table(x)",
      '  assert_has_columns(x, c("id", "amount"))',
      '  assert_character(x[["id"]])',
      '  assert_no_missing_values(x[["id"]])',
      '  assert_double(x[["amount"]])',
      '  assert_between(x[["amount"]], lower = 0, lower_inclusive = FALSE, na_ok = TRUE)',
      "}"
    )
  )
})

test_that("every intentionally-invalid form is rejected", {
  invalid <- c(
    "(scalar<numeric, 1>)", # scalar takes no length
    "(scalar<numeric> | NA)", # | NA must be inside <>
    "(numeric | NULL?)", # both nullability markers
    "(numeric)?", # ? must be inside the parens
    "(complex in [0, 1])", # interval on a non-ordered type
    "(character in [0, 1])", # interval on a non-ordered type
    "(integer in [0.5, 2.5])", # fractional integer bound
    "(integer in c(1, 2, 3))", # integer set needs the L suffix
    "(character in c(1, 2))", # character set needs string literals
    "(Date in [0, 1])", # bare-number Date bound (type error)
    "(numeric in [Inf, 0])", # Inf is the high sentinel only
    "(numeric in ]-Inf, Inf[)", # both-sentinel: bounds nothing
    "(numeric in ]1, 1[)", # empty / reversed interval
    "(logical in c(TRUE, FALSE))", # logical takes no set
    "(complex in c(0+0i, 1+0i))", # complex takes no set
    "(raw in OPCODES)", # raw takes no set
    "(raw | NA)", # raw has no NA representation
    "(any in c(1, 2))", # any takes no constraint
    "(any | NA)", # any takes no | NA
    "(scalar<function>)", # function is a bare reference
    "(vector<function, 3>)", # function is length-1
    "(R6 | NULL)", # R6 must name a class
    "(data.table | NA)", # | NA is element-level, not composite
    "(vector<numeric>)", # vector<> requires a length
    "(frobnicate)" # unknown type
  )
  for (a in invalid) {
    expect_error(parse_annotation(a), info = a)
  }
})

test_that("invalid composite-bullet (S1) and misplaced-? forms are rejected", {
  expect_error(parse_annotation("(data.table | data.frame)\n- a (character) x."), "single bare composite")
  expect_error(parse_annotation("(list<numeric>)\n- a (character) x."), "leaf")
  expect_error(parse_annotation("(list)\n- cur (scalar<character>)? next."), "must sit inside")
})

test_that("promise<T> / T | promise<T> lower to the resolved type's checks (no promise code)", {
  expect_equal(genf("(promise<scalar<numeric>>)"), "assert_scalar_double(x)")
  expect_equal(genf("(promise<data.table>)"), "assert_data_table(x)")
  expect_equal(genf("(promise<list<character>>)"), c("assert_list(x)", 'assert_list_of(x, "character")'))
  # the explicit union collapses to the same single validator
  expect_equal(genf("(data.table | promise<data.table>)"), "assert_data_table(x)")
  expect_equal(genf("(promise<data.table> | data.table)"), "assert_data_table(x)")
  # promise<data.table> carries typed columns
  expect_equal(
    genf("(promise<data.table>)\n- id (character) i.\n- ok (scalar<logical>) o."),
    c(
      "assert_data_table(x)",
      'assert_has_columns(x, c("id", "ok"))',
      'assert_character(x[["id"]])',
      'assert_no_missing_values(x[["id"]])',
      'assert_scalar_logical(x[["ok"]])'
    )
  )
})

test_that("promise<T> over a reference / nullable / nested resolved value", {
  expect_equal(genf("(promise<R6<Engine>>)"), 'assert_class(x, "Engine")')
  expect_equal(genf("(promise<data.table>?)"), c("if (!is.null(x)) {", "  assert_data_table(x)", "}"))
  expect_equal(genf("(promise<promise<scalar<numeric>>>)"), "assert_scalar_double(x)")
})
