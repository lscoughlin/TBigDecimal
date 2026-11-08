{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: fixed point, error bound, working precision
documentation: doc/design.md
notes:
  - fixed-point values with a running absolute error bound in units of the last place
  - the function library builds its series on these values and applies the Ziv check
---
}
unit BigDecimal.Fixed;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$coperators on}

interface

uses
  SysUtils, Math, BigDecimal.Types, BigDecimal, BigDecimal.Limbs;

type
  { A fixed-point value V (exactly W digits after the point) with a bound E on
    its absolute error, counted in units of 10^-W. }
  TFx = record
    V: TBigDecimal;
    E: Double;
    W: Integer;
  end;

{ Approximate magnitude as a Double (for error bookkeeping only). }
function ApproxAbs(const X: TBigDecimal): Double;

function FxFromDecimal(const X: TBigDecimal; W: Integer): TFx;
function FxFromInt(N: Int64; W: Integer): TFx;
function FxAdd(const A, B: TFx): TFx;
function FxSub(const A, B: TFx): TFx;
function FxNeg(const A: TFx): TFx;
function FxMul(const A, B: TFx): TFx;
function FxSqr(const A: TFx): TFx;
function FxMulInt(const A: TFx; N: Int64): TFx;
function FxDivInt(const A: TFx; D: Int64): TFx;
function FxDiv(const A, B: TFx): TFx;
{ Re-expresses A with scale W2 (rounds toward zero when W2 < A.W). }
function FxRescale(const A: TFx; W2: Integer): TFx;
{ Multiplies by 10^K exactly (scale shifts, then the value re-aligns to W). }
function FxShift10(const A: TFx; K: Int64): TFx;
function FxAbs(const A: TFx): Double;
{ True when the value is below one unit in the last place (it truncated to 0). }
function FxTiny(const A: TFx): Boolean; inline;

{ Tries to round the interval [V - E, V + E] to a single value. Returns True
  and the rounded Result when both ends round alike. }
function FxRound(const A: TFx; const C: TMathContext; out R: TBigDecimal): Boolean;

{ Same for a value scaled by 10^K (the shift is exact). }
function FxRoundShifted(const A: TFx; K: Int64; const C: TMathContext;
  out R: TBigDecimal): Boolean;

{ Number of decimal digits of the integer part of |x| (0 when |x| < 1). }
function IntDigits(const X: TBigDecimal): Integer;

implementation

uses
  BigDecimal.Multiply, BigDecimal.Rounding;

{ Truncating product of two values at scale W, in heap buffers. Same
  contract as the stack path, without a length limit except MaxExactDigits.
  R holds no array yet. }
function HeapMulTrunc(const va, vb: TMagView; sp: Int64; W: Integer;
  var R: TBigDecimal): Boolean;
var
  prod, tr: TLimbs;
  n, nr: Integer;
  drop: Int64;
  inexact: Boolean;
begin
  Result := False;
  if Int64(va.N) + vb.N > MaxExactDigits div 9 + 2 then Exit;
  SetLength(prod, va.N + vb.N);
  n := MulMag(va.P, va.N, vb.P, vb.N, @prod[0]);
  drop := sp - W;
  if drop = 0 then
    PutFromPtr(R, va.Neg <> vb.Neg, @prod[0], n, W)
  else
  begin
    if MagDigits(@prod[0], n) <= drop then
    begin
      PutFromPtr(R, False, nil, 0, W);
      Result := True;
      Exit;
    end;
    SetLength(tr, n + 1);
    RoundMagDrop(@prod[0], n, drop, rmDown, va.Neg <> vb.Neg, False, @tr[0], nr, inexact);
    PutFromPtr(R, va.Neg <> vb.Neg, @tr[0], nr, W);
  end;
  Result := True;
end;

{ Truncating square of a value at scale W, in heap buffers. Same contract
  as HeapMulTrunc. }
function HeapSqrTrunc(const va: TMagView; sp: Int64; W: Integer;
  var R: TBigDecimal): Boolean;
