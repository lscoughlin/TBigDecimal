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

Karatsuba against schoolbook (alternating best-of-15 trials, machine under
load): about even from 128 to 160 limbs, 15% faster at 256, 1.4 times faster at
512, 2.2 times at 1024. `KaratsubaThreshold = 160`.

## Division (2n limbs by n limbs)

The Knuth multiply-and-subtract loop splits each product without a dependency
on the previous limb and computes the borrow without branches. It takes about
0.6 times as long as the loop that carries the split through the chain.
Newton division wins from about 2000 limbs (31 ms against 34 ms at 2048 limbs,
94 ms against 143 ms at 4096 limbs). `NewtonDivThreshold = 1792`.

## Python decimal (libmpdec 4.0.1)

`bench/BenchCompare.lpr` and `tools/benchpython.py` time the same operations on
the same operands. The cells hold the best of three runs, in microseconds. The
machine was under load for both programs.

| digits | operation | TBigDecimal | Python | ratio |
|-------:|-----------|------------:|-------:|------:|
| 34 | multiply | 0.35 | 0.12 | 2.9 |
| 34 | divide | 0.84 | 0.21 | 4.0 |
| 34 | sqrt | 8.6 | 2.0 | 4.4 |
| 34 | exp | 33.9 | 10.9 | 3.1 |
| 34 | ln | 33.9 | 25.6 | 1.3 |
| 300 | multiply | 1.9 | 1.1 | 1.8 |
| 300 | divide | 13.6 | 2.4 | 5.6 |
| 300 | sqrt | 66.7 | 35.6 | 1.9 |
| 300 | exp | 125 | 330 | 0.38 |
| 300 | ln | 500 | 446 | 1.1 |
| 1000 | multiply | 16.0 | 13.3 | 1.2 |
| 1000 | divide | 117 | 20.7 | 5.6 |
| 1000 | sqrt | 400 | 337 | 1.2 |
| 1000 | exp | 1333 | 6754 | 0.20 |
| 1000 | ln | 7000 | 8170 | 0.86 |
| 3000 | multiply | 84 | 122 | 0.69 |
| 3000 | divide | 991 | 168 | 5.9 |
| 3000 | sqrt | 3667 | 2858 | 1.3 |
| 3000 | exp | 19000 | 353730 | 0.05 |
| 3000 | ln | 102000 | 389897 | 0.26 |
| 10000 | multiply | 682 | 480 | 1.4 |
| 10000 | divide | 10591 | 1713 | 6.2 |
| 10000 | sqrt | 39500 | 30841 | 1.3 |
| 10000 | exp | 386000 | 1959349 | 0.20 |
| 10000 | ln | 1974000 | 4665585 | 0.42 |

Division is the slowest operation relative to libmpdec. libmpdec uses 10^19
limbs, which need a quarter of the limb pairs.

## Factorial and binomial

The swing recursion wins from about 600. `FactorialSwingThreshold = 600`.
Kummer prime factorization beats the multiplicative form already at k = 20
(10× faster) and by 80× at k = 10000. `BinomialKummerThreshold = 12`, with the
multiplicative form kept for n above 4,000,000 where the sieve is too large.

## Functions (microseconds per call)

The machine was under load for this table.

| digits | sqrt | exp | ln | pow(x, y) | sin | gamma(7.5) |
|-------:|-----:|----:|---:|----------:|----:|-----------:|
| 16 | 8 | 30 | 30 | 80 | 34 | 203 |
| 34 | 9 | 35 | 43 | 95 | 43 | 319 |
| 100 | 24 | 49 | 98 | 171 | 98 | 1220 |
| 300 | 133 | 200 | 400 | 800 | 400 | 13467 |
| 1000 | 400 | 3200 | 8000 | 11600 | 4800 | 1693400 |

## Small values (bench/BenchSmall.lpr)

Add 70 to 90 ns, multiply 60 to 80 ns (the machine load changes these numbers).
A counting memory manager sees zero allocations in 1000 additions,
subtractions, multiplications and comparisons of small values. The read of the
thread-local default context costs 2.6 to 3.8 ns. With a default context of 16
or 34 digits, the times for values with no more digits than the precision are
equal to the times without a default context.

## Kernel loops

The assembly of `BigDecimal.Limbs`, `BigDecimal.Multiply` and
`BigDecimal.Rounding` holds no call to a managed-type helper. In
`BigDecimal.Divide`, the only such calls are `SetLength` for scratch buffers in
the reciprocal and Newton routines, outside the inner loops.
