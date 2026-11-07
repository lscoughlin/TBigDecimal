{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: financial, compound interest, present value, annuity
documentation: doc/design.md
notes:
  - thin wrappers over Pow and Divide
  - intermediate values use ten extra digits and one rounding gives the result
---
}
unit BigDecimal.Financial;

{$mode objfpc}{$H+}
{$coperators on}

interface

uses
  SysUtils, BigDecimal.Types, BigDecimal;

{ (1 + Rate)^Periods. Periods may be fractional. }
function CompoundFactor(const Rate, Periods: TBigDecimal; const C: TMathContext): TBigDecimal;
{ Value now of Amount due after Periods at a periodic Rate. }
function PresentValue(const Amount, Rate, Periods: TBigDecimal; const C: TMathContext): TBigDecimal;
{ Value after Periods of Amount invested at a periodic Rate. }
function FutureValue(const Amount, Rate, Periods: TBigDecimal; const C: TMathContext): TBigDecimal;
{ (1 - (1 + Rate)^-Periods) / Rate, the present value of one unit per period. }
function AnnuityFactor(const Rate, Periods: TBigDecimal; const C: TMathContext): TBigDecimal;
{ Ratio^(1 / Periods) - 1, the periodic rate that turns 1 into Ratio. }
function AnnualizedRate(const Ratio, Periods: TBigDecimal; const C: TMathContext): TBigDecimal;

{ Excel PMT: payment per period for a present value Pv (and a future value Fv)
  at a periodic Rate over Periods periods. Money paid out is negative. }
