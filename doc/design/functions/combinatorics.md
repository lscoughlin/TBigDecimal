### 5.8 Factorials, combinatorics and gamma

The functions of this section live in `BigDecimal.Combinatorics` and
`BigDecimal.Gamma`. Arguments `n` and `k` are non-negative `Int64` values
unless stated. A negative argument raises `EBigDecimalDomain`.

**Exact functions.** `Factorial`, `DoubleFactorial`, `Primorial`,
`FallingFactorial` (also `Permutations`), `RisingFactorial`, `Binomial`,
`CentralBinomial`, `Multinomial` and `Catalan` return exact integers with
scale 0. They ignore the default context ([section 4.1](../context.md)), as `Create` does. A
guard estimates the result size before work starts. If the estimate exceeds
`MaxExactDigits` (the limit that `Pow` uses), the function raises
`EBigDecimalOverflow`. The estimate uses the Stirling formula in `Double`
arithmetic, with a safety margin.

**Methods considered.**

| Method | Verdict |
|--------|---------|
| Plain loop `n × (n−1) × ...` | Rejected. Each step multiplies a large number by a small one, so the cost is O(n²) digit operations. |
| Binary splitting of the product | Chosen for ranges. The tree of balanced products lets Karatsuba apply. |
| Swing recursion `n! = (⌊n/2⌋!)² · swing(n)` | Chosen for large `n`. |
| Direct Legendre prime factorization of `n!` | Kept as a test oracle and a benchmark candidate. |
| Gamma function at integer arguments | Rejected for integers. Exact methods are faster and exact. |

**Factorial.** Three size classes:

1. `n ≤ 20`: a constant table of `UInt64` values (20! is below 2^63).
2. `n` up to a threshold (about 600, set by benchmark): binary splitting of
   the range `2..n`. The code first packs factors into `UInt64` words (as many
   as keep the product below 1.8 × 10^19), then multiplies the words in a
   balanced tree. This is the first of the two methods in the GMP manual:
   it "forms big multiplies, allowing Karatsuba and higher algorithms to be
   used" ([GMP manual, factorial algorithm](https://gmplib.org/manual/Factorial-Algorithm)).
