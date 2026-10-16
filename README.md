# TBigDecimal

TBigDecimal is an arbitrary-precision decimal math library for Object Pascal.
It targets Free Pascal (FPC). It exposes the `TBigDecimal` type. The current
version is 0.2.0 (`BigDecimalVersion` in unit `BigDecimal.Types`).

`TBigDecimal` is an advanced record. It follows the Java `BigDecimal` type
in its model and its names. A value is an unscaled integer of any size and a
32-bit scale. The value of the number is `unscaled × 10^(-scale)`.

## Goals

- Exact decimal arithmetic. Addition, subtraction and multiplication never
  lose digits.
- Value semantics. A `TBigDecimal` behaves like an `Integer`. It needs no
  `Free` call and no `try..finally` block.
- Full control of rounding. The library has a rounding mode enum and a
  precision context, as Java has.
- Financial functions: `Ln`, `Log10`, `Log`, `Exp`, `Pow` and `Sqrt`, with
  results at a precision the caller chooses.
- High speed. The library uses the methods that FPC supports well: base 10^9
  limbs, 64-bit intermediate products, constant divisors, and algorithms that
  change with operand size.

## Non-goals

- Binary floating point. `Double` and MPFR serve that need.
- Decimal NaN, infinity and negative zero. `TBigDecimal` has finite values
  only. An invalid operation raises an exception.
- Thread-shared mutable state. A `TBigDecimal` value is immutable. Any thread
  can read a value that no thread changes.

## Requirements

- Free Pascal 3.2.2 or newer. The development compiler is 3.2.4 (release candidate 2).
- Tested: aarch64 on macOS with FPC 3.2.4-rc2. The code uses no platform-specific
  feature except one assembler routine on aarch64 (`umulh`), with a portable
  fallback for other targets. x86_64, Linux and Windows are untested.
- Runtime dependencies: `SysUtils` and `Math` only.
- Test dependency: `fpcunit`. The test vector generator needs Python 3 with
  `mpmath`.

## Type model

| Part       | Meaning                                                   |
|------------|-----------------------------------------------------------|
| Sign       | -1, 0 or +1                                               |
| Magnitude  | Unsigned integer in base 10^9 limbs, least significant first |
| Scale      | Signed 32-bit integer. A positive scale counts digits right of the decimal point. |
| Precision  | Count of decimal digits in the unscaled value. Derived, not stored. |

Equal numbers can have different scales. `1.0` and `1.00` compare equal with
`CompareTo` and `=`. They are different under `Hash` and `Identical`. This
matches Java `compareTo` and `equals`.

## Rounding

`TRoundingMode` has the eight Java modes:

