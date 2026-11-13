## 11. Measurements and limits

Measurements are in [`RESULTS.md`](../RESULTS.md) (Apple Silicon aarch64, FPC
3.2.4-rc2). The main facts:

- **Tests.** The suite has 129 fpcunit tests. It runs the oracle vectors (about
  45,000 cases across 42 files), the dectest files `add`, `subtract`,
  `multiply`, `divide`, `divideint`, `remainder`, `compare`, `max`, `min`,
  `abs`, `minus`, `plus`, `rounding`, `quantize`, `rescale`, `tointegral`,
  `tointegralx`, `reduce`, `squareroot`, `exp`, `ln`, `log10` and `power`, the
  OEIS files, and the pi digit files. About 11,400 dectest cases run and pass.
  Cases with NaN, infinity, exponent limits or negative zero are skipped and
  counted (about 30% of the cases). No dectest case is on the
  expected-failure list.
- **Thresholds.** Karatsuba from 160 limbs, NTT from 4096 limbs, Newton division
  from 4096 limbs, Burnikel-Ziegler division from 512 limbs, swing factorial from 600,
  Kummer binomial from k = 13.
- **Small values.** A small-value `+`, `-` or `*` allocates no memory. The
  read of the thread-local default context costs about 3 ns. A default context
  adds no measurable time when the value has no more digits than the
  precision.
- **Python `decimal`.** Ratios of the library time to the Python time (libmpdec
  4.0.1) at 34 to 10,000 digits: multiply 0.6 to 1.9, divide 1.7 to 2.5, `Sqrt`
  0.37 to 1.5, `Exp` 0.05 to 1.5, `Ln` 0.14 to 1.1. At 30,000 to 3,000,000 digits,
  the NTT multiply ratio to Python ranges from 3.7 to 7.5.
- **Limits.** Constants and the elementary functions cost O(w²) limb operations
  at w digits, so precisions of many thousands of digits are slow
  (`Gamma(7.5)` takes about 1.1 s at 1000 digits). The `Gamma` function takes a
  shift of about `0.4 w` multiplications for a small argument.
- **Platform.** Only aarch64 macOS has built and run the library.
