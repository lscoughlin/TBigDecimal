### 3.1 Addition and subtraction

The operation first aligns the scales. It multiplies the operand with the
smaller scale by a power of ten. A multiply by `10^k` is `k div 9` limb
shifts plus one single-limb multiply by `10^(k mod 9)`. A single carry pass
then adds or subtracts the magnitudes. Subtraction compares the magnitudes
first, so the result sign is known.

When the scale gap is very large and one operand is small, the result is the
exact sum. The library does not truncate silently. A context-aware
`Add(A, B, Context)` rounds the result and may skip the alignment work when
the smaller operand lies far below the rounding position (a sticky-digit
shortcut).