3. Larger `n`: the swing recursion. The identity is
   `n! = (⌊n/2⌋!)² · swing(n)`, where `swing(n) = n! / (⌊n/2⌋!)²`. The
   swing number has a prime factorization with a small exponent for every
   prime: `swing(n) = ∏ p^L(p,n)`, where `L(p,n)` is the sum, over `i ≥ 1`,
   of `floor(n / p^i) mod 2`. Each exponent is therefore at most
   `log_p n`. The GMP manual describes the same structure: for large `n`,
   `n! / (⌊n/2⌋!)² · 2^k = ∏ p^L(p,n)` over odd primes `p`, with `k` the count
   of 1 bits of `⌊n/2⌋`
   ([GMP manual, factorial algorithm](https://gmplib.org/manual/Factorial-Algorithm)).
   The recursion needs `⌊n/2⌋!`, then `⌊n/4⌋!`, and so on, for a depth of
   `log2 n`. The cost is dominated by the last level. The big step is one
   squaring, and the design has a dedicated squaring kernel. The reason for
   the speed is the small exponents and the squaring, not a binary radix, so
   the method works in base 10^9.

   The factors of `swing(n)` are the primes up to `n` (from a sieve of
   Eratosthenes, odd numbers only, bit-packed, segmented), each raised to a
   power at most `log_p n`. The code multiplies them with the batched binary
   splitting tree of class 2. The power of 2 in the swing number is at most
   `log2 n`, so it is one small word, and no special handling of the factors
   2 and 5 is needed.

   The direct form `n! = ∏ p^e(p)` with Legendre's exponent
   `e(p) = Σ floor(n / p^i)` is also implemented, as a test oracle and as a
   benchmark candidate. In that form the exponent of 2 is about `n`, and the
   decimal base has no free shift for a power of two. The candidate uses the
   exponent of 5 to take `10^e(5)` as trailing zeros (a limb shift and one
   single-limb multiply), and the factor `2^(e(2) − e(5))` joins the tree as one
   leaf by repeated squaring.

   The sieve costs O(n) time and n/16 bytes. It is rebuilt on each call. At
   the size limit set by `MaxExactDigits` (about n = 1.7 × 10^6), the sieve
   takes a few milliseconds, so the design has no sieve cache.

**Double factorial and primorial.** `n!!` uses the same two-tier structure:
binary splitting over the arithmetic progression `n, n−2, ...`. A prime
factorization form is not used because the exponent formulas are less regular.
`Primorial(n)` is the product of the primes up to `n`. It reuses the sieve
and the batching tree.

**Falling and rising factorial.** `FallingFactorial(n, k)` is
`n (n−1) ... (n−k+1)`. `RisingFactorial(x, k)` is `x (x+1) ... (x+k−1)`.
Both use binary splitting of the product over the `k` terms. They avoid the
division of `n! / (n−k)!`, so no large number is formed that the result does
not need. The rising factorial also accepts a `TBigDecimal` argument `x`. In
that form it multiplies exact decimal values and rounds only on request.
Python `math.perm` splits `P(n,k) = P(n,j) · P(n−j,k−j)` with `j = k/2` in
the same way
([CPython change 60c320c38e](https://android.googlesource.com/platform/external/python/cpython3/+/60c320c38e%5E%21)).

**Binomial coefficient.** `Binomial(n, k)` first sets `k = min(k, n−k)` by
symmetry. If `k = 0` the result is 1. Two size classes apply:

1. Small `k` (at most `BinomialKummerThreshold`, 12) or very large `n`
   (above `BinomialSieveLimit`, 4,000,000, where the sieve would be too large):
   the multiplicative form `r ← r · (n−k+i) / i` for `i = 1..k`. Each division
   is exact, because after step `i` the partial result is a binomial
   coefficient. Each step is one multiplication by a word and one exact
   single-limb division. GMP uses this form and accumulates the numerators and
   denominators into one machine word first, to save multi-precision
   operations
   ([GMP manual, binomial coefficients](https://gmplib.org/manual/Binomial-Coefficients-Algorithm.html)).
2. Otherwise: prime factorization with Kummer's theorem. The exponent of a
   prime `p` in `C(n, k)` equals the number of carries when `k` and `n−k` are
   added in base `p`. Equivalently it is
   `Σ (floor(n/p^i) − floor(k/p^i) − floor((n−k)/p^i))`. Only primes up to `n`
   occur. A prime `p > n/2` has exponent 1 when `p > n−k`, else 0. The product
   uses the same batched tree as `Factorial`. Every exponent is at most
   `log_p n`, so the powers of 2 and 5 are small and need no special handling.
   This needs no big division.

The library has no separate class for results that fit in `UInt64` (CPython
keeps a table of limits for it). The benchmark in [`RESULTS.md`](../../RESULTS.md) shows
Kummer's form ten times faster than the multiplicative form already at
`k = 20`, and the cost of a `TBigDecimal` for a result below 2^63 is small.
The recursion `C(n,k) = C(n,j) · C(n−j,k−j) / C(k,j)` with `j = k/2`, which
CPython uses, needs an exact big division at every node. The library does not
use it, because Kummer's form needs no division.

**Central binomial and Catalan.** `CentralBinomial(n) = C(2n, n)`.
`Catalan(n) = C(2n, n) / (n + 1)`. The division is exact. For `n + 1` below
10^9 it is a single-limb exact division. A larger `n` is out of range for
`MaxExactDigits` in practice. The code then raises `EBigDecimalOverflow`
before it reaches the division.

**Multinomial.** `Multinomial([k1, ..., km])` is
`C(k1, k1) · C(k1+k2, k2) · ... · C(k1+...+km, km)`. It multiplies the
binomial coefficients in a balanced tree. For a single large `n = Σ ki` and
many parts, the prime factorization form (exponent of `p` is
`e_n(p) − Σ e_ki(p)`) is used instead, because it needs one sieve and one
product tree.

**Generalized binomial.** `Binomial(x: TBigDecimal, k: Int64)` is
`FallingFactorial(x, k) / k!`. It follows the usual definition for any real
`x`. Financial code uses it for binomial lattices and series. The result
rounds per the context (explicit or default), because the quotient need not
terminate.

**Gamma and log-gamma.** `Gamma(x, Context)`, `LnGamma(x, Context)` and
`Factorial(x: TBigDecimal, Context)` (defined as `Gamma(x + 1)`) cover
non-integer arguments.

- *Integer arguments.* `Gamma(n)` for a positive integer `n` below 10^8 is
  `(n−1)!`, computed exactly and then rounded. A half-integer argument takes
  the general path below, which is correct and a little slower than a closed
  form `(2n)! / (4^n n!) · sqrt(pi)` would be.
- *Other arguments.* The Stirling series with argument shift. When `x` is
  below a shift target `T`, the recurrence
  `Gamma(x) = Gamma(x + r) / (x (x+1) ... (x+r−1))` shifts the argument up to
  `x + r ≥ T`. This applies to every `x` below `T`, including negative
  non-integers. The rising factorial in the denominator uses binary splitting.
  The shift costs about `T − x` multiplications, which grows with the size of
  a negative `x`. For `x` far below zero (below `−T`, with the break-even point
  set by benchmark) the reflection formula
  `Gamma(x) = pi / (sin(pi x) · Gamma(1 − x))` is cheaper. It needs one
  `Sin` ([section 5.9](trigonometry.md)) and one `Gamma` at the large positive argument
  `1 − x`, which needs no shift. The code reduces `x` modulo 2 exactly in
  decimal before it multiplies by `Pi`, so a large `x` costs no extra digits
  of `Pi`. When `x` is an integer, `sin(pi x)` is exactly zero, and the
  function raises `EBigDecimalDomain` (a pole) before any computation. The target `T` is `0.4 w + 8` for `w` working decimal digits (the series
  terms fall below `10^-w` near the minimum term `e^(-2 pi z)`). The Stirling series for
  `LnGamma(x + r)` then needs at most about `0.32 · b` terms for `b` bits of
  working precision, with Bernoulli numbers `B_2k`. The terms span many orders
  of magnitude (`B_2k` grows factorially while `z^-(2k-1)` falls), so the series
  is summed in floating point at `w + 6` digits of relative precision, not in
  fixed point, and the terms add exactly. A non-positive integer
  `x` is a pole and raises `EBigDecimalDomain`. `LnGamma(x)` is defined for
  `x > 0` only. `Gamma(x)` for negative non-integer `x` takes its sign from
  the sign of the rising factorial.
- *Why Stirling.* Johansson
  ([arXiv 2109.08392](https://arxiv.org/abs/2109.08392)) compares the Stirling
  series, Spouge and Lanczos. The Stirling series needs fewer terms than
  Spouge (about 0.323 b against 0.377 b terms, for b-bit accuracy). Each Stirling
  term costs less than one multiplication, where each Spouge term needs a
  division. The Bernoulli numbers are reusable across precisions. Spouge and
  Lanczos coefficients depend on the target precision and need extra working
  digits because their terms are large and alternate in sign. For that reason
  the design does not use them.
- *Bernoulli numbers.* A cache holds the tangent numbers `T_k` (integers) for
  the highest `k` computed, under a lock. The coefficient of the series is
  `B_2k / (2k (2k−1)) = (−1)^(k−1) T_k / ((2k−1) 4^k (4^k − 1))`. The tangent
  numbers come from the Brent and Harvey algorithm, which is O(n²) in the count
  of numbers and uses integer arithmetic only. The cache doubles when a larger
  index is requested.
- *Accuracy.* The functions use the Ziv loop of [section 5.1](precision.md). The error bound
  covers the Stirling truncation error (the first omitted term bounds it, for
  real `x > 0`), the shift product, and the Bernoulli rounding.
- `LnFactorial(n)` for an integer `n` is `LnGamma(n + 1)`.