var
  prod, tr: TLimbs;
  n, nr: Integer;
  drop: Int64;
  inexact: Boolean;
begin
  Result := False;
  if Int64(va.N) * 2 > MaxExactDigits div 9 + 2 then Exit;
  SetLength(prod, 2 * va.N);
  n := SqrMag(va.P, va.N, @prod[0]);
  drop := sp - W;
  if drop = 0 then
    PutFromPtr(R, False, @prod[0], n, W)
  else
  begin
    if MagDigits(@prod[0], n) <= drop then
    begin
      PutFromPtr(R, False, nil, 0, W);
      Result := True;
      Exit;
    end;
    SetLength(tr, n + 1);
    RoundMagDrop(@prod[0], n, drop, rmDown, False, False, @tr[0], nr, inexact);
    PutFromPtr(R, False, @tr[0], nr, W);
  end;
  Result := True;
end;

{ Truncating product of two values at scale W. Uses stack buffers for short
  operands and heap buffers beyond MaxStackLimbs. Returns False when an
  operand is zero or the product scale is below W. R holds no array yet. }
function TryMulTrunc(const A, B: TBigDecimal; W: Integer; var R: TBigDecimal): Boolean;
var
  va, vb: TMagView;
  prod, tr: array[0..MaxStackLimbs] of TLimb;
  n, nr: Integer;
  sp, drop: Int64;
  inexact: Boolean;
begin
  Result := False;
  GetMagView(A, va);
  GetMagView(B, vb);
  if (va.N = 0) or (vb.N = 0) then Exit;
  sp := Int64(A.Scale) + B.Scale;
  if sp < W then Exit;
  if va.N + vb.N > MaxStackLimbs then Exit(HeapMulTrunc(va, vb, sp, W, R));
  n := MulMag(va.P, va.N, vb.P, vb.N, @prod[0]);
  drop := sp - W;
  if drop = 0 then
    PutFromPtr(R, va.Neg <> vb.Neg, @prod[0], n, W)
  else
  begin
    if MagDigits(@prod[0], n) <= drop then
    begin
      PutFromPtr(R, False, nil, 0, W);
      Result := True;
      Exit;
    end;
    RoundMagDrop(@prod[0], n, drop, rmDown, va.Neg <> vb.Neg, False, @tr[0], nr, inexact);
    PutFromPtr(R, va.Neg <> vb.Neg, @tr[0], nr, W);
  end;
  Result := True;
end;

{ Truncating square of a value at scale W. Same contract as TryMulTrunc. }
function TrySqrTrunc(const A: TBigDecimal; W: Integer; var R: TBigDecimal): Boolean;
var
  va: TMagView;
  prod, tr: array[0..MaxStackLimbs] of TLimb;
  n, nr: Integer;
  sp, drop: Int64;
  inexact: Boolean;
begin
  Result := False;
  GetMagView(A, va);
  if va.N = 0 then Exit;
  sp := Int64(A.Scale) * 2;
  if sp < W then Exit;
  if 2 * va.N > MaxStackLimbs then Exit(HeapSqrTrunc(va, sp, W, R));
  n := SqrMag(va.P, va.N, @prod[0]);
  drop := sp - W;
  if drop = 0 then
    PutFromPtr(R, False, @prod[0], n, W)
  else
  begin
    if MagDigits(@prod[0], n) <= drop then
    begin
      PutFromPtr(R, False, nil, 0, W);
      Result := True;
      Exit;
    end;
    RoundMagDrop(@prod[0], n, drop, rmDown, False, False, @tr[0], nr, inexact);
    PutFromPtr(R, False, @tr[0], nr, W);
  end;
  Result := True;
end;

{ A divided by a positive D below 2^32, truncated, at the scale of A (which is
  W). Returns False when it does not apply. R holds no array yet. }
function TryDivSmallTrunc(const A: TBigDecimal; D: Int64; W: Integer;
  var R: TBigDecimal): Boolean;
var
  va: TMagView;
  q: array[0..MaxStackLimbs] of TLimb;
  nq: Integer;
