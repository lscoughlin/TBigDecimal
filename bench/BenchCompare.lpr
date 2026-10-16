{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: benchmark
notes:
  - times the operations that tools/benchpython.py times
---
}
program BenchCompare;
{ Times multiply, divide, Sqrt, Exp and Ln at p significant digits on operands
  built from a fixed digit pattern. tools/benchpython.py times the same
  operations in Python decimal. Run: make benchcompare }
{$mode objfpc}{$H+}
{$coperators on}
uses
  SysUtils, BigDecimal.Types, BigDecimal, BigDecimal.Math;

function Secs: Double;
begin
  Result := Now * 86400.0;
end;

function Digits(P, Seed: Integer): string;
var
  i: Integer;
begin
  SetLength(Result, P);
  for i := 1 to P do
    Result[i] := Chr(Ord('0') + ((i * 7 + Seed * 13 + (i * i) mod 11) mod 10));
  Result[1] := '1';
  Result := Result[1] + '.' + Copy(Result, 2, P - 1);
end;

function PerCall(Reps: Integer; T0: Double): string;
begin
  Result := Format('%12.2f', [(Secs - T0) / Reps * 1e6]);
end;

var
  P, Reps, I, K: Integer;
  X, Y, Z: TBigDecimal;
  C: TMathContext;
  T: Double;
  Sizes: array of Integer;
begin
  Sizes := [34, 100, 300, 1000, 3000, 10000];
  WriteLn('digits    multiply      divide        sqrt         exp          ln   (microseconds)');
  for K := 0 to High(Sizes) do
  begin
    P := Sizes[K];
    C := TMathContext.Make(P, rmHalfEven);
    X := TBigDecimal.Create(Digits(P, 1));
    Y := TBigDecimal.Create(Digits(P, 2));
    Write(P: 6);
    Reps := 20000000 div (P * P div 100 + 1) + 3;
    T := Secs;
    for I := 1 to Reps do Z := X.Multiply(Y, C);
    Write(PerCall(Reps, T));
    T := Secs;
    for I := 1 to Reps do Z := X.Divide(Y, C);
    Write(PerCall(Reps, T));
    Reps := 4000 div (P + 1) + 2;
    T := Secs;
    for I := 1 to Reps do Z := Sqrt(X, C);
    Write(PerCall(Reps, T));
    Reps := 2000 div (P + 1) + 2;
    if P >= 3000 then Reps := 2;
    T := Secs;
    for I := 1 to Reps do Z := Exp(X, C);
    Write(PerCall(Reps, T));
    T := Secs;
    for I := 1 to Reps do Z := Ln(X, C);
    WriteLn(PerCall(Reps, T));
  end;
end.
