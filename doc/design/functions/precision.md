## 5. Mathematical functions

Every function takes a `TMathContext`, or reads the thread-local default when
the call has no context argument ([section 4.1](../context.md)). The caller picks the
precision and the mode. A function with `Precision = 0` raises
`EBigDecimalDomain`, because an exact transcendental result does not exist. The sole exceptions are the
cases with an exact answer (`Exp(0)`, `Ln(1)`, `Pow` with an integer
exponent).

### 5.1 Working precision and correct rounding

Each function computes at `p + g` digits, where `p` is the target precision
and `g` is a guard (about 10 digits plus `log10` of the term count). It
estimates a bound on the total error. If the interval
`[result − error, result + error]` rounds to one value in the requested
mode, the function returns that value. Otherwise it repeats with a larger
guard (Ziv's strategy). The loop ends quickly because a hard case is rare.
This yields a correctly rounded result in all modes, which is better than the
1 ulp that many libraries give. The one exception is an exact tie that the
function can never separate. Transcendental functions of non-trivial
arguments never produce an exact tie. The loop does not end when the true
result is exactly representable at the target precision, because the error
interval then always straddles the result. That case occurs for `Pow(4, 0.5)`,
`Pow(100, 1.5)`, `Pow(5.0625, 0.5)` (a midpoint, 2.25), `Log(2, 8)`,
`Log(4, 2)`, perfect powers under `Root`, and every exactly representable
result in the four directed modes.

Each function therefore tests for an exact result before the loop. For
`Pow(x, y)` with `y = a/b` in lowest terms, the code rounds a candidate
`c` and checks `c^b = x^a` exactly with integer arithmetic (MPFR does a
similar test for `pow`). `Log(b, x)` tests a rational candidate `a/c` the same
way: `b^a = x^c`. `Root` tests `c^n = x`. `Exp` and `Ln` have exact results
only at 0 and 1. When an exact result exists, the function returns it and
applies rounding to it. As a last resort, the code caps the guard at a fixed
number of digits and raises `EBigDecimalPrecision`.
