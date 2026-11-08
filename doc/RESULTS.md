# Benchmark results

Machine: Apple Silicon (aarch64, macOS), Free Pascal 3.2.4 (3.2.4-rc2, 2026/08/26), `-O3`.
Run `make bench` to regenerate. Numbers are microseconds unless noted.

Dated paragraphs below hold numbers measured on 2026-11-08 with the
Burnikel-Ziegler integrated tree. The machine load was high during the runs
(load average above 4), so each reported cell is the best (minimum) of
repeated runs: the best of two runs for the comparison tables, the bench
program's own minimum of seven or fifteen trials elsewhere.

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
| compiler `div` (hardware `udiv`) | 3817 ms |
| `Double` estimate | 7274 ms |
| multiply-high, pure Pascal | 5209 ms |
| multiply-high, `umulh` assembler | 3178 ms |

Measured 2026-11-08, best of two runs (mismatches 0 in both runs).

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

Karatsuba against schoolbook (alternating best-of-15 trials, measured
2026-11-08): schoolbook wins at 64 and from 112 to 144 limbs (Karatsuba takes
the 96-limb row by about 1%, within noise), Karatsuba wins by about 10% at
160, 1.1 times at 192 and 256, 1.5 times at 512 and 1.9 times at 1024.
`KaratsubaThreshold = 160`.

## Division (2n limbs by n limbs)

The Knuth multiply-and-subtract loop is a separate routine, because FPC keeps
the locals of a routine with a `try` block in memory (8.0 ns per limb step
inside such a routine, 3.6 ns as a separate routine with a short chain, 1.8 ns
after the normalization of each limb moved off the borrow chain). Knuth
division at 128 limbs takes 46 µs. Newton division is slower up to 2048 limbs;
at 4096 it wins by about 3% on the 2026-11-08 run (35.0 ms against 34.0 ms).
`NewtonDivThreshold = 4096`.

## Series thresholds (exp bit-burst, ln split)

The probes below force the threshold globals off and on in the same binary
and time the same call, so each ratio compares the two production paths.
Times are best of three (exp) or best of two (ln) with a millisecond clock.
Both paths agree exactly on every case (difference 0).

Exp of 0.5, bit-burst core against the halved Taylor series, measured
2026-11-08 (milliseconds per call):

| precision | bit-burst | series | ratio |
|----------:|----------:|-------:|------:|
| 1000 | 1.0 | 1.0 | 1.00 |
| 3000 | 2.0 | 11.0 | 5.50 |
| 6000 | 6.0 | 58.0 | 9.67 |
| 8000 | 8.0 | 123.0 | 15.38 |

The crossover sits near 1000 digits on this machine, not at the
`ExpBitBurstDigits = 8000` gate: the gate is conservative. The fresh ratios
contradict the comment at the constant (burst wins 1.09 times at 8000
digits, loses at 6000); the cause of the difference is not established.
Lowering the gate is future work; the gate value is unchanged.

Ln of a short operand (9 digits) at several precisions, split against the
term loop, measured 2026-11-08 (milliseconds per call):

| operand digits | precision | split | series | ratio |
|---------------:|----------:|------:|-------:|------:|
| 9 | 300 | 0.0 | 0.0 | tie, below clock resolution |
| 9 | 1000 | 2.0 | 3.0 | 1.50 |
| 9 | 3000 | 9.0 | 54.0 | 6.00 |
| 9 | 10000 | 46.0 | 1166.0 | 25.35 |

`LnSplitDigits = 1000`: the split wins by about 1.5 times at 1000 digits
(2 ms against 3 ms on the millisecond clock) and ties at 300 digits below
clock resolution.

Wider operands at high precision, measured 2026-11-08:

