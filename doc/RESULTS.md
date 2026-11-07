# Benchmark results

Machine: Apple Silicon (aarch64, macOS), Free Pascal 3.2.4 (3.2.4-rc2, 2026/08/26), `-O3`.
Run `make bench` to regenerate. Numbers are microseconds unless noted.

## Baseline of 2026-11-07 (monotonic best-of method)

Machine: Liams-MacBook-Air.local, Apple Silicon arm64, macOS (Darwin 27.2.0),
Free Pascal 3.2.4, `-O3`. Date: 2026-11-07.

The method is the monotonic-clock method. Each bench program reads time
from `Double(GetTickCount64) / 1000.0`, with the name and unit of the old
`Secs` function kept. No bench program calls `Now`. A timed section runs
through `TimeIt` with seven trials or `TimeBoth` with fifteen trials.
Each row prints the minimum, the median and the spread. The spread is the
interquartile range over the median, in percent. Trial counts are
calibrated so that one trial takes at least 50 ms. All operands are
built once before the timed loops. A global sink checksum of precision
plus exponent accumulates over every timed result, so a call cannot be
removed as dead code. The parse bench parses only in the parse rows.

The baseline file `bench/baseline.csv` holds the minimum of three runs
of `tools/benchcompare.sh write`, merged by
`tools/benchcompare.sh merge`. A write run now captures timing rows
from BenchAll, BenchParseFormat and BenchFinancial, plus the nine
BenchSmall allocation rows. Timing rows hold the printed median of the
run, in nanoseconds. The minimum value can be zero for very fast rows
under the millisecond clock, so the median is the recorded value.
The merged baseline holds 407 rows: 398 timing rows with non-zero
nanoseconds and 9 allocation rows. The compare mode prints a row with
a delta over 5 percent and exits nonzero when a row regresses over
10 percent. A compare of the baseline with itself exits 0. A synthetic
compare with one row raised by 15 percent prints the row and exits 1.

The full bench set (`make bench benchsmall benchcompare benchbcd
benchparse benchfinancial benchdivmod`) runs to completion on this
machine. `make bench` ran three times. The factorial 100000 row spreads
(range / swing, interquartile percent) are 4.9 / 8.1, 5.0 / 3.6 and
14.0 / 11.3 in the three runs. The machine load is high during these
runs (load average over 4), so the spread of the large factorial rows
is not under 5 percent in every run. The min and median values are
253 ms / 266 ms, 253 ms / 258 ms and 257 ms / 271 ms for the range form.

The x86_64 kernel run is not recorded. This machine is arm64, so that
run needs an x86_64 host.

All rows below this section use the old method. The old method reads
`Now * 86400`, uses ad hoc trial counts, and builds some operands inside
the timed loops. Those rows stay for history and are not part of the
2026-11-07 baseline.

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
the same operands. Each cell is the best of two runs of five trials of at
least 50 ms, in microseconds. The machine was under load for both programs.

| digits | operation | TBigDecimal | Python | ratio |
|-------:|-----------|------------:|-------:|------:|
| 34 | multiply | 0.19 | 0.11 | 1.73 |
| 34 | divide | 0.43 | 0.19 | 2.26 |
| 34 | sqrt | 1.08 | 1.49 | 0.72 |
| 34 | exp | 14 | 9.26 | 1.48 |
| 34 | ln | 25 | 22 | 1.12 |
| 100 | multiply | 0.35 | 0.22 | 1.59 |
| 100 | divide | 1.05 | 0.48 | 2.19 |
| 100 | sqrt | 4.64 | 5.77 | 0.80 |
| 100 | exp | 27 | 20 | 1.39 |
| 100 | ln | 43 | 49 | 0.87 |
| 300 | multiply | 1.83 | 0.95 | 1.93 |
| 300 | divide | 5.13 | 2.09 | 2.45 |
| 300 | sqrt | 46 | 30 | 1.52 |
| 300 | exp | 178 | 304 | 0.59 |
| 300 | ln | 203 | 409 | 0.50 |
| 1000 | multiply | 14 | 12 | 1.14 |
| 1000 | divide | 43 | 20 | 2.20 |
| 1000 | sqrt | 211 | 336 | 0.63 |
| 1000 | exp | 1281 | 6751 | 0.19 |
| 1000 | ln | 2875 | 8150 | 0.35 |
| 3000 | multiply | 73 | 121 | 0.60 |
| 3000 | divide | 293 | 168 | 1.75 |
| 3000 | sqrt | 1234 | 2865 | 0.43 |
| 3000 | exp | 16500 | 366547 | 0.05 |
| 3000 | ln | 58000 | 411703 | 0.14 |
| 10000 | multiply | 562 | 552 | 1.02 |
| 10000 | divide | 3125 | 1794 | 1.74 |
| 10000 | sqrt | 12250 | 33348 | 0.37 |
| 10000 | exp | 342000 | 2020689 | 0.17 |
| 10000 | ln | 1215000 | 4685930 | 0.26 |

