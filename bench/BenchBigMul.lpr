{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: benchmark, ntt, large multiplication
notes:
  - times large exact multiplication for 30k to 3M digits
---
}
program BenchBigMul;
{$mode objfpc}{$H+}
{$coperators on}
uses
  SysUtils, BigDecimal.Types, BigDecimal;

function Secs: Double;
begin
  Result := Double(GetTickCount64) / 1000.0;
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

procedure RunMul(Reps: Integer);
var
  I: Integer;
begin
  for I := 1 to Reps do
    GZ := GX.Multiply(GY, Unlimited);
end;

{ Best of three trials, reported in milliseconds. }
function Measure(P: Integer): Double;
var
  T, Best: Double;
  Trial, Reps: Integer;
begin
  Reps := 1;
  repeat
    T := Secs;
    RunMul(Reps);
    T := Secs - T;
    if T >= 0.05 then Break;
    Reps *= 2;
  until False;
  Best := T / Reps * 1000.0;
  for Trial := 2 to 3 do
  begin
    T := Secs;
    RunMul(Reps);
    T := (Secs - T) / Reps * 1000.0;
    if T < Best then Best := T;
  end;
  Result := Best;
end;

var
  P, K: Integer;
  Sizes: array of Integer;
  T: Double;
begin
  Sizes := [30000, 100000, 300000, 1000000, 3000000];
  WriteLn('digits        time (ms)');
  for K := 0 to High(Sizes) do
  begin
    P := Sizes[K];
    GX := TBigDecimal.Create(Digits(P, 1));
    GY := TBigDecimal.Create(Digits(P, 2));
    T := Measure(P);
    WriteLn(Format('%8d %12.2f ms', [P, T]));
  end;
end.
