## 7. Unit layout

Each file stays below 2000 lines.

The unit names under `BigDecimal.` differ from the names of RTL units. FPC
searches the namespace of the current unit first, so a `uses Math` clause in
`BigDecimal.Divide` finds a unit `BigDecimal.Math` before the RTL unit `Math`.
Which unit wins then depends on the compile order, and a build can fail with a
circular reference. The elementary functions therefore live in
`BigDecimal.Elementary`.

| Unit                     | Content |
|--------------------------|---------|
| `BigDecimal.Types`       | Enums, `TMathContext`, exception classes, constants (power-of-ten tables) |
| `BigDecimal.Limbs`       | Magnitude kernels: compare, add, sub, shift by powers of ten, single-limb ops, digit count |
| `BigDecimal.Multiply`    | Schoolbook, squaring, Karatsuba, unbalanced split |
| `BigDecimal.Divide`      | Knuth D, single-limb division, Newton reciprocal with block splitting |
| `BigDecimal.Rounding`    | `RoundMagnitude` and the mode logic |
| `BigDecimal.Convert`     | Parse, digit text, exact and correctly rounded `Double` conversion on raw limbs |
| `BigDecimal`             | The `TBigDecimal` record and its operators |
| `BigDecimal.Fixed`       | Fixed-point values with a running error bound; the Ziv interval check |
| `BigDecimal.Elementary`  | `Sqrt`, `Exp`, `Ln`, `Log10`, `Log`, `Pow`, `Root` |
| `BigDecimal.Constants`   | `Pi`, `E`, `Ln2`, `Ln10` with caches |
| `BigDecimal.Financial`   | Financial helpers |
| `BigDecimal.Combinatorics` | Factorial, double factorial, primorial, falling and rising factorial, binomial, multinomial, Catalan, prime sieve |
| `BigDecimal.Trig`        | `Sin`, `Cos`, `Tan` |
| `BigDecimal.Gamma`       | `Gamma`, `LnGamma`, non-integer factorial, Bernoulli number cache |

Each unit starts with the pasdoc front matter block that `AGENTS.md`
requires.
