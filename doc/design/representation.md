## 1. Representation

### 1.1 Fields

```pascal
TBigDecimal = record
private
  FSmall: Int64;            // unscaled value when FLimbs is nil
  FLimbs: array of UInt32;  // magnitude, base 10^9, least significant first
  FScale: Int32;
  FSign: Int8;              // -1, 0, +1 (used when FLimbs is not nil)
end;
```

- A limb is a `UInt32` that holds a value from 0 to 999,999,999. The product
  of two limbs is less than 10^18. This fits in an `UInt64` (maximum about
  1.8 × 10^19). A product plus a carry plus an addend also fits. A kernel
  loop therefore needs one 64-bit multiply and one division by the constant
  10^9 for each limb pair.
- The README sketch used `Int64` limbs. `UInt32` limbs halve the memory
  traffic, keep the cache hot, and avoid sign handling in the kernels.
- Base 10^9 is chosen over base 2^32 because decimal output, decimal scaling
  and decimal rounding then need no base conversion. Base 2^32 multiplies
  faster per bit, but each parse, print and `SetScale` needs a conversion that
  costs O(n²) or a divide-and-conquer algorithm. Decimal workloads (financial
  math) scale and print often. They gain more from base 10^9.
- **Small-value fast path.** When the unscaled value fits in `Int64`,
  `FLimbs` is `nil` and `FSmall` holds the value. Most financial values
  (prices, rates, amounts) are in this class. They then need no heap
  allocation. Add, subtract and multiply use `Int64` arithmetic with overflow
  checks and fall to the limb path on overflow. Java uses the same idea
  (`intCompact`).
- A dynamic array is reference counted and copy-on-write only in the
  sense that the program never writes to a shared array. A `TBigDecimal` is
  immutable after construction. Assignment copies one pointer and increments
  one counter. No code copies limbs on assignment.

### 1.2 Invariants

1. Limbs hold no high zero limb.
2. The value zero has `FLimbs = nil`, `FSmall = 0`. Its scale is kept.
3. If the magnitude fits in `Int64`, the value uses the small form. The
   constructors enforce this. It gives one representation for each value and
   makes comparison and hashing simple.
4. `FScale` is any `Int32`. An operation that overflows the scale raises
   `EBigDecimalOverflow`.

### 1.3 Precision

`Precision` is the count of decimal digits of the unscaled value. For the
limb form it equals `9 × (n − 1) + DigitCount(top limb)`. `DigitCount` uses a
compare chain against a constant table of powers of ten (no logarithm, no
division).
