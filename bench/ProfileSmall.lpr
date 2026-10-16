{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: benchmark, profile
notes:
  - loops over one operation at 34 digits so that a sampling profiler can see it
---
}
program ProfileSmall;
{ Usage: ProfileSmall m|d|a|s|e|l. Loops one operation at 34 digits (m multiply,
  d divide, a add, s Sqrt, e Exp, l Ln). Run: make profile }
{$mode objfpc}{$H+}
uses
  SysUtils, BigDecimal.Types, BigDecimal, BigDecimal.Elementary;

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
  X, Y, Z: TBigDecimal;
  C: TMathContext;
  I, N: Integer;
  Op: string;
begin
  Op := ParamStr(1);
  if Op = '' then Op := 'm';
  C := TMathContext.Make(34, rmHalfEven);
  X := TBigDecimal.Create(Digits(34, 1));
  Y := TBigDecimal.Create(Digits(34, 2));
  N := 30000000;
  case Op[1] of
    'm': for I := 1 to N do Z := X.Multiply(Y, C);
    'd': for I := 1 to N div 2 do Z := X.Divide(Y, C);
    'a': for I := 1 to N do Z := X.Add(Y, C);
    's': for I := 1 to N div 50 do Z := Sqrt(X, C);
    'e': for I := 1 to N div 50 do Z := Exp(X, C);
    'l': for I := 1 to N div 50 do Z := Ln(X, C);
  end;
  WriteLn(Z.Precision);
end.
