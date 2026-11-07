### 5.2 Sqrt and Root

`Sqrt` and `Root` work on integers and round once, so the result is correctly
rounded in every mode with no Ziv loop. The code first scales the unscaled
value by a power of ten so that the scale is a multiple of the root index `k`,
and by `10^(k·t)` so that the integer root has at least `p + 2` digits. It then
computes the floor of the `k`-th root by Newton iteration on integers,
`y ← ((k−1)·y + n div y^(k−1)) div k`. The start value is above the root and
has about half of the digits right. It comes from the floor root of the
leading half of the digits of `n`, which the same function computes
recursively, plus one unit, shifted back. Below `40·k` digits the start value
is a power of ten above the root. Two Newton steps at full size follow the
recursion, so the cost is about four divisions at full size, not one division
for each doubling of the precision. A remainder test (`r^k = n`) tells whether the root is exact. When it is
not exact, the code appends a sticky digit 1 to the root, so that every
rounding mode sees a value just above the truncated root, and rounds to `p`
digits. When the root is exact, the result has the preferred scale
`ceil(scale / k)` if it fits in `p` digits. Each Newton step costs one
division ([section 3.3](../algorithms/division.md)). A reciprocal-root iteration that needs only
multiplications is not used ([section 10](../future.md)).

For a short, non-exact result (at most 48 limbs after scaling) the code runs
the same algorithm on stack limbs. The start value comes from a `Double` square
root of the top two limbs, widened to stay above the root. Newton steps with
limb division follow, and a check that `y² ≤ n < (y+1)²` confirms the floor.
The rounding appends the sticky digit to the limbs and rounds once. Results that
are exact, and unlimited contexts, use the general path above.
