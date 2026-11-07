### 5.4 Ln

- The reduction uses powers of ten and a small table. The code writes
  `x = m · 10^e` with `1 ≤ m < 10`. Then `ln(x) = ln(m) + e·ln(10)`. Further write `m = c · (1+u)`
  with `c` from a short table (`1`, `1.5`, `2`, `3`, `5`, `7`). Now `|u|` is
  small. The table needs `ln 2`, `ln 3`, `ln 5` and `ln 7` (`ln 1.5` is
  `ln 3 − ln 2`, and `ln 10` is `ln 2 + ln 5`). [Section 5.6](constants.md) gives the
  formulas.
- The code evaluates `ln(1+u)` as `2·atanh(z)` with `z = u/(2+u)`. This series has
  only odd powers and converges as `z²`. At 34 digits it needs about 15 to 20
  terms. It is the fastest method at low and medium precision.
- `ln(2)`, `ln(10)` and the table values are cached per working precision.
  The constants cache ([section 5.6](constants.md)) holds them.
- For precision above a few thousand digits, a Newton iteration on `Exp`
  (`y ← y + 2(x − e^y)/(x + e^y)`) or the AGM method
  (`ln x ≈ π / (2·agm(1, 4/s)) − m·ln 2`, the approach MPFR uses for large
  precision) takes over. The AGM needs `Pi` and `Ln2`. See
  [Brent](https://maths-people.anu.edu.au/~brent/pd/RNC7-Brent.pdf). The
  library uses neither method ([section 10](../future.md)).
