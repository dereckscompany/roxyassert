test_that("add works with basic numbers", {
  expect_equal(add(2, 3), 5)
  expect_equal(add(-1, 1), 0)
  expect_equal(add(0, 0), 0)
})

test_that("add handles decimals", {
  expect_equal(add(1.5, 2.5), 4)
})

test_that("add validates input", {
  expect_error(add("a", 3), "must be numeric")
  expect_error(add(2, "b"), "must be numeric")
})
