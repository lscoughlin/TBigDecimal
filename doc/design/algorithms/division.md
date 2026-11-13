### 3.3 Division

`Divide` has three steps: choose the working scale, divide the magnitudes,
round the result.

- **Single-limb divisor.** One pass of 64-bit division by the divisor.
- **Multi-limb divisor.** Knuth Algorithm D adapted to base 10^9
  ([ridiculousfish on Algorithm D](https://ridiculousfish.com/blog/posts/labor-of-division-episode-iv.html),
  Knuth TAOCP vol. 2, section 4.3.1). Normalization multiplies both operands
  by `d = floor(10^9 / (v1 + 1))` so the top divisor limb is at least
  `10^9 / 2`. The quotient digit estimate uses the top two dividend limbs and
  the top divisor limb. A second-limb check removes almost all wrong
  estimates. One add-back step handles the rare remaining case. The
  multiply-and-subtract loop is a separate routine without a `try` block, so
  FPC keeps its locals in registers. It splits each product `qhat · v[i]` into a
  limb part and a carry, and normalizes each limb, without a dependency on the
  previous limb. The dependent chain is one subtraction, one compare and one
  masked addition, with no branches. A step costs about 1.8 ns.
- **Large operands.** When the divisor and the quotient both have at least
  `NewtonDivThreshold` (4096) limbs, division uses a Newton reciprocal followed
  by a multiply and a correction step. It runs in O(M(n)). GMP and other
  libraries use the same method
  ([Möller and Granlund, "Improved division by invariant integers"](https://www.lysator.liu.se/~nisse/archive/draft-division-paper.pdf)).
  The implementation normalizes the divisor, builds a reciprocal `Y` of its
  top `n` limbs with `n = nq + 2` (quotient limbs plus two guard limbs) by the
  Newton step `Z ← Z + Z·(B^(2n) − D·Z) / B^(2n)`, starting from the reciprocal
  of the top half of the limbs, estimates the quotient as the top limbs of
  `a'·Y`, and corrects the estimate by at most a few units with the exact
  product `q·b`. When the quotient has more than `nb − 2` limbs, the dividend is
  processed in blocks of `nb − 2` limbs from the top, each block divided by the
  same reciprocal. A correction loop makes the result exact whatever the
  accuracy of the estimate, and a counter of estimates that needed more than
  six corrections (`NewtonFallbacks`) stays at zero in the tests. Knuth's
  algorithm is faster below the threshold, because its inner loop costs little
  per limb pair.
- **Burnikel-Ziegler recursion.** Above `BZDivThreshold` (512 limbs) with the
  dividend within 256 limbs below twice the divisor, division recurses on 2n-by-n
  blocks with asymmetric halves, a one-limb pre-step, and correction loops of
  at most a few iterations. Any failed internal check falls back to Algorithm D
  and counts `BZFallbacks`. A prototype matched Knuth bit-for-bit on 8560 fuzz
  cases with the remainder proof checked on every case. Measured 2026-11-07 on
  raw limb arrays, the recursion against Knuth runs 1.4 to 2.9 times slower at
  334 divisor limbs and below, 0.77 at 512, 0.67 at 768, 0.58 to 0.78 at 1111,
  0.42 to 0.55 at 2048, and 0.31 to 0.41 at 4096 divisor limbs. Fully
  unbalanced shapes with a small divisor stay slower, and the divisor gate
  keeps them on Algorithm D.
- **Exact division.** `Divide(A, B)` computes the preferred scale
  `A.scale − B.scale`. The quotient of the unscaled values terminates only if
  the reduced denominator has no prime factors other than 2 and 5. The code
  writes `B = 2^a · 5^b · B'`, where `B'` has no factor 2 or 5. It strips the
  factors with single-limb divisions. The quotient terminates if and only if
  `B'` divides `A`, which one remainder operation tests. No gcd is needed. If
  `B'` does not divide `A`, the code raises `EBigDecimalNonTerminating`.
  Otherwise, with `m = max(a, b)`, the unscaled quotient is
  `(A / B') · 2^(m−a) · 5^(m−b)` at scale `m` above the preferred scale. The
  code then removes trailing zeros down to the preferred scale. This follows
  the Java rule for the result scale.
- **Context division.** `Divide(A, B, Context)` produces `Precision + 2`
  digits plus a sticky remainder flag. It then rounds once. This gives a
  correctly rounded result for every rounding mode.
- **Small context division.** `TryDivideFast` serves precisions whose scaled
  magnitude fits `MaxStackLimbs` (96) limbs in stack buffers with no heap
  allocation on the divide path. The 300-digit shape (69 limbs after scaling)
  uses this path; the 1000-digit shape (225 limbs) uses the heap path.
- **Gap to libmpdec.** Measured 2026-11-07, division runs 1.6 to 2.0 times the
  libmpdec time across 34 to 10000 digits. The per-limb cost is at parity or
  better (about 2.5 ns per inner iteration at 10000 digits against about
  6.5 ns for libmpdec, derived from iteration counts and wall time). The gap
  comes from limb width: libmpdec uses base 10^19 (about a quarter of the limb
  pairs) with native 128-bit products, while this library uses base 10^9 with
  64-bit division per limb. A prototype Barrett reduction for a base 10^18
  inner loop (128-bit split with a precomputed reciprocal of 10^18, verified
  exact against binary long division on 2001 dense values) costs 4.0 ns per
  split against 2.0 ns per native 64-bit split, a ratio of 2.00 where a ratio
  below 2.0 is the break-even point before packing and estimator costs. The
  emulated 128-bit chain therefore cannot repay its halved iteration count on
  this toolchain, and the wide-limb path stays unused. On targets with a
  single-instruction 64 by 64 to 128-bit product and a fast 128-bit division,
  the trade may differ; no such host is available for measurement.

The `/` operator uses the thread-local default context when one is set
([section 4.1](../context.md)). With no default context, it rounds to 34
significant
digits, half-even, unless `NoContextFallback128` is off, in which case it
calls the exact `Divide(A, B)`. The `*` operator follows the same rule. A
caller who needs another rounding at one call site uses the context form.
A caller who needs the exact quotient calls `Divide(A, B)` directly.
