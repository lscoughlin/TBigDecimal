# Benchmark results

Machine: Apple Silicon (aarch64, macOS), Free Pascal 3.2.4 (3.2.4-rc2, 2026/08/26), `-O3`.
Run `make bench` to regenerate. Numbers are microseconds unless noted.

## Division by 10^9 (bench/BenchDivMod.lpr, dependent carry chain)

| Form | Time for 1.3 × 10^9 divisions |
|------|------------------------------:|
| compiler `div` (hardware `udiv`) | 5900 ms |
| `Double` estimate | 9694 ms |
| multiply-high, pure Pascal | 6182 ms |
| multiply-high, `umulh` assembler | 3680 ms |

The kernel uses the `umulh` form on aarch64. Other targets use the compiler divide.
The x86_64 form was written (`mul`) but could not be run on this machine, so it is not enabled.

## Multiplication

The schoolbook kernel sums the products of one column in a `UInt64` and divides
by 10^9 once for each 16 products (Comba order). Against the row-order kernel,
which divides after every product, it takes 0.55 times as long at 8 limbs, and
about 0.33 times as long from 16 to 128 limbs (755 ns against 256 ns at 16
limbs, 41.8 µs against 13.9 µs at 128 limbs, measured with both kernels in one
program).

Squaring calls the column-order kernel with equal operands. The row-order
squaring kernel that computes each cross product once took 1.6 to 1.8 times as
long (22.1 µs against 12.3 µs at 128 limbs).

Karatsuba against schoolbook (alternating best-of-15 trials): schoolbook wins
up to 144 limbs, Karatsuba wins by 17% at 160, 1.2 times at 192, 1.8 times at
512, 2 times at 1024. `KaratsubaThreshold = 160`.

## Division (2n limbs by n limbs)

The Knuth multiply-and-subtract loop is a separate routine, because FPC keeps
the locals of a routine with a `try` block in memory (8.0 ns per limb step
inside such a routine, 3.6 ns as a separate routine with a short chain, 1.8 ns
after the normalization of each limb moved off the borrow chain). Knuth
division at 128 limbs takes 46 µs. Newton division is slower up to 2048 limbs
and ties at 4096 (30.5 ms against 29.5 ms). `NewtonDivThreshold = 4096`.

## Python decimal (libmpdec 4.0.1)

`bench/BenchCompare.lpr` and `tools/benchpython.py` time the same operations on
the same operands. Each cell is the best of five trials of at least 50 ms, in
microseconds. The machine was under load for both programs.

| digits | operation | TBigDecimal | Python | ratio |
|-------:|-----------|------------:|-------:|------:|
| 34 | multiply | 0.19 | 0.12 | 1.58 |
| 34 | divide | 0.33 | 0.20 | 1.65 |
| 34 | sqrt | 8.54 | 1.58 | 5.41 |
| 34 | exp | 16 | 9.23 | 1.72 |
| 34 | ln | 23 | 22 | 1.06 |
| 100 | multiply | 0.35 | 0.22 | 1.59 |
| 100 | divide | 0.98 | 0.50 | 1.96 |
| 100 | sqrt | 18 | 6.04 | 2.99 |
| 100 | exp | 37 | 22 | 1.66 |
| 100 | ln | 55 | 53 | 1.04 |
| 300 | multiply | 1.37 | 0.94 | 1.46 |
| 300 | divide | 4.46 | 2.10 | 2.12 |
| 300 | sqrt | 38 | 30 | 1.27 |
| 300 | exp | 129 | 272 | 0.47 |
| 300 | ln | 191 | 338 | 0.57 |
| 1000 | multiply | 11 | 11 | 1.04 |
| 1000 | divide | 38 | 17 | 2.20 |
| 1000 | sqrt | 178 | 274 | 0.65 |
| 1000 | exp | 1078 | 5497 | 0.20 |
| 1000 | ln | 2375 | 6779 | 0.35 |
| 3000 | multiply | 64 | 100 | 0.64 |
| 3000 | divide | 625 | 143 | 4.38 |
| 3000 | sqrt | 2219 | 3268 | 0.68 |
| 3000 | exp | 14750 | 343771 | 0.04 |
| 3000 | ln | 52000 | 349099 | 0.15 |
| 10000 | multiply | 523 | 438 | 1.19 |
| 10000 | divide | 4625 | 1532 | 3.02 |
| 10000 | sqrt | 18500 | 27055 | 0.68 |
| 10000 | exp | 295000 | 1950829 | 0.15 |
| 10000 | ln | 1262001 | 4746390 | 0.27 |

Division is the slowest operation relative to libmpdec (1.7 to 4.4 times).
libmpdec uses 10^19 limbs, which need a quarter of the limb pairs, and its
Newton division runs above the sizes where this library still uses Knuth.

## Build profiles

FPC does not rebuild a unit when only the compiler options change. The
Makefile keeps one unit directory for each profile (`lib/debug`, `lib/release`,
`lib/heap`) so that a benchmark never links objects from a debug build.

## Factorial and binomial

The swing recursion wins from about 600. `FactorialSwingThreshold = 600`.
Kummer prime factorization beats the multiplicative form already at k = 20
(10× faster) and by 80× at k = 10000. `BinomialKummerThreshold = 12`, with the
multiplicative form kept for n above 4,000,000 where the sieve is too large.

## Functions (microseconds per call)

| digits | sqrt | exp | ln | pow(x, y) | sin | gamma(7.5) |
|-------:|-----:|----:|---:|----------:|----:|-----------:|
| 16 | 4 | 21 | 17 | 55 | 21 | 127 |
| 34 | 9 | 26 | 26 | 60 | 26 | 198 |
| 100 | 18 | 49 | 49 | 98 | 49 | 634 |
| 300 | 67 | 67 | 200 | 400 | 200 | 5867 |
| 1000 | 200 | 1000 | 2800 | 3800 | 1400 | 758200 |

## Small values (bench/BenchSmall.lpr)

Add 80 to 90 ns, multiply 70 to 80 ns (the machine load changes these numbers).
A counting memory manager sees zero allocations in 1000 additions,
subtractions, multiplications and comparisons of small values. The read of the
thread-local default context costs 1.4 to 3.8 ns. With a default context of 16
or 34 digits, the times for values with no more digits than the precision are
equal to the times without a default context.

## Kernel loops

The assembly of `BigDecimal.Limbs`, `BigDecimal.Multiply` and
`BigDecimal.Rounding` holds no call to a managed-type helper. In
`BigDecimal.Divide`, the only such calls are `SetLength` for scratch buffers in
the reciprocal and Newton routines, outside the inner loops.
