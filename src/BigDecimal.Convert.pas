{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: parse, print, double conversion
documentation: doc/design.md
notes:
  - text and Double conversion on raw limb magnitudes
  - ToDouble uses exact integer quotient and remainder and rounds half to even
---
}
unit BigDecimal.Convert;

{$mode objfpc}{$H+}
{$R-}{$Q-}
{$coperators on}

interface

uses
  SysUtils, Math, BigDecimal.Types, BigDecimal.Limbs;

{ Parses [+-]digits[.digits][E[+-]digits]. The unscaled digits go to Limbs
  (normalized, N = 0 for zero). Scale = fraction digits - exponent.
  Returns False when the text is malformed. Raises EBigDecimalOverflow when the
  scale does not fit in Int32. }
function ParseRaw(const S: string; out Neg: Boolean; var Limbs: TLimbs;
  out N: Integer; out Scale: Int64): Boolean;

{ Decimal digits of a normalized magnitude without leading zeros ('0' for zero). }
function RawDigits(a: PLimb; n: Integer): string;

{ Exact binary expansion of a finite Double: value = unscaled * 10^-Scale. }
procedure DoubleToRaw(X: Double; out Neg: Boolean; var Limbs: TLimbs;
  out N: Integer; out Scale: Int64);

{ Correctly rounded (half to even) conversion of unscaled * 10^-Scale. }
function RawToDouble(Neg: Boolean; a: PLimb; n: Integer; Scale: Int64): Double;

{ Multiplies the magnitude in place by 2^k or 5^k (k >= 0). The array must have
  room. Returns the new length. Helper exported for tests. }
function MulPow2(a: PLimb; n: Integer; k: Integer; r: PLimb): Integer;

implementation

uses
  BigDecimal.Divide;

function ParseRaw(const S: string; out Neg: Boolean; var Limbs: TLimbs;
  out N: Integer; out Scale: Int64): Boolean;
var
  i, len, nd, fracDigits, startDigits: Integer;
  ch: Char;
  digits: string;
  expNeg: Boolean;
  expVal: Int64;
  anyDigit: Boolean;
  seenPoint: Boolean;
  j, k, nl, firstNZ: Integer;
  chunk: UInt32;
  pos: Integer;
begin
  Result := False;
  N := 0;
  Scale := 0;
  Neg := False;
  len := Length(S);
  i := 1;
  if i > len then Exit;
  if S[i] = '+' then Inc(i)
  else if S[i] = '-' then begin Neg := True; Inc(i); end;
  digits := '';
  SetLength(digits, len);
  nd := 0;
  fracDigits := 0;
  anyDigit := False;
  seenPoint := False;
  while i <= len do
  begin
    ch := S[i];
    if (ch >= '0') and (ch <= '9') then
    begin
      Inc(nd);
      digits[nd] := ch;
      anyDigit := True;
      if seenPoint then Inc(fracDigits);
    end
    else if (ch = '.') and (not seenPoint) then
      seenPoint := True
    else
      Break;
    Inc(i);
  end;
  if not anyDigit then Exit;
  expVal := 0;
  if i <= len then
  begin
    if (S[i] <> 'e') and (S[i] <> 'E') then Exit;
    Inc(i);
    expNeg := False;
    if (i <= len) and (S[i] = '+') then Inc(i)
    else if (i <= len) and (S[i] = '-') then begin expNeg := True; Inc(i); end;
    if i > len then Exit;
    while i <= len do
    begin
      ch := S[i];
      if (ch < '0') or (ch > '9') then Exit;
      expVal := expVal * 10 + (Ord(ch) - 48);
      if expVal > 4000000000 then
        raise EBigDecimalOverflow.Create('exponent is too large');
      Inc(i);
    end;
    if expNeg then expVal := -expVal;
  end;
  Scale := Int64(fracDigits) - expVal;
  if (Scale > High(Int32)) or (Scale < Low(Int32)) then
    raise EBigDecimalOverflow.Create('scale is out of range');
  // strip leading zeros
  firstNZ := 1;
  while (firstNZ <= nd) and (digits[firstNZ] = '0') do Inc(firstNZ);
  startDigits := nd - firstNZ + 1;
  if startDigits <= 0 then
  begin
    N := 0;
    Result := True;
    Exit;
  end;
  nl := (startDigits + 8) div 9;
  if Length(Limbs) < nl then SetLength(Limbs, nl);
  pos := nd; // last digit index
  for j := 0 to nl - 1 do
  begin
    chunk := 0;
    k := pos - 8;
    if k < firstNZ then k := firstNZ;
    while k <= pos do
    begin
      chunk := chunk * 10 + UInt32(Ord(digits[k]) - 48);
      Inc(k);
    end;
    Limbs[j] := chunk;
    pos -= 9;
  end;
  N := NormLen(@Limbs[0], nl);
  Result := True;