| operand digits | precision | split | series | ratio |
|---------------:|----------:|------:|-------:|------:|
| 20 | 10000 | 146.0 | 1278.0 | 8.75 |
| 30 | 10000 | 287.0 | 1302.0 | 4.54 |
| 50 | 10000 | 567.0 | 1337.0 | 2.36 |
| 64 | 10000 | 808.0 | 1274.0 | 1.58 |
| 30 | 3000 | 42.0 | 54.0 | 1.29 |
| 64 | 3000 | 129.0 | 53.0 | 0.41 |
| 100 | 10000 | 1313.0 | 1318.0 | 1.00, gate rejects the split |
| 500 | 3000 | 54.0 | 53.0 | 0.98, gate rejects the split |
| 1000 | 10000 | 1241.0 | 1283.0 | 1.03, gate rejects the split |

`LnSplitTopMul = 50`: the gate admits the winning shapes and rejects the
large-operand shapes (100 digits and up tie at 1.00). One admitted shape
loses: the 64-digit operand at precision 3000 runs the split 2.4 times
slower than the series. The gate admits both 64-digit shapes with opposite
outcomes (1.58 times faster at precision 10000, 0.41 times at 3000), so the
top-size ratio alone does not predict the outcome across precisions.
Tightening the gate is future work; the gate value is unchanged.

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

On 2026-11-07 the same machine gave these divide and multiply rows before and
after `MaxStackLimbs` moved from 48 to 96 (microseconds, Python from the same
run):

| digits | operation | before | after | Python | after ratio |
|-------:|-----------|-------:|------:|-------:|------------:|
| 34 | multiply | 0.14 | 0.14 | 0.10 | 1.40 |
| 34 | divide | 0.31 | 0.31 | 0.16 | 1.94 |
| 100 | multiply | 0.26 | 0.26 | 0.20 | 1.30 |
| 100 | divide | 0.76 | 0.77 | 0.42 | 1.83 |
| 300 | multiply | 1.34 | 1.02 | 0.82 | 1.24 |
| 300 | divide | 3.72 | 3.60 | 1.88 | 1.91 |
| 1000 | multiply | 9.64 | 9.52 | 10.16 | 0.94 |
| 1000 | divide | 30.76 | 30.76 | 16.12 | 1.91 |
| 3000 | multiply | 54.69 | 54.69 | 94.89 | 0.58 |
| 3000 | divide | 214.84 | 214.84 | 130.96 | 1.64 |
| 10000 | multiply | 421.87 | 406.25 | 399.13 | 1.02 |
| 10000 | divide | 2375.00 | 2281.26 | 1400.28 | 1.63 |

The remaining divide gap is structural: per-limb cost is at parity or better,
and libmpdec wins on limb count (base 10^19 with native 128-bit products). A
Barrett base-10^18 prototype measured 2.0 times a native 64-bit split per
operation and cannot repay its halved iteration count on this toolchain
(see the division design note).

On 2026-11-07 a Burnikel-Ziegler prototype measured these raw-limb ratios
against Knuth (best of five, nanoseconds per call, threshold 128):

| dividend limbs | divisor limbs | Knuth | Burnikel-Ziegler | ratio |
|---------------:|--------------:|------:|-----------------:|------:|
| 668 | 334 | 250006 | 300002 | 1.20 |
| 1024 | 512 | 650001 | 500000 | 0.77 |
| 1536 | 768 | 1499999 | 999999 | 0.67 |
| 2222 | 1111 | 2999942 | 2333323 | 0.78 |
| 2048 | 1024 | 2666632 | 1666625 | 0.62 |
| 4096 | 2048 | 10333300 | 4666646 | 0.45 |
| 8192 | 4096 | 41666667 | 13333321 | 0.32 |

The prototype matches Knuth bit-for-bit on 8560 fuzz cases with the remainder
proof checked on every case. At the 10000-digit bench shape the ratio 0.78
projects the divide row from 1.63 toward about 1.2. Shapes below 512 divisor
limbs stay on Knuth.

On 2026-11-07 the integrated recursion measured end to end in `make
benchcompare` (microseconds, Python from the same run):

| digits | TBigDecimal divide | Python divide | ratio |
|-------:|-------------------:|--------------:|------:|
| 10000 | 1109.37 | 1395.21 | 0.80 |

