## 9. Decisions

1. With no thread-local default context, `*` and `/` round to 34
   significant digits, half-even. This differs from Java, where the
   operators are exact. The fallback keeps naive code safe: a product
   cannot grow without bound and a quotient cannot raise. The global
   `NoContextFallback128` restores exact operators when set to `False`.
   The thread-local default context ([section 4.1](context.md)) lets a program choose
   another rounding without changing the operator syntax.
2. `+`, `-` and `*` round under a default context, as in Python `decimal`.
   Java has no such feature, so no Java behavior conflicts.
3. Constants are cached in one shared cache that a lock guards ([section 5.6](functions/constants.md)).
4. Large-scale multiplication uses a two-prime 64-bit Number-Theoretic Transform (NTT)
   with radix-2 DIF and DIT passes for base 10^9 limbs. Alternatives not taken:
   - Three prime moduli: unnecessary because the coefficient bound `min(na, nb) * 10^18`
     fits within two 64-bit primes (`3.4 * 10^38`) for all practical lengths.
   - `Double` floating-point FFT: requires splitting base 10^9 limbs into smaller chunks
     and managing floating-point rounding errors.
   - Toom-3 only: `O(n^1.465)` asymptotic complexity is less efficient than NTT `O(n log n)`
     for operands from 30,000 to 3,000,000 digits.