| Mode           | Behavior                                         |
|----------------|--------------------------------------------------|
| `rmUp`         | Away from zero                                   |
| `rmDown`       | Toward zero                                      |
| `rmCeiling`    | Toward positive infinity                         |
| `rmFloor`      | Toward negative infinity                         |
| `rmHalfUp`     | Nearest. A tie goes away from zero.              |
| `rmHalfDown`   | Nearest. A tie goes toward zero.                 |
| `rmHalfEven`   | Nearest. A tie goes to the even neighbor (banker's rounding). |
| `rmUnnecessary`| Asserts that no rounding is needed. Else it raises `EBigDecimalRounding`. |

`TMathContext` is a record with a `Precision` (significant digits, 0 means
exact) and a `RoundingMode`. Predefined contexts: `Decimal32`, `Decimal64`,
`Decimal128` and `Unlimited`.

Each thread can set a default `TMathContext` (`TMathContext.SetDefault`, or
the scoped `TMathContextScope.Enter`). When a default exists, operators and
context-free function overloads round to it. An explicit context argument
overrides it. A new thread starts with no default. With no default, `+`, `-`
and `*` are exact, and `/` is exact or raises.

## API summary

- Creation: `Create(Int64)`, `Create(Double)` (the shortest text that round-trips),
  `Create(string)`, `Create(Unscaled, Scale)`, `FromString`, `FromUInt64`,
  `FromDouble`, `FromDoubleExact` (the exact binary expansion), `TryParse`,
  `Zero`, `One`, `Ten`. Implicit conversion from `Integer` and `Int64`.
- Arithmetic: `+ - * /`, unary minus, `Abs`, `Negate`, `Plus`, `Square`,
  `Add`, `Subtract` and `Multiply` with a context, `Remainder`,
  `DivideToIntegralValue`, `DivRem`.
- Division: `Divide(B)` is exact and raises when the quotient does not
  end. `Divide(B, Scale, Mode)` and `Divide(B, Context)` round.
- Scale and rounding: `SetScale`, `Round`, `StripTrailingZeros`,
  `MovePointLeft`, `MovePointRight`, `ScaleByPowerOfTen`, `UnscaledValue`.
- Comparison: `= <> < > <= >=`, `CompareTo`, `Min`, `Max`, `Hash`, `Identical`,
  `Sign`, `IsZero`, `IsInteger`.
- Conversion: `ToString`, `ToPlainString`, `ToEngineeringString`, `ToInt64`
  (truncates, raises on overflow), `ToDouble` (correctly rounded), explicit
  casts to `Double` and `string`.
- Default context: `TMathContext.SetDefault`, `ClearDefault`, `Default`,
  `HasDefault`, and `TMathContextScope`.
- Functions (unit `BigDecimal.Elementary`): `Sqrt`, `Root`, `Exp`, `Ln`, `Log10`,
  `Log`, `Pow` (integer and decimal exponent), `PowExact`. Unit
  `BigDecimal.Trig`: `Sin`, `Cos`, `Tan`. Unit `BigDecimal.Constants`:
  `BigPi`, `BigE`, `BigLn2`, `BigLn10`. Every function has a form with a
  context argument and a form that reads the default context.
- Combinatorics (unit `BigDecimal.Combinatorics`): `Factorial`,
  `DoubleFactorial`, `Primorial`, `FallingFactorial`, `RisingFactorial`,
  `Permutations`, `Binomial` (integer and decimal first argument),
  `CentralBinomial`, `Multinomial`, `Catalan`, `PrimesUpTo`. These return
  exact integers. Unit `BigDecimal.Gamma`: `Gamma`, `LnGamma`, non-integer
  `Factorial`, `LnFactorial`.
- Financial helpers (unit `BigDecimal.Financial`): `CompoundFactor`,
  `PresentValue`, `FutureValue`, `AnnuityFactor`, `AnnualizedRate`.

## Build and test

```
make test     # downloads reference files, builds, runs the fpcunit suites
make bench    # builds and runs the benchmark program
make benchsmall    # small-value allocations and default-context cost
make benchcompare  # timings next to Python decimal
sh tools/setup-venv.sh && tools/.venv/bin/python tools/genvectors.py 3000
```

Lazarus files are in `lazarus/`. The package `TBigDecimal.lpk` (version 0.2.0)
holds the library units. The projects `RunTests.lpi` (modes Release and Debug),
`BenchAll.lpi` and `BenchCompare.lpi` require the package. `lazbuild` builds
them, for example `lazbuild lazarus/TBigDecimal.lpk` and
`lazbuild lazarus/RunTests.lpi`. The binaries go to `bin/`, and the test
binary runs from the project root, where `tests/refs` and `tests/vectors` are.

`make test` needs the vector files that `tools/genvectors.py` writes. The
generator needs Python 3 with `mpmath`.

## Documentation

The design is in [`doc/design.md`](doc/design.md). Usage examples are in
[`doc/usage.md`](doc/usage.md). Benchmark results are in
[`bench/RESULTS.md`](bench/RESULTS.md). Faults of FPC 3.2.4 management operators
that limit the record layout are in
[`doc/management-operators.md`](doc/management-operators.md).

## Original API sketch

The sketch below is the starting point. The final field types differ, and the final
type has no `Clear` method. The design document describes the final type.

```pascal
unit BigDecimalMath;

interface

uses
  SysUtils;

type
  TBigDecimal = record
  private
    FSign: Integer;          // 1 for positive, -1 for negative (0 for zero)
    FChunks: array of Int64; // Dynamic array of base-10^9 chunks
    FScale: Integer;         // Number of decimal places represented
  public
    // Constructors & Factory Methods
    class function Create(Value: Int64): TBigDecimal; overload;
    class function Create(Value: Double): TBigDecimal; overload;
    class function Create(const Value: string): TBigDecimal; overload;

    // Arithmetic Operator Overloads
    class operator Add(const A, B: TBigDecimal): TBigDecimal;
    class operator Subtract(const A, B: TBigDecimal): TBigDecimal;
    class operator Multiply(const A, B: TBigDecimal): TBigDecimal;
    class operator Divide(const A, B: TBigDecimal): TBigDecimal;
    class operator Negative(const Value: TBigDecimal): TBigDecimal; // Unary minus (-)

    // Comparison Operator Overloads
    class operator Equal(const A, B: TBigDecimal): Boolean;
    class operator NotEqual(const A, B: TBigDecimal): Boolean;
    class operator GreaterThan(const A, B: TBigDecimal): Boolean;
    class operator LessThan(const A, B: TBigDecimal): Boolean;
    class operator GreaterThanOrEqual(const A, B: TBigDecimal): Boolean;
    class operator LessThanOrEqual(const A, B: TBigDecimal): Boolean;

    // Implicit & Explicit Casting Operators
    class operator Implicit(Value: Int64): TBigDecimal;
    class operator Implicit(Value: Integer): TBigDecimal;
    class operator Explicit(const Value: TBigDecimal): Double;
    class operator Explicit(const Value: TBigDecimal): string;

    // Utility Methods
    function ToString: string;
    procedure Clear;
  end;

implementation

{ Implementation goes here }

end.
```

## License

LGPL-2.1-only WITH Independent-modules-exception.

Full name: GNU Lesser General Public License, version 2.1 only, with the
Independent Modules Exception. Copyright 2026 Liam Seamus Coughlin.
