### 3.2 Multiplication

The result scale is `A.scale + B.scale`. The magnitude product uses these
algorithms by operand size in limbs. The thresholds are variables that a
benchmark sets per target ([`RESULTS.md`](../../RESULTS.md)).

| Size (limbs)       | Algorithm            | Notes |
|--------------------|----------------------|-------|
| 1 × n              | Single-limb loop     | One carry chain. |
| below `KaratsubaThreshold` (160) | Schoolbook in column order | Described below. |
| `KaratsubaThreshold` and up | Karatsuba   | O(n^1.585). |
| unbalanced         | Split the long operand into chunks of the short operand's size | Keeps Karatsuba efficient. |

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

A Schönhage-Strassen or NTT multiply is out of scope. A number of 10^5 limbs
or more is beyond the target use. The multiplication entry point `MulMag` is
the single place where such a method can be added.

Squaring calls the same column-order kernel with both operands equal. A
kernel that computes each cross product once and doubles the sum measured
slower, because it needs a separate doubling pass.
