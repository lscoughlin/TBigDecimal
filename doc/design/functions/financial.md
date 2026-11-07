### 5.7 Financial helpers

The helpers are thin wrappers: compound factor `(1 + r)^n`, present value,
future value, annuity factor, and annualized rate from a growth ratio
(`ratio^(1/t) − 1` with `Pow`). They accept non-integer periods and
use `Pow(x, y)`. Each helper takes a context. A helper computes the power at
`p + 12` digits (`p + 20` for the annuity factor and the annualized rate, which
subtract nearly equal values or round an exponent) and rounds once at the end.
These helpers are not Ziv-checked, so in rare cases (about 1 in 10^11 for the
`p + 12` form) the last digit can differ from the correctly rounded value.

The nine Excel functions (`PaymentXL`, `InterestPaymentXL`,
`PrincipalPaymentXL`, `PresentValueXL`, `FutureValueXL`, `PeriodCountXL`,
`PeriodicRateXL`, `EffectiveRateXL`, `NominalRateXL`) take an integer period
count, so `(1 + r)^n` is an integer power. The shared `GrowthMinusOne` routine
computes it exactly while the digit estimate stays below a threshold, else
rounded once at the working precision. Each function divides once at the
working precision and rounds once to the context. The working precision is
`p + 20` plus twice the cancellation depth of `r·n`, a growth-depth estimate
for large `(1 + r)^n`, and the deepest input tail. `PeriodCountXL` is the only
annuity function that uses `Ln`, and `NominalRateXL` is the only one that uses
a fractional `Pow`; both are covered by the same guards.

`PeriodicRateXL` solves `FutureValueXL(r) = fv` by Newton iteration with a
closed-form derivative. The iteration runs at the guarded precision, stops
when the step drops below `10^-(p+10)`, and allows 100 iterations. A step
that reaches `-1` is halved, up to 60 halvings per iteration. A zero payment
goes through `AnnualizedRate` directly, and exact-zero inputs return zero
without iteration. Inputs without a root raise `EBigDecimalDomain`; an
iteration that exhausts its budget, or a rounded result at or below `-1`,
raises `EBigDecimalNoConvergence`. With two sign changes the result is the
root that Newton reaches from `Guess`, as in Excel.
