## 8. Testing and verification

- **External reference material.** [Section 8.1](reference-material.md) lists the sources. Tests
  read them as input data.
- **Oracle vectors.** A Python script ([`tools/genvectors.py`](../../tools/genvectors.py), run with the
  environment that [`tools/setup-venv.sh`](../../tools/setup-venv.sh) creates) uses `decimal` (exact
  arithmetic and seven of the eight rounding modes; `ROUND_05UP` is not used
  and `rmUnnecessary` has no `decimal` counterpart) and `mpmath`
  (transcendental functions at 300 digits) to write test vector files.
  For the transcendental functions the 300-digit value rounds to `p` digits in
  each of the seven modes. The vector files are generated and are not stored. The unit tests read these files.
  Vectors cover zero, one, powers of ten, limb boundaries (`10^9 ± 1`),
  carry chains (`999...9`), negative scales, and random operands from 1 to
  5000 digits.
- **Properties.** Tests assert `(a + b) − b = a`, `(a × b) / b = a`,
  `DivRem` identity `a = q·b + r`, `Sqrt(x²) = |x|`, and
  `Exp(Ln(x)) ≈ x` within the stated error. They also assert that every
  multiplication algorithm agrees with schoolbook on random operands.
- **Rounding table.** A table drives all eight modes through the values
  `±5.5, ±2.5, ±1.6, ±1.1, ±1.0` (the table in the Java documentation).
- **Fuzzing.** The vector generator uses a fixed seed and writes thousands of
  random cases for each operation. The kernel tests run random operands of 1 to
  220 limbs, including operands made of all-nines limbs.
- **Benchmarks.** [`bench/BenchAll.lpr`](../../bench/BenchAll.lpr) times multiplication and division at 8
  to 2048 limbs, factorial and binomial at several sizes, and each function at
  16 to 1000 digits. It prints the crossover points that set the algorithm
  thresholds. [`bench/BenchDivMod.lpr`](../../bench/BenchDivMod.lpr) compares forms of division by 10^9.
- **Isolation.** A test runs every public function under a 5-digit default
  context and requires the result to be identical to the result with no
  default. A heap-traced run (`make heaptest`) reports no unfreed blocks.