The 3000-digit row is unchanged at 1.71 because its 334-limb divisor stays
below the gate.

On 2026-11-08 the BZ-integrated tree gave these best-of-two cells (each run
best of five trials of at least 50 ms; the machine was under load, and the
second run was slower across the board, so the first run wins every
TBigDecimal cell):

| digits | operation | TBigDecimal | Python | ratio |
|-------:|-----------|------------:|-------:|------:|
| 34 | multiply | 0.14 | 0.12 | 1.17 |
| 34 | divide | 0.34 | 0.20 | 1.70 |
| 34 | sqrt | 0.90 | 1.58 | 0.57 |
| 34 | exp | 12.70 | 9.27 | 1.37 |
| 34 | ln | 25.88 | 21.42 | 1.21 |
| 100 | multiply | 0.32 | 0.22 | 1.45 |
| 100 | divide | 0.98 | 0.51 | 1.92 |
| 100 | sqrt | 4.03 | 6.77 | 0.60 |
| 100 | exp | 25.39 | 21.95 | 1.16 |
| 100 | ln | 41.02 | 53.33 | 0.77 |
| 300 | multiply | 1.24 | 0.95 | 1.31 |
| 300 | divide | 4.33 | 2.27 | 1.91 |
| 300 | sqrt | 43.46 | 31.42 | 1.38 |
| 300 | exp | 94.73 | 284.66 | 0.33 |
| 300 | ln | 148.44 | 364.97 | 0.41 |
| 1000 | multiply | 11.47 | 12.01 | 0.96 |
| 1000 | divide | 37.60 | 18.39 | 2.04 |
| 1000 | sqrt | 175.78 | 287.44 | 0.61 |
| 1000 | exp | 1078.13 | 5778.07 | 0.19 |
| 1000 | ln | 2500.00 | 6974.69 | 0.36 |
| 3000 | multiply | 64.45 | 103.84 | 0.62 |
| 3000 | divide | 265.63 | 143.11 | 1.86 |
| 3000 | sqrt | 1140.62 | 2342.50 | 0.49 |
| 3000 | exp | 14499.96 | 301725.88 | 0.05 |
| 3000 | ln | 49999.95 | 338114.63 | 0.15 |
| 10000 | multiply | 492.19 | 438.30 | 1.12 |
| 10000 | divide | 1343.75 | 1539.97 | 0.87 |
| 10000 | sqrt | 6000.00 | 28069.42 | 0.21 |
| 10000 | exp | 234999.90 | 1701446.46 | 0.14 |
| 10000 | ln | 1320999.86 | 4107316.62 | 0.32 |

The 10000-digit divide now runs faster than Python (0.87, against 0.80 on
2026-11-07; both runs show a ratio below 1.0 under load). The 3000-digit
divide stays near 1.9 with its 334-limb divisor below the gate. Exp and ln
run faster than Python from 300 digits up (0.33 and 0.41 at 300 digits,
0.05 and 0.15 at 3000 digits).

## Small operands

Results of up to 96 limbs (864 digits) are formed in stack buffers, and the
rounding to a context reads those buffers. A result then needs one allocation.
`Sqrt` of a short value runs on stack limbs (`ISqrtMag`), and the fixed-point
multiply, square and small division of the series code use stack buffers.
Before this change a 34-digit multiply made about three allocations, and
`Sqrt` 11.8 µs; after it, `Sqrt` takes 0.8 to 1.1 µs.

