### 3.4 Rounding

All rounding goes through one routine:
`RoundMagnitude(Limbs, DropDigits, Mode, Sign)`.

1. The routine splits the magnitude at `DropDigits` decimal digits. The
   split is a limb index plus a `10^(k mod 9)` divisor for one limb.
2. It classifies the discarded part as zero, below half, exactly half, or
   above half. This needs only the top discarded digit and a flag for "any
   non-zero digit below". No comparison against a full `5 × 10^k` number
   occurs.
3. The mode, the sign, the class, and the parity of the kept last digit
   decide between increment and truncation.
4. An increment is a carry pass. After the increment, the routine tests
   whether the rounded magnitude became a power of ten (a value such as 999
   that becomes 1000 inside one limb, or a carry out of the top limb). If so,
   the precision has grown by one digit, and the routine drops one more digit
   (the dropped digit is a zero).