end;

function RawDigits(a: PLimb; n: Integer): string;
var
  i, p, k: Integer;
  t: UInt32;
  tmp: string;
begin
  if n = 0 then Exit('0');
  SetLength(Result, n * 9);
  p := 0;
  // top limb without padding
  tmp := IntToStr(a[n - 1]);
  for k := 1 to Length(tmp) do
  begin
    Inc(p);
    Result[p] := tmp[k];
  end;
  for i := n - 2 downto 0 do
  begin
    t := a[i];
    for k := 8 downto 0 do
    begin
      Result[p + 1 + k] := Chr(48 + t mod 10);
      t := t div 10;
    end;
    p += 9;
  end;
  SetLength(Result, p);
end;

function MulPow2(a: PLimb; n: Integer; k: Integer; r: PLimb): Integer;
var
  step: Integer;
  i: Integer;
begin
  if r <> a then
    for i := 0 to n - 1 do r[i] := a[i];
  Result := n;
  while k > 0 do
  begin
    step := k;
    if step > 29 then step := 29;
    Result := MulSmall(r, Result, UInt32(1) shl step, r);
    k -= step;
  end;
end;

function MulPow5(a: PLimb; n: Integer; k: Integer; r: PLimb): Integer;
var
  step, i: Integer;
  f: UInt32;
begin
  if r <> a then
    for i := 0 to n - 1 do r[i] := a[i];
  Result := n;
  while k > 0 do
  begin
    step := k;
    if step > 13 then step := 13; // 5^13 = 1220703125 < 2^32
    f := 1;
    for i := 1 to step do f *= 5;
    Result := MulSmall(r, Result, f, r);
    k -= step;
  end;
end;

procedure DoubleToRaw(X: Double; out Neg: Boolean; var Limbs: TLimbs;
  out N: Integer; out Scale: Int64);
var
  bits: UInt64;
  expBits: Integer;
  mant: UInt64;
  e: Integer;
  tmp: array[0..3] of TLimb;
  nt: Integer;
  cap: Integer;
begin
  if IsNan(X) or IsInfinite(X) then
    raise EBigDecimalDomain.Create('Double is not finite');
  bits := PUInt64(@X)^;
  Neg := (bits shr 63) <> 0;
  expBits := Integer((bits shr 52) and $7FF);
  mant := bits and ((UInt64(1) shl 52) - 1);
  if expBits = 0 then
    e := -1074
  else
  begin
    mant := mant or (UInt64(1) shl 52);
    e := expBits - 1075;
  end;
  Scale := 0;
  if mant = 0 then
  begin
    N := 0;
    Exit;
  end;
  // an even mantissa with a negative exponent has a shorter exact decimal form
  while ((mant and 1) = 0) and (e < 0) do
  begin
    mant := mant shr 1;
    Inc(e);
  end;
  // mant as limbs
  nt := 0;
  while mant <> 0 do
  begin
    tmp[nt] := UInt32(mant mod LimbBase);
    mant := mant div LimbBase;
    Inc(nt);
  end;
  cap := nt + (Abs(e) * 3) div 29 + 8;
  if e < 0 then
    cap := nt + (-e * 233) div 1000 div 9 * 1 + (-e) div 13 + 8 + (-e) div 3;
  if Length(Limbs) < cap then SetLength(Limbs, cap);
  Move(tmp[0], Limbs[0], nt * SizeOf(TLimb));
  if e >= 0 then
  begin
    N := MulPow2(@Limbs[0], nt, e, @Limbs[0]);
    Scale := 0;
  end
  else
  begin
    N := MulPow5(@Limbs[0], nt, -e, @Limbs[0]);
    Scale := -e;
  end;
end;

{ Number of bits in a UInt64 (0 for zero). }
function BitLen64(x: UInt64): Integer;
begin
  Result := 0;
  while x <> 0 do
  begin
    Inc(Result);
    x := x shr 1;
  end;
end;

{ Approximate log2 of a normalized non-zero magnitude. }
function Log2Mag(a: PLimb; n: Integer): Double;
var
  v: Double;
  i, used: Integer;
