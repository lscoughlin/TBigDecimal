{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: benchmark, financial
notes:
  - times the Excel-compatible financial functions at 16 and 34 digits
---
}
program BenchFinancial;
{ Times PaymentXL, PresentValueXL, FutureValueXL, PeriodCountXL,
  InterestPaymentXL, PrincipalPaymentXL, PeriodicRateXL, EffectiveRateXL
  and NominalRateXL at precisions 16 and 34 for 12, 48 and 360 periods,
  plus one 360-call PrincipalPaymentXL schedule row for each precision.
  Best of seven trials. Operands are built once before the timed loops.
  Run: make benchfinancial }
{$mode objfpc}{$H+}
{$coperators on}
uses
  SysUtils, BigDecimal.Types, BigDecimal, BigDecimal.Financial;

function Secs: Double;
begin
  Result := Double(GetTickCount64) / 1000.0;
end;

var
  GSink: Int64 = 0;
  GLastMedian, GLastSpread: Double;
  GRate, GPv, GPmt, GNom, GEff, GOut: TBigDecimal;
  GPer, GNper: Int64;
  GC: TMathContext;

procedure SinkAdd(const X: TBigDecimal);
begin
  GSink := GSink + X.Precision + (X.Precision - X.Scale - 1);
end;

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
    if (Secs - t0 >= 0.02) or (reps > 50000000) then Break;
    reps := reps * 2;
  end;
  Result := TimeIt(reps, P);
end;

procedure DoPayment; begin GOut := PaymentXL(GRate, GNper, GPv, GC); SinkAdd(GOut); end;
procedure DoPV; begin GOut := PresentValueXL(GRate, GNper, GPmt, GC); SinkAdd(GOut); end;
procedure DoFV; begin GOut := FutureValueXL(GRate, GNper, GPmt, GC); SinkAdd(GOut); end;
procedure DoNPer; begin GOut := PeriodCountXL(GRate, GPmt, GPv, GC); SinkAdd(GOut); end;
procedure DoIPmt; begin GOut := InterestPaymentXL(GRate, GPer, GNper, GPv, GC); SinkAdd(GOut); end;
procedure DoPPmt; begin GOut := PrincipalPaymentXL(GRate, GPer, GNper, GPv, GC); SinkAdd(GOut); end;
procedure DoRate; begin GOut := PeriodicRateXL(GNper, GPmt, GPv, GC); SinkAdd(GOut); end;
procedure DoEffect; begin GOut := EffectiveRateXL(GNom, GNper, GC); SinkAdd(GOut); end;
procedure DoNominal; begin GOut := NominalRateXL(GEff, GNper, GC); SinkAdd(GOut); end;
procedure DoSchedule;
var
  per: Int64;
begin
  for per := 1 to 360 do
  begin
    GOut := PrincipalPaymentXL(GRate, per, 360, GPv, GC);
    SinkAdd(GOut);
  end;
end;

const
  Precisions: array[0..1] of Integer = (16, 34);
  Periods: array[0..2] of Int64 = (12, 48, 360);
  OpNames: array[0..8] of string = ('PaymentXL', 'PresentValueXL', 'FutureValueXL',
    'PeriodCountXL', 'InterestPaymentXL', 'PrincipalPaymentXL', 'PeriodicRateXL',
    'EffectiveRateXL', 'NominalRateXL');

var
  pi, ni, op: Integer;
  t: Double;
  ops: array[0..8] of TProcedure;

begin
  ops[0] := @DoPayment; ops[1] := @DoPV; ops[2] := @DoFV; ops[3] := @DoNPer;
  ops[4] := @DoIPmt; ops[5] := @DoPPmt; ops[6] := @DoRate; ops[7] := @DoEffect;
  ops[8] := @DoNominal;
  WriteLn('operation digits periods us/call (best of 7, min / median / spread)');
  GRate := TBigDecimal.Create('0.005');
  GPv := TBigDecimal.Create('10000');
  GPmt := TBigDecimal.Create('-60');
  GNom := TBigDecimal.Create('0.06');
  GEff := TBigDecimal.Create('0.0616778118644996');
  GPer := 1;
  for pi := 0 to High(Precisions) do
  begin
    GC := TMathContext.Make(Precisions[pi], rmHalfEven);
    for ni := 0 to High(Periods) do
    begin
      GNper := Periods[ni];
      for op := 0 to 8 do
      begin
        // PeriodicRateXL solves for the rate of a -60 payment on 10000 only
        // at 12 periods in reasonable iterations; all rows use these operands.
        t := Measure(ops[op]);
        WriteLn(Format('%-18s %6d %7d %12.3f us/call median %12.3f spread %5.1f %%',
          [OpNames[op], Precisions[pi], Periods[ni], t, GLastMedian, GLastSpread]));
      end;
    end;
    GNper := 360;
    t := Measure(@DoSchedule);
    WriteLn(Format('%-18s %6d %7d %12.2f us/schedule median %12.2f spread %5.1f %%',
      ['PrincipalSchedule', Precisions[pi], 360, t, GLastMedian, GLastSpread]));
  end;
  WriteLn('sink: ', GSink);
end.
