#' Add two numbers
#'
#' @param x Numeric value
#' @param y Numeric value
#'
#' @return Sum of x and y
#' @export
add <- function(x, y) {
  if (!is.numeric(x) || !is.numeric(y)) {
    stop("x and y must be numeric")
  }
  return(x + y)
}