begin
  Result := False;
  if (D <= 0) or (D >= Int64(1) shl 32) or (A.Scale <> W) then Exit;
  GetMagView(A, va);
  if (va.N = 0) or (va.N > MaxStackLimbs) then Exit;
  DivSmall(va.P, va.N, UInt32(D), @q[0]);
  nq := NormLen(@q[0], va.N);
  PutFromPtr(R, va.Neg, @q[0], nq, W);
  Result := True;
end;

{ Multiplies E by 10^K for K >= 0 without Math.Power. Math.Power routes
  integral exponents through IntPower, which traps with an overflow fault
  on targets that leave that trap unmasked; the plain multiplies below
  return the 1e300 sentinel instead of overflowing. }
function ScaleUp10(E: Double; K: Integer): Double;
begin
  Result := E;
  while K >= 9 do
  begin
    if Result > 9e298 then Exit(1e300);
    Result := Result * 1e9;
    Dec(K, 9);
  end;
  while K > 0 do
  begin
    if Result > 9e306 then Exit(1e300);
    Result := Result * 10.0;
    Dec(K);
  end;
end;

function ApproxAbs(const X: TBigDecimal): Double;
var
  v: TMagView;
  m: Double;
  e10: Double;
  k: Integer;
begin
  GetMagView(X, v);
  if v.N = 0 then Exit(0.0);
  if v.N = 1 then
    m := v.P[0]
  else
    m := Double(v.P[v.N - 1]) * LimbBase + v.P[v.N - 2];
  if v.N >= 2 then e10 := (v.N - 2) * 9.0 else e10 := 0;
  e10 -= X.Scale;
  if e10 > 300 then Exit(1e300);
  if e10 < -300 then Exit(1e-300);
  { e10 holds an integral value. }
  k := Trunc(e10);
  if k >= 0 then
    Result := ScaleUp10(m, k)
  else
  begin
    Result := m;
    while k <= -9 do
    begin
      Result := Result / 1e9;
      Inc(k, 9);
    end;
    while k < 0 do
    begin
      Result := Result / 10.0;
      Inc(k);
    end;
  end;
end;

function FxFromDecimal(const X: TBigDecimal; W: Integer): TFx;
var
  t: TBigDecimal;
begin
  Result.W := W;
  t := X.SetScale(W, rmDown);
  Result.V := t;
  if t.CompareTo(X) = 0 then Result.E := 0 else Result.E := 1;
end;

function FxFromInt(N: Int64; W: Integer): TFx;
begin
  Result.W := W;
  Result.V := TBigDecimal.Create(N).SetScale(W, rmDown);
  Result.E := 0;
end;

function FxAdd(const A, B: TFx): TFx;
begin
  Result.W := A.W;
  Result.V := A.V + B.V;
  Result.E := A.E + B.E;
end;

function FxSub(const A, B: TFx): TFx;
begin
  Result.W := A.W;
  Result.V := A.V - B.V;
  Result.E := A.E + B.E;
end;

function FxNeg(const A: TFx): TFx;
begin
  Result.W := A.W;
  Result.V := -A.V;
  Result.E := A.E;
end;

function FxAbs(const A: TFx): Double;
begin
  Result := ApproxAbs(A.V);
end;

function FxTiny(const A: TFx): Boolean;
begin
  Result := A.V.IsZero;
end;

function FxMul(const A, B: TFx): TFx;
var
  ma, mb: Double;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  ma := ApproxAbs(A.V);
  mb := ApproxAbs(B.V);
  Result.W := A.W;
  if not TryMulTrunc(A.V, B.V, A.W, Result.V) then
    Result.V := (A.V * B.V).SetScale(A.W, rmDown);
  Result.E := (ma * B.E + mb * A.E + 1.0) * 1.0000001;
end;

function FxSqr(const A: TFx): TFx;
var
  ma: Double;
begin
  ma := ApproxAbs(A.V);
  Result.W := A.W;
  if not TrySqrTrunc(A.V, A.W, Result.V) then
    Result.V := A.V.Square.SetScale(A.W, rmDown);
  Result.E := (2 * ma * A.E + 1.0) * 1.0000001;
