{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: benchmark, comparison
notes:
  - times add, multiply and divide of TBigDecimal against TBcd of the FPC RTL unit FmtBCD
---
}
program BenchBcd;
{ TBcd holds at most 64 digits, has no square root, exponential or logarithm,
  and BcdDivide raises ERangeError for some operands in FPC 3.2.4, so only add,
  multiply and divide are compared. The multiply operands have at most 32 digits
  so that the exact product fits in 64 digits. TBcd divides to 63 digits, and
  TBigDecimal divides to a precision of 63 digits. Run: make benchbcd }
{$mode objfpc}{$H+}
{$coperators on}
uses
  SysUtils, FmtBCD, BigDecimal.Types, BigDecimal;

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
  GBX, GBY, GBZ: TBcd;
  GC: TMathContext;

procedure RunOurs(Op, Reps: Integer);
var
  I: Integer;
begin
  case Op of
    0: for I := 1 to Reps do GZ := GX + GY;
    1: for I := 1 to Reps do GZ := GX * GY;
    2: for I := 1 to Reps do GZ := GX.Divide(GY, GC);
  end;
end;

procedure RunBcd(Op, Reps: Integer);
var
  I: Integer;
begin
  case Op of
    0: for I := 1 to Reps do BcdAdd(GBX, GBY, GBZ);
    1: for I := 1 to Reps do BcdMultiply(GBX, GBY, GBZ);
    2: for I := 1 to Reps do BcdDivide(GBX, GBY, GBZ);
  end;
end;

{ Best of five trials of at least 50 ms, in microseconds per call. }
function Measure(Bcd: Boolean; Op: Integer): Double;
var
  T, Best: Double;
  Trial, Reps: Integer;

  procedure Run(R: Integer);
  begin
    if Bcd then RunBcd(Op, R) else RunOurs(Op, R);
  end;

begin
  Reps := 1;
  repeat
    T := Secs;
    Run(Reps);
    T := Secs - T;
    if T >= 0.05 then Break;
    Reps *= 2;
  until False;
  Best := T / Reps * 1e6;
  for Trial := 2 to 5 do
  begin
    T := Secs;
    Run(Reps);
    T := (Secs - T) / Reps * 1e6;
    if T < Best then Best := T;
  end;
  Result := Best;
end;

const
  OpNames: array[0..2] of string = ('add', 'multiply', 'divide');
  Sizes: array[0..2] of Integer = (16, 32, 62);

var
  K, Op, P: Integer;
  Ours, Theirs: Double;
  Works: Boolean;
begin
  WriteLn('digits  operation   TBigDecimal(us)   TBcd(us)   ratio (TBigDecimal / TBcd)');
  for K := 0 to High(Sizes) do
  begin
    P := Sizes[K];
    GX := TBigDecimal.Create(Digits(P, 1));
    GY := TBigDecimal.Create(Digits(P, 2));
    GBX := StrToBcd(Digits(P, 1));
    GBY := StrToBcd(Digits(P, 2));
    GC := TMathContext.Make(63, rmHalfEven);
    for Op := 0 to 2 do
    begin
      // multiply needs the exact product in 64 digits
      if (Op = 1) and (P > 32) then Continue;
      Works := True;
      try
        RunBcd(Op, 1);
      except
        on E: Exception do
        begin
          Works := False;
          WriteLn(P: 6, '  ', OpNames[Op]: 9, '   TBcd raises ', E.ClassName);
        end;
      end;
      Ours := Measure(False, Op);
      if not Works then
      begin
        WriteLn(P: 6, '  ', OpNames[Op]: 9, Ours: 18: 3, '   not comparable');
        Continue;
      end;
      Theirs := Measure(True, Op);
      WriteLn(P: 6, '  ', OpNames[Op]: 9, Ours: 18: 3, Theirs: 12: 3, (Ours / Theirs): 8: 2);
    end;
  end;
end.
