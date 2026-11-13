### 3.2 Multiplication

The result scale is `A.scale + B.scale`. The magnitude product uses these
algorithms by operand size in limbs. The thresholds are variables that a
benchmark sets per target ([`RESULTS.md`](../../RESULTS.md)).

| Size (limbs)       | Algorithm            | Notes |
|--------------------|----------------------|-------|
| 1 × n              | Single-limb loop     | One carry chain. |
| below `KaratsubaThreshold` (160) | Schoolbook in column order | Described below. |
| `KaratsubaThreshold` to `NttThreshold` | Karatsuba | O(n^1.585). |
| `NttThreshold` (4096) and up | Number-Theoretic Transform (NTT) | O(n log n). Described below. |
| unbalanced         | Split the long operand into chunks of the short operand's size | Keeps Karatsuba and NTT efficient. |

**Column-order schoolbook (Comba).** The kernel computes one column of the
product at a time. The sum of the products in a column accumulates in a
`UInt64`. Each product is below 10^18, so 16 products fit below 2^64. After
every 16 products, one division by 10^9 splits the accumulator into a limb part
and a carry count. A row-order loop divides after every product. The column
order divides 16 times less often and has no dependent chain through the
division. It is about 3 times faster for 16 to 128 limbs.

Java `BigInteger` switches to Karatsuba at 1600 bits (50 ints)
([OpenJDK patch review](https://mail.openjdk.org/pipermail/core-libs-dev/2013-May/016790.html)).
That figure holds for base 2^32 limbs. The column-order kernel makes
schoolbook strong in base 10^9, so the crossover is at 160 limbs.

Karatsuba in base 10^9 works the same as in any base. The middle term
`(a0+a1)(b0+b1) − a0b0 − a1b1` can need one extra limb. The scratch sizing
accounts for this.

**Number-Theoretic Transform (NTT).** Products of `NttThreshold` limbs and
above use a two-prime NTT convolution with Chinese Remainder Theorem (CRT)
reconstruction.

The transform uses two 64-bit prime moduli:
- `P1 = 18446744069414584321` (`2^64 - 2^32 + 1`), with primitive root `G1 = 7` and 2-adic order `2^32`.
- `P2 = 18446744056529682433` (`2^64 - 2^34 + 1`), with primitive root `G2 = 10` and 2-adic order `2^34`.

A convolution coefficient is at most `min(na, nb) * (10^9 - 1)^2 < min(na, nb) * 10^18`.
The product of the two primes is approximately `3.4 * 10^38`. This product exceeds
`min(na, nb) * 10^18` for operand lengths up to `3 * 10^20` limbs. Two primes are
sufficient for base 10^9 limbs. libmpdec uses three primes because its limbs use
base 10^19, where coefficients exceed two 64-bit primes.

The NTT pipeline operates as follows:
1. The transform length `N` is the smallest power of two with `N >= na + nb`.
2. For each prime, operand limbs are copied into zero-padded 64-bit arrays. A
   radix-2 Decimation-In-Frequency (DIF) forward transform processes each operand.
   Pointwise products are computed modulo the prime, and a radix-2
   Decimation-In-Time (DIT) inverse transform recovers the convolution. The DIF and
   DIT pair avoids bit-reversal permutations.
3. CRT reconstruction combines the residues `r1` and `r2` using Garner's formula:
   `t = (r2 - r1) * inv(P1) mod P2`, and `x = r1 + P1 * t`. The integer `x` fits
   within 90 bits (held as two 64-bit words).
4. A two-word carry pass adds the running carry to `x`, divides by 10^9 to
   produce the result limb, and propagates the remainder carry to the next position.
5. Squaring transforms the operand once and squares the pointwise frequency domain
   coefficients.
6. Unbalanced operands with `na >= 2 * nb` divide the longer operand into chunks
   of `nb` limbs, matching the chunking structure of Karatsuba.

Squaring calls `SqrSchool` below `KaratsubaThreshold`, Karatsuba `SqrRec` up to
`NttThreshold`, and `NttSqrMag` at and above `NttThreshold`.