`make profile` samples each 34-digit operation for 3 seconds. On 2026-11-08
the add and ln profiles are led by the runtime handlers (`fpc_initialize`,
`fpc_finalize`, `fpc_copy`, the record RTTI routine and the dynamic array
helpers, about seven eighths of the collected samples); the exp profile is
led by the double conversion `ApproxAbs` with the runtime handlers next
(about two thirds); the multiply profile is led by the schoolbook kernel,
and the divide profile by the Knuth multiply-and-subtract routine. The
34-digit divide stays below the Burnikel-Ziegler gate, so the Knuth core
still shows there. The sqrt profile was not captured (the sqrt batch exits
before the sampler attaches).

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
| 16 | add | 0.083 | 0.118 | 0.70 |
| 16 | multiply | 0.160 | 0.603 | 0.27 |
| 32 | add | 0.147 | 0.275 | 0.53 |
| 32 | multiply | 0.221 | 1.923 | 0.12 |
| 62 | add | 0.168 | 0.580 | 0.29 |
| 62 | divide | 0.580 | 28.320 | 0.02 |

Measured 2026-11-08, best of five trials of at least 50 ms.

`BcdDivide` raises `ERangeError` for the 16-digit and 32-digit operands of the
benchmark (and for some other operands, such as 1.23456789 / 2.71828182) in
FPC 3.2.4, so those divisions are not compared.

## Build profiles

FPC does not rebuild a unit when only the compiler options change. The
Makefile keeps one unit directory for each profile (`lib/debug`, `lib/release`,
`lib/heap`) so that a benchmark never links objects from a debug build.

## Factorial and binomial

The swing recursion wins from about 600. `FactorialSwingThreshold = 600`.
On 2026-11-08 one run gave 266 ms / 276 ms for range splitting and 172 ms /
179 ms for swing at 100000 (min / median). Kummer prime factorization beats
the multiplicative form already at k = 20 (12× faster on the 2026-11-08 run)
and by about 114× at k = 10000. `BinomialKummerThreshold = 12`, with the
multiplicative form kept for n above 4,000,000 where the sieve is too large.

## Functions (microseconds per call)

| digits | sqrt | exp | ln | pow(x, y) | sin | gamma(7.5) |
|-------:|-----:|----:|---:|----------:|----:|-----------:|
| 16 | 4 | 21 | 17 | 55 | 21 | 127 |
| 34 | 9 | 26 | 26 | 60 | 26 | 198 |
| 100 | 18 | 49 | 49 | 98 | 49 | 634 |
| 300 | 67 | 67 | 200 | 400 | 200 | 5867 |
| 1000 | 200 | 1000 | 2800 | 3800 | 1400 | 758200 |

On 2026-11-08 `BenchAll` gave these minima of seven trials (microseconds
per call):

| digits | sqrt | exp | ln | pow(x, y) | sin | gamma(7.5) |
|-------:|-----:|----:|---:|----------:|----:|-----------:|
| 16 | 0.5 | 15 | 18 | 44 | 20 | 129 |
| 34 | 0.9 | 17 | 20 | 57 | 25 | 186 |
| 100 | 4 | 29 | 37 | 83 | 41 | 461 |
| 300 | 33 | 93 | 160 | 273 | 143 | 2000 |
| 1000 | 162 | 1000 | 2156 | 3313 | 1516 | 55000 |

A separate probe confirms gamma(7.5) at 1000 digits at 65 ms warm (best of
three); the first call takes about 890 ms cold.

## Small values (bench/BenchSmall.lpr)

Add 80 to 90 ns, multiply 70 to 80 ns (the machine load changes these numbers).
On 2026-11-08 the same bench gives add 108.0 ns and multiply 124.2 ns under
load. A counting memory manager sees zero allocations in 1000 additions,
subtractions, multiplications and comparisons of small values. The read of the
thread-local default context costs 1.4 to 3.8 ns (2.40 ns on 2026-11-08).
With a default context of 16 or 34 digits, the times for values with no more
digits than the precision are equal to the times without a default context
(add 103.0 ns and multiply 124.6 ns with default Decimal128 on 2026-11-08,
against 108.0 ns and 124.2 ns without).

## Kernel loops

The assembly of `BigDecimal.Limbs`, `BigDecimal.Multiply` and
`BigDecimal.Rounding` holds no call to a managed-type helper. In
`BigDecimal.Divide`, the only such calls are `SetLength` for scratch buffers in
the reciprocal and Newton routines, outside the inner loops.
