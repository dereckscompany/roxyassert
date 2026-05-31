#include <Rcpp.h>
using namespace Rcpp;

#include "sum_array.h"

//' Sum a numeric vector using loop unrolling
//'
//' @param x A numeric vector
//' @return The sum of all elements
//' @export
// [[Rcpp::export]]
double sum_array_cpp(NumericVector x) {
  R_xlen_t n = x.size();

  if (n == 0) {
    return 0.0;
  }

  double sum0 = 0.0, sum1 = 0.0, sum2 = 0.0, sum3 = 0.0;

  R_xlen_t i = 0;
  R_xlen_t n_unrolled = n - (n % 4);

  // Process 4 elements at a time (loop unrolling)
  for (; i < n_unrolled; i += 4) {
    sum0 += x[i];
    sum1 += x[i + 1];
    sum2 += x[i + 2];
    sum3 += x[i + 3];
  }

  // Handle remaining elements
  double remainder = 0.0;
  for (; i < n; i++) {
    remainder += x[i];
  }

  return sum0 + sum1 + sum2 + sum3 + remainder;
}
