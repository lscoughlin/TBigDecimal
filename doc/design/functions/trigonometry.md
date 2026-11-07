### 5.9 Trigonometric functions

`Sin`, `Cos` and `Tan` take a `TBigDecimal` in radians and a context. `Atan`
is not part of the first release. Trigonometric functions help in two places:
the gamma reflection formula ([section 5.8](combinatorics.md)), and users who need periodic or
seasonal terms and wave models in financial code. They do not speed up
`Exp` or `Ln`.

- **Argument reduction.** The code writes `x = q · (pi/2) + r` with
  `|r| ≤ pi/4`. It computes `q` from `x · (2/pi)` at working precision
  `p + g + digits(|x|)`, and `Pi` at the same precision. The extra
  `digits(|x|)` digits make up for the cancellation in `x − q·pi/2`. Arbitrary
  precision makes the Payne-Hanek method for huge arguments unnecessary. The
  quadrant `q mod 4` selects among `sin r`, `cos r`, `−sin r`, `−cos r`.
- **Series.** The code sets `r' = r / 2^s` with `s = min(40, floor(sqrt(w)))`,
  as for `Exp`. It sums the Taylor series of `sin r'` (odd powers, term ratio
  `−r'²/((2k)(2k+1))`) and of `cos r'` (even powers, term ratio
  `−r'²/((2k−1)(2k))`). It then doubles the angle `s` times with
  `sin 2a = 2 sin a cos a` and `cos 2a = 1 − 2 sin² a`.
  The second form is stable because `sin² a` is small at the early steps. The
  guard grows by about `s · log10(2)` digits, as for `Exp`.
- **Tan.** `Sin / Cos` at working precision `p + g`. A cosine that is zero
  within the error bound cannot occur for a decimal `x`, because `x` is
  rational and `pi/2` is irrational.
- **Exact cases.** `Sin(0) = 0`, `Cos(0) = 1` and `Tan(0) = 0` are exact. No
  other decimal argument gives an exact result, because `sin`, `cos` and `tan`
  of a non-zero rational are transcendental (Lindemann-Weierstrass). The Ziv
  loop of [section 5.1](precision.md) therefore ends for them.
- **High precision.** The library evaluates the series directly. Bit-burst
  evaluation through `Exp` of a complex argument is not used ([section 10](../future.md)).
