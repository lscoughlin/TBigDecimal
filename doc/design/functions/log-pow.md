### 5.5 Log10, Log, Pow, Root

- `Log10(x)`: exact when `x` is `10^k` (including scaled forms such as
  `0.001`). Otherwise `Ln(x)/Ln(10)` at working precision.
- `Log(b, x) = Ln(x)/Ln(b)`. It raises `EBigDecimalDomain` for `b ≤ 0` or
  `b = 1`. A first approximation at 40 digits is tested for a rational value
  `a/q` (`q ≤ 8`) with `x^q = b^a` by exact integer powers. When the identity
  holds and `a/q` terminates, the result is that exact decimal.
- `Pow(x, n)` with integer `n`: binary exponentiation. The code first strips
  trailing zeros from the base (so `10^n` costs one digit of work), computes the
  exact power when its estimated size is at most 20,000 digits (or the context
  is `Unlimited`), and rounds once. A larger power is evaluated by rounded
  square-and-multiply while an exactness flag records whether any step lost a
  digit; an exact result is then returned exactly, and an inexact one goes
  through the Ziv check. An exact result with a positive exponent keeps the
  natural scale `scale(x)·n`, padded with zeros up to `p` digits when the
  natural form has more than `p` digits. The result is exact when the context is `Unlimited`. A guard check refuses an exact result
  whose digit count would exceed a configurable limit
  (`MaxExactDigits`, default 10^7) to prevent memory exhaustion. A negative
  `n` computes `1 / x^|n|` at context precision. With a finite context the
  product loop rounds at working precision `p + g`, where `g` includes
  `log10(|n|)`.
- `Pow(x, y)` with a decimal `y`: if `y` is an integer value, the integer
  path applies. For `y = a/q` in lowest terms with `q ≤ 64`, the code tests
  whether `x` is a perfect `q`-th power (an integer root of the stripped
  unscaled value), and if so returns `root^a` exactly. Such a result, like every
  result with a fractional exponent, is padded with trailing zeros up to `p`
  digits, as in the General Decimal Arithmetic power operation and in Python
  `decimal`. Otherwise `Exp(y · Ln(x))` with the working precision raised by the
  number of digits of `|y · Ln(x)|`, because the absolute error of the exponent
  turns into a relative error of the result. It raises `EBigDecimalDomain` for
  `x < 0` with non-integer `y`.
- `Root(x, n)`: Newton iteration. `Sqrt` is the `n = 2` case.
