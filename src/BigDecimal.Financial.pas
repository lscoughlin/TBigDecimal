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

{ Overloads that read the thread-local default context. }
function CompoundFactor(const Rate, Periods: TBigDecimal): TBigDecimal;
function PresentValue(const Amount, Rate, Periods: TBigDecimal): TBigDecimal;
function FutureValue(const Amount, Rate, Periods: TBigDecimal): TBigDecimal;
function AnnuityFactor(const Rate, Periods: TBigDecimal): TBigDecimal;
function AnnualizedRate(const Ratio, Periods: TBigDecimal): TBigDecimal;

implementation

uses
  BigDecimal.Elementary;

function Work(const C: TMathContext): TMathContext;
begin
  if C.Precision <= 0 then
    raise EBigDecimalDomain.Create('financial functions need a finite precision');
  Result := TMathContext.Make(C.Precision + 12, rmHalfEven);
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
  w := Work(C);
  w.Precision := C.Precision + 20;
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
  w := Work(C);
  w.Precision := C.Precision + 20;
  e := TBigDecimal.One.Divide(Periods, w);
  Result := (Pow(Ratio, e, w) - TBigDecimal.One).Round(C);
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

end.
