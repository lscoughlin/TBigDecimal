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

var
  GX, GY, GZ: TBigDecimal;
  GC: TMathContext;

procedure RunOp(Op, Reps: Integer);
var
  I: Integer;
begin
  case Op of
    0: for I := 1 to Reps do GZ := GX.Multiply(GY, GC);
    1: for I := 1 to Reps do GZ := GX.Divide(GY, GC);
    2: for I := 1 to Reps do GZ := Sqrt(GX, GC);
    3: for I := 1 to Reps do GZ := Exp(GX, GC);
    4: for I := 1 to Reps do GZ := Ln(GX, GC);
  end;
end;

{ Best of five trials of at least 50 ms, in microseconds per call. }
function Measure(Op: Integer): string;
var
  T, Best: Double;
  Trial, Reps: Integer;
begin
  Reps := 1;
  repeat
    T := Secs;
    RunOp(Op, Reps);
    T := Secs - T;
    if T >= 0.05 then Break;
    Reps *= 2;
  until False;
  Best := T / Reps * 1e6;
  for Trial := 2 to 5 do
  begin
    T := Secs;
    RunOp(Op, Reps);
    T := (Secs - T) / Reps * 1e6;
    if T < Best then Best := T;
  end;
  Result := Format('%12.2f', [Best]);
end;

var
  P, K, Op: Integer;
  Sizes: array of Integer;
begin
  Sizes := [34, 100, 300, 1000, 3000, 10000];
  WriteLn('digits    multiply      divide        sqrt         exp          ln   (microseconds)');
  for K := 0 to High(Sizes) do
  begin
    P := Sizes[K];
    GC := TMathContext.Make(P, rmHalfEven);
    GX := TBigDecimal.Create(Digits(P, 1));
    GY := TBigDecimal.Create(Digits(P, 2));
    Write(P: 6);
    for Op := 0 to 4 do
      Write(Measure(Op));
    WriteLn;
  end;
end.
