### 8.1 External reference material

Each source below was downloaded and inspected on 2026-10-15. The checksums
identify the inspected files.

**General Decimal Arithmetic testcases (`dectest.zip`).**
- Source: <https://speleotrove.com/decimal/dectest.html>. Archive:
  <https://speleotrove.com/decimal/dectest.zip>. The archive is 791,733 bytes.
  SHA-256: `b70a224cd52e82b7a8150aedac5efa2d0cb3941696fd829bdbe674f9f65c3926`.
- Author: Mike Cowlishaw (IBM). Version 2.62 of the files. The files state
  that they are experimental, offered as-is, and not exhaustive. The files
  carry a copyright notice. The repository therefore does not store them. A
  tool downloads the archive and checks the checksum.
- Content: plain-text cases of the form
  `id operation operand... -> result [conditions]`, with the directives
  `precision`, `rounding`, `maxExponent` and `minexponent`. The archive holds
  about 140 files. The files that match this library are `add`, `subtract`,
  `multiply`, `divide`, `divideint`, `remainder`, `compare`, `max`, `min`,
  `abs`, `minus`, `plus`, `quantize`, `reduce`, `rescale`, `tointegral`,
  `rounding`, `squareroot`, `power`, `exp`, `ln` and `log10`. The `ln`, `exp`,
  `log10`, `squareroot` and `power` files hold 610, 673, 550, 3833 and 1623
  lines. The `exp` file states that its results are correctly rounded
  (at most 0.5 ulp). The `exp`, `ln` and `log10` files set only the rounding
  mode `half_even`, so other modes for these functions are covered by the
  `mpmath` vectors. The `power` file notes a few cases that are not within
  0.5 ulp.
- Scope limits. The cases include NaN, infinity, subnormal values, exponent
  range limits and signal flags. `TBigDecimal` has none of these (see the
  README non-goals). The test runner skips a case when any operand or result
  is NaN or infinity, when an exponent limit applies, or when the case uses
  an operation that the library does not have. The runner counts skipped
  cases per file and prints the count, so a silent loss of coverage is
  visible. The directive `precision` maps to `TMathContext.Precision`. The
  directive `rounding` maps to `TRoundingMode`. The `half_even`, `half_up`,
  `half_down`, `up`, `down`, `ceiling` and `floor` names map directly. The
  mode `05up` has no counterpart and the runner skips it.

- Expected failures. A checked-in file, `tests/dectest-expected-failures.txt`,
  lists case IDs where the library result is known to differ from the
  reference. Each line holds the case ID and a reason (for example, the case
  is not within 0.5 ulp, as `power.decTest` notes). The runner reports these
  cases as known failures. The run fails when a listed case passes (the entry
  is then stale) and when any unlisted case fails. Each entry needs a review,
  so a deviation never hides.

**Digits of pi.**
- Source 1: <https://www.angio.net/pi/digits/10000.txt>. The file holds the
  first 10,000 decimal places of pi. SHA-256:
  `1f08958df70c30bbf3f7205ad5f9b2b9430e3378b4e4e6300063bd9fbd83d6e3`.
- Source 2: OEIS sequence A000796, b-file
  <https://oeis.org/A000796/b000796.txt>. The file holds 20,000 digits as
  `index digit` lines. SHA-256:
  `f8772370d624d403f056e3e3d4aadb15fec135d5075b5506053eb86460f4e20b`.
- Validation. The first 10,000 digits of both sources were compared and are
  identical. The tests accept a pi value only when both sources agree. They
  use the 20,000-digit file for precision above 10,000 digits.
- Use: expected values for `Pi(Context)` at every precision up to 20,000
  digits and for every rounding mode.

**Java `BigDecimal` specification.**
- Source: <https://www2.seas.gwu.edu/~rhyspj/docs/api/java/math/BigDecimal.html>
  (a copy of the Java API documentation).
- Use: the rules for `precision`, `scale`, preferred scale of `divide`,
  `toString` and the eight rounding modes. The rounding table test takes its
  inputs and expected values from the rounding mode table in the
  `RoundingMode` documentation.

**OEIS b-files for combinatorial values.** Each file lists `index value`
pairs. Each file was downloaded and checked against Python `math` (exact
integer arithmetic) on 2026-10-15. All entries matched.

| Sequence | File | Range | SHA-256 |
|----------|------|-------|---------|
| A000142 factorials | <https://oeis.org/A000142/b000142.txt> | n = 0..100 | `9d872b96c262cc2fe3f854e1b06d6624d7b8fe2f5666ce37f98acb7f523289c3` |
| A001147 double factorials (2n−1)!! | <https://oeis.org/A001147/b001147.txt> | n = 0..400 | `3bdf1d3bf0bb5046308f5f496552d9d8f21280bb354d480c21f625e7925ab222` |
| A000984 central binomial C(2n,n) | <https://oeis.org/A000984/b000984.txt> | n = 0..1500 | `4f911fe749c2ceb35425d1dbdfd12a6c0ac68f24fddea021339dddcf54bb09d7` |
| A000108 Catalan numbers | <https://oeis.org/A000108/b000108.txt> | n = 0..1000 | `5623739c73b08deddc3cc2e9c670e231a56194eecabb88199a1cf4f0a0989e18` |
| A000040 primes | <https://oeis.org/A000040/b000040.txt> | first 10,000 primes (to 104,729) | `ef3beecd3bca4a02ca5053e5a3afc3e0d69e43b49b9aaa91073fc4fb9e4d50de` |

The prime file checks the sieve. The other files check `Factorial`,
`DoubleFactorial`, `CentralBinomial` and `Catalan`. These files reach only
n = 1500 at most, so tests for larger arguments use the oracle programs and
the identities below.

Identity tests cover the prime factorization paths against the other paths:
`Factorial` by prime factorization equals `Factorial` by binary splitting,
`Binomial` by Kummer's form equals the multiplicative form and the
recursive form, `C(n,k) = C(n,n−k)`, Pascal's rule
`C(n,k) = C(n−1,k−1) + C(n−1,k)`, the row sum `Σ C(n,k) = 2^n`, and
`Gamma(n) = (n−1)!` at integer arguments.

**Oracle programs.** Python `decimal` and `mpmath` generate additional
vectors (see [testing](testing.md)). They are computed values, not fixed reference data.
The vectors for `Exp`, `Ln`, `Log10`, `Pow`, `Sqrt` and `Pi` are
cross-checked against the dectest files and the pi digits where the cases
overlap.