end;

function FxMulInt(const A: TFx; N: Int64): TFx;
var
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  Result.W := A.W;
  Result.V := A.V * TBigDecimal.Create(N);
  Result.E := A.E * Abs(N);
end;

function FxDivInt(const A: TFx; D: Int64): TFx;
begin
  Result.W := A.W;
  if (D > 0) and TryDivSmallTrunc(A.V, D, A.W, Result.V) then
  else if (D < 0) and TryDivSmallTrunc(A.V, -D, A.W, Result.V) then
    Result.V := -Result.V
  else
    Result.V := A.V.Divide(TBigDecimal.Create(D), A.W, rmDown);
  Result.E := A.E / Abs(D) + 1.0;
end;

function FxDiv(const A, B: TFx): TFx;
var
  mb, q: Double;
begin
  mb := ApproxAbs(B.V);
  if (mb <= 0) or (Log10(mb) + A.W <= Log10(4 * B.E + 2)) then
    raise EBigDecimalPrecision.Create('divisor is not resolved at the working precision');
  q := ApproxAbs(A.V) / mb;
  Result.W := A.W;
  Result.V := A.V.Divide(B.V, A.W, rmDown);
  Result.E := ((A.E + q * B.E) / mb * 1.0000001) + 1.0;
end;

function FxRescale(const A: TFx; W2: Integer): TFx;
begin
  Result.W := W2;
  Result.V := A.V.SetScale(W2, rmDown);
  if W2 >= A.W then
  begin
    if W2 - A.W > 280 then Result.E := 1e300
    else Result.E := ScaleUp10(A.E, W2 - A.W);
  end
  else if A.W - W2 > 280 then
    Result.E := 1.0
  else
    Result.E := A.E / ScaleUp10(1.0, A.W - W2) + 1.0;
end;

function FxShift10(const A: TFx; K: Int64): TFx;
begin
  // value * 10^K, kept at scale W by adjusting the scale field only
  Result := A;
  Result.V := A.V.ScaleByPowerOfTen(Integer(K));
end;

function BoundIfLarge(E: Double): Double; inline;
begin
  if E > 1e18 then Result := 1e18 else Result := E;
end;

function ErrDecimal(const A: TFx): TBigDecimal;
var
  e: Double;
begin
  // ceil of E as an integer number of ulps, at least 1 when E > 0
  e := BoundIfLarge(A.E);
  if e <= 0 then
    Result := TBigDecimal.Zero.SetScale(A.W, rmDown)
  else
    Result := TBigDecimal.Create(Int64(Trunc(e)) + 1).ScaleByPowerOfTen(-A.W);
end;

function FxRound(const A: TFx; const C: TMathContext; out R: TBigDecimal): Boolean;
var
  err, lo, hi, r1, r2: TBigDecimal;
begin
  if not (A.E < 1e18) then Exit(False);
  err := ErrDecimal(A);
  lo := A.V - err;
  hi := A.V + err;
  r1 := lo.Round(C);
  r2 := hi.Round(C);
  Result := r1.Identical(r2);
  if Result then R := r1;
end;

function FxRoundShifted(const A: TFx; K: Int64; const C: TMathContext;
  out R: TBigDecimal): Boolean;
var
  err, lo, hi, r1, r2: TBigDecimal;
begin
  if not (A.E < 1e18) then Exit(False);
  err := ErrDecimal(A);
  lo := (A.V - err).ScaleByPowerOfTen(Integer(K));
  hi := (A.V + err).ScaleByPowerOfTen(Integer(K));
  r1 := lo.Round(C);
  r2 := hi.Round(C);
  Result := r1.Identical(r2);
  if Result then R := r1;
end;

function IntDigits(const X: TBigDecimal): Integer;
var
  t: TBigDecimal;
begin
  t := X.Abs.SetScale(0, rmDown);
  if t.IsZero then Exit(0);
  Result := t.Precision;
end;

end.
