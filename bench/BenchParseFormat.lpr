{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: benchmark, parse, format
notes:
  - times parsing and formatting at five sizes and five shapes
---
}
program BenchParseFormat;
{ Times Create(string), TryParse, ToString, ToPlainString,
  ToEngineeringString, ToDouble, FromDouble and FromDoubleExact at
  16/34/100/1000/10000 digits for plain, scientific, small-scale,
  large-scale and zero shapes. Best of seven trials. Operands are built
  once before the timed loops. Run: make benchparse }
{$mode objfpc}{$H+}
{$coperators on}
uses
  SysUtils, BigDecimal.Types, BigDecimal;

function Secs: Double;
begin
  Result := Double(GetTickCount64) / 1000.0;
end;

var
  GSink: Int64 = 0;
  GLastMedian, GLastSpread: Double;
  GStr: string;
  GVal: TBigDecimal;
  GDbl: Double;
  GDblIn: Double;
  GOk: Boolean;

procedure SortD(var A: array of Double);
var
  i, j: Integer;
  t: Double;
begin
  for i := 1 to High(A) do
  begin
    t := A[i]; j := i - 1;
    while (j >= 0) and (A[j] > t) do begin A[j + 1] := A[j]; Dec(j); end;
    A[j + 1] := t;
  end;
end;

function TimeIt(Reps: Integer; const P: TProcedure): Double;
var
  t0: Double;
  i, trial: Integer;
  samples: array[0..6] of Double;
begin
  for trial := 0 to 6 do
  begin
    t0 := Secs;
    for i := 1 to Reps do P();
    samples[trial] := (Secs - t0) / Reps * 1e6;
  end;
  SortD(samples);
  Result := samples[0];
  GLastMedian := samples[3];
  if samples[3] > 0 then GLastSpread := (samples[5] - samples[1]) / samples[3] * 100 else GLastSpread := 0;
end;

function Measure(const P: TProcedure): Double;
var
  reps, i: Integer;
  t0: Double;
begin
  reps := 1;
  while True do
  begin
    t0 := Secs;
    for i := 1 to reps do P();
    if (Secs - t0 >= 0.03) or (reps > 50000000) then Break;
    reps := reps * 2;
  end;
  Result := TimeIt(reps, P);
end;

procedure DoCreate; begin GVal := TBigDecimal.Create(GStr); GSink := GSink + GVal.Precision + GVal.Scale; end;
procedure DoTryParse; begin GOk := TBigDecimal.TryParse(GStr, GVal); GSink := GSink + GVal.Precision + GVal.Scale + Ord(GOk); end;
procedure DoToString; begin GStr := GVal.ToString; GSink := GSink + Length(GStr); end;
procedure DoToPlain; begin GStr := GVal.ToPlainString; GSink := GSink + Length(GStr); end;
procedure DoToEng; begin GStr := GVal.ToEngineeringString; GSink := GSink + Length(GStr); end;
procedure DoToDouble; begin GDbl := GVal.ToDouble; if (GDbl < 1e15) and (GDbl > -1e15) then GSink := GSink + Int64(Trunc(Abs(GDbl) * 1000)) mod 1000003 else GSink := GSink + 7; end;
procedure DoFromDouble; begin GVal := TBigDecimal.FromDouble(GDblIn); GSink := GSink + GVal.Precision + GVal.Scale; end;
procedure DoFromDoubleExact; begin GVal := TBigDecimal.FromDoubleExact(GDblIn); GSink := GSink + GVal.Precision + GVal.Scale; end;

function DigitsStr(P: Integer): string;
var
  i: Integer;
begin
  SetLength(Result, P);
  for i := 1 to P do Result[i] := Chr(Ord('0') + ((i * 7 + 3 + (i * i) mod 11) mod 10));
  Result[1] := '1';
end;

function ShapeStr(Size, Shape: Integer): string;
var
  d: string;
begin
  d := DigitsStr(Size);
  case Shape of
    0: Result := d;
    1: Result := d[1] + '.' + Copy(d, 2, Size - 1) + 'E+42';
    2: Result := '0.000' + d;
    3: Result := d[1] + '.' + Copy(d, 2, Size - 1) + 'E+10000';
  else
    Result := '0.' + StringOfChar('0', Size);
  end;
end;

const
  Sizes: array[0..4] of Integer = (16, 34, 100, 1000, 10000);
  ShapeNames: array[0..4] of string = ('plain', 'scientific', 'small-scale', 'large-scale', 'zero');
  OpNames: array[0..7] of string = ('Create(string)', 'TryParse', 'ToString', 'ToPlainString',
    'ToEngineeringString', 'ToDouble', 'FromDouble', 'FromDoubleExact');

var
  si, sh, op: Integer;
  input, savedInput: string;
  val: TBigDecimal;
  t: Double;
  ops: array[0..7] of TProcedure;

begin
  ops[0] := @DoCreate; ops[1] := @DoTryParse; ops[2] := @DoToString;
  ops[3] := @DoToPlain; ops[4] := @DoToEng; ops[5] := @DoToDouble;
  ops[6] := @DoFromDouble; ops[7] := @DoFromDoubleExact;
  WriteLn('operation digits shape us/call (best of 7, min / median / spread)');
  GDblIn := 1234567.89012345;
  for si := 0 to High(Sizes) do
    for sh := 0 to 4 do
    begin
      input := ShapeStr(Sizes[si], sh);
      savedInput := input;
      val := TBigDecimal.Create(input);
      for op := 0 to 7 do
      begin
        GVal := val; GStr := savedInput; GDbl := 0; GOk := False;
        t := Measure(ops[op]);
        WriteLn(Format('%-20s %6d %-12s %10.3f us/call median %10.3f spread %5.1f %%',
          [OpNames[op], Sizes[si], ShapeNames[sh], t, GLastMedian, GLastSpread]));
        // restore inputs that output ops overwrote
        GStr := savedInput; GVal := val;
      end;
    end;
  WriteLn('sink: ', GSink);
end.
