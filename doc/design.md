# TBigDecimal Design

This document describes the design of `TBigDecimal`. It states the
representation, the algorithms, and the reason for each choice.

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
  than the `umulh` form (`bench/RESULTS.md`).
- Kernel loops split a product into a limb part and a carry in a way that does
  not depend on the previous limb where possible (the column-order multiply
  of section 3.2 and the multiply-and-subtract step of section 3.3). The
  dependent chain is then one addition or one borrow.
- Scratch buffers for Karatsuba and Newton iteration are allocated once per
  top-level call and passed down. Recursive calls never allocate.

## 3. Algorithms

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

### 3.2 Multiplication

The result scale is `A.scale + B.scale`. The magnitude product uses these
algorithms by operand size in limbs. The thresholds are variables that a
benchmark sets per target (`bench/RESULTS.md`).

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

### 3.3 Division

`Divide` has three steps: choose the working scale, divide the magnitudes,
round the result.

- **Single-limb divisor.** One pass of 64-bit division by the divisor.
- **Multi-limb divisor.** Knuth Algorithm D adapted to base 10^9
  ([ridiculousfish on Algorithm D](https://ridiculousfish.com/blog/posts/labor-of-division-episode-iv.html),
  Knuth TAOCP vol. 2, section 4.3.1). Normalization multiplies both operands
  by `d = floor(10^9 / (v1 + 1))` so the top divisor limb is at least
  `10^9 / 2`. The quotient digit estimate uses the top two dividend limbs and
  the top divisor limb. A second-limb check removes almost all wrong
  estimates. One add-back step handles the rare remaining case. The
  multiply-and-subtract loop is a separate routine without a `try` block, so
  FPC keeps its locals in registers. It splits each product `qhat · v[i]` into a
  limb part and a carry, and normalizes each limb, without a dependency on the
  previous limb. The dependent chain is one subtraction, one compare and one
  masked addition, with no branches. A step costs about 1.8 ns.
- **Large operands.** When the divisor and the quotient both have at least
  `NewtonDivThreshold` (4096) limbs, division uses a Newton reciprocal followed
  by a multiply and a correction step. It runs in O(M(n)). GMP and other
  libraries use the same method
  ([Möller and Granlund, "Improved division by invariant integers"](https://www.lysator.liu.se/~nisse/archive/draft-division-paper.pdf)).
  The implementation normalizes the divisor, builds a reciprocal `Y` of its
  top `n` limbs with `n = nq + 2` (quotient limbs plus two guard limbs) by the
  Newton step `Z ← Z + Z·(B^(2n) − D·Z) / B^(2n)`, starting from the reciprocal
  of the top half of the limbs, estimates the quotient as the top limbs of
  `a'·Y`, and corrects the estimate by at most a few units with the exact
  product `q·b`. When the quotient has more than `nb − 2` limbs, the dividend is
  processed in blocks of `nb − 2` limbs from the top, each block divided by the
  same reciprocal. A correction loop makes the result exact whatever the
  accuracy of the estimate, and a counter of estimates that needed more than
  six corrections (`NewtonFallbacks`) stays at zero in the tests. Knuth's
  algorithm is faster below the threshold, because its inner loop costs little
  per limb pair. Recursive Burnikel-Ziegler division is an alternative that the
  library does not use.
- **Exact division.** `Divide(A, B)` computes the preferred scale
  `A.scale − B.scale`. The quotient of the unscaled values terminates only if
  the reduced denominator has no prime factors other than 2 and 5. The code
  writes `B = 2^a · 5^b · B'`, where `B'` has no factor 2 or 5. It strips the
  factors with single-limb divisions. The quotient terminates if and only if
  `B'` divides `A`, which one remainder operation tests. No gcd is needed. If
  `B'` does not divide `A`, the code raises `EBigDecimalNonTerminating`.
  Otherwise, with `m = max(a, b)`, the unscaled quotient is
  `(A / B') · 2^(m−a) · 5^(m−b)` at scale `m` above the preferred scale. The
  code then removes trailing zeros down to the preferred scale. This follows
  the Java rule for the result scale.
- **Context division.** `Divide(A, B, Context)` produces `Precision + 2`
  digits plus a sticky remainder flag. It then rounds once. This gives a
  correctly rounded result for every rounding mode.

The `/` operator uses the thread-local default context when one is set
(section 4.1). With no default context, it calls the exact `Divide(A, B)`.
This agrees with Java when no context is set. A caller who needs a rounded
quotient at one call site uses the three-argument form.

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

### 3.5 Parsing and printing

- Parsing reads nine decimal digits at a time into a limb. It handles
  exponent notation (`1.5E-7`). It runs in O(n).
- `ToPlainString` prints each limb with zero padding. It then inserts the
  decimal point. Output is O(n).
- `ToString` follows the Java scientific rule: use plain notation when
  `scale >= 0` and the adjusted exponent is at least −6. Otherwise it uses
  exponent notation. `ToEngineeringString` uses exponents that are multiples
  of three.
- `Create(Double)` has two forms. `FromDoubleExact` expands the binary value
  exactly (a double has at most 1074 fractional binary digits, so the result
  is finite). `FromDouble` tries 15, then 16, then 17 significant digits and keeps the
  first text that parses back to the same `Double`. This always ends, because
  17 digits always round-trip. The `Create` overload uses `FromDouble`,
  because that is the form callers expect. `ToDouble` does not rely on the FPC
  `Val` routine. It scales the value by a power of ten and a power of two to
  get a 54-bit integer quotient and a remainder with exact big integer
  arithmetic, and rounds half to even. This is the method of Clinger's
  Algorithm R. It is correctly rounded for any input length.

### 3.6 Comparison

Comparison checks the signs first. It then checks the adjusted exponents
(`Precision − Scale − 1`). If these differ, the larger exponent wins. Only
when they are equal does it compare limbs. When the scales differ and the adjusted exponents are equal, the operand with
the smaller scale is multiplied by a power of ten into a temporary array, and
the limbs then compare. This case allocates one array. Equal scales, and
operands whose adjusted exponents differ, allocate nothing.

## 4. Context and precision model

```pascal
TRoundingMode = (rmUp, rmDown, rmCeiling, rmFloor,
                 rmHalfUp, rmHalfDown, rmHalfEven, rmUnnecessary);

TMathContext = record
  Precision: Integer;        // 0 means exact
  RoundingMode: TRoundingMode;
end;
```

Exceptions descend from `EBigDecimal`: `EBigDecimalDivByZero`,
`EBigDecimalNonTerminating`, `EBigDecimalRounding`,
`EBigDecimalOverflow`, `EBigDecimalParse`, `EBigDecimalNoContext` (a
function needs a context and none is available), `EBigDecimalPrecision` (the
guard cap of section 5.1 was reached) and `EBigDecimalDomain` (for
example `Ln` of a value that is not positive).

Java defines `Precision = 0` as exact and `MathContext.UNLIMITED` as exact
([BigDecimal specification](https://www2.seas.gwu.edu/~rhyspj/docs/api/java/math/BigDecimal.html)).
This design keeps that rule.

### 4.1 Thread-local default context

Each thread can hold one default `TMathContext`. The default is stored in
`threadvar` variables in `BigDecimal.Types`:

```pascal
threadvar
  GDefaultContext: TMathContext;
  GHasDefaultContext: Boolean;   // False at thread start
```

Interface:

```pascal
class function TMathContext.Default: TMathContext;          // raises if none
class function TMathContext.HasDefault: Boolean;
class procedure TMathContext.SetDefault(const C: TMathContext);
class procedure TMathContext.ClearDefault;

// Scoped form. Enter saves the current state. Finalize restores it.
TMathContextScope = record
  procedure Enter(const C: TMathContext);
  class operator Finalize(var S: TMathContextScope);
  // fields: FPrev: TMathContext; FHadPrev: Boolean; FActive: Boolean
end;
```

Rules:

- A new thread starts with no default context. A thread does not inherit the
  context of its creator. A shared global would create data races and
  surprising results across threads.
- The default context applies to every call that has no explicit context
  argument and that rounds: `+`, `-`, `*`, `/`, unary `Plus`, and the
  context-free overloads of `Sqrt`, `Exp`, `Ln`, `Log10`, `Log`, `Pow`, `Root`
  and the financial helpers. The result rounds to `Precision` significant
  digits in the context `RoundingMode`. A default context with
  `Precision = 0` means exact arithmetic, as `MathContext.UNLIMITED` does.
- An explicit context argument always overrides the default.
- With no default context, `+`, `-` and `*` are exact. `/` is exact and can
  raise `EBigDecimalNonTerminating`. A transcendental function without a
  context argument raises `EBigDecimalNoContext`, because the result needs a
  precision.
- Methods whose meaning does not involve a precision ignore the default:
  comparison, `Abs`, `Negate`, `SetScale` (it has explicit scale and mode),
  `ToString`, parsing and conversion. `Create` never rounds.
- Library internals never read the default. The code in `BigDecimal.Math`
  and `BigDecimal.Constants` calls the kernels and the explicit-context
  routines, so a caller's default context cannot change the working
  precision of an internal step. The cached constants (`Pi`, `E`, `Ln2`,
  `Ln10`) are independent of the default.
- `TMathContextScope` restores the previous state on every exit path,
  including an exception. A program declares a local variable and calls
  `Enter`:

  ```pascal
  var Scope: TMathContextScope;
  begin
    Scope.Enter(Decimal128);
    ...
  end;
  ```

  Probes on FPC 3.2.4 (aarch64) established these facts. Inline variable
  declarations (`var X := ...`) do not compile in FPC 3.2.4, so the design
  does not use them. `Finalize` runs once per local variable on normal exit and
  on exit by exception, and nested scopes restore in reverse order. A
  function that returns a managed record, discarded as a statement, ran
  `Finalize` twice on one temporary in the probe. A factory function such as
  `Enter` that returns the scope record is therefore unsafe, and `Enter` is a
  procedure on a variable. `Finalize` also sets `FActive` to false after it
  restores, so a repeated call does nothing.
- A record with a management operator needs an `Initialize` operator that
  clears its flag. FPC does not zero a record that has only unmanaged fields,
  so without it the flag holds stack garbage. `TMathContextScope` has one.
- Every library function that takes an explicit context, and every exact
  combinatorics function, begins with a `TSuspendDefault` guard, a record of the
  same kind. The guard clears the default context of the thread while the
  function runs and restores it at exit, so the `+`, `-`, `*` and `/` operators
  inside the library stay exact. This is how internals never read the default.
- Only unmanaged types live in `threadvar` variables. A probe under `heaptrc`
  showed that a `threadvar` that holds a dynamic array leaks its array when
  the thread ends. `TMathContext` has no managed field, so the default
  context does not leak.
- Cost. Each rounding operator reads `GHasDefaultContext` once. A `threadvar`
  read is a thread-pointer-relative load on current FPC targets, but the cost
  is not assumed. A benchmark measures it. The small-value path
  tests the flag only after an exact result is ready, and skips rounding
  when the result precision is already within the limit.

## 5. Mathematical functions

Every function takes a `TMathContext`, or reads the thread-local default when
the call has no context argument (section 4.1). The caller picks the
precision and the mode. A function with `Precision = 0` raises
`EBigDecimalDomain`, because an exact transcendental result does not exist. The sole exceptions are the
cases with an exact answer (`Exp(0)`, `Ln(1)`, `Pow` with an integer
exponent).

### 5.1 Working precision and correct rounding

Each function computes at `p + g` digits, where `p` is the target precision
and `g` is a guard (about 10 digits plus `log10` of the term count). It
estimates a bound on the total error. If the interval
`[result − error, result + error]` rounds to one value in the requested
mode, the function returns that value. Otherwise it repeats with a larger
guard (Ziv's strategy). The loop ends quickly because a hard case is rare.
This yields a correctly rounded result in all modes, which is better than the
1 ulp that many libraries give. The one exception is an exact tie that the
function can never separate. Transcendental functions of non-trivial
arguments never produce an exact tie. The loop does not end when the true
result is exactly representable at the target precision, because the error
interval then always straddles the result. That case occurs for `Pow(4, 0.5)`,
`Pow(100, 1.5)`, `Pow(5.0625, 0.5)` (a midpoint, 2.25), `Log(2, 8)`,
`Log(4, 2)`, perfect powers under `Root`, and every exactly representable
result in the four directed modes.

Each function therefore tests for an exact result before the loop. For
`Pow(x, y)` with `y = a/b` in lowest terms, the code rounds a candidate
`c` and checks `c^b = x^a` exactly with integer arithmetic (MPFR does a
similar test for `pow`). `Log(b, x)` tests a rational candidate `a/c` the same
way: `b^a = x^c`. `Root` tests `c^n = x`. `Exp` and `Ln` have exact results
only at 0 and 1. When an exact result exists, the function returns it and
applies rounding to it. As a last resort, the code caps the guard at a fixed
number of digits and raises `EBigDecimalPrecision`.

### 5.2 Sqrt and Root

`Sqrt` and `Root` work on integers and round once, so the result is correctly
rounded in every mode with no Ziv loop. The code first scales the unscaled
value by a power of ten so that the scale is a multiple of the root index `k`,
and by `10^(k·t)` so that the integer root has at least `p + 2` digits. It then
computes the floor of the `k`-th root by Newton iteration on integers,
`y ← ((k−1)·y + n div y^(k−1)) div k`. The start value is above the root and
has about half of the digits right. It comes from the floor root of the
leading half of the digits of `n`, which the same function computes
recursively, plus one unit, shifted back. Below `40·k` digits the start value
is a power of ten above the root. Two Newton steps at full size follow the
recursion, so the cost is about four divisions at full size, not one division
for each doubling of the precision. A remainder test (`r^k = n`) tells whether the root is exact. When it is
not exact, the code appends a sticky digit 1 to the root, so that every
rounding mode sees a value just above the truncated root, and rounds to `p`
digits. When the root is exact, the result has the preferred scale
`ceil(scale / k)` if it fits in `p` digits. Each Newton step costs one
division (section 3.3). A reciprocal-root iteration that needs only
multiplications is not used (section 10).

### 5.3 Exp

1. The first reduction splits `x = k · ln(10) + r`, with `k` an integer and
   `|r| ≤ ln(10)/2`. Then `exp(x) = 10^k · exp(r)`. The factor `10^k` is a
   change of scale, which costs nothing in a decimal library. This is better
   than a power of the constant `e`. The step needs `Ln10` at a precision of
   `p` plus the digit count of `k`, because the error in `Ln10` is multiplied
   by `k`.
2. The second reduction sets `r' = r / 2^s`, with `s = min(40, floor(sqrt(w)))`
   for a working precision of `w` digits. The limit of 40 keeps the error
   bound after the squarings below 10^15 units. The Taylor series then
   converges quickly.
3. The Taylor series of `exp(r')` uses the term recurrence
   `t_{k+1} = t_k · r' / (k+1)`. With step 2, the cost is
   O(M(p)·sqrt(p)) (see
   [Brent, "Fast algorithms for high-precision computation of elementary functions"](https://maths-people.anu.edu.au/~brent/pd/RNC7-Brent.pdf)).
4. `s` squarings restore the result. Each squaring loses about one bit, so
   the guard digit count grows by about `s · log10(2)`.
5. For high precision (above about 1000 digits) switch to **bit-burst**:
   split `r` into chunks of 1, 2, 4, 8, ... leading bits and use binary
   splitting on each chunk ([Johansson, elementary functions](https://www.fredrikj.net/math/aric2023elementary.pdf)).
   This gives O(M(p)·log²p). The library does not use it (section 10).

### 5.4 Ln

- The reduction uses powers of ten and a small table. The code writes
  `x = m · 10^e` with `1 ≤ m < 10`. Then `ln(x) = ln(m) + e·ln(10)`. Further write `m = c · (1+u)`
  with `c` from a short table (`1`, `1.5`, `2`, `3`, `5`, `7`). Now `|u|` is
  small. The table needs `ln 2`, `ln 3`, `ln 5` and `ln 7` (`ln 1.5` is
  `ln 3 − ln 2`, and `ln 10` is `ln 2 + ln 5`). Section 5.6 gives the
  formulas.
- The code evaluates `ln(1+u)` as `2·atanh(z)` with `z = u/(2+u)`. This series has
  only odd powers and converges as `z²`. At 34 digits it needs about 15 to 20
  terms. It is the fastest method at low and medium precision.
- `ln(2)`, `ln(10)` and the table values are cached per working precision.
  The constants cache (section 5.6) holds them.
- For precision above a few thousand digits, a Newton iteration on `Exp`
  (`y ← y + 2(x − e^y)/(x + e^y)`) or the AGM method
  (`ln x ≈ π / (2·agm(1, 4/s)) − m·ln 2`, the approach MPFR uses for large
  precision) takes over. The AGM needs `Pi` and `Ln2`. See
  [Brent](https://maths-people.anu.edu.au/~brent/pd/RNC7-Brent.pdf). The
  library uses neither method (section 10).

### 5.5 Log10, Log, Pow, Root

- `Log10(x)`: exact when `x` is `10^k` (including scaled forms such as
  `0.001`). Otherwise `Ln(x)/Ln(10)` at working precision.
- `Log(b, x) = Ln(x)/Ln(b)`. It raises `EBigDecimalDomain` for `b ≤ 0` or
  `b = 1`. A first approximation at 40 digits is tested for a rational value
  `a/q` (`q ≤ 8`) with `x^q = b^a` by exact integer powers. When the identity
  holds and `a/q` terminates, the result is that exact decimal.
- `Pow(x, n)` with integer `n`: binary exponentiation. The code first strips
  trailing zeros from the base (so `10^n` costs one digit of work), computes the
  exact power when its estimated size is at most 20,000 digits (or the context
  is `Unlimited`), and rounds once. A larger power is evaluated by rounded
  square-and-multiply while an exactness flag records whether any step lost a
  digit; an exact result is then returned exactly, and an inexact one goes
  through the Ziv check. An exact result with a positive exponent keeps the
  natural scale `scale(x)·n`, padded with zeros up to `p` digits when the
  natural form has more than `p` digits. The result is exact when the context is `Unlimited`. A guard check refuses an exact result
  whose digit count would exceed a configurable limit
  (`MaxExactDigits`, default 10^7) to prevent memory exhaustion. A negative
  `n` computes `1 / x^|n|` at context precision. With a finite context the
  product loop rounds at working precision `p + g`, where `g` includes
  `log10(|n|)`.
- `Pow(x, y)` with a decimal `y`: if `y` is an integer value, the integer
  path applies. For `y = a/q` in lowest terms with `q ≤ 64`, the code tests
  whether `x` is a perfect `q`-th power (an integer root of the stripped
  unscaled value), and if so returns `root^a` exactly. Such a result, like every
  result with a fractional exponent, is padded with trailing zeros up to `p`
  digits, as in the General Decimal Arithmetic power operation and in Python
  `decimal`. Otherwise `Exp(y · Ln(x))` with the working precision raised by the
  number of digits of `|y · Ln(x)|`, because the absolute error of the exponent
  turns into a relative error of the result. It raises `EBigDecimalDomain` for
  `x < 0` with non-integer `y`.
- `Root(x, n)`: Newton iteration. `Sqrt` is the `n = 2` case.

### 5.6 Constants

`Pi` uses Machin's formula `pi = 16 atan(1/5) − 4 atan(1/239)`. `E` uses the
Taylor series of `exp(1)`. All the series run in fixed point and divide by a
single limb at each step (the divisors are at most 8749² and k), so each series
costs O(w²) limb operations for w digits. Binary splitting, and the Chudnovsky
series for `Pi` with about 14 digits per term, are possible extensions for
precisions of many thousands of digits.

`Ln2`, `Ln3`, `Ln5` and `Ln7` come from four `atanh` series of small
rational arguments. With `a(n) = atanh(1/n)`:

```
ln 2 = 144·a(251) +  54·a(449) −  38·a(4801) +  62·a(8749)
ln 3 = 228·a(251) +  86·a(449) −  60·a(4801) +  98·a(8749)
ln 5 = 334·a(251) + 126·a(449) −  88·a(4801) + 144·a(8749)
ln 7 = 404·a(251) + 152·a(449) − 106·a(4801) + 174·a(8749)
```

Each of these four identities was checked numerically against `mpmath` to 55
digits. Each series term divides by `n²` (at least 63,001), so a term adds
about 4.8 digits. `Ln10` is `ln 2 + ln 5`.

A cached value is stored at the highest precision computed so far, with an
error bound of one unit in its last place. A request for a lower precision
does not round the stored digits. Rounding a stored value would round twice
and could give a wrong result in the half modes and in the directed modes.
The lookup instead treats the stored value as an interval of one unit in the
last place and applies the Ziv check of section 5.1. If the interval rounds
to one value at the requested precision, that value is the result. If not, the
constant is recomputed at a higher precision and stored.


The constants cache holds one value for each constant, at the highest
precision any thread has computed. A `TRTLCriticalSection` guards it. A
lookup holds the lock only to read or replace one reference. It does not hold
the lock during a computation:

1. The thread takes the lock and reads the stored value. If the stored
   precision is enough, the thread copies the reference and releases the lock.
2. Otherwise the thread releases the lock and computes the constant at the
   needed precision plus a margin (a growth factor of about 1.5, so a
   sequence of rising requests does not recompute each time). It then takes
   the lock, replaces the stored value if its own is still higher, and
   releases the lock.

Two threads that miss together can both compute the same constant. The
result is correct, and the cost is limited to one duplicate computation. The
design accepts this to avoid holding the lock during a long computation.

A copy of the reference does not copy the limbs, because a `TBigDecimal` is
immutable and its limb array is reference counted. This needs the reference
count update to be atomic. The code relies on the FPC runtime to update dynamic
array counts with locked instructions when threads are present. A test runs
eight threads that request `Pi`, `Ln2` and `E` at mixed precisions and compare
the digits with the reference file. The test does not prove that the
count updates are atomic.

The cache is shared, not per thread. In FPC 3.2.4 a `threadvar` that holds a
dynamic array is not finalized when the thread ends, and the array leaks. A
per-thread cache would need a thread-exit hook that the FPC runtime does not
provide for every kind of thread. The shared cache with a short lock has no
such leak. A per-thread cache of unmanaged raw memory is the alternative if
lock contention shows in a profile.

### 5.7 Financial helpers

The helpers are thin wrappers: compound factor `(1 + r)^n`, present value,
future value, annuity factor, and annualized rate from a growth ratio
(`ratio^(1/t) − 1` with `Pow`). They accept non-integer periods and
use `Pow(x, y)`. Each helper takes a context. A helper computes the power at
`p + 12` digits (`p + 20` for the annuity factor and the annualized rate, which
subtract nearly equal values or round an exponent) and rounds once at the end.
These helpers are not Ziv-checked, so in rare cases (about 1 in 10^11 for the
`p + 12` form) the last digit can differ from the correctly rounded value.

### 5.8 Factorials, combinatorics and gamma

The functions of this section live in `BigDecimal.Combinatorics` and
`BigDecimal.Gamma`. Arguments `n` and `k` are non-negative `Int64` values
unless stated. A negative argument raises `EBigDecimalDomain`.

**Exact functions.** `Factorial`, `DoubleFactorial`, `Primorial`,
`FallingFactorial` (also `Permutations`), `RisingFactorial`, `Binomial`,
`CentralBinomial`, `Multinomial` and `Catalan` return exact integers with
scale 0. They ignore the default context (section 4.1), as `Create` does. A
guard estimates the result size before work starts. If the estimate exceeds
`MaxExactDigits` (the limit that `Pow` uses), the function raises
`EBigDecimalOverflow`. The estimate uses the Stirling formula in `Double`
arithmetic, with a safety margin.

**Methods considered.**

| Method | Verdict |
|--------|---------|
| Plain loop `n × (n−1) × ...` | Rejected. Each step multiplies a large number by a small one, so the cost is O(n²) digit operations. |
| Binary splitting of the product | Chosen for ranges. The tree of balanced products lets Karatsuba apply. |
| Swing recursion `n! = (⌊n/2⌋!)² · swing(n)` | Chosen for large `n`. |
| Direct Legendre prime factorization of `n!` | Kept as a test oracle and a benchmark candidate. |
| Gamma function at integer arguments | Rejected for integers. Exact methods are faster and exact. |

**Factorial.** Three size classes:

1. `n ≤ 20`: a constant table of `UInt64` values (20! is below 2^63).
2. `n` up to a threshold (about 1000, set by benchmark): binary splitting of
   the range `2..n`. The code first packs factors into `UInt64` words (as many
   as keep the product below 1.8 × 10^19), then multiplies the words in a
   balanced tree. This is the first of the two methods in the GMP manual:
   it "forms big multiplies, allowing Karatsuba and higher algorithms to be
   used" ([GMP manual, factorial algorithm](https://gmplib.org/manual/Factorial-Algorithm)).
3. Larger `n`: the swing recursion. The identity is
   `n! = (⌊n/2⌋!)² · swing(n)`, where `swing(n) = n! / (⌊n/2⌋!)²`. The
   swing number has a prime factorization with a small exponent for every
   prime: `swing(n) = ∏ p^L(p,n)`, where `L(p,n)` is the sum, over `i ≥ 1`,
   of `floor(n / p^i) mod 2`. Each exponent is therefore at most
   `log_p n`. The GMP manual describes the same structure: for large `n`,
   `n! / (⌊n/2⌋!)² · 2^k = ∏ p^L(p,n)` over odd primes `p`, with `k` the count
   of 1 bits of `⌊n/2⌋`
   ([GMP manual, factorial algorithm](https://gmplib.org/manual/Factorial-Algorithm)).
   The recursion needs `⌊n/2⌋!`, then `⌊n/4⌋!`, and so on, for a depth of
   `log2 n`. The cost is dominated by the last level. The big step is one
   squaring, and the design has a dedicated squaring kernel. The reason for
   the speed is the small exponents and the squaring, not a binary radix, so
   the method works in base 10^9.

   The factors of `swing(n)` are the primes up to `n` (from a sieve of
   Eratosthenes, odd numbers only, bit-packed, segmented), each raised to a
   power at most `log_p n`. The code multiplies them with the batched binary
   splitting tree of class 2. The power of 2 in the swing number is at most
   `log2 n`, so it is one small word, and no special handling of the factors
   2 and 5 is needed.

   The direct form `n! = ∏ p^e(p)` with Legendre's exponent
   `e(p) = Σ floor(n / p^i)` is also implemented, as a test oracle and as a
   benchmark candidate. In that form the exponent of 2 is about `n`, and the
   decimal base has no free shift for a power of two. The candidate uses the
   exponent of 5 to take `10^e(5)` as trailing zeros (a limb shift and one
   single-limb multiply), and the factor `2^(e(2) − e(5))` joins the tree as one
   leaf by repeated squaring.

   The sieve costs O(n) time and n/16 bytes. It is rebuilt on each call. At
   the size limit set by `MaxExactDigits` (about n = 1.7 × 10^6), the sieve
   takes a few milliseconds, so the design has no sieve cache.

**Double factorial and primorial.** `n!!` uses the same two-tier structure:
binary splitting over the arithmetic progression `n, n−2, ...`. A prime
factorization form is not used because the exponent formulas are less regular.
`Primorial(n)` is the product of the primes up to `n`. It reuses the sieve
and the batching tree.

**Falling and rising factorial.** `FallingFactorial(n, k)` is
`n (n−1) ... (n−k+1)`. `RisingFactorial(x, k)` is `x (x+1) ... (x+k−1)`.
Both use binary splitting of the product over the `k` terms. They avoid the
division of `n! / (n−k)!`, so no large number is formed that the result does
not need. The rising factorial also accepts a `TBigDecimal` argument `x`. In
that form it multiplies exact decimal values and rounds only on request.
Python `math.perm` splits `P(n,k) = P(n,j) · P(n−j,k−j)` with `j = k/2` in
the same way
([CPython change 60c320c38e](https://android.googlesource.com/platform/external/python/cpython3/+/60c320c38e%5E%21)).

**Binomial coefficient.** `Binomial(n, k)` first sets `k = min(k, n−k)` by
symmetry. If `k = 0` the result is 1. Two size classes apply:

1. Small `k` (at most `BinomialKummerThreshold`, 12) or very large `n`
   (above `BinomialSieveLimit`, 4,000,000, where the sieve would be too large):
   the multiplicative form `r ← r · (n−k+i) / i` for `i = 1..k`. Each division
   is exact, because after step `i` the partial result is a binomial
   coefficient. Each step is one multiplication by a word and one exact
   single-limb division. GMP uses this form and accumulates the numerators and
   denominators into one machine word first, to save multi-precision
   operations
   ([GMP manual, binomial coefficients](https://gmplib.org/manual/Binomial-Coefficients-Algorithm.html)).
2. Otherwise: prime factorization with Kummer's theorem. The exponent of a
   prime `p` in `C(n, k)` equals the number of carries when `k` and `n−k` are
   added in base `p`. Equivalently it is
   `Σ (floor(n/p^i) − floor(k/p^i) − floor((n−k)/p^i))`. Only primes up to `n`
   occur. A prime `p > n/2` has exponent 1 when `p > n−k`, else 0. The product
   uses the same batched tree as `Factorial`. Every exponent is at most
   `log_p n`, so the powers of 2 and 5 are small and need no special handling.
   This needs no big division.

The library has no separate class for results that fit in `UInt64` (CPython
keeps a table of limits for it). The benchmark in `bench/RESULTS.md` shows
Kummer's form ten times faster than the multiplicative form already at
`k = 20`, and the cost of a `TBigDecimal` for a result below 2^63 is small.
The recursion `C(n,k) = C(n,j) · C(n−j,k−j) / C(k,j)` with `j = k/2`, which
CPython uses, needs an exact big division at every node. The library does not
use it, because Kummer's form needs no division.

**Central binomial and Catalan.** `CentralBinomial(n) = C(2n, n)`.
`Catalan(n) = C(2n, n) / (n + 1)`. The division is exact. For `n + 1` below
10^9 it is a single-limb exact division. A larger `n` is out of range for
`MaxExactDigits` in practice. The code then raises `EBigDecimalOverflow`
before it reaches the division.

**Multinomial.** `Multinomial([k1, ..., km])` is
`C(k1, k1) · C(k1+k2, k2) · ... · C(k1+...+km, km)`. It multiplies the
binomial coefficients in a balanced tree. For a single large `n = Σ ki` and
many parts, the prime factorization form (exponent of `p` is
`e_n(p) − Σ e_ki(p)`) is used instead, because it needs one sieve and one
product tree.

**Generalized binomial.** `Binomial(x: TBigDecimal, k: Int64)` is
`FallingFactorial(x, k) / k!`. It follows the usual definition for any real
`x`. Financial code uses it for binomial lattices and series. The result
rounds per the context (explicit or default), because the quotient need not
terminate.

**Gamma and log-gamma.** `Gamma(x, Context)`, `LnGamma(x, Context)` and
`Factorial(x: TBigDecimal, Context)` (defined as `Gamma(x + 1)`) cover
non-integer arguments.

- *Integer arguments.* `Gamma(n)` for a positive integer `n` below 10^8 is
  `(n−1)!`, computed exactly and then rounded. A half-integer argument takes
  the general path below, which is correct and a little slower than a closed
  form `(2n)! / (4^n n!) · sqrt(pi)` would be.
- *Other arguments.* The Stirling series with argument shift. When `x` is
  below a shift target `T`, the recurrence
  `Gamma(x) = Gamma(x + r) / (x (x+1) ... (x+r−1))` shifts the argument up to
  `x + r ≥ T`. This applies to every `x` below `T`, including negative
  non-integers. The rising factorial in the denominator uses binary splitting.
  The shift costs about `T − x` multiplications, which grows with the size of
  a negative `x`. For `x` far below zero (below `−T`, with the break-even point
  set by benchmark) the reflection formula
  `Gamma(x) = pi / (sin(pi x) · Gamma(1 − x))` is cheaper. It needs one
  `Sin` (section 5.9) and one `Gamma` at the large positive argument
  `1 − x`, which needs no shift. The code reduces `x` modulo 2 exactly in
  decimal before it multiplies by `Pi`, so a large `x` costs no extra digits
  of `Pi`. When `x` is an integer, `sin(pi x)` is exactly zero, and the
  function raises `EBigDecimalDomain` (a pole) before any computation. The target `T` is `0.4 w + 8` for `w` working decimal digits (the series
  terms fall below `10^-w` near the minimum term `e^(-2 pi z)`). The Stirling series for
  `LnGamma(x + r)` then needs at most about `0.32 · b` terms for `b` bits of
  working precision, with Bernoulli numbers `B_2k`. The terms span many orders
  of magnitude (`B_2k` grows factorially while `z^-(2k-1)` falls), so the series
  is summed in floating point at `w + 6` digits of relative precision, not in
  fixed point, and the terms add exactly. A non-positive integer
  `x` is a pole and raises `EBigDecimalDomain`. `LnGamma(x)` is defined for
  `x > 0` only. `Gamma(x)` for negative non-integer `x` takes its sign from
  the sign of the rising factorial.
- *Why Stirling.* Johansson
  ([arXiv 2109.08392](https://arxiv.org/abs/2109.08392)) compares the Stirling
  series, Spouge and Lanczos. The Stirling series needs fewer terms than
  Spouge (about 0.323 b against 0.377 b terms, for b-bit accuracy). Each Stirling
  term costs less than one multiplication, where each Spouge term needs a
  division. The Bernoulli numbers are reusable across precisions. Spouge and
  Lanczos coefficients depend on the target precision and need extra working
  digits because their terms are large and alternate in sign. For that reason
  the design does not use them.
- *Bernoulli numbers.* A cache holds the tangent numbers `T_k` (integers) for
  the highest `k` computed, under a lock. The coefficient of the series is
  `B_2k / (2k (2k−1)) = (−1)^(k−1) T_k / ((2k−1) 4^k (4^k − 1))`. The tangent
  numbers come from the Brent and Harvey algorithm, which is O(n²) in the count
  of numbers and uses integer arithmetic only. The cache doubles when a larger
  index is requested.
- *Accuracy.* The functions use the Ziv loop of section 5.1. The error bound
  covers the Stirling truncation error (the first omitted term bounds it, for
  real `x > 0`), the shift product, and the Bernoulli rounding.
- `LnFactorial(n)` for an integer `n` is `LnGamma(n + 1)`.

### 5.9 Trigonometric functions

`Sin`, `Cos` and `Tan` take a `TBigDecimal` in radians and a context. `Atan`
is not part of the first release. Trigonometric functions help in two places:
the gamma reflection formula (section 5.8), and users who need periodic or
seasonal terms and wave models in financial code. They do not speed up
`Exp` or `Ln`.

- **Argument reduction.** The code writes `x = q · (pi/2) + r` with
  `|r| ≤ pi/4`. It computes `q` from `x · (2/pi)` at working precision
  `p + g + digits(|x|)`, and `Pi` at the same precision. The extra
  `digits(|x|)` digits make up for the cancellation in `x − q·pi/2`. Arbitrary
  precision makes the Payne-Hanek method for huge arguments unnecessary. The
  quadrant `q mod 4` selects among `sin r`, `cos r`, `−sin r`, `−cos r`.
- **Series.** The code sets `r' = r / 2^s` with `s = min(40, floor(sqrt(w)))`,
  as for `Exp`. It sums the Taylor series of `sin r'` (odd powers, term ratio
  `−r'²/((2k)(2k+1))`) and of `cos r'` (even powers, term ratio
  `−r'²/((2k−1)(2k))`). It then doubles the angle `s` times with
  `sin 2a = 2 sin a cos a` and `cos 2a = 1 − 2 sin² a`.
  The second form is stable because `sin² a` is small at the early steps. The
  guard grows by about `s · log10(2)` digits, as for `Exp`.
- **Tan.** `Sin / Cos` at working precision `p + g`. A cosine that is zero
  within the error bound cannot occur for a decimal `x`, because `x` is
  rational and `pi/2` is irrational.
- **Exact cases.** `Sin(0) = 0`, `Cos(0) = 1` and `Tan(0) = 0` are exact. No
  other decimal argument gives an exact result, because `sin`, `cos` and `tan`
  of a non-zero rational are transcendental (Lindemann-Weierstrass). The Ziv
  loop of section 5.1 therefore ends for them.
- **High precision.** The library evaluates the series directly. Bit-burst
  evaluation through `Exp` of a complex argument is not used (section 10).

## 6. API conventions

- The record is `TBigDecimal`. The main unit is `BigDecimal`. A separate unit,
  `BigDecimal.Math`, holds the transcendental functions. A program that does
  only arithmetic does not link the function code.
- `Implicit` conversion from `Integer` and `Int64` only. A conversion from
  `Double` is `Explicit`, because a silent `Double` conversion hides binary
  error.
- Mixed `TBigDecimal` / `Integer` arithmetic works through the implicit
  conversion. Each such operation takes the small-value path.
- The README sketch has `Create` as `class function`. The final API keeps
  that form and adds `class function FromString`, `FromUnscaled`, and
  `TryParse`.
- The default record state (all zero) is the value 0 with scale 0. A
  `TBigDecimal` needs no initialization call. The type has no `Clear`
  method, because assignment of zero does the same work.

## 7. Unit layout

Each file stays below 2000 lines.

| Unit                     | Content |
|--------------------------|---------|
| `BigDecimal.Types`       | Enums, `TMathContext`, exception classes, constants (power-of-ten tables) |
| `BigDecimal.Limbs`       | Magnitude kernels: compare, add, sub, shift by powers of ten, single-limb ops, digit count |
| `BigDecimal.Multiply`    | Schoolbook, squaring, Karatsuba, unbalanced split |
| `BigDecimal.Divide`      | Knuth D, single-limb division, Newton reciprocal with block splitting |
| `BigDecimal.Rounding`    | `RoundMagnitude` and the mode logic |
| `BigDecimal.Convert`     | Parse, digit text, exact and correctly rounded `Double` conversion on raw limbs |
| `BigDecimal`             | The `TBigDecimal` record and its operators |
| `BigDecimal.Fixed`       | Fixed-point values with a running error bound; the Ziv interval check |
| `BigDecimal.Math`        | `Sqrt`, `Exp`, `Ln`, `Log10`, `Log`, `Pow`, `Root` |
| `BigDecimal.Constants`   | `Pi`, `E`, `Ln2`, `Ln10` with caches |
| `BigDecimal.Financial`   | Financial helpers |
| `BigDecimal.Combinatorics` | Factorial, double factorial, primorial, falling and rising factorial, binomial, multinomial, Catalan, prime sieve |
| `BigDecimal.Trig`        | `Sin`, `Cos`, `Tan` |
| `BigDecimal.Gamma`       | `Gamma`, `LnGamma`, non-integer factorial, Bernoulli number cache |

Each unit starts with the pasdoc front matter block that `AGENTS.md`
requires.

## 8. Testing and verification

- **External reference material.** Section 8.1 lists the sources. Tests
  read them as input data.
- **Oracle vectors.** A Python script (`tools/genvectors.py`, run with the
  environment that `tools/setup-venv.sh` creates) uses `decimal` (exact
  arithmetic and seven of the eight rounding modes; `ROUND_05UP` is not used
  and `rmUnnecessary` has no `decimal` counterpart) and `mpmath`
  (transcendental functions at 300 digits) to write test vector files.
  For the transcendental functions the 300-digit value rounds to `p` digits in
  each of the seven modes. The vector files are generated and are not stored. The unit tests read these files.
  Vectors cover zero, one, powers of ten, limb boundaries (`10^9 ± 1`),
  carry chains (`999...9`), negative scales, and random operands from 1 to
  5000 digits.
- **Properties.** Tests assert `(a + b) − b = a`, `(a × b) / b = a`,
  `DivRem` identity `a = q·b + r`, `Sqrt(x²) = |x|`, and
  `Exp(Ln(x)) ≈ x` within the stated error. They also assert that every
  multiplication algorithm agrees with schoolbook on random operands.
- **Rounding table.** A table drives all eight modes through the values
  `±5.5, ±2.5, ±1.6, ±1.1, ±1.0` (the table in the Java documentation).
- **Fuzzing.** The vector generator uses a fixed seed and writes thousands of
  random cases for each operation. The kernel tests run random operands of 1 to
  220 limbs, including operands made of all-nines limbs.
- **Benchmarks.** `bench/BenchAll.lpr` times multiplication and division at 8
  to 2048 limbs, factorial and binomial at several sizes, and each function at
  16 to 1000 digits. It prints the crossover points that set the algorithm
  thresholds. `bench/BenchDivMod.lpr` compares forms of division by 10^9.
- **Isolation.** A test runs every public function under a 5-digit default
  context and requires the result to be identical to the result with no
  default. A heap-traced run (`make heaptest`) reports no unfreed blocks.

### 8.1 External reference material

Each source below was downloaded and inspected on 2026-10-15. The checksums
identify the inspected files.

**General Decimal Arithmetic testcases (`dectest.zip`).**
- Source: <https://speleotrove.com/decimal/dectest.html>. Archive:
  <https://speleotrove.com/decimal/dectest.zip>. The archive is 791,733 bytes.
  SHA-256: `b70a224cd52e82b7a8150aedac5efa2d0cb3941696fd829bdbe674f9f65c3926`.
- Author: Mike Cowlishaw (IBM). Version 2.62 of the files. The files state
  that they are experimental, offered as-is, and not exhaustive. The files
  carry a copyright notice. The repository therefore does not store them. A
  tool downloads the archive and checks the checksum.
- Content: plain-text cases of the form
  `id operation operand... -> result [conditions]`, with the directives
  `precision`, `rounding`, `maxExponent` and `minexponent`. The archive holds
  about 140 files. The files that match this library are `add`, `subtract`,
  `multiply`, `divide`, `divideint`, `remainder`, `compare`, `max`, `min`,
  `abs`, `minus`, `plus`, `quantize`, `reduce`, `rescale`, `tointegral`,
  `rounding`, `squareroot`, `power`, `exp`, `ln` and `log10`. The `ln`, `exp`,
  `log10`, `squareroot` and `power` files hold 610, 673, 550, 3833 and 1623
  lines. The `exp` file states that its results are correctly rounded
  (at most 0.5 ulp). The `exp`, `ln` and `log10` files set only the rounding
  mode `half_even`, so other modes for these functions are covered by the
  `mpmath` vectors. The `power` file notes a few cases that are not within
  0.5 ulp.
- Scope limits. The cases include NaN, infinity, subnormal values, exponent
  range limits and signal flags. `TBigDecimal` has none of these (see the
  README non-goals). The test runner skips a case when any operand or result
  is NaN or infinity, when an exponent limit applies, or when the case uses
  an operation that the library does not have. The runner counts skipped
  cases per file and prints the count, so a silent loss of coverage is
  visible. The directive `precision` maps to `TMathContext.Precision`. The
  directive `rounding` maps to `TRoundingMode`. The `half_even`, `half_up`,
  `half_down`, `up`, `down`, `ceiling` and `floor` names map directly. The
  mode `05up` has no counterpart and the runner skips it.

- Expected failures. A checked-in file, `tests/dectest-expected-failures.txt`,
  lists case IDs where the library result is known to differ from the
  reference. Each line holds the case ID and a reason (for example, the case
  is not within 0.5 ulp, as `power.decTest` notes). The runner reports these
  cases as known failures. The run fails when a listed case passes (the entry
  is then stale) and when any unlisted case fails. Each entry needs a review,
  so a deviation never hides.

**Digits of pi.**
- Source 1: <https://www.angio.net/pi/digits/10000.txt>. The file holds the
  first 10,000 decimal places of pi. SHA-256:
  `1f08958df70c30bbf3f7205ad5f9b2b9430e3378b4e4e6300063bd9fbd83d6e3`.
- Source 2: OEIS sequence A000796, b-file
  <https://oeis.org/A000796/b000796.txt>. The file holds 20,000 digits as
  `index digit` lines. SHA-256:
  `f8772370d624d403f056e3e3d4aadb15fec135d5075b5506053eb86460f4e20b`.
- Validation. The first 10,000 digits of both sources were compared and are
  identical. The tests accept a pi value only when both sources agree. They
  use the 20,000-digit file for precision above 10,000 digits.
- Use: expected values for `Pi(Context)` at every precision up to 20,000
  digits and for every rounding mode.

**Java `BigDecimal` specification.**
- Source: <https://www2.seas.gwu.edu/~rhyspj/docs/api/java/math/BigDecimal.html>
  (a copy of the Java API documentation).
- Use: the rules for `precision`, `scale`, preferred scale of `divide`,
  `toString` and the eight rounding modes. The rounding table test takes its
  inputs and expected values from the rounding mode table in the
  `RoundingMode` documentation.

**OEIS b-files for combinatorial values.** Each file lists `index value`
pairs. Each file was downloaded and checked against Python `math` (exact
integer arithmetic) on 2026-10-15. All entries matched.

| Sequence | File | Range | SHA-256 |
|----------|------|-------|---------|
| A000142 factorials | <https://oeis.org/A000142/b000142.txt> | n = 0..100 | `9d872b96c262cc2fe3f854e1b06d6624d7b8fe2f5666ce37f98acb7f523289c3` |
| A001147 double factorials (2n−1)!! | <https://oeis.org/A001147/b001147.txt> | n = 0..400 | `3bdf1d3bf0bb5046308f5f496552d9d8f21280bb354d480c21f625e7925ab222` |
| A000984 central binomial C(2n,n) | <https://oeis.org/A000984/b000984.txt> | n = 0..1500 | `4f911fe749c2ceb35425d1dbdfd12a6c0ac68f24fddea021339dddcf54bb09d7` |
| A000108 Catalan numbers | <https://oeis.org/A000108/b000108.txt> | n = 0..1000 | `5623739c73b08deddc3cc2e9c670e231a56194eecabb88199a1cf4f0a0989e18` |
| A000040 primes | <https://oeis.org/A000040/b000040.txt> | first 10,000 primes (to 104,729) | `ef3beecd3bca4a02ca5053e5a3afc3e0d69e43b49b9aaa91073fc4fb9e4d50de` |

The prime file checks the sieve. The other files check `Factorial`,
`DoubleFactorial`, `CentralBinomial` and `Catalan`. These files reach only
n = 1500 at most, so tests for larger arguments use the oracle programs and
the identities below.

Identity tests cover the prime factorization paths against the other paths:
`Factorial` by prime factorization equals `Factorial` by binary splitting,
`Binomial` by Kummer's form equals the multiplicative form and the
recursive form, `C(n,k) = C(n,n−k)`, Pascal's rule
`C(n,k) = C(n−1,k−1) + C(n−1,k)`, the row sum `Σ C(n,k) = 2^n`, and
`Gamma(n) = (n−1)!` at integer arguments.

**Oracle programs.** Python `decimal` and `mpmath` generate additional
vectors (see above). They are computed values, not fixed reference data.
The vectors for `Exp`, `Ln`, `Log10`, `Pow`, `Sqrt` and `Pi` are
cross-checked against the dectest files and the pi digits where the cases
overlap.

## 9. Decisions

1. With no thread-local default context, `/` is exact and can raise. This
   matches Java. The thread-local default context (section 4.1) lets a
   program choose rounded arithmetic without changing the operator syntax.
2. `+`, `-` and `*` round under a default context, as in Python `decimal`.
   Java has no such feature, so no Java behavior conflicts.
3. Constants are cached in one shared cache that a lock guards (section 5.6).

## 10. Future directions

- **mpmath cross-check for expected failures.** For each case in the
  expected-failure list, the runner could ignore the dectest result and
  compare the library result with an `mpmath` value computed at 200 digits and
  rounded in the mode of the case. The reference for those cases would then
  be independent of the dectest files, and a library result that is correct
  but differs from a dectest result outside 0.5 ulp would pass with evidence.
  The cost is a second oracle to maintain and a Python dependency at test
  run time, not only at vector generation time.
- **Binary splitting and bit-burst evaluation.** Binary splitting of the
  series for `Pi`, `E` and `Ln` of small primes, the Chudnovsky series for
  `Pi`, and bit-burst evaluation of `Exp` and `Ln` would give O(M(p) log² p)
  at high precision. The library evaluates these series in fixed point at
  O(p²).
- **Faster division.** Division is 1.7 to 4.4 times slower than Python
  `decimal` (`bench/RESULTS.md`). A Burnikel-Ziegler recursion, or a division
  in 10^18 limbs with 128-bit products, would reduce the gap.
- **Reciprocal-root square root.** A Newton iteration for `1/sqrt(x)` needs
  only multiplications and avoids the divisions of the integer iteration.
- **Other targets.** Builds and runs on x86_64, Linux and Windows. The
  `DivMod1e9` form for x86_64 (`mul`) is not enabled.

## 11. Measurements and limits

Measurements are in `bench/RESULTS.md` (Apple Silicon aarch64, FPC
3.2.4-rc2). The main facts:

- **Tests.** The suite has 101 fpcunit tests. It runs the oracle vectors (about
  45,000 cases across 41 files), the dectest files `add`, `subtract`,
  `multiply`, `divide`, `divideint`, `remainder`, `compare`, `max`, `min`,
  `abs`, `minus`, `plus`, `rounding`, `quantize`, `rescale`, `tointegral`,
  `tointegralx`, `reduce`, `squareroot`, `exp`, `ln`, `log10` and `power`, the
  OEIS files, and the pi digit files. About 11,400 dectest cases run and pass.
  Cases with NaN, infinity, exponent limits or negative zero are skipped and
  counted (about 30% of the cases). No dectest case is on the
  expected-failure list.
- **Thresholds.** Karatsuba from 160 limbs, Newton division from 4096 limbs,
  swing factorial from 600, Kummer binomial from k = 13.
- **Small values.** A small-value `+`, `-` or `*` allocates no memory. The
  read of the thread-local default context costs about 3 ns. A default context
  adds no measurable time when the value has no more digits than the
  precision.
- **Python `decimal`.** Ratios of the library time to the Python time (libmpdec
  4.0.1) at 34 to 10,000 digits: multiply 0.6 to 1.6, divide 1.7 to 4.4, `Sqrt`
  0.65 to 5.4, `Exp` 0.04 to 1.7, `Ln` 0.15 to 1.1.
- **Limits.** Constants and the elementary functions cost O(w²) limb operations
  at w digits, so precisions of many thousands of digits are slow
  (`Gamma(7.5)` takes about 1.1 s at 1000 digits). The `Gamma` function takes a
  shift of about `0.4 w` multiplications for a small argument.
- **Platform.** Only aarch64 macOS has built and run the library.
