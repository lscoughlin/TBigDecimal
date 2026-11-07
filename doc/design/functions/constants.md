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
last place and applies the Ziv check of [section 5.1](precision.md). If the interval rounds
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
