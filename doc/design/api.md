## 6. API conventions

- The record is `TBigDecimal`. The main unit is `BigDecimal`. A separate unit,
  `BigDecimal.Elementary`, holds the transcendental functions. A program that does
  only arithmetic does not link the function code.
- `Implicit` conversion from `Integer` and `Int64` only. A conversion from
  `Double` is `Explicit`, because a silent `Double` conversion hides binary
  error.
- Mixed `TBigDecimal` / `Integer` arithmetic works through the implicit
  conversion. Each such operation takes the small-value path.
- The README sketch has `Create` as `class function`. The final API keeps
  that form and adds `class function FromString`, `FromUnscaled`, and
  `TryParse`.
- The default record state (all zero) is the value 0 with scale 0. A
  `TBigDecimal` needs no initialization call. The type has no `Clear`
  method, because assignment of zero does the same work.
