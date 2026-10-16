{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: gamma, log gamma, stirling series, bernoulli numbers
documentation: doc/design.md
notes:
  - Stirling series with an upward argument shift (no reflection through a pole)
  - reflection through sin(pi x) serves arguments far below zero
  - Bernoulli numbers come from the tangent-number algorithm and are cached
---
}
unit BigDecimal.Gamma;

{$mode objfpc}{$H+}
{$coperators on}

interface

uses
  SysUtils, BigDecimal.Types, BigDecimal;

function Gamma(const X: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function Gamma(const X: TBigDecimal): TBigDecimal; overload;
function LnGamma(const X: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function LnGamma(const X: TBigDecimal): TBigDecimal; overload;
{ Factorial of a non-integer (or integer) value: Gamma(X + 1). }
function Factorial(const X: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function LnFactorial(N: Int64; const C: TMathContext): TBigDecimal;

{ Tangent number T_k (1, 2, 16, 272, 7936, ...), k >= 1. }
function TangentNumber(K: Integer): TBigDecimal;

implementation

uses
  Math, BigDecimal.Fixed, BigDecimal.Constants, BigDecimal.Math, BigDecimal.Trig,
  BigDecimal.Combinatorics;

var
  GTan: array of TBigDecimal;
  GTanLock: TRTLCriticalSection;

procedure ComputeTangent(N: Integer; out T: array of TBigDecimal);
var
  k, j: Integer;
  a: array of TBigDecimal;
begin
  SetLength(a, N + 1);
  a[1] := TBigDecimal.One;
  for k := 2 to N do
    a[k] := a[k - 1] * TBigDecimal.Create(k - 1);
  for k := 2 to N do
    for j := k to N do
      a[j] := a[j - 1] * TBigDecimal.Create(j - k) + a[j] * TBigDecimal.Create(j - k + 2);
  for k := 1 to N do T[k] := a[k];
end;

function TangentNumber(K: Integer): TBigDecimal;
var
  n: Integer;
  tmp: array of TBigDecimal;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  if K < 1 then raise EBigDecimalDomain.Create('tangent number index must be positive');
  EnterCriticalSection(GTanLock);
  try
    if Length(GTan) <= K then
    begin
      n := Max(2 * Length(GTan), K + 16);
      SetLength(tmp, n + 1);
      ComputeTangent(n, tmp);
      GTan := tmp;
    end;
    Result := GTan[K];
  finally
    LeaveCriticalSection(GTanLock);
  end;
end;

{ ln Gamma(z) for z >= shift target, as a fixed-point value at W digits. }
function LnGammaStirling(const Z: TBigDecimal; W: Integer): TFx;
var
  zfx, one, half, l, t1, sum, lnTwoPi, piFx: TFx;
  k, wp: Integer;
  piDec: TBigDecimal;
  W2: Integer;
  zinvF, zinv2F, pF, sumF, termF, tk, four, dk: TBigDecimal;
  fc: TMathContext;
begin
  W2 := W + 6;
  zfx := FxFromDecimal(Z, W);
  one := FxFromInt(1, W);
  half := FxFromDecimal(TBigDecimal.Create('0.5'), W);
  l := LnFx(Z, W);
  t1 := FxMul(FxSub(zfx, half), l);
  t1 := FxSub(t1, zfx);
  // ln(2 pi) / 2
  piFx := ConstPi(W2);
  piDec := piFx.V;
  lnTwoPi := LnFx(piDec, W);
  lnTwoPi.E += 2 + piFx.E * 1e-6;
  lnTwoPi := FxAdd(lnTwoPi, FxRescale(ConstLnPrime(2, W2), W));
  lnTwoPi := FxDivInt(lnTwoPi, 2);
  t1 := FxAdd(t1, lnTwoPi);
  // The series terms span many orders of magnitude, so they are evaluated in
  // floating point (relative precision wP) and summed exactly.
  wp := W + 6;
  fc := TMathContext.Make(wp, rmHalfEven);
  zinvF := TBigDecimal.One.Divide(Z, fc);
  zinv2F := zinvF.Multiply(zinvF, fc);
  pF := zinvF;
  sumF := TBigDecimal.Zero;
  k := 1;
  repeat
    tk := TangentNumber(k);
    four := PowExact(TBigDecimal.Create(4), k);
    dk := TBigDecimal.Create(2 * k - 1) * four * (four - TBigDecimal.One);
    termF := tk.Divide(dk, fc).Multiply(pF, fc);
    if (k and 1) = 0 then termF := termF.Negate;
    sumF := sumF + termF;
    if (termF.IsZero) or (Int64(termF.Precision) - termF.Scale < -Int64(W) - 1) then Break;
    if k > 4 * W + 100 then
      raise EBigDecimalPrecision.Create('Stirling series did not converge');
    pF := pF.Multiply(zinv2F, fc);
    Inc(k);
  until False;
  sum := FxFromDecimal(sumF, W);
  // relative errors of the terms (about 4k units of 10^-wP each) and the tail
  sum.E += 3 + 100.0 * k * Power(10.0, -6);
  Result := FxAdd(t1, sum);
end;

function TreeOf(const F: array of TBigDecimal; Lo, Hi: Integer): TBigDecimal;
var
  mid: Integer;
begin
  if Hi < Lo then Exit(TBigDecimal.One);
  if Lo = Hi then Exit(F[Lo]);
  mid := (Lo + Hi) div 2;
  Result := TreeOf(F, Lo, mid) * TreeOf(F, mid + 1, Hi);
end;

function ProductTree(const F: array of TBigDecimal): TBigDecimal;
begin
  Result := TreeOf(F, 0, High(F));
end;

function ShiftTarget(W: Integer): Int64;
begin
  Result := Trunc(0.4 * W) + 8;
end;

procedure CheckPole(const X: TBigDecimal);
begin
  if X.IsInteger and (X.Sign <= 0) then
    raise EBigDecimalDomain.Create('Gamma has a pole at a non-positive integer');
end;

function GammaCore(const X: TBigDecimal; const C: TMathContext): TBigDecimal;
var
  p, w, i: Integer;
  t, r: Int64;
  z, pr, pn, one, fl, xr: TBigDecimal;
  f: array of TBigDecimal;
  l, y, q, pf, s, cs, pif, g, den, num: TFx;
  k: Int64;
  mdig: Int64;
  res: TBigDecimal;
  ld: Double;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  p := C.Precision;
  if p <= 0 then raise EBigDecimalDomain.Create('Gamma needs a finite precision');
  w := p + 25;
  repeat
    t := ShiftTarget(w);
    if X.CompareTo(TBigDecimal.Create(-t)) < 0 then
    begin
      // reflection: Gamma(x) = pi / (sin(pi x) Gamma(1 - x))
      one := TBigDecimal.One;
      z := one - X;
      fl := X.Divide(TBigDecimal.Create(2), 0, rmFloor);
      xr := X - fl * TBigDecimal.Create(2);
      pif := ConstPi(w + 4);
      num := FxRescale(pif, w);
      g := FxMul(FxFromDecimal(xr, w), num);
      SinCosOfFx(g, w, s, cs);
      ld := ApproxAbs(z) * Ln(Max(2.0, ApproxAbs(z)));
      l := LnGammaStirling(z, w + Length(IntToStr(Trunc(Min(ld, 1e15)))) + 2);
      l := FxRescale(l, w);
      y := ExpFx(l, k);
      den := FxMul(s, y);
      q := FxDiv(num, den);
      if FxRoundShifted(q, -k, C, res) then Exit(res);
    end
    else
    begin
      r := 0;
      if X.CompareTo(TBigDecimal.Create(t)) < 0 then
      begin
        r := Int64(Trunc(ApproxAbs(TBigDecimal.Create(t) - X))) + 1;
        if X.Sign < 0 then r := Trunc(ApproxAbs(TBigDecimal.Create(t) - X)) + 1;
      end;
      z := X + TBigDecimal.Create(r);
      mdig := 0;
      pn := TBigDecimal.One;
      if r > 0 then
      begin
        SetLength(f, r);
        for i := 0 to r - 1 do f[i] := X + TBigDecimal.Create(i);
        pr := ProductTree(f);
        mdig := Int64(pr.Precision) - pr.Scale;
        pn := pr.ScaleByPowerOfTen(Integer(-mdig));
      end;
      ld := ApproxAbs(z) * Ln(Max(2.0, ApproxAbs(z)));
      l := LnGammaStirling(z, w + Length(IntToStr(Trunc(Min(ld, 1e15)))) + 2);
      l := FxRescale(l, w);
      y := ExpFx(l, k);
      if r > 0 then
      begin
        pf := FxFromDecimal(pn, w);
        q := FxDiv(y, pf);
      end
      else
        q := y;
      if FxRoundShifted(q, k - mdig, C, res) then Exit(res);
    end;
    w += w div 3 + 12;
    if w > 6 * p + 1500 then
      raise EBigDecimalPrecision.Create('Gamma could not be rounded');
  until False;
end;

function Gamma(const X: TBigDecimal; const C: TMathContext): TBigDecimal;
var
  n: Int64;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  CheckPole(X);
  if X.IsInteger and (X.Sign > 0) and (X.Precision - X.Scale <= 8) then
  begin
    n := X.ToInt64;
    Result := Factorial(n - 1);
    if C.Precision > 0 then Result := Result.Round(C);
    Exit;
  end;
  Result := GammaCore(X, C);
end;

function Gamma(const X: TBigDecimal): TBigDecimal;
var
  c: TMathContext;
begin
  RequireContext(c);
  Result := Gamma(X, c);
end;

function Factorial(const X: TBigDecimal; const C: TMathContext): TBigDecimal;
var
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  Result := Gamma(X + TBigDecimal.One, C);
end;

function LnGamma(const X: TBigDecimal; const C: TMathContext): TBigDecimal;
var
  p, w, i: Integer;
  t, r: Int64;
  z, pr: TBigDecimal;
  f: array of TBigDecimal;
  l, lp: TFx;
  res: TBigDecimal;
  ld: Double;
  lead: Integer;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  if X.Sign <= 0 then raise EBigDecimalDomain.Create('LnGamma is defined for positive arguments');
  p := C.Precision;
  if p <= 0 then raise EBigDecimalDomain.Create('LnGamma needs a finite precision');
  if (X.CompareTo(TBigDecimal.One) = 0) or (X.CompareTo(TBigDecimal.Create(2)) = 0) then
    Exit(TBigDecimal.Zero);
  lead := 0;
  // near 1 and 2 the result is small
  for i := 1 to 2 do
  begin
    ld := ApproxAbs(X - TBigDecimal.Create(i));
    if (ld > 0) and (ld < 0.1) then lead := Max(lead, Trunc(-Log10(ld)) + 1);
  end;
  w := p + 25 + lead;
  repeat
    t := ShiftTarget(w);
    r := 0;
    if X.CompareTo(TBigDecimal.Create(t)) < 0 then
      r := Trunc(ApproxAbs(TBigDecimal.Create(t) - X)) + 1;
    z := X + TBigDecimal.Create(r);
    ld := ApproxAbs(z) * Ln(Max(2.0, ApproxAbs(z)));
    l := LnGammaStirling(z, w + Length(IntToStr(Trunc(Min(ld, 1e15)))) + 2);
    l := FxRescale(l, w);
    if r > 0 then
    begin
      SetLength(f, r);
      for i := 0 to r - 1 do f[i] := X + TBigDecimal.Create(i);
      pr := ProductTree(f);
      lp := LnFx(pr, w);
      l := FxSub(l, lp);
    end;
    if FxRound(l, C, res) then Exit(res);
    w += w div 3 + 12;
    if w > 6 * p + 1500 + lead then
      raise EBigDecimalPrecision.Create('LnGamma could not be rounded');
  until False;
end;

function LnGamma(const X: TBigDecimal): TBigDecimal;
var
  c: TMathContext;
begin
  RequireContext(c);
  Result := LnGamma(X, c);
end;

function LnFactorial(N: Int64; const C: TMathContext): TBigDecimal;
var
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  if N < 0 then raise EBigDecimalDomain.Create('argument must not be negative');
  Result := LnGamma(TBigDecimal.Create(N + 1), C);
end;

initialization
  InitCriticalSection(GTanLock);
finalization
  DoneCriticalSection(GTanLock);
end.