begin
  v := 0;
  used := 0;
  i := n - 1;
  while (i >= 0) and (used < 3) do
  begin
    v := v * LimbBase + a[i];
    Dec(i);
    Inc(used);
  end;
  Result := Log2(v) + (i + 1) * 29.897352853986263;
end;

function RawToDouble(Neg: Boolean; a: PLimb; n: Integer; Scale: Int64): Double;
var
  num, den, qb, rb: TLimbs;
  nn, nd, nq, nr, k, i, cap: Integer;
  l2n, l2d: Double;
  kk: Int64;
  q: UInt64;
  sticky: Boolean;
  e2: Int64;
  bl, p, shift: Integer;
  m, remb, half: UInt64;
  pw: TLimbs;
  npw: Integer;
  r: Double;
  unscaledExp: Int64;
begin
  if n = 0 then Exit(0.0);
  // quick range checks on the decimal exponent
  unscaledExp := Int64(Round(Log2Mag(a, n) * 0.30102999566398)) - Scale;
  if unscaledExp > 400 then
  begin
    if Neg then Exit(NegInfinity) else Exit(Infinity);
  end;
  if unscaledExp < -400 then
  begin
    if Neg then Exit(-0.0) else Exit(0.0);
  end;
  // N / D with N = a * 10^max(-Scale,0), D = 10^max(Scale,0)
  if Scale <= 0 then
  begin
    cap := n + Integer((-Scale) div 9) + 2;
    SetLength(num, cap);
    nn := MulPow10(a, n, -Scale, @num[0]);
    SetLength(den, 1);
    den[0] := 1;
    nd := 1;
  end
  else
  begin
    SetLength(num, n);
    Move(a^, num[0], n * SizeOf(TLimb));
    nn := n;
    cap := Integer(Scale div 9) + 2;
    SetLength(den, cap);
    for i := 0 to cap - 1 do den[i] := 0;
    den[0] := 1;
    nd := MulPow10(@den[0], 1, Scale, @den[0]);
  end;
  l2n := Log2Mag(@num[0], nn);
  l2d := Log2Mag(@den[0], nd);
  kk := 62 - Round(l2n - l2d);
  // scale numerator by 2^kk when kk >= 0, else denominator by 2^-kk
  if kk >= 0 then
  begin
    SetLength(qb, nn + Integer(kk div 29) + 2);
    nn := MulPow2(@num[0], nn, Integer(kk), @qb[0]);
    num := qb;
    qb := nil;
  end
  else
  begin
    SetLength(qb, nd + Integer((-kk) div 29) + 2);
    nd := MulPow2(@den[0], nd, Integer(-kk), @qb[0]);
    den := qb;
    qb := nil;
  end;
  SetLength(qb, nn + 2);
  SetLength(rb, nd + 1);
  if CmpMag(@num[0], nn, @den[0], nd) < 0 then
  begin
    q := 0;
    sticky := True;
  end
  else
  begin
    DivRemMag(@num[0], nn, @den[0], nd, @qb[0], nq, @rb[0], nr);
    q := 0;
    if nq > 3 then
      // estimate was off by a lot; the quotient does not fit in 64 bits
      q := High(UInt64) shr 1
    else
      for i := nq - 1 downto 0 do q := q * LimbBase + qb[i];
    sticky := nr <> 0;
  end;
  if q = 0 then
  begin
    if Neg then Exit(-0.0) else Exit(0.0);
  end;
  e2 := -kk;
  bl := BitLen64(q);
  // exponent of the value's leading bit
  p := 53;
  if (bl - 1 + e2) < -1022 then
    p := 53 - Integer(-1022 - (bl - 1 + e2));
  if (bl - 1 + e2) >= 1024 then
  begin
    if Neg then Exit(NegInfinity) else Exit(Infinity);
  end;
  shift := bl - p;
  if shift <= 0 then
  begin
    m := q;
    shift := 0;
  end
  else if shift > bl then
  begin
    m := 0;
  end
  else
  begin
    m := q shr shift;
    remb := q and ((UInt64(1) shl shift) - 1);
    half := UInt64(1) shl (shift - 1);
    if (remb > half) or ((remb = half) and (sticky or ((m and 1) = 1))) then
      Inc(m);
  end;
  if shift > bl then
    r := 0.0
  else
    r := Ldexp(Double(m), Integer(shift + e2));
  if Neg then r := -r;
  Result := r;
end;

end.
