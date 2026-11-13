# Benchmark results

Machine: Apple Silicon (aarch64, macOS), Free Pascal 3.2.4 (3.2.4-rc2), `-O3`.
Date: 2026-11-13.
Numbers are microseconds unless noted.

This document records the current benchmark results for `TBigDecimal`.
Each timed section runs through `TimeIt` with seven trials or `TimeBoth` with
fifteen trials. Each row prints the minimum, the median and the spread. The spread
is the interquartile range over the median, in percent.

## Baseline (monotonic best-of method)

The baseline file `bench/baseline.csv` holds the recorded values of
`tools/benchcompare.sh write`, merged by `tools/benchcompare.sh merge`.
The baseline contains timing rows from `BenchAll`, `BenchParseFormat` and
`BenchFinancial`, plus allocation rows from `BenchSmall`.

## Small-value operations and allocations (`bench/BenchSmall.lpr`)

Small values that fit in 64 bits allocate no heap memory.

| Operation | Allocations per 1000 calls | Bytes per 1000 calls | Time per call |
|-----------|---------------------------:|---------------------:|--------------:|
| Addition | 0 | 0 | 85.2 ns |
| Multiplication | 0 | 0 | 112.2 ns |
| Subtraction | 0 | 0 | 85.0 ns |
| Comparison | 0 | 0 | 28.0 ns |
| Division (stack path) | 1000 | 32,000 | 310.0 ns |
| Square root (stack path) | 1000 | 32,000 | 780.0 ns |
| Parse (34 digits) | 2000 | 54,000 | 1150.0 ns |
| Format (34 digits) | 7000 | 226,000 | 2100.0 ns |
| 1000-digit multiplication | 4000 | 2,764,000 | 11.5 µs |

Thread-local default context read (`HasDefault`) costs 1.60 ns.
Addition with `Decimal128` default context takes 112.4 ns.
Multiplication with `Decimal128` default context takes 138.6 ns.

## Division by 10^9 (`bench/BenchDivMod.lpr`)

Dependent carry chain of 1.3 × 10^9 divisions:

| Implementation | Time for 1.3 × 10^9 divisions |
|----------------|------------------------------:|
| Compiler `div` (hardware `udiv`) | 4183 ms |
| `Double` estimate with correction | 7945 ms |
| Multiply-high, pure Pascal | 5346 ms |
| Multiply-high, `umulh` assembler | 3376 ms |

The kernel uses `umulh` assembler on aarch64. Other targets use compiler division.

## Multiplication (`bench/BenchAll.lpr`)

Schoolbook versus Karatsuba on balanced operands (microseconds per product):

| Limbs | Schoolbook (µs) | Karatsuba (µs) | Winner |
|------:|----------------:|---------------:|--------|
| 64 | 3.11 | 3.05 | Karatsuba |
| 96 | 7.32 | 7.32 | Schoolbook |
| 112 | 10.74 | 10.86 | Schoolbook |
| 128 | 13.92 | 13.92 | Schoolbook |
| 144 | 16.60 | 16.60 | Schoolbook |
| 160 | 21.24 | 19.29 | Karatsuba |
| 192 | 29.79 | 26.86 | Karatsuba |
| 256 | 50.78 | 44.92 | Karatsuba |
| 512 | 199.22 | 136.72 | Karatsuba |
| 1024 | 781.25 | 406.25 | Karatsuba |
| 2048 | 3000.00 | 1343.75 | Karatsuba |

`KaratsubaThreshold = 160`.

Karatsuba versus Number-Theoretic Transform (NTT) on balanced operands:

| Limbs | Karatsuba (µs) | NTT (µs) | Winner | Ratio (Kara/NTT) |
|------:|---------------:|---------:|--------|-----------------:|
| 512 | 134.77 | 132.81 | NTT | 1.01 |
| 1024 | 398.44 | 398.44 | Karatsuba | 1.00 |
| 2048 | 1343.75 | 1343.75 | Karatsuba | 1.00 |
| 4096 | 4187.49 | 5062.51 | Karatsuba | 0.83 |
| 8192 | 13000.01 | 10999.98 | NTT | 1.18 |
| 16384 | 41499.97 | 24500.01 | NTT | 1.69 |
| 65536 | 359999.90 | 104000.09 | NTT | 3.46 |

`NttThreshold = 4096`. For squaring, NTT wins at 4096 limbs and above. For general
multiplication, NTT wins from 8192 limbs and is 3.5 times faster at 65536 limbs.

## Large multiplication against Python (`bench/BenchBigMul.lpr`)

Exact product of two n-digit operands against Python `decimal` (libmpdec 4.0.1):

| Digits | TBigDecimal (ms) | Python (ms) | Ratio |
|-------:|-----------------:|------------:|------:|
| 30,000 | 2.47 | 0.66 | 3.74 |
| 100,000 | 20.00 | 3.07 | 6.51 |
| 300,000 | 89.00 | 7.61 | 11.70 |
| 1,000,000 | 192.00 | 31.73 | 6.05 |
| 3,000,000 | 853.00 | 114.17 | 7.47 |

## Division of 2n limbs by n limbs (`bench/BenchAll.lpr`)

Knuth Algorithm D versus Newton reciprocal division:

| Limbs | Knuth (µs) | Newton (µs) | Winner |
|------:|-----------:|------------:|--------|
| 96 | 24.90 | 73.24 | Knuth |
| 128 | 37.60 | 122.56 | Knuth |
| 192 | 83.01 | 225.59 | Knuth |
| 256 | 140.63 | 378.91 | Knuth |
| 384 | 312.50 | 707.03 | Knuth |
| 512 | 585.94 | 1156.25 | Knuth |
| 768 | 1234.37 | 2140.62 | Knuth |
| 1024 | 2187.50 | 3593.74 | Knuth |
| 1536 | 6375.01 | 8250.03 | Knuth |
| 2048 | 8625.00 | 11000.01 | Knuth |
| 4096 | 34500.00 | 34999.97 | Knuth (tie) |

`NewtonDivThreshold = 4096`. `BZDivThreshold = 512`.

## Factorial (`bench/BenchAll.lpr`)

Range splitting versus swing recursion:

| n | Range min (ms) | Swing min (ms) | Winner |
|--:|---------------:|---------------:|--------|
| 500 | 0.058 | 0.058 | Tie |
| 600 | 0.091 | 0.090 | Swing |
| 700 | 0.104 | 0.104 | Tie |
| 800 | 0.096 | 0.096 | Tie |
| 1000 | 0.129 | 0.129 | Tie |
| 1500 | 0.258 | 0.207 | Swing |
| 2000 | 0.336 | 0.277 | Swing |
| 4000 | 0.922 | 0.625 | Swing |
| 8000 | 3.250 | 1.937 | Swing |
| 20000 | 16.000 | 9.750 | Swing |
| 50000 | 76.000 | 47.000 | Swing |
| 100000 | 213.000 | 130.000 | Swing |

`FactorialSwingThreshold = 600`.

## Binomial C(2k, k) (`bench/BenchAll.lpr`)

Multiplicative algorithm versus Kummer prime factorization:

| k | Multiplicative (ms) | Kummer (ms) | Winner |
|--:|--------------------:|------------:|--------|
| 20 | 0.0060 | 0.0005 | Kummer |
| 50 | 0.0154 | 0.0007 | Kummer |
| 100 | 0.0308 | 0.0016 | Kummer |
| 200 | 0.0674 | 0.0035 | Kummer |
| 400 | 0.1699 | 0.0067 | Kummer |
| 1000 | 0.6406 | 0.0188 | Kummer |
| 3000 | 4.2500 | 0.0771 | Kummer |
| 10000 | 37.4999 | 0.3203 | Kummer |

`BinomialKummerThreshold = 12`.

## Mathematical functions (`bench/BenchCompare.lpr`)

Comparison of `TBigDecimal` and Python `decimal` (libmpdec 4.0.1) across precision levels
(microseconds per call, `rmHalfEven`):

| Digits | Operation | TBigDecimal (µs) | Python (µs) | Ratio |
|-------:|-----------|-----------------:|------------:|------:|
| 34 | multiply | 0.14 | 0.10 | 1.40 |
| 34 | divide | 0.31 | 0.19 | 1.63 |
| 34 | sqrt | 0.78 | 1.40 | 0.56 |
| 34 | exp | 10.99 | 8.65 | 1.27 |
| 34 | ln | 21.24 | 21.24 | 1.00 |
| 100 | multiply | 0.30 | 0.20 | 1.50 |
| 100 | divide | 0.92 | 0.44 | 2.09 |
| 100 | sqrt | 4.03 | 5.37 | 0.75 |
| 100 | exp | 24.41 | 18.23 | 1.34 |
| 100 | ln | 40.53 | 46.10 | 0.88 |
| 300 | multiply | 1.30 | 0.90 | 1.44 |
| 300 | divide | 4.33 | 1.95 | 2.22 |
| 300 | sqrt | 39.55 | 27.83 | 1.42 |
| 300 | exp | 89.84 | 283.47 | 0.32 |
| 300 | ln | 148.44 | 383.60 | 0.39 |
| 1000 | multiply | 11.47 | 10.93 | 1.05 |
| 1000 | divide | 35.64 | 18.20 | 1.96 |
| 1000 | sqrt | 179.69 | 314.90 | 0.57 |
| 1000 | exp | 1125.00 | 6310.23 | 0.18 |
| 1000 | ln | 2562.50 | 7620.45 | 0.34 |
| 3000 | multiply | 64.45 | 114.50 | 0.56 |
| 3000 | divide | 269.53 | 156.40 | 1.72 |
| 3000 | sqrt | 1078.13 | 2680.50 | 0.40 |
| 3000 | exp | 14250.04 | 344210.00 | 0.04 |
| 3000 | ln | 51999.81 | 384350.00 | 0.14 |
| 10000 | multiply | 546.88 | 532.10 | 1.03 |
| 10000 | divide | 2875.00 | 1675.30 | 1.72 |
| 10000 | sqrt | 11125.00 | 31250.00 | 0.36 |
| 10000 | exp | 312500.00 | 1920000.00 | 0.16 |
| 10000 | ln | 1125000.00 | 4350000.00 | 0.26 |

`ExpBitBurstDigits = 8000`. `LnSplitDigits = 1000`.
