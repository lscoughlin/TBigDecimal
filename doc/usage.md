# Using TBigDecimal

This document shows the common ways to use `TBigDecimal`. The examples are
fragments. Each unit named in a `uses` clause is in `src/`.

## Values and text

A `TBigDecimal` is a record. It needs no `Create` call and no `Free` call. The
default value is 0 with scale 0.

```pascal
uses BigDecimal, BigDecimal.Types;

var
  a, b: TBigDecimal;
begin
  a := TBigDecimal.Create('123.4500');   // unscaled 1234500, scale 4
  b := 7;                                // implicit from Integer and Int64
  WriteLn((a + b).ToString);             // 130.4500
  WriteLn(a.StripTrailingZeros.ToString);// 123.45
  WriteLn(a = TBigDecimal.Create('123.45')); // TRUE: equal by value
  WriteLn(a.Identical(TBigDecimal.Create('123.45'))); // FALSE: scale differs
end;
```

`+`, `-` and `*` are exact. The scale of a sum is the larger scale, and the
scale of a product is the sum of the scales.

## Division and rounding

The `/` operator is exact. It raises `EBigDecimalNonTerminating` when the
quotient has no finite decimal expansion. A division that rounds names its
rounding:

```pascal
a := TBigDecimal.Create(1).Divide(TBigDecimal.Create(3), Decimal128);  // 34 digits
a := TBigDecimal.Create(10).Divide(TBigDecimal.Create(3), 2, rmHalfUp); // 3.33
a := TBigDecimal.Create('2.5').SetScale(0, rmHalfEven);                 // 2
a := TBigDecimal.Create('1234.5678').Round(TMathContext.Make(6, rmDown)); // 1234.56
```

`TMathContext` holds a precision in significant digits (0 means exact) and a
rounding mode. The predefined contexts are `Decimal32`, `Decimal64`,
`Decimal128` and `Unlimited`.

## A default context for a thread

A thread can set a default context. Operators and the context-free forms of
the functions then round to it:

```pascal
var
  Scope: TMathContextScope;
begin
  Scope.Enter(Decimal64);
  a := TBigDecimal.Create(1) / TBigDecimal.Create(3);   // 0.3333333333333333
  b := Sqrt(TBigDecimal.Create(2));                     // 1.414213562373095
end;                                                    // the previous default returns
```

An explicit context argument overrides the default. A new thread starts with no
default. Library functions ignore the default while they run, so a function
with a context argument gives the same result with and without a default.

## Functions

```pascal
uses BigDecimal.Math, BigDecimal.Trig, BigDecimal.Constants, BigDecimal.Gamma;

c := TMathContext.Make(50, rmHalfEven);
Sqrt(TBigDecimal.Create(2), c);
Exp(TBigDecimal.Create(1), c);
Ln(TBigDecimal.Create(10), c);
Log10(TBigDecimal.Create('0.001'), c);          // -3 exactly
Pow(TBigDecimal.Create('1.05'), 10, c);         // exact, rounded once
Pow(TBigDecimal.Create(2), TBigDecimal.Create('0.5'), c);
Sin(TBigDecimal.Create(1), c);
BigPi(c);
Gamma(TBigDecimal.Create('0.5'), c);            // sqrt(pi)
```

Each of these results is correctly rounded in the mode of the context. A result
that is exactly representable is returned exactly (for example `Sqrt(4)` is
`2`).

## Combinatorics

```pascal
uses BigDecimal.Combinatorics;

Factorial(100);              // exact integer
Binomial(200, 100);
Catalan(50);
Binomial(TBigDecimal.Create('0.5'), 3, Decimal64);  // generalized, rounded
```

These functions return exact integers and refuse a result with more than
`MaxExactDigits` (10,000,000) digits by raising `EBigDecimalOverflow`.

## Financial helpers

```pascal
uses BigDecimal.Financial;

FutureValue(TBigDecimal.Create(1000), TBigDecimal.Create('0.05'), TBigDecimal.Create(10), Decimal64);
AnnuityFactor(TBigDecimal.Create('0.05'), TBigDecimal.Create(10), Decimal64);
```

## Exceptions

All library exceptions descend from `EBigDecimal`:

| Exception | Raised when |
|-----------|-------------|
| `EBigDecimalDivByZero` | the divisor is zero |
| `EBigDecimalNonTerminating` | an exact quotient has no finite expansion |
| `EBigDecimalRounding` | `rmUnnecessary` meets a value that needs rounding |
| `EBigDecimalOverflow` | a scale or an exact result is out of range |
| `EBigDecimalParse` | text is not a decimal number |
| `EBigDecimalNoContext` | a function needs a precision and no default exists |
| `EBigDecimalPrecision` | a result could not be rounded within the working-precision limit |
| `EBigDecimalDomain` | an argument is outside the domain of the function |

## Speed

Values that fit in 64 bits use `Int64` arithmetic and allocate nothing. Larger
values use base 10^9 limbs. Multiplication uses Karatsuba above 160 limbs.
Division uses a Newton reciprocal above 4096 limbs. The elementary functions
cost O(w²) limb operations at w digits, so a precision of many thousands of
digits is slow (see `bench/RESULTS.md`).