function PaymentXL(const Rate: TBigDecimal; Periods: Int64; const Pv: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function PaymentXL(const Rate: TBigDecimal; Periods: Int64; const Pv, Fv: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function PaymentXL(const Rate: TBigDecimal; Periods: Int64; const Pv, Fv: TBigDecimal; Timing: TPaymentTiming; const C: TMathContext): TBigDecimal; overload;
{ Excel PV: present value of periodic payments Pmt (and a future value Fv). }
function PresentValueXL(const Rate: TBigDecimal; Periods: Int64; const Pmt: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function PresentValueXL(const Rate: TBigDecimal; Periods: Int64; const Pmt, Fv: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function PresentValueXL(const Rate: TBigDecimal; Periods: Int64; const Pmt, Fv: TBigDecimal; Timing: TPaymentTiming; const C: TMathContext): TBigDecimal; overload;
{ Excel FV: future value of periodic payments Pmt (and a present value Pv). }
function FutureValueXL(const Rate: TBigDecimal; Periods: Int64; const Pmt: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function FutureValueXL(const Rate: TBigDecimal; Periods: Int64; const Pmt, Pv: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function FutureValueXL(const Rate: TBigDecimal; Periods: Int64; const Pmt, Pv: TBigDecimal; Timing: TPaymentTiming; const C: TMathContext): TBigDecimal; overload;
{ Excel NPER: number of periods for periodic payments Pmt against Pv (and Fv).
  The result can be fractional. }
function PeriodCountXL(const Rate, Pmt, Pv: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function PeriodCountXL(const Rate, Pmt, Pv, Fv: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function PeriodCountXL(const Rate, Pmt, Pv, Fv: TBigDecimal; Timing: TPaymentTiming; const C: TMathContext): TBigDecimal; overload;
{ Excel IPMT: interest part of the payment of period Per. }
function InterestPaymentXL(const Rate: TBigDecimal; Per, Periods: Int64; const Pv: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function InterestPaymentXL(const Rate: TBigDecimal; Per, Periods: Int64; const Pv, Fv: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function InterestPaymentXL(const Rate: TBigDecimal; Per, Periods: Int64; const Pv, Fv: TBigDecimal; Timing: TPaymentTiming; const C: TMathContext): TBigDecimal; overload;
{ Excel PPMT: principal part of the payment of period Per. }
function PrincipalPaymentXL(const Rate: TBigDecimal; Per, Periods: Int64; const Pv: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function PrincipalPaymentXL(const Rate: TBigDecimal; Per, Periods: Int64; const Pv, Fv: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function PrincipalPaymentXL(const Rate: TBigDecimal; Per, Periods: Int64; const Pv, Fv: TBigDecimal; Timing: TPaymentTiming; const C: TMathContext): TBigDecimal; overload;
{ Excel RATE: periodic rate for Periods payments Pmt against Pv (and Fv),
  solved by Newton iteration from Guess. }
function PeriodicRateXL(Periods: Int64; const Pmt, Pv: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function PeriodicRateXL(Periods: Int64; const Pmt, Pv, Fv: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function PeriodicRateXL(Periods: Int64; const Pmt, Pv, Fv: TBigDecimal; Timing: TPaymentTiming; const C: TMathContext): TBigDecimal; overload;
function PeriodicRateXL(Periods: Int64; const Pmt, Pv, Fv: TBigDecimal; Timing: TPaymentTiming; const Guess: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
{ Excel EFFECT: annual effective rate of a nominal rate with Periods
  compounding periods per year. }
function EffectiveRateXL(const Nominal: TBigDecimal; Periods: Int64; const C: TMathContext): TBigDecimal; overload;
{ Excel NOMINAL: annual nominal rate of an effective rate with Periods
  compounding periods per year. }
function NominalRateXL(const Effect: TBigDecimal; Periods: Int64; const C: TMathContext): TBigDecimal; overload;

{ Overloads that read the thread-local default context. }
function CompoundFactor(const Rate, Periods: TBigDecimal): TBigDecimal;
function PresentValue(const Amount, Rate, Periods: TBigDecimal): TBigDecimal;
function FutureValue(const Amount, Rate, Periods: TBigDecimal): TBigDecimal;
function AnnuityFactor(const Rate, Periods: TBigDecimal): TBigDecimal;
function AnnualizedRate(const Ratio, Periods: TBigDecimal): TBigDecimal;
function PaymentXL(const Rate: TBigDecimal; Periods: Int64; const Pv: TBigDecimal): TBigDecimal; overload;
function PaymentXL(const Rate: TBigDecimal; Periods: Int64; const Pv, Fv: TBigDecimal): TBigDecimal; overload;
function PaymentXL(const Rate: TBigDecimal; Periods: Int64; const Pv, Fv: TBigDecimal; Timing: TPaymentTiming): TBigDecimal; overload;
function PresentValueXL(const Rate: TBigDecimal; Periods: Int64; const Pmt: TBigDecimal): TBigDecimal; overload;
function PresentValueXL(const Rate: TBigDecimal; Periods: Int64; const Pmt, Fv: TBigDecimal): TBigDecimal; overload;
function PresentValueXL(const Rate: TBigDecimal; Periods: Int64; const Pmt, Fv: TBigDecimal; Timing: TPaymentTiming): TBigDecimal; overload;
function FutureValueXL(const Rate: TBigDecimal; Periods: Int64; const Pmt: TBigDecimal): TBigDecimal; overload;
function FutureValueXL(const Rate: TBigDecimal; Periods: Int64; const Pmt, Pv: TBigDecimal): TBigDecimal; overload;
function FutureValueXL(const Rate: TBigDecimal; Periods: Int64; const Pmt, Pv: TBigDecimal; Timing: TPaymentTiming): TBigDecimal; overload;
function PeriodCountXL(const Rate, Pmt, Pv: TBigDecimal): TBigDecimal; overload;
function PeriodCountXL(const Rate, Pmt, Pv, Fv: TBigDecimal): TBigDecimal; overload;
function PeriodCountXL(const Rate, Pmt, Pv, Fv: TBigDecimal; Timing: TPaymentTiming): TBigDecimal; overload;
function InterestPaymentXL(const Rate: TBigDecimal; Per, Periods: Int64; const Pv: TBigDecimal): TBigDecimal; overload;
function InterestPaymentXL(const Rate: TBigDecimal; Per, Periods: Int64; const Pv, Fv: TBigDecimal): TBigDecimal; overload;
function InterestPaymentXL(const Rate: TBigDecimal; Per, Periods: Int64; const Pv, Fv: TBigDecimal; Timing: TPaymentTiming): TBigDecimal; overload;
function PrincipalPaymentXL(const Rate: TBigDecimal; Per, Periods: Int64; const Pv: TBigDecimal): TBigDecimal; overload;
function PrincipalPaymentXL(const Rate: TBigDecimal; Per, Periods: Int64; const Pv, Fv: TBigDecimal): TBigDecimal; overload;
function PrincipalPaymentXL(const Rate: TBigDecimal; Per, Periods: Int64; const Pv, Fv: TBigDecimal; Timing: TPaymentTiming): TBigDecimal; overload;
function PeriodicRateXL(Periods: Int64; const Pmt, Pv: TBigDecimal): TBigDecimal; overload;
function PeriodicRateXL(Periods: Int64; const Pmt, Pv, Fv: TBigDecimal): TBigDecimal; overload;
function PeriodicRateXL(Periods: Int64; const Pmt, Pv, Fv: TBigDecimal; Timing: TPaymentTiming): TBigDecimal; overload;
function PeriodicRateXL(Periods: Int64; const Pmt, Pv, Fv: TBigDecimal; Timing: TPaymentTiming; const Guess: TBigDecimal): TBigDecimal; overload;
function EffectiveRateXL(const Nominal: TBigDecimal; Periods: Int64): TBigDecimal; overload;
function NominalRateXL(const Effect: TBigDecimal; Periods: Int64): TBigDecimal; overload;

implementation

uses
  BigDecimal.Elementary;

function Work(const C: TMathContext; Extra: Integer): TMathContext; overload;
begin
  if C.Precision <= 0 then
    raise EBigDecimalDomain.Create('financial functions need a finite precision');
  Result := TMathContext.Make(C.Precision + Extra, rmHalfEven);
end;

function Work(const C: TMathContext): TMathContext; overload;
begin
  Result := Work(C, 12);
end;

{ Rate must keep the growth factor positive. }
procedure CheckRate(const Rate: TBigDecimal);
begin
  if (TBigDecimal.One + Rate).Sign <= 0 then
    raise EBigDecimalDomain.Create('rate must be greater than -1');
end;

{ Payment functions: a zero count divides by zero, a negative one is outside
  the domain. }
procedure CheckPeriod(Periods: Int64);
begin
  if Periods = 0 then
    raise EBigDecimalDivByZero.Create('period count is zero');
  if Periods < 0 then
    raise EBigDecimalDomain.Create('period count is negative');
end;

{ Compounding counts start at one. }
procedure CheckNpery(Periods: Int64);
begin
  if Periods < 1 then
    raise EBigDecimalDomain.Create('periods per year must be at least 1');
end;

procedure CheckPer(Per, Periods: Int64);
begin
  if (Per < 1) or (Per > Periods) then
    raise EBigDecimalDomain.Create('period number is outside 1..nper');
end;

{ Count of leading fractional zeros of X; 0 when |X| >= 1 or X = 0. }
function LeadZeros(const X: TBigDecimal): Integer;
begin
  if X.IsZero then Exit(0);
  Result := X.Scale - X.Precision;
  if Result < 0 then Result := 0;
end;

{ Depth of the fractional tail of X; inputs hide tails at their own depth. }
function InputDepth(const X: TBigDecimal): Integer;
begin
  Result := X.Scale;
  if Result < 0 then Result := 0;
end;

{ Estimate of log10((1 + Rate)^Periods), floored at 0. }
function GrowthDepth(const Rate: TBigDecimal; Periods: Int64): Integer;
var
  r, x: Double;
begin
  Result := 0;
  try
    r := Rate.ToDouble;
  except
    Exit(0);
  end;
  if r <= 0 then Exit(0);
  x := Periods * (Ln(1 + r) / Ln(10));
  if (x > 0) and (x < 1.0e12) then Result := Trunc(x) + 1
  else if x >= 1.0e12 then Result := 1000000;
end;

{ Extra working digits over the target precision: a base margin, twice the
  cancellation depth of Rate * Periods, the growth depth, and the deepest
  input tail. }
function ExtraDigits(const Rate: TBigDecimal; Periods: Int64;
  const Vals: array of TBigDecimal): Integer;
var
  i, m: Integer;
begin
  Result := 20;
  if not Rate.IsZero then
  begin
    Result += 2 * LeadZeros(Rate * TBigDecimal.Create(Periods));
    Result += GrowthDepth(Rate, Periods);
  end;
  m := InputDepth(Rate);
  for i := 0 to High(Vals) do
    if InputDepth(Vals[i]) > m then m := InputDepth(Vals[i]);
  Result += m;
end;

{ 1 + Rate * t with t = 0 for ptEnd and 1 for ptBegin. }
function TimingFactor(const Rate: TBigDecimal; Timing: TPaymentTiming): TBigDecimal;
begin
  if Timing = ptBegin then Result := TBigDecimal.One + Rate
  else Result := TBigDecimal.One;
end;

{ (1 + Rate)^Periods - 1. The power is exact while its digit estimate stays
  below the threshold, else rounded once at W. }
function GrowthMinusOne(const Rate: TBigDecimal; Periods: Int64;
  const W: TMathContext): TBigDecimal;
var
  base: TBigDecimal;
  est: Double;
begin
  base := TBigDecimal.One + Rate;
  est := Periods * (base.Precision + 1);
  if (est <= 60000) and (Periods >= 0) then
    try
      Result := PowExact(base, Periods) - TBigDecimal.One;
      Exit;
    except
      on EBigDecimalOverflow do ; // fall through to the rounded path
    end;
  Result := Pow(base, Periods, W) - TBigDecimal.One;
end;

function CompoundFactor(const Rate, Periods: TBigDecimal; const C: TMathContext): TBigDecimal;
var
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  Result := Pow(TBigDecimal.One + Rate, Periods, Work(C)).Round(C);
end;

function PresentValue(const Amount, Rate, Periods: TBigDecimal; const C: TMathContext): TBigDecimal;
var
  w: TMathContext;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  w := Work(C);
  Result := Amount.Divide(Pow(TBigDecimal.One + Rate, Periods, w), C);
end;

function FutureValue(const Amount, Rate, Periods: TBigDecimal; const C: TMathContext): TBigDecimal;
var
  w: TMathContext;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  w := Work(C);
  Result := Amount.Multiply(Pow(TBigDecimal.One + Rate, Periods, w), C);
end;

function AnnuityFactor(const Rate, Periods: TBigDecimal; const C: TMathContext): TBigDecimal;
var
  w: TMathContext;
  f: TBigDecimal;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  if Rate.IsZero then Exit(Periods.Round(C));
  w := Work(C, 20);
  f := Pow(TBigDecimal.One + Rate, Periods.Negate, w);
  Result := (TBigDecimal.One - f).Divide(Rate, C);
end;

function AnnualizedRate(const Ratio, Periods: TBigDecimal; const C: TMathContext): TBigDecimal;
var
  w: TMathContext;
  e: TBigDecimal;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  w := Work(C, 20);
  e := TBigDecimal.One.Divide(Periods, w);
  Result := (Pow(Ratio, e, w) - TBigDecimal.One).Round(C);
end;

{ ----- shared Excel cores: exact numerators, one division at W ----- }

function PaymentCore(const Rate: TBigDecimal; Periods: Int64;
  const Pv, Fv: TBigDecimal; Timing: TPaymentTiming;
  const W: TMathContext): TBigDecimal;
var
  gm1, g, a, num, den: TBigDecimal;
begin
  if Rate.IsZero then
    Exit((Pv + Fv).Negate.Divide(TBigDecimal.Create(Periods), W));
  gm1 := GrowthMinusOne(Rate, Periods, W);
  g := gm1 + TBigDecimal.One;
  a := TimingFactor(Rate, Timing);
  num := (Pv * g + Fv) * Rate;
  den := a * gm1;
  Result := num.Negate.Divide(den, W);
end;

function PresentValueCore(const Rate: TBigDecimal; Periods: Int64;
  const Pmt, Fv: TBigDecimal; Timing: TPaymentTiming;
  const W: TMathContext): TBigDecimal;
var
  gm1, g, a, num, den: TBigDecimal;
begin
  if Rate.IsZero then
    Exit((Fv + Pmt * TBigDecimal.Create(Periods)).Negate);
  gm1 := GrowthMinusOne(Rate, Periods, W);
  g := gm1 + TBigDecimal.One;
  a := TimingFactor(Rate, Timing);
  num := Fv * Rate + Pmt * a * gm1;
  den := Rate * g;
  Result := num.Negate.Divide(den, W);
end;

function FutureValueCore(const Rate: TBigDecimal; Periods: Int64;
  const Pmt, Pv: TBigDecimal; Timing: TPaymentTiming;
  const W: TMathContext): TBigDecimal;
var
  gm1, g, a, num: TBigDecimal;
begin
  if Rate.IsZero then
    Exit((Pv + Pmt * TBigDecimal.Create(Periods)).Negate);
  gm1 := GrowthMinusOne(Rate, Periods, W);
  g := gm1 + TBigDecimal.One;
  a := TimingFactor(Rate, Timing);
  num := Pv * g * Rate + Pmt * a * gm1;
  Result := num.Negate.Divide(Rate, W);
end;

function PeriodCountCore(const Rate, Pmt, Pv, Fv: TBigDecimal;
  Timing: TPaymentTiming; const W: TMathContext): TBigDecimal;
var
  a, num, den, q: TBigDecimal;
begin
  if Rate.IsZero then
    Exit((Pv + Fv).Negate.Divide(Pmt, W));
  a := TimingFactor(Rate, Timing);
  num := Pmt * a - Fv * Rate;
  den := Pmt * a + Pv * Rate;
  if num.IsZero or (num.Sign <> den.Sign) then
    raise EBigDecimalDomain.Create('period count has no real solution');
  q := num.Divide(den, W);
  Result := Ln(q, W).Divide(Ln(TBigDecimal.One + Rate, W), W);
end;

{ Interest of an end-of-period schedule after K payments: -(Pv * gk * r +
  pmt * (gk - 1)), exact for the given payment. }
function EndInterest(const Rate: TBigDecimal; K: Int64;
  const Pv, Pmt: TBigDecimal; const W: TMathContext): TBigDecimal;
var
  gm1, gk: TBigDecimal;
begin
  if Rate.IsZero then Exit(TBigDecimal.Zero);
  gm1 := GrowthMinusOne(Rate, K, W);
  gk := gm1 + TBigDecimal.One;
  Result := (Pv * gk * Rate + Pmt * gm1).Negate;
end;

function InterestCore(const Rate: TBigDecimal; Per, Periods: Int64;
  const Pv, Fv: TBigDecimal; Timing: TPaymentTiming;
  const W: TMathContext): TBigDecimal;
var
  pmt, e: TBigDecimal;
begin
  if (Timing = ptBegin) and (Per = 1) then Exit(TBigDecimal.Zero);
  pmt := PaymentCore(Rate, Periods, Pv, Fv, Timing, W);
  if Timing = ptBegin then
  begin
    e := EndInterest(Rate, Per - 1, Pv, pmt, W);
    Result := e.Divide(TBigDecimal.One + Rate, W);
  end
  else
    Result := EndInterest(Rate, Per - 1, Pv, pmt, W);
end;

function PrincipalCore(const Rate: TBigDecimal; Per, Periods: Int64;
  const Pv, Fv: TBigDecimal; Timing: TPaymentTiming;
  const W: TMathContext): TBigDecimal;
begin
  Result := PaymentCore(Rate, Periods, Pv, Fv, Timing, W) -
    InterestCore(Rate, Per, Periods, Pv, Fv, Timing, W);
end;

{ f(r) and f'(r) of the rate equation
  f(r) = pv * g + pmt * (1 + r * t) * (g - 1) / r + fv
  with g = (1 + r)^n, through l'Hopital limits at r = 0. }
procedure RateFG(const R: TBigDecimal; Periods: Int64;
  const Pmt, Pv, Fv: TBigDecimal; Timing: TPaymentTiming;
  const Wi: TMathContext; out F, DF: TBigDecimal);
var
  n_, g, gm1, u, h, gp, dh, half, base: TBigDecimal;
begin
  n_ := TBigDecimal.Create(Periods);
  if R.IsZero then
  begin
    F := Pv + Fv + Pmt * n_;
    half := (n_ - TBigDecimal.One).Divide(TBigDecimal.Create(Int64(2)));
    DF := Pv * n_ + Pmt * n_ * half;
    if Timing = ptBegin then DF := DF + Pmt * n_;
    Exit;
  end;
  base := TBigDecimal.One + R;
  gm1 := GrowthMinusOne(R, Periods, Wi);
  g := gm1 + TBigDecimal.One;
  u := TimingFactor(R, Timing);
  h := gm1.Divide(R, Wi);
  gp := (g * n_).Divide(base, Wi);
  dh := (R * gp - gm1).Divide(R * R, Wi);
  F := Pv * g + Pmt * u * h + Fv;
  DF := Pv * gp + Pmt * u * dh;
  if Timing = ptBegin then DF := DF + Pmt * h;
end;

function PeriodicRateCore(Periods: Int64; const Pmt, Pv, Fv: TBigDecimal;
  Timing: TPaymentTiming; const Guess: TBigDecimal;
  const C: TMathContext): TBigDecimal;
var
  r, f, df, dr, step, rNew, tol, ratio, n_: TBigDecimal;
  wi: TMathContext;
  iter, damp, halved: Integer;
  damped: Boolean;
  idep: Integer;
begin
  n_ := TBigDecimal.Create(Periods);
  if (Pv + Fv + Pmt * n_).IsZero then Exit(TBigDecimal.Zero);
  if Pmt.IsZero then
  begin
    if Pv.IsZero then
      raise EBigDecimalDomain.Create('rate has no unique solution');
    wi := Work(C, 20 + InputDepth(Pv) + InputDepth(Fv));
    ratio := Fv.Negate.Divide(Pv, wi);
    if ratio.Sign <= 0 then
      raise EBigDecimalDomain.Create('rate has no real solution');
    Result := AnnualizedRate(ratio, n_, C);
    Exit;
  end;
  if Pv.IsZero and Fv.IsZero then
    raise EBigDecimalDomain.Create('rate has no unique solution');
  if (not Pv.IsZero) and (not Fv.IsZero) and
     (Pv.Sign = Pmt.Sign) and (Fv.Sign = Pmt.Sign) then
    raise EBigDecimalDomain.Create('rate has no real solution');
  idep := InputDepth(Pmt);
  if InputDepth(Pv) > idep then idep := InputDepth(Pv);
  if InputDepth(Fv) > idep then idep := InputDepth(Fv);
  tol := TBigDecimal.Create(TBigDecimal.One, C.Precision + 10);
  r := Guess;
  halved := 0;
  while (TBigDecimal.One + r).Sign <= 0 do
  begin
    Inc(halved);
    if halved > 1100 then
      raise EBigDecimalNoConvergence.Create('rate iteration did not converge');
    r := r.Divide(TBigDecimal.Create(Int64(2)));
  end;
  for iter := 1 to 100 do
  begin
    wi := Work(C, 20 + idep + 2 * LeadZeros(r * n_));
    RateFG(r, Periods, Pmt, Pv, Fv, Timing, wi, f, df);
    if f.IsZero then Exit(r);
    if df.IsZero then
      raise EBigDecimalNoConvergence.Create('rate iteration did not converge');
    dr := f.Divide(df, wi);
    if dr.Abs.CompareTo(tol) < 0 then Exit(r - dr);
    step := dr;
    damped := False;
    for damp := 1 to 60 do
    begin
      rNew := r - step;
      if (TBigDecimal.One + rNew).Sign > 0 then
      begin
        damped := True;
        Break;
      end;
      step := step.Divide(TBigDecimal.Create(Int64(2)));
    end;
    if not damped then
      raise EBigDecimalNoConvergence.Create('rate iteration did not converge');
    r := rNew;
  end;
  raise EBigDecimalNoConvergence.Create('rate iteration did not converge');
end;

{ ----- public Excel functions ----- }

function PaymentXL(const Rate: TBigDecimal; Periods: Int64;
  const Pv, Fv: TBigDecimal; Timing: TPaymentTiming;
  const C: TMathContext): TBigDecimal;
var
  w: TMathContext;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  CheckRate(Rate);
  CheckPeriod(Periods);
  w := Work(C, ExtraDigits(Rate, Periods, [Pv, Fv]));
  Result := PaymentCore(Rate, Periods, Pv, Fv, Timing, w).Round(C);
end;

function PaymentXL(const Rate: TBigDecimal; Periods: Int64;
  const Pv, Fv: TBigDecimal; const C: TMathContext): TBigDecimal;
begin
  Result := PaymentXL(Rate, Periods, Pv, Fv, ptEnd, C);
end;

function PaymentXL(const Rate: TBigDecimal; Periods: Int64;
  const Pv: TBigDecimal; const C: TMathContext): TBigDecimal;
begin
  Result := PaymentXL(Rate, Periods, Pv, TBigDecimal.Zero, C);
end;

function PresentValueXL(const Rate: TBigDecimal; Periods: Int64;
  const Pmt, Fv: TBigDecimal; Timing: TPaymentTiming;
  const C: TMathContext): TBigDecimal;
var
  w: TMathContext;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  CheckRate(Rate);
  CheckPeriod(Periods);
  w := Work(C, ExtraDigits(Rate, Periods, [Pmt, Fv]));
  Result := PresentValueCore(Rate, Periods, Pmt, Fv, Timing, w).Round(C);
end;

function PresentValueXL(const Rate: TBigDecimal; Periods: Int64;
  const Pmt, Fv: TBigDecimal; const C: TMathContext): TBigDecimal;
begin
  Result := PresentValueXL(Rate, Periods, Pmt, Fv, ptEnd, C);
end;

function PresentValueXL(const Rate: TBigDecimal; Periods: Int64;
  const Pmt: TBigDecimal; const C: TMathContext): TBigDecimal;
begin
  Result := PresentValueXL(Rate, Periods, Pmt, TBigDecimal.Zero, C);
end;

function FutureValueXL(const Rate: TBigDecimal; Periods: Int64;
  const Pmt, Pv: TBigDecimal; Timing: TPaymentTiming;
  const C: TMathContext): TBigDecimal;
var
  w: TMathContext;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  CheckRate(Rate);
  CheckPeriod(Periods);
  w := Work(C, ExtraDigits(Rate, Periods, [Pmt, Pv]));
  Result := FutureValueCore(Rate, Periods, Pmt, Pv, Timing, w).Round(C);
end;

function FutureValueXL(const Rate: TBigDecimal; Periods: Int64;
  const Pmt, Pv: TBigDecimal; const C: TMathContext): TBigDecimal;
begin
  Result := FutureValueXL(Rate, Periods, Pmt, Pv, ptEnd, C);
end;

function FutureValueXL(const Rate: TBigDecimal; Periods: Int64;
  const Pmt: TBigDecimal; const C: TMathContext): TBigDecimal;
begin
  Result := FutureValueXL(Rate, Periods, Pmt, TBigDecimal.Zero, C);
end;

function PeriodCountXL(const Rate, Pmt, Pv, Fv: TBigDecimal;
  Timing: TPaymentTiming; const C: TMathContext): TBigDecimal;
var
  w: TMathContext;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  CheckRate(Rate);
  w := Work(C, ExtraDigits(Rate, 1, [Pmt, Pv, Fv]));
  Result := PeriodCountCore(Rate, Pmt, Pv, Fv, Timing, w).Round(C);
end;

function PeriodCountXL(const Rate, Pmt, Pv, Fv: TBigDecimal;
  const C: TMathContext): TBigDecimal;
begin
  Result := PeriodCountXL(Rate, Pmt, Pv, Fv, ptEnd, C);
end;

function PeriodCountXL(const Rate, Pmt, Pv: TBigDecimal;
  const C: TMathContext): TBigDecimal;
begin
  Result := PeriodCountXL(Rate, Pmt, Pv, TBigDecimal.Zero, C);
end;

function InterestPaymentXL(const Rate: TBigDecimal; Per, Periods: Int64;
  const Pv, Fv: TBigDecimal; Timing: TPaymentTiming;
  const C: TMathContext): TBigDecimal;
var
  w: TMathContext;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  CheckRate(Rate);
  CheckPeriod(Periods);
  CheckPer(Per, Periods);
  w := Work(C, ExtraDigits(Rate, Periods, [Pv, Fv]));
  Result := InterestCore(Rate, Per, Periods, Pv, Fv, Timing, w).Round(C);
end;

function InterestPaymentXL(const Rate: TBigDecimal; Per, Periods: Int64;
  const Pv, Fv: TBigDecimal; const C: TMathContext): TBigDecimal;
begin
  Result := InterestPaymentXL(Rate, Per, Periods, Pv, Fv, ptEnd, C);
end;

function InterestPaymentXL(const Rate: TBigDecimal; Per, Periods: Int64;
  const Pv: TBigDecimal; const C: TMathContext): TBigDecimal;
begin
  Result := InterestPaymentXL(Rate, Per, Periods, Pv, TBigDecimal.Zero, C);
end;

function PrincipalPaymentXL(const Rate: TBigDecimal; Per, Periods: Int64;
  const Pv, Fv: TBigDecimal; Timing: TPaymentTiming;
  const C: TMathContext): TBigDecimal;
var
  w: TMathContext;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  CheckRate(Rate);
  CheckPeriod(Periods);
  CheckPer(Per, Periods);
  w := Work(C, ExtraDigits(Rate, Periods, [Pv, Fv]));
  Result := PrincipalCore(Rate, Per, Periods, Pv, Fv, Timing, w).Round(C);
end;

function PrincipalPaymentXL(const Rate: TBigDecimal; Per, Periods: Int64;
  const Pv, Fv: TBigDecimal; const C: TMathContext): TBigDecimal;
begin
  Result := PrincipalPaymentXL(Rate, Per, Periods, Pv, Fv, ptEnd, C);
end;

function PrincipalPaymentXL(const Rate: TBigDecimal; Per, Periods: Int64;
  const Pv: TBigDecimal; const C: TMathContext): TBigDecimal;
begin
  Result := PrincipalPaymentXL(Rate, Per, Periods, Pv, TBigDecimal.Zero, C);
end;

function PeriodicRateXL(Periods: Int64; const Pmt, Pv, Fv: TBigDecimal;
  Timing: TPaymentTiming; const Guess: TBigDecimal;
  const C: TMathContext): TBigDecimal;
var
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  CheckPeriod(Periods);
  if C.Precision <= 0 then
    raise EBigDecimalDomain.Create('financial functions need a finite precision');
  Result := PeriodicRateCore(Periods, Pmt, Pv, Fv, Timing, Guess, C).Round(C);
  if (TBigDecimal.One + Result).Sign <= 0 then
    raise EBigDecimalNoConvergence.Create('rate iteration did not converge');
end;

function PeriodicRateXL(Periods: Int64; const Pmt, Pv, Fv: TBigDecimal;
  Timing: TPaymentTiming; const C: TMathContext): TBigDecimal;
begin
  Result := PeriodicRateXL(Periods, Pmt, Pv, Fv, Timing,
    TBigDecimal.Create('0.1'), C);
end;

function PeriodicRateXL(Periods: Int64; const Pmt, Pv, Fv: TBigDecimal;
  const C: TMathContext): TBigDecimal;
begin
  Result := PeriodicRateXL(Periods, Pmt, Pv, Fv, ptEnd, C);
end;

function PeriodicRateXL(Periods: Int64; const Pmt, Pv: TBigDecimal;
  const C: TMathContext): TBigDecimal;
begin
  Result := PeriodicRateXL(Periods, Pmt, Pv, TBigDecimal.Zero, C);
end;

function EffectiveRateXL(const Nominal: TBigDecimal; Periods: Int64;
  const C: TMathContext): TBigDecimal;
var
  w: TMathContext;
  per, g: TBigDecimal;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  CheckNpery(Periods);
  if Nominal.Sign <= 0 then
    raise EBigDecimalDomain.Create('nominal rate must be positive');
  w := Work(C, 20 + 2 * LeadZeros(Nominal.Divide(TBigDecimal.Create(Periods), Work(C, 20))) +
    Length(IntToStr(Periods)) + InputDepth(Nominal));
  per := Nominal.Divide(TBigDecimal.Create(Periods), w);
  g := Pow(TBigDecimal.One + per, Periods, w);
  Result := (g - TBigDecimal.One).Round(C);
end;

function NominalRateXL(const Effect: TBigDecimal; Periods: Int64;
  const C: TMathContext): TBigDecimal;
var
  w: TMathContext;
  e, pw: TBigDecimal;
  nd: Integer;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  CheckNpery(Periods);
  if Effect.Sign <= 0 then
    raise EBigDecimalDomain.Create('effective rate must be positive');
  nd := Length(IntToStr(Periods));
  w := Work(C, 30 + 2 * (LeadZeros(Effect) + nd) + nd + InputDepth(Effect));
  e := TBigDecimal.One.Divide(TBigDecimal.Create(Periods), w);
  pw := Pow(TBigDecimal.One + Effect, e, w);
  Result := ((pw - TBigDecimal.One) * TBigDecimal.Create(Periods)).Round(C);
end;

function Need(out C: TMathContext): TMathContext;
begin
  if not EffectiveContext(C) then
    raise EBigDecimalNoContext.Create('no math context is available');
  Result := C;
end;

function CompoundFactor(const Rate, Periods: TBigDecimal): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := CompoundFactor(Rate, Periods, c); end;

function PresentValue(const Amount, Rate, Periods: TBigDecimal): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := PresentValue(Amount, Rate, Periods, c); end;

function FutureValue(const Amount, Rate, Periods: TBigDecimal): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := FutureValue(Amount, Rate, Periods, c); end;

function AnnuityFactor(const Rate, Periods: TBigDecimal): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := AnnuityFactor(Rate, Periods, c); end;

function AnnualizedRate(const Ratio, Periods: TBigDecimal): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := AnnualizedRate(Ratio, Periods, c); end;

function PaymentXL(const Rate: TBigDecimal; Periods: Int64;
  const Pv, Fv: TBigDecimal; Timing: TPaymentTiming): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := PaymentXL(Rate, Periods, Pv, Fv, Timing, c); end;

function PaymentXL(const Rate: TBigDecimal; Periods: Int64;
  const Pv, Fv: TBigDecimal): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := PaymentXL(Rate, Periods, Pv, Fv, c); end;

function PaymentXL(const Rate: TBigDecimal; Periods: Int64;
  const Pv: TBigDecimal): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := PaymentXL(Rate, Periods, Pv, c); end;

function PresentValueXL(const Rate: TBigDecimal; Periods: Int64;
  const Pmt, Fv: TBigDecimal; Timing: TPaymentTiming): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := PresentValueXL(Rate, Periods, Pmt, Fv, Timing, c); end;

function PresentValueXL(const Rate: TBigDecimal; Periods: Int64;
  const Pmt, Fv: TBigDecimal): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := PresentValueXL(Rate, Periods, Pmt, Fv, c); end;

function PresentValueXL(const Rate: TBigDecimal; Periods: Int64;
  const Pmt: TBigDecimal): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := PresentValueXL(Rate, Periods, Pmt, c); end;

function FutureValueXL(const Rate: TBigDecimal; Periods: Int64;
  const Pmt, Pv: TBigDecimal; Timing: TPaymentTiming): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := FutureValueXL(Rate, Periods, Pmt, Pv, Timing, c); end;

function FutureValueXL(const Rate: TBigDecimal; Periods: Int64;
  const Pmt, Pv: TBigDecimal): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := FutureValueXL(Rate, Periods, Pmt, Pv, c); end;

function FutureValueXL(const Rate: TBigDecimal; Periods: Int64;
  const Pmt: TBigDecimal): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := FutureValueXL(Rate, Periods, Pmt, c); end;

function PeriodCountXL(const Rate, Pmt, Pv, Fv: TBigDecimal;
  Timing: TPaymentTiming): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := PeriodCountXL(Rate, Pmt, Pv, Fv, Timing, c); end;

function PeriodCountXL(const Rate, Pmt, Pv, Fv: TBigDecimal): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := PeriodCountXL(Rate, Pmt, Pv, Fv, c); end;

function PeriodCountXL(const Rate, Pmt, Pv: TBigDecimal): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := PeriodCountXL(Rate, Pmt, Pv, c); end;

function InterestPaymentXL(const Rate: TBigDecimal; Per, Periods: Int64;
  const Pv, Fv: TBigDecimal; Timing: TPaymentTiming): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := InterestPaymentXL(Rate, Per, Periods, Pv, Fv, Timing, c); end;

function InterestPaymentXL(const Rate: TBigDecimal; Per, Periods: Int64;
  const Pv, Fv: TBigDecimal): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := InterestPaymentXL(Rate, Per, Periods, Pv, Fv, c); end;

function InterestPaymentXL(const Rate: TBigDecimal; Per, Periods: Int64;
  const Pv: TBigDecimal): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := InterestPaymentXL(Rate, Per, Periods, Pv, c); end;

function PrincipalPaymentXL(const Rate: TBigDecimal; Per, Periods: Int64;
  const Pv: TBigDecimal): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := PrincipalPaymentXL(Rate, Per, Periods, Pv, c); end;

function PrincipalPaymentXL(const Rate: TBigDecimal; Per, Periods: Int64;
  const Pv, Fv: TBigDecimal): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := PrincipalPaymentXL(Rate, Per, Periods, Pv, Fv, c); end;

function PrincipalPaymentXL(const Rate: TBigDecimal; Per, Periods: Int64;
  const Pv, Fv: TBigDecimal; Timing: TPaymentTiming): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := PrincipalPaymentXL(Rate, Per, Periods, Pv, Fv, Timing, c); end;

function PeriodicRateXL(Periods: Int64; const Pmt, Pv, Fv: TBigDecimal;
  Timing: TPaymentTiming; const Guess: TBigDecimal): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := PeriodicRateXL(Periods, Pmt, Pv, Fv, Timing, Guess, c); end;

function PeriodicRateXL(Periods: Int64; const Pmt, Pv, Fv: TBigDecimal;
  Timing: TPaymentTiming): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := PeriodicRateXL(Periods, Pmt, Pv, Fv, Timing, c); end;

function PeriodicRateXL(Periods: Int64; const Pmt, Pv, Fv: TBigDecimal): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := PeriodicRateXL(Periods, Pmt, Pv, Fv, c); end;

function PeriodicRateXL(Periods: Int64; const Pmt, Pv: TBigDecimal): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := PeriodicRateXL(Periods, Pmt, Pv, c); end;

function EffectiveRateXL(const Nominal: TBigDecimal; Periods: Int64): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := EffectiveRateXL(Nominal, Periods, c); end;

function NominalRateXL(const Effect: TBigDecimal; Periods: Int64): TBigDecimal;
var c: TMathContext;
begin Need(c); Result := NominalRateXL(Effect, Periods, c); end;

end.
