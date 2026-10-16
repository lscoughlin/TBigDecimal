{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: sin, cos, tan, trigonometry
documentation: doc/design.md
notes:
  - argument reduction by pi/2 with extra digits for the size of the argument
  - Taylor series on the halved argument, then double-angle recovery
  - results are correctly rounded (Ziv strategy with error bounds)
---
}
unit BigDecimal.Trig;

{$mode objfpc}{$H+}
{$coperators on}

interface

uses
  SysUtils, BigDecimal.Types, BigDecimal, BigDecimal.Fixed;

function Sin(const X: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function Sin(const X: TBigDecimal): TBigDecimal; overload;
function Cos(const X: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function Cos(const X: TBigDecimal): TBigDecimal; overload;
function Tan(const X: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function Tan(const X: TBigDecimal): TBigDecimal; overload;

{ sin and cos of an argument held as a fixed-point value (W digits). }
procedure SinCosOfFx(const Xin: TFx; W: Integer; out S, Cs: TFx);

implementation

uses
  Math, BigDecimal.Constants;

procedure SinCosOfFx(const Xin: TFx; W: Integer; out S, Cs: TFx);
var
  w2, i, k, sh, qm: Integer;
  xf, halfpi, t, qf, r, rp, rp2, sinSum, cosSum, ts, tc, c2: TFx;
  q, qr: TBigDecimal;
  lim: Double;
  s1, c1: TFx;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  w2 := W + IntDigits(Xin.V) + 8;
  xf := FxRescale(Xin, w2);
  halfpi := FxDivInt(ConstPi(w2), 2);
  t := FxDiv(xf, halfpi);
  q := t.V.SetScale(0, rmHalfEven);
  qf := FxFromDecimal(q, w2);
  r := FxSub(xf, FxMul(qf, halfpi));
  r := FxRescale(r, W);
  qr := q.Remainder(TBigDecimal.Create(4));
  qm := Integer(qr.ToInt64);
  if qm < 0 then qm += 4;
  sh := Min(40, Trunc(Sqrt(Double(W))));
  if sh < 1 then sh := 1;
  rp := FxDivInt(r, Int64(1) shl sh);
  rp2 := FxSqr(rp);
  // sin series
  sinSum := rp;
  ts := rp;
  k := 1;
  while not FxTiny(ts) do
  begin
    ts := FxDivInt(FxMul(ts, rp2), Int64(2 * k) * (2 * k + 1));
    if (k and 1) = 1 then sinSum := FxSub(sinSum, ts) else sinSum := FxAdd(sinSum, ts);
    Inc(k);
  end;
  sinSum.E += 2;
  // cos series
  cosSum := FxFromInt(1, W);
  tc := cosSum;
  k := 1;
  while not FxTiny(tc) do
  begin
    tc := FxDivInt(FxMul(tc, rp2), Int64(2 * k - 1) * (2 * k));
    if (k and 1) = 1 then cosSum := FxSub(cosSum, tc) else cosSum := FxAdd(cosSum, tc);
    Inc(k);
  end;
  cosSum.E += 2;
  s1 := sinSum;
  c1 := cosSum;
  for i := 1 to sh do
  begin
    c2 := FxSub(FxFromInt(1, W), FxMulInt(FxSqr(s1), 2));
    s1 := FxMulInt(FxMul(s1, c1), 2);
    c1 := c2;
  end;
  case qm of
    0: begin S := s1; Cs := c1; end;
    1: begin S := c1; Cs := FxNeg(s1); end;
    2: begin S := FxNeg(s1); Cs := FxNeg(c1); end;
  else
    S := FxNeg(c1); Cs := s1;
  end;
end;

procedure SinCosFx(const X: TBigDecimal; W: Integer; out S, Cs: TFx);
begin
  SinCosOfFx(FxFromDecimal(X, W + IntDigits(X) + 8), W, S, Cs);
end;

function LeadDigits(const X: TBigDecimal): Integer;
var
  adj: Int64;
begin
  adj := Int64(X.Precision) - X.Scale - 1;
  if adj >= 0 then Exit(0);
  if adj < -100000000 then Exit(100000000);
  Result := Integer(-adj);
end;

function Evaluate(const X: TBigDecimal; const C: TMathContext; Which: Integer): TBigDecimal;
var
  w, p: Integer;
  s, cs, q: TFx;
  r: TBigDecimal;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  if C.Precision <= 0 then raise EBigDecimalDomain.Create('trigonometric functions need a finite precision');
  p := C.Precision;
  if X.IsZero then
  begin
    if Which = 1 then Exit(TBigDecimal.One.Round(C));
    Exit(TBigDecimal.Zero);
  end;
  w := p + 16 + LeadDigits(X);
  repeat
    try
      SinCosFx(X, w, s, cs);
      case Which of
        0: q := s;
        1: q := cs;
      else
        q := FxDiv(s, cs);
      end;
      if FxRound(q, C, r) then Exit(r);
    except
      on EBigDecimalPrecision do ;
    end;
    w += w div 3 + 12;
    if w > 6 * p + 1500 + LeadDigits(X) then
      raise EBigDecimalPrecision.Create('trigonometric function could not be rounded');
  until False;
end;

function Sin(const X: TBigDecimal; const C: TMathContext): TBigDecimal;
begin
  Result := Evaluate(X, C, 0);
end;

function Cos(const X: TBigDecimal; const C: TMathContext): TBigDecimal;
begin
  Result := Evaluate(X, C, 1);
end;

function Tan(const X: TBigDecimal; const C: TMathContext): TBigDecimal;
begin
  Result := Evaluate(X, C, 2);
end;

function Sin(const X: TBigDecimal): TBigDecimal;
var c: TMathContext;
begin
  if not EffectiveContext(c) then raise EBigDecimalNoContext.Create('Sin needs a context');
  Result := Sin(X, c);
end;

function Cos(const X: TBigDecimal): TBigDecimal;
var c: TMathContext;
begin
  if not EffectiveContext(c) then raise EBigDecimalNoContext.Create('Cos needs a context');
  Result := Cos(X, c);
end;

function Tan(const X: TBigDecimal): TBigDecimal;
var c: TMathContext;
begin
  if not EffectiveContext(c) then raise EBigDecimalNoContext.Create('Tan needs a context');
  Result := Tan(X, c);
end;

end.
