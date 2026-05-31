test_that("sum_array_cpp works correctly", {
  expect_equal(sum_array_cpp(1:10), 55)
  expect_equal(sum_array_cpp(c(1, 2, 3, 4, 5)), 15)
  expect_equal(sum_array_cpp(numeric(0)), 0)
  expect_equal(sum_array_cpp(c(1, 2, 3)), 6) # remainder case
})

test_that("sum_array_cpp matches base R sum", {
  set.seed(42)
  x <- rnorm(1000)
  expect_equal(sum_array_cpp(x), sum(x), tolerance = 1e-10)
})
