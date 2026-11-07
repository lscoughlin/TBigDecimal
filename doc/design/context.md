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
guard cap of [section 5.1](functions/precision.md) was reached) and `EBigDecimalDomain` (for
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
- With no default context, `+` and `-` are exact. `*` and `/` round to 34
  significant digits, half-even, unless the global `NoContextFallback128`
  is off (its default is on). With the flag off, `*` is exact and `/` is
  exact and can raise `EBigDecimalNonTerminating`. A transcendental
  function without a context argument raises `EBigDecimalNoContext`,
  because the result needs a precision.
- Methods whose meaning does not involve a precision ignore the default:
  comparison, `Abs`, `Negate`, `SetScale` (it has explicit scale and mode),
  `ToString`, parsing and conversion. `Create` never rounds.
- Library internals never read the default. The code in `BigDecimal.Elementary`
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
  The guard also marks the region as exact, so the fallback of the rule
  above does not apply inside a library function.
- Only unmanaged types live in `threadvar` variables. A probe under `heaptrc`
  showed that a `threadvar` that holds a dynamic array leaks its array when
  the thread ends. `TMathContext` has no managed field, so the default
  context does not leak.
- Cost. Each rounding operator reads `GHasDefaultContext` once. A `threadvar`
  read is a thread-pointer-relative load on current FPC targets, but the cost
  is not assumed. A benchmark measures it. The small-value path
  tests the flag only after an exact result is ready, and skips rounding
  when the result precision is already within the limit.