Division is the slowest operation relative to libmpdec (1.7 to 2.5 times).
libmpdec uses 10^19 limbs, which need a quarter of the limb pairs.

## Small operands

Results of up to 48 limbs (432 digits) are formed in stack buffers, and the
rounding to a context reads those buffers. A result then needs one allocation.
`Sqrt` of a short value runs on stack limbs (`ISqrtMag`), and the fixed-point
multiply, square and small division of the series code use stack buffers.
Before this change a 34-digit multiply made about three allocations, and
`Sqrt` 11.8 µs; after it, `Sqrt` takes 0.8 to 1.1 µs.

`make profile` samples each 34-digit operation for 3 seconds. After the change
the top entries of the add, exp and ln profiles are `fpc_initialize`,
`fpc_finalize`, `fpc_copy` and the record RTTI routine (about half of the
samples); the multiply profile is led by the schoolbook kernel, and the divide
profile by the Knuth multiply-and-subtract routine.

## Allocators

| Allocator | Result |
|-----------|--------|
| FPC default heap | baseline |
| `cmem` (C `malloc`) | equal within noise from 34 to 300 digits; 10 to 25% faster from 3000 digits |
| FastMM5 | not usable: it supports Delphi only, and its GPL 3 license conflicts with the library license |
| Arena allocator | not built: a 34-digit operation makes one allocation, so an arena would save at most the cost of that allocation |

The cost that remains is the runtime handling of a record with a dynamic
array, not the allocator. A record with a pointer and management operators
measured 4.7 times faster in a micro-benchmark (38.6 ns against 8.2 ns for
`Z := Add(X, Y)`), but FPC 3.2.4 does not call the management operators as
documented, so the layout is not usable (`doc/management-operators.md`).

## TBcd (RTL unit FmtBCD)

`bench/BenchBcd.lpr` (`make benchbcd`) compares add, multiply and divide with
`TBcd`, the decimal type of the FPC RTL. `TBcd` holds at most 64 digits and has
no square root, exponential or logarithm. The multiply operands have at most
32 digits so that the exact product fits. `TBcd` divides to 63 digits, and
`TBigDecimal` divides to a precision of 63. Each cell is the best of five
trials of at least 50 ms, in microseconds. The ratio is TBigDecimal time
divided by TBcd time.

| digits | operation | TBigDecimal | TBcd | ratio |
|-------:|-----------|------------:|-----:|------:|
| 16 | add | 0.107 | 0.151 | 0.71 |
| 16 | multiply | 0.175 | 0.694 | 0.25 |
| 32 | add | 0.151 | 0.286 | 0.53 |
| 32 | multiply | 0.191 | 2.136 | 0.09 |
| 62 | add | 0.160 | 0.534 | 0.30 |
| 62 | divide | 0.626 | 32.715 | 0.02 |

`BcdDivide` raises `ERangeError` for the 16-digit and 32-digit operands of the
benchmark (and for some other operands, such as 1.23456789 / 2.71828182) in
FPC 3.2.4, so those divisions are not compared.

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
