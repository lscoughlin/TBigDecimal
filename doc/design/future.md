## 10. Future directions

- **mpmath cross-check for expected failures.** For each case in the
  expected-failure list, the runner could ignore the dectest result and
  compare the library result with an `mpmath` value computed at 200 digits and
  rounded in the mode of the case. The reference for those cases would then
  be independent of the dectest files, and a library result that is correct
  but differs from a dectest result outside 0.5 ulp would pass with evidence.
  The cost is a second oracle to maintain and a Python dependency at test
  run time, not only at vector generation time.
- **Binary splitting and bit-burst evaluation.** Binary splitting of the
  series for `Pi`, `E` and `Ln` of small primes, the Chudnovsky series for
  `Pi`, and bit-burst evaluation of `Exp` and `Ln` would give O(M(p) log² p)
  at high precision. The library evaluates these series in fixed point at
  O(p²).
- **Faster division.** Division is 1.7 to 2.5 times slower than Python
  `decimal` ([`RESULTS.md`](../RESULTS.md)). A Burnikel-Ziegler recursion, or a division
  in 10^18 limbs with 128-bit products, would reduce the gap.
- **Reciprocal-root square root.** A Newton iteration for `1/sqrt(x)` needs
  only multiplications and avoids the divisions of the integer iteration.
- **NTT optimizations.** Radix-4 butterfly decomposition to halve memory passes,
  transform lengths `3 * 2^k` to reduce power-of-two padding overhead, four-step
  cache-blocked transform layout for operands exceeding L2 cache, and high-half cyclic
  products for Newton reciprocal division.
- **Other targets.** Builds and runs on x86_64, Linux and Windows. The
  `DivMod1e9` form for x86_64 (`mul`) is not enabled.
