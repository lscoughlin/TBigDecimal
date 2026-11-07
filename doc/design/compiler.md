## 2. Memory and compiler strategy (FPC)

The research on FPC behavior gives these points
([FPC devel list on management operators](https://lists.freepascal.org/fpc-devel/2016-April/037050.html),
[Delphi managed records](https://blogs.embarcadero.com/custom-managed-records-coming-in-delphi-10-3/)):

- An advanced record with a dynamic array field is a managed type. The
  compiler inserts initialization, reference counting and finalization code
  around every copy. The small-value fast path avoids most of this cost
  because `FLimbs` stays `nil`.
- Function results are built in place through a hidden result pointer.
  Operators therefore return `TBigDecimal` without a copy, but each result
  still allocates one limb array.
- The arithmetic kernels do not use `TBigDecimal`. They work on
  `PUInt32` with explicit lengths. The record operators allocate the result
  array once with `SetLength`, call the kernel, then normalize. This keeps
  managed-type overhead out of every inner loop.
- Kernel units set `{$R-}`, `{$Q-}`, `{$OPTIMIZATION LEVEL3}` and
  `{$INLINE ON}`. Hot helpers carry `inline`.
- **Division by 10^9.** FPC 3.2.4 (release candidate 2) on aarch64 compiles
  `UInt64 div 1000000000` and `mod 1000000000` at `-O2` to a hardware `udiv`
  (plus `msub` for the remainder). It does not use a multiply by a reciprocal.
  The kernel therefore does not rely on the compiler. On aarch64, `DivMod1e9`
  is a multiply-high by a reciprocal (inline assembler `umulh`): with
  `M = 19342813113834067`, `x div 10^9 = ((x shr 9) · M) shr 75`, exact for
  every `UInt64`. Other targets use the compiler divide. A pure Pascal
  multiply-high from 32-bit pieces and a `Double` estimate
  `q = Trunc(Double(x) · 1e-9)` with a one-step correction both measure slower
  than the `umulh` form ([`RESULTS.md`](../RESULTS.md)).
- Kernel loops split a product into a limb part and a carry in a way that does
  not depend on the previous limb where possible (the column-order multiply
  of [section 3.2](algorithms/multiplication.md) and the multiply-and-subtract
  step of [section 3.3](algorithms/division.md)). The
  dependent chain is then one addition or one borrow.
- **Short operands.** Addition, subtraction, multiplication, division with a
  context and rounding work in stack buffers when the operands and the result
  have at most `MaxStackLimbs` (48) limbs. The routines that do this
  (`TryAddFast`, `TryMulFast`, `TryDivideFast`, `PutRounded`) have no managed
  local variable, because FPC keeps the locals of a routine with a try block
  in memory and runs initialization and finalization code at each entry and
  exit. A result needs at most one allocation. The rounding to a context reads
  the stack buffer, so the product or sum does not exist as a `TBigDecimal`
  before it is rounded. Larger operands use the general paths.
- **Record layout.** `TBigDecimal` holds a dynamic array for the limbs. FPC
  initializes, copies and finalizes such a record through run-time type
  information, which costs about 30 ns for each result record. A record with a
  pointer to a reference counted block and management operators would avoid
  that cost, but FPC 3.2.4 does not call the management operators as documented
  ([`management-operators.md`](../management-operators.md)), so the library does not use them.
- Scratch buffers for Karatsuba and Newton iteration are allocated once per
  top-level call and passed down. Recursive calls never allocate.
