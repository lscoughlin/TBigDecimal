{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: bigdecimal, record, arithmetic
documentation: doc/design.md
notes:
  - the TBigDecimal advanced record
  - small values use an Int64, large values use base 10^9 limbs
  - a value is immutable after construction
---
}
unit BigDecimal;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$R-}{$Q-}
{$coperators on}

interface

uses
  SysUtils, BigDecimal.Types, BigDecimal.Limbs;

type
  { TBigDecimal }

  TBigDecimal = record
  private
    FSmall: Int64;       // the unscaled value when FLimbs is nil
    FLimbs: TLimbs;      // magnitude, base 10^9, least significant first
    FScale: Int32;
    FSign: Int8;         // -1, 0, +1, valid when FLimbs is not nil
    function GetSign: Integer;
    function GetPrecision: Integer;
    function GetIsZero: Boolean;
  public
    // creation
    class function Create(Value: Int64): TBigDecimal; overload; static;
    class function Create(Value: Double): TBigDecimal; overload; static;
    class function Create(const Value: string): TBigDecimal; overload; static;
    class function Create(const Unscaled: TBigDecimal; AScale: Integer): TBigDecimal; overload; static;
    class function FromString(const Value: string): TBigDecimal; static;
    class function FromUInt64(Value: UInt64): TBigDecimal; static;
    class function FromDouble(Value: Double): TBigDecimal; static;
    class function FromDoubleExact(Value: Double): TBigDecimal; static;
    class function TryParse(const Value: string; out R: TBigDecimal): Boolean; static;
    class function Zero: TBigDecimal; static;
    class function One: TBigDecimal; static;
    class function Ten: TBigDecimal; static;

    // arithmetic operators (a default thread context rounds the result)
    class operator +(const A, B: TBigDecimal): TBigDecimal;
    class operator -(const A, B: TBigDecimal): TBigDecimal;
    class operator *(const A, B: TBigDecimal): TBigDecimal;
    class operator /(const A, B: TBigDecimal): TBigDecimal;
    class operator -(const Value: TBigDecimal): TBigDecimal;
    class operator +(const Value: TBigDecimal): TBigDecimal;

    // comparison operators
    class operator =(const A, B: TBigDecimal): Boolean;
    class operator <>(const A, B: TBigDecimal): Boolean;
    class operator >(const A, B: TBigDecimal): Boolean;
    class operator <(const A, B: TBigDecimal): Boolean;
    class operator >=(const A, B: TBigDecimal): Boolean;
    class operator <=(const A, B: TBigDecimal): Boolean;

    // conversion operators
    class operator :=(Value: Int64): TBigDecimal;
    class operator :=(Value: Integer): TBigDecimal;
    class operator Explicit(const Value: TBigDecimal): Double;
    class operator Explicit(const Value: TBigDecimal): string;

    // explicit-context arithmetic
    function Add(const B: TBigDecimal; const C: TMathContext): TBigDecimal;
    function Subtract(const B: TBigDecimal; const C: TMathContext): TBigDecimal;
    function Multiply(const B: TBigDecimal; const C: TMathContext): TBigDecimal;
    function Divide(const B: TBigDecimal): TBigDecimal; overload;
    function Divide(const B: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
    function Divide(const B: TBigDecimal; AScale: Integer; Mode: TRoundingMode): TBigDecimal; overload;
    function DivideToIntegralValue(const B: TBigDecimal): TBigDecimal;
    function Remainder(const B: TBigDecimal): TBigDecimal;
    procedure DivRem(const B: TBigDecimal; out Quotient, Rem: TBigDecimal);
    function Abs: TBigDecimal;
    function Negate: TBigDecimal;
    function Plus(const C: TMathContext): TBigDecimal; overload;
    function Plus: TBigDecimal; overload;
    function Square: TBigDecimal;

    // scale and rounding
    function SetScale(NewScale: Integer; Mode: TRoundingMode): TBigDecimal;
    function Round(const C: TMathContext): TBigDecimal; overload;
    function Round: TBigDecimal; overload;
    function StripTrailingZeros: TBigDecimal;
    function MovePointLeft(N: Integer): TBigDecimal;
    function MovePointRight(N: Integer): TBigDecimal;
    function ScaleByPowerOfTen(N: Integer): TBigDecimal;
    function UnscaledValue: TBigDecimal;

    // comparison
    function CompareTo(const B: TBigDecimal): Integer;
    function Hash: Cardinal;
    function Identical(const B: TBigDecimal): Boolean;
    class function Min(const A, B: TBigDecimal): TBigDecimal; static;
    class function Max(const A, B: TBigDecimal): TBigDecimal; static;

    // conversion
    function ToString: string;
    function ToPlainString: string;
    function ToEngineeringString: string;
    function ToInt64: Int64;
    function ToDouble: Double;
    function IsInteger: Boolean;

    property Sign: Integer read GetSign;
    property Scale: Integer read FScale;
    property Precision: Integer read GetPrecision;
    property IsZero: Boolean read GetIsZero;
  end;

  PBigDecimal = ^TBigDecimal;
  TBigDecimalArray = array of TBigDecimal;

{ Internal access for sibling units (Math, Combinatorics, ...). }
type
  TMagView = record
    P: PLimb;
    N: Integer;
    Neg: Boolean;
    Buf: array[0..2] of TLimb;
  end;

const
  { Magnitudes up to this many limbs use stack buffers in the arithmetic. }
  MaxStackLimbs = 48;

procedure GetMagView(const X: TBigDecimal; var V: TMagView);
{ Stores a value built from the magnitude at P (not consumed) in R, which holds
  no array yet. At most one allocation. }
procedure PutFromPtr(var R: TBigDecimal; Neg: Boolean; P: PLimb; n: Integer; Scale: Int64);
{ Rounds the magnitude at P (N limbs, N at most MaxStackLimbs, scale Scale) to
  the context (precision above zero) and stores the value in R, which holds no
  array yet. Sticky tells that a non-zero part lies below the magnitude.
  Inexact tells that the result differs from the exact value. }
procedure PutRounded(var R: TBigDecimal; Neg: Boolean; P: PLimb; N: Integer;
  Scale: Int64; const C: TMathContext; Sticky: Boolean; out Inexact: Boolean);
{ Builds a value from a magnitude. L is trimmed to n limbs and is consumed. }
function MakeFromMag(Neg: Boolean; var L: TLimbs; n: Integer; Scale: Int64): TBigDecimal;
{ Product of an unscaled magnitude view with 10^k, as a limb array. }
function ScaledMag(const V: TMagView; k: Int64; out L: TLimbs): Integer;

implementation

uses
  BigDecimal.Multiply, BigDecimal.Divide, BigDecimal.Rounding, BigDecimal.Convert;

const
  MaxSmallMul = 3037000499;

procedure GetMagView(const X: TBigDecimal; var V: TMagView);
var
  m: UInt64;
  k: Integer;
begin
  if X.FLimbs <> nil then
  begin
    V.P := @X.FLimbs[0];
    V.N := Length(X.FLimbs);
    V.Neg := X.FSign < 0;
    Exit;
  end;
  V.P := @V.Buf[0];
  V.Neg := X.FSmall < 0;
  if X.FSmall = 0 then
  begin
    V.N := 0;
    Exit;
  end;
  if X.FSmall < 0 then
    m := UInt64(-(X.FSmall + 1)) + 1
  else
    m := UInt64(X.FSmall);
  k := 0;
  while m <> 0 do
  begin
    V.Buf[k] := UInt32(m mod LimbBase);
    m := m div LimbBase;
    Inc(k);
  end;
  V.N := k;
end;

function CheckScale(Scale: Int64): Int32;
begin
  if (Scale > High(Int32)) or (Scale < Low(Int32)) then
    raise EBigDecimalOverflow.Create('scale is out of range');
  Result := Int32(Scale);
end;

function MakeFromMag(Neg: Boolean; var L: TLimbs; n: Integer; Scale: Int64): TBigDecimal;
var
  m: UInt64;
  limit: UInt64;
  fits: Boolean;
begin
  Result.FScale := CheckScale(Scale);
  if n > 0 then
    n := NormLen(@L[0], n);
  if n = 0 then
  begin
    Result.FSmall := 0;
    Result.FLimbs := nil;
    Result.FSign := 0;
    Exit;
  end;
  fits := False;
  m := 0;
  if (n < 3) or ((n = 3) and (L[2] <= 9)) then
  begin
    m := 0;
    if n >= 3 then m := UInt64(L[2]) * 1000000000000000000;
    if n >= 2 then m += UInt64(L[1]) * LimbBase;
    m += L[0];
    if Neg then limit := UInt64(1) shl 63 else limit := (UInt64(1) shl 63) - 1;
    fits := m <= limit;
  end;
  if fits then
  begin
    if Neg then
      Result.FSmall := -Int64(m - 1) - 1
    else
      Result.FSmall := Int64(m);
    Result.FLimbs := nil;
    if Neg then Result.FSign := -1 else Result.FSign := 1;
  end
  else
  begin
    if Length(L) <> n then SetLength(L, n);
    Result.FLimbs := L;
    Result.FSmall := 0;
    if Neg then Result.FSign := -1 else Result.FSign := 1;
  end;
end;

function SmallResult(V: Int64; Scale: Int64): TBigDecimal; inline;
begin
  Result.FSmall := V;
  Result.FLimbs := nil;
  Result.FScale := CheckScale(Scale);
  if V < 0 then Result.FSign := -1
  else if V > 0 then Result.FSign := 1
  else Result.FSign := 0;
end;

type
  PMathContext = ^TMathContext;


{ Stores a value built from the magnitude at P (not consumed) in R. At most one
  allocation. R is a result that holds no array yet. }
procedure PutFromPtr(var R: TBigDecimal; Neg: Boolean; P: PLimb; n: Integer; Scale: Int64);
var
  m, limit: UInt64;
  fits: Boolean;
begin
  R.FScale := CheckScale(Scale);
  if n > 0 then
    n := NormLen(P, n);
  if n = 0 then
  begin
    R.FSmall := 0;
    R.FLimbs := nil;
    R.FSign := 0;
    Exit;
  end;
  fits := False;
  m := 0;
  if (n < 3) or ((n = 3) and (P[2] <= 9)) then
  begin
    if n >= 3 then m := UInt64(P[2]) * 1000000000000000000;
    if n >= 2 then m += UInt64(P[1]) * LimbBase;
    m += P[0];
    if Neg then limit := UInt64(1) shl 63 else limit := (UInt64(1) shl 63) - 1;
    fits := m <= limit;
  end;
  if Neg then R.FSign := -1 else R.FSign := 1;
  if fits then
  begin
    if Neg then
      R.FSmall := -Int64(m - 1) - 1
    else
      R.FSmall := Int64(m);
    R.FLimbs := nil;
  end
  else
  begin
    R.FSmall := 0;
    SetLength(R.FLimbs, n);
    Move(P^, R.FLimbs[0], n * SizeOf(TLimb));
  end;
end;

{ Rounds the magnitude at P (N limbs, N at most MaxStackLimbs, scale Scale) to
  the context and stores the value in R. Sticky tells that a non-zero part lies
  below the magnitude. Inexact tells that the result differs from the exact
  value. The context has a precision above zero. }
procedure PutRounded(var R: TBigDecimal; Neg: Boolean; P: PLimb; N: Integer;
  Scale: Int64; const C: TMathContext; Sticky: Boolean; out Inexact: Boolean);
var
  buf, buf2: array[0..MaxStackLimbs] of TLimb;
  drop: Int64;
  nr: Integer;
begin
  Inexact := Sticky;
  N := NormLen(P, N);
  if N = 0 then
  begin
    PutFromPtr(R, Neg, P, 0, Scale);
    Exit;
  end;
  drop := MagDigits(P, N) - C.Precision;
  if drop <= 0 then
  begin
    PutFromPtr(R, Neg, P, N, Scale);
    Exit;
  end;
  RoundMagDrop(P, N, drop, C.RoundingMode, Neg, Sticky, @buf[0], nr, Inexact);
  Scale -= drop;
  if MagDigits(@buf[0], nr) > C.Precision then
  begin
    // the rounded magnitude became a power of ten: drop one more zero digit
    nr := DivPow10(@buf[0], nr, 1, @buf2[0]);
    Dec(Scale);
    PutFromPtr(R, Neg, @buf2[0], nr, Scale);
    Exit;
  end;
  PutFromPtr(R, Neg, @buf[0], nr, Scale);
end;

procedure PutSmall(var R: TBigDecimal; V: Int64; Scale: Int64); inline;
begin
  R.FSmall := V;
  R.FLimbs := nil;
  R.FScale := CheckScale(Scale);
  if V < 0 then R.FSign := -1
  else if V > 0 then R.FSign := 1
  else R.FSign := 0;
end;

{ Magnitude of V times 10^k into a fresh array. Returns the length. }
function ScaledMag(const V: TMagView; k: Int64; out L: TLimbs): Integer;
begin
  if V.N = 0 then
  begin
    L := nil;
    Exit(0);
  end;
  if k > MaxExactDigits + 1000 then
    raise EBigDecimalOverflow.Create('result is too large');
  SetLength(L, V.N + Integer(k div LimbDigits) + 2);
  if k = 0 then
  begin
    Move(V.P^, L[0], V.N * SizeOf(TLimb));
    Result := V.N;
  end
  else
    Result := MulPow10(V.P, V.N, k, @L[0]);
end;

function PrecisionOf(const X: TBigDecimal): Integer;
var
  m: UInt64;
begin
  if X.FLimbs <> nil then
    Exit(Integer(MagDigits(@X.FLimbs[0], Length(X.FLimbs))));
  if X.FSmall = 0 then Exit(1);
  if X.FSmall < 0 then m := UInt64(-(X.FSmall + 1)) + 1 else m := UInt64(X.FSmall);
  Result := DigitCount64(m);
end;

{ ----- creation ----- }

class function TBigDecimal.Create(Value: Int64): TBigDecimal;
begin
  Result := SmallResult(Value, 0);
end;

class function TBigDecimal.FromUInt64(Value: UInt64): TBigDecimal;
var
  L: TLimbs;
  n: Integer;
begin
  if Value <= UInt64(High(Int64)) then Exit(SmallResult(Int64(Value), 0));
  SetLength(L, 3);
  n := 0;
  while Value <> 0 do
  begin
    L[n] := UInt32(Value mod LimbBase);
    Value := Value div LimbBase;
    Inc(n);
  end;
  Result := MakeFromMag(False, L, n, 0);
end;

class function TBigDecimal.TryParse(const Value: string; out R: TBigDecimal): Boolean;
var
  neg: Boolean;
  L: TLimbs;
  n: Integer;
  sc: Int64;
begin
  R := Zero;
  Result := ParseRaw(Value, neg, L, n, sc);
  if Result then
    R := MakeFromMag(neg, L, n, sc);
end;

class function TBigDecimal.Create(const Value: string): TBigDecimal;
begin
  if not TryParse(Value, Result) then
    raise EBigDecimalParse.CreateFmt('invalid decimal text: "%s"', [Value]);
end;

class function TBigDecimal.FromString(const Value: string): TBigDecimal;
begin
  Result := Create(Value);
end;

class function TBigDecimal.Create(const Unscaled: TBigDecimal; AScale: Integer): TBigDecimal;
begin
  Result := Unscaled;
  Result.FScale := AScale;
end;

class function TBigDecimal.FromDoubleExact(Value: Double): TBigDecimal;
var
  neg: Boolean;
  L: TLimbs;
  n: Integer;
  sc: Int64;
begin
  DoubleToRaw(Value, neg, L, n, sc);
  Result := MakeFromMag(neg, L, n, sc);
end;

class function TBigDecimal.FromDouble(Value: Double): TBigDecimal;
var
  ex, c: TBigDecimal;
  digits: Integer;
begin
  ex := FromDoubleExact(Value);
  if ex.IsZero then Exit(ex.SetScale(0, rmDown));
  for digits := 15 to 16 do
  begin
    c := ex.Round(TMathContext.Make(digits, rmHalfEven)).StripTrailingZeros;
    if c.ToDouble = Value then Exit(c);
  end;
  Result := ex.Round(TMathContext.Make(17, rmHalfEven)).StripTrailingZeros;
end;

class function TBigDecimal.Create(Value: Double): TBigDecimal;
begin
  Result := FromDouble(Value);
end;

class function TBigDecimal.Zero: TBigDecimal;
begin
  Result := SmallResult(0, 0);
end;

class function TBigDecimal.One: TBigDecimal;
begin
  Result := SmallResult(1, 0);
end;

class function TBigDecimal.Ten: TBigDecimal;
begin
  Result := SmallResult(10, 0);
end;

{ ----- accessors ----- }

function TBigDecimal.GetSign: Integer;
begin
  if FLimbs <> nil then Exit(FSign);
  if FSmall > 0 then Result := 1
  else if FSmall < 0 then Result := -1
  else Result := 0;
end;

function TBigDecimal.GetPrecision: Integer;
begin
  Result := PrecisionOf(Self);
end;

function TBigDecimal.GetIsZero: Boolean;
begin
  Result := (FLimbs = nil) and (FSmall = 0);
end;

function TBigDecimal.IsInteger: Boolean;
var
  v: TMagView;
begin
  if IsZero or (FScale <= 0) then Exit(True);
  GetMagView(Self, v);
  Result := MagLowZero(v.P, v.N, FScale);
end;

function TBigDecimal.UnscaledValue: TBigDecimal;
begin
  Result := Self;
  Result.FScale := 0;
end;

{ ----- add and subtract ----- }

function SmallMagnitude(V: Int64): UInt64; inline;
begin
  if V < 0 then Result := UInt64(-(V + 1)) + 1 else Result := UInt64(V);
end;

function ApplyCtx(const X: TBigDecimal; const c: TMathContext): TBigDecimal; inline;
begin
  if c.Precision <= 0 then
    Result := X
  // an Int64 value that has no more digits than the precision needs no rounding
  else if (X.FLimbs = nil) and (c.Precision >= 19) then
    Result := X
  else if (X.FLimbs = nil) and (SmallMagnitude(X.FSmall) < Pow10_64[c.Precision]) then
    Result := X
  else
    Result := X.Round(c);
end;


function WithCtx(const X: TBigDecimal; Ctx: PMathContext): TBigDecimal; inline;
begin
  if Ctx = nil then Result := X else Result := ApplyCtx(X, Ctx^);
end;

{ Fast paths of A + B or A - B: Int64 operands, and magnitudes of up to
  MaxStackLimbs limbs in stack buffers. A non-nil Ctx with a precision above
  zero rounds the result once. Returns False when no fast path applies. R holds
  no array yet. The routine has no managed local, so it needs no finalization. }
function TryAddFast(const A, B: TBigDecimal; NegateB: Boolean; Ctx: PMathContext;
  var R: TBigDecimal): Boolean;
var
  va, vb: TMagView;
  pa, pb: PLimb;
  na, nb, nr, c: Integer;
  sa, sb, s: Int64;
  negA, negB, rounding: Boolean;
  x, y, z: Int64;
  d: Integer;
  ba, bb, br: array[0..MaxStackLimbs + 2] of TLimb;
  inexact: Boolean;
begin
  Result := True;
  sa := A.FScale;
  sb := B.FScale;
  rounding := (Ctx <> nil) and (Ctx^.Precision > 0);
  if (A.FLimbs = nil) and (B.FLimbs = nil) then
  begin
    x := A.FSmall;
    y := B.FSmall;
    if sa = sb then
      d := 0
    else if sa > sb then
    begin
      d := Integer(sa - sb);
      if (d <= 18) and (Abs(y) <= High(Int64) div Pow10_64[d]) then
        y := y * Int64(Pow10_64[d])
      else d := -1;
    end
    else
    begin
      d := Integer(sb - sa);
      if (d <= 18) and (Abs(x) <= High(Int64) div Pow10_64[d]) then
        x := x * Int64(Pow10_64[d])
      else d := -1;
    end;
    if d >= 0 then
    begin
      if NegateB then
      begin
        if y = Low(Int64) then d := -1 else y := -y;
      end;
      if d >= 0 then
      begin
        z := x + y;
        if ((x xor z) and (y xor z)) >= 0 then
        begin
          if sa > sb then s := sa else s := sb;
          if rounding and (Ctx^.Precision < 19) and
             (SmallMagnitude(z) >= Pow10_64[Ctx^.Precision]) then
            R := SmallResult(z, s).Round(Ctx^)
          else
            PutSmall(R, z, s);
          Exit;
        end;
      end;
    end;
  end;
  if sa > sb then s := sa else s := sb;
  if (s - sa >= 9 * MaxStackLimbs) or (s - sb >= 9 * MaxStackLimbs) then
    Exit(False);
  GetMagView(A, va);
  GetMagView(B, vb);
  if (va.N = 0) or (vb.N = 0) then Exit(False);
  if (va.N + Integer((s - sa) div LimbDigits) + 2 > MaxStackLimbs) or
     (vb.N + Integer((s - sb) div LimbDigits) + 2 > MaxStackLimbs) then
    Exit(False);
  negA := va.Neg;
  negB := vb.Neg;
  if NegateB then negB := not negB;
  pa := va.P; na := va.N;
  pb := vb.P; nb := vb.N;
  if sa < s then
  begin
    na := MulPow10(pa, na, s - sa, @ba[0]);
    pa := @ba[0];
  end;
  if sb < s then
  begin
    nb := MulPow10(pb, nb, s - sb, @bb[0]);
    pb := @bb[0];
  end;
  if negA = negB then
  begin
    nr := AddMag(pa, na, pb, nb, @br[0]);
    c := 0;
  end
  else
  begin
    c := CmpMag(pa, na, pb, nb);
    if c = 0 then
    begin
      PutFromPtr(R, False, nil, 0, s);
      Exit;
    end;
    if c > 0 then
      nr := SubMag(pa, na, pb, nb, @br[0])
    else
    begin
      nr := SubMag(pb, nb, pa, na, @br[0]);
      negA := negB;
    end;
  end;
  if rounding then
    PutRounded(R, negA, @br[0], nr, s, Ctx^, False, inexact)
  else
    PutFromPtr(R, negA, @br[0], nr, s);
end;

function AddCoreX(const A, B: TBigDecimal; NegateB: Boolean; Ctx: PMathContext): TBigDecimal;
var
  va, vb: TMagView;
  la, lb, r: TLimbs;
  pa, pb: PLimb;
  na, nb, nr, c: Integer;
  sa, sb, s: Int64;
  negA, negB: Boolean;
begin
  if TryAddFast(A, B, NegateB, Ctx, Result) then Exit;
  sa := A.FScale;
  sb := B.FScale;
  GetMagView(A, va);
  GetMagView(B, vb);
  negA := va.Neg;
  negB := vb.Neg;
  if NegateB then negB := (not negB) and (vb.N > 0);
  if sa > sb then s := sa else s := sb;
  if va.N = 0 then begin negA := False; end;
  // align
  pa := va.P; na := va.N;
  pb := vb.P; nb := vb.N;
  if (sa < s) and (na > 0) then
  begin
    na := ScaledMag(va, s - sa, la);
    pa := @la[0];
  end;
  if (sb < s) and (nb > 0) then
  begin
    nb := ScaledMag(vb, s - sb, lb);
    pb := @lb[0];
  end;
  if na = 0 then
  begin
    SetLength(r, nb);
    if nb > 0 then Move(pb^, r[0], nb * SizeOf(TLimb));
    Exit(WithCtx(MakeFromMag(negB, r, nb, s), Ctx));
  end;
  if nb = 0 then
  begin
    SetLength(r, na);
    Move(pa^, r[0], na * SizeOf(TLimb));
    Exit(WithCtx(MakeFromMag(negA, r, na, s), Ctx));
  end;
  if negA = negB then
  begin
    if na > nb then SetLength(r, na + 1) else SetLength(r, nb + 1);
    nr := AddMag(pa, na, pb, nb, @r[0]);
    Exit(WithCtx(MakeFromMag(negA, r, nr, s), Ctx));
  end;
  c := CmpMag(pa, na, pb, nb);
  if c = 0 then
  begin
    r := nil;
    Exit(MakeFromMag(False, r, 0, s));
  end;
  if c > 0 then
  begin
    SetLength(r, na);
    nr := SubMag(pa, na, pb, nb, @r[0]);
    Result := WithCtx(MakeFromMag(negA, r, nr, s), Ctx);
  end
  else
  begin
    SetLength(r, nb);
    nr := SubMag(pb, nb, pa, na, @r[0]);
    Result := WithCtx(MakeFromMag(negB, r, nr, s), Ctx);
  end;
end;


function AddCore(const A, B: TBigDecimal; NegateB: Boolean): TBigDecimal;
begin
  Result := AddCoreX(A, B, NegateB, nil);
end;

function ApplyDefault(const X: TBigDecimal): TBigDecimal; inline;
var
  c: TMathContext;
begin
  if EffectiveContext(c) then
    Result := ApplyCtx(X, c)
  else
    Result := X;
end;

class operator TBigDecimal.+(const A, B: TBigDecimal): TBigDecimal;
var
  c: TMathContext;
begin
  if EffectiveContext(c) then
  begin
    if not TryAddFast(A, B, False, @c, Result) then Result := AddCoreX(A, B, False, @c);
  end
  else if not TryAddFast(A, B, False, nil, Result) then
    Result := AddCoreX(A, B, False, nil);
end;

class operator TBigDecimal.-(const A, B: TBigDecimal): TBigDecimal;
var
  c: TMathContext;
begin
  if EffectiveContext(c) then
  begin
    if not TryAddFast(A, B, True, @c, Result) then Result := AddCoreX(A, B, True, @c);
  end
  else if not TryAddFast(A, B, True, nil, Result) then
    Result := AddCoreX(A, B, True, nil);
end;

function TBigDecimal.Add(const B: TBigDecimal; const C: TMathContext): TBigDecimal;
begin
  if not TryAddFast(Self, B, False, @C, Result) then Result := AddCoreX(Self, B, False, @C);
end;

function TBigDecimal.Subtract(const B: TBigDecimal; const C: TMathContext): TBigDecimal;
begin
  if not TryAddFast(Self, B, True, @C, Result) then Result := AddCoreX(Self, B, True, @C);
end;

class operator TBigDecimal.-(const Value: TBigDecimal): TBigDecimal;
begin
  Result := Value.Negate;
end;

class operator TBigDecimal.+(const Value: TBigDecimal): TBigDecimal;
begin
  Result := Value;
end;

function TBigDecimal.Negate: TBigDecimal;
begin
  Result := Self;
  if Result.FLimbs <> nil then
    Result.FSign := -Result.FSign
  else if Result.FSmall = Low(Int64) then
  begin
    // magnitude 2^63 does not fit a positive Int64: use the limb form
    Result := AddCore(SmallResult(0, FScale), Self, True);
  end
  else
  begin
    Result.FSmall := -Result.FSmall;
    Result.FSign := -Result.FSign;
  end;
end;

function TBigDecimal.Abs: TBigDecimal;
begin
  if Sign < 0 then Result := Negate else Result := Self;
end;

function TBigDecimal.Plus(const C: TMathContext): TBigDecimal;
begin
  Result := Round(C);
end;

function TBigDecimal.Plus: TBigDecimal;
begin
  Result := ApplyDefault(Self);
end;

{ ----- multiply ----- }

{ Fast paths of A * B: Int64 operands, and products of up to MaxStackLimbs
  limbs in a stack buffer. A non-nil Ctx with a precision above zero rounds the
  result once. Returns False when no fast path applies. R holds no array yet.
  The routine has no managed local, so it needs no finalization. }
function TryMulFast(const A, B: TBigDecimal; Ctx: PMathContext;
  var R: TBigDecimal): Boolean;
var
  va, vb: TMagView;
  nr: Integer;
  x, y, z: Int64;
  s: Int64;
  buf: array[0..MaxStackLimbs] of TLimb;
  inexact, rounding: Boolean;
begin
  Result := True;
  rounding := (Ctx <> nil) and (Ctx^.Precision > 0);
  s := Int64(A.FScale) + B.FScale;
  if (A.FLimbs = nil) and (B.FLimbs = nil) then
  begin
    x := A.FSmall;
    y := B.FSmall;
    if (x > -MaxSmallMul) and (x < MaxSmallMul) and
       (y > -MaxSmallMul) and (y < MaxSmallMul) then
    begin
      z := x * y;
      if rounding and (Ctx^.Precision < 19) and
         (SmallMagnitude(z) >= Pow10_64[Ctx^.Precision]) then
        R := SmallResult(z, s).Round(Ctx^)
      else
        PutSmall(R, z, s);
      Exit;
    end;
  end;
  GetMagView(A, va);
  GetMagView(B, vb);
  if (va.N = 0) or (vb.N = 0) or (va.N + vb.N > MaxStackLimbs) then
    Exit(False);
  nr := MulMag(va.P, va.N, vb.P, vb.N, @buf[0]);
  if rounding then
    PutRounded(R, va.Neg <> vb.Neg, @buf[0], nr, s, Ctx^, False, inexact)
  else
    PutFromPtr(R, va.Neg <> vb.Neg, @buf[0], nr, s);
end;

{ A * B for any size. }
function MulCoreX(const A, B: TBigDecimal; Ctx: PMathContext): TBigDecimal;
var
  va, vb: TMagView;
  r: TLimbs;
  nr: Integer;
  s: Int64;
begin
  if TryMulFast(A, B, Ctx, Result) then Exit;
  s := Int64(A.FScale) + B.FScale;
  GetMagView(A, va);
  GetMagView(B, vb);
  if (va.N = 0) or (vb.N = 0) then
  begin
    r := nil;
    Exit(MakeFromMag(False, r, 0, s));
  end;
  SetLength(r, va.N + vb.N);
  nr := MulMag(va.P, va.N, vb.P, vb.N, @r[0]);
  Result := WithCtx(MakeFromMag(va.Neg <> vb.Neg, r, nr, s), Ctx);
end;

function MulCore(const A, B: TBigDecimal): TBigDecimal;
begin
  Result := MulCoreX(A, B, nil);
end;

class operator TBigDecimal.*(const A, B: TBigDecimal): TBigDecimal;
var
  c: TMathContext;
begin
  if EffectiveContext(c) then
  begin
    if not TryMulFast(A, B, @c, Result) then Result := MulCoreX(A, B, @c);
  end
  else if not TryMulFast(A, B, nil, Result) then
    Result := MulCoreX(A, B, nil);
end;

function TBigDecimal.Multiply(const B: TBigDecimal; const C: TMathContext): TBigDecimal;
begin
  if not TryMulFast(Self, B, @C, Result) then Result := MulCoreX(Self, B, @C);
end;

function TBigDecimal.Square: TBigDecimal;
var
  v: TMagView;
  r: TLimbs;
  nr: Integer;
begin
  if FLimbs = nil then Exit(MulCore(Self, Self));
  GetMagView(Self, v);
  SetLength(r, 2 * v.N);
  nr := SqrMag(v.P, v.N, @r[0]);
  Result := MakeFromMag(False, r, nr, Int64(FScale) * 2);
end;

{ ----- rounding and scale ----- }

function TBigDecimal.Round(const C: TMathContext): TBigDecimal;
var
  v: TMagView;
  r: TLimbs;
  nr: Integer;
  drop: Int64;
  inexact: Boolean;
  prec: Integer;
  sc: Int64;
  tmp: TLimbs;
  nt: Integer;
begin
  if (C.Precision = 0) or IsZero then Exit(Self);
  prec := PrecisionOf(Self);
  if prec <= C.Precision then Exit(Self);
  drop := prec - C.Precision;
  GetMagView(Self, v);
  if v.N <= MaxStackLimbs then
  begin
    PutRounded(Result, v.Neg, v.P, v.N, FScale, C, False, inexact);
    Exit;
  end;
  SetLength(r, v.N + 1);
  RoundMagDrop(v.P, v.N, drop, C.RoundingMode, v.Neg, False, @r[0], nr, inexact);
  sc := Int64(FScale) - drop;
  if MagDigits(@r[0], nr) > C.Precision then
  begin
    // the rounded magnitude became a power of ten: drop one more zero digit
    SetLength(tmp, nr);
    nt := DivPow10(@r[0], nr, 1, @tmp[0]);
    r := tmp;
    nr := nt;
    Dec(sc);
  end;
  Result := MakeFromMag(v.Neg, r, nr, sc);
end;

function TBigDecimal.Round: TBigDecimal;
var
  c: TMathContext;
begin
  if EffectiveContext(c) then Result := Round(c) else Result := Self;
end;

function TBigDecimal.SetScale(NewScale: Integer; Mode: TRoundingMode): TBigDecimal;
var
  v: TMagView;
  r: TLimbs;
  nr: Integer;
  drop: Int64;
  inexact: Boolean;
begin
  if NewScale = FScale then Exit(Self);
  GetMagView(Self, v);
  if v.N = 0 then
  begin
    r := nil;
    Exit(MakeFromMag(False, r, 0, NewScale));
  end;
  if NewScale > FScale then
  begin
    nr := ScaledMag(v, Int64(NewScale) - FScale, r);
    Exit(MakeFromMag(v.Neg, r, nr, NewScale));
  end;
  drop := Int64(FScale) - NewScale;
  SetLength(r, v.N + 1);
  RoundMagDrop(v.P, v.N, drop, Mode, v.Neg, False, @r[0], nr, inexact);
  Result := MakeFromMag(v.Neg, r, nr, NewScale);
end;

function TBigDecimal.StripTrailingZeros: TBigDecimal;
var
  v: TMagView;
  r: TLimbs;
  nr, i: Integer;
  zeros: Int64;
  t: UInt32;
begin
  if IsZero then Exit(SmallResult(0, 0));
  GetMagView(Self, v);
  zeros := 0;
  i := 0;
  while (i < v.N) and (v.P[i] = 0) do
  begin
    zeros += LimbDigits;
    Inc(i);
  end;
  t := v.P[i];
  while (t mod 10) = 0 do
  begin
    t := t div 10;
    Inc(zeros);
  end;
  if zeros = 0 then Exit(Self);
  SetLength(r, v.N);
  nr := DivPow10(v.P, v.N, zeros, @r[0]);
  Result := MakeFromMag(v.Neg, r, nr, Int64(FScale) - zeros);
end;

function TBigDecimal.ScaleByPowerOfTen(N: Integer): TBigDecimal;
begin
  Result := Self;
  Result.FScale := CheckScale(Int64(FScale) - N);
end;

function TBigDecimal.MovePointLeft(N: Integer): TBigDecimal;
begin
  if N = 0 then Exit(Self);
  Result := Self;
  Result.FScale := CheckScale(Int64(FScale) + N);
  if Result.FScale < 0 then Result := Result.SetScale(0, rmUnnecessary);
end;

function TBigDecimal.MovePointRight(N: Integer): TBigDecimal;
begin
  if N = 0 then Exit(Self);
  Result := Self;
  Result.FScale := CheckScale(Int64(FScale) - N);
  if Result.FScale < 0 then Result := Result.SetScale(0, rmUnnecessary);
end;

{ ----- compare ----- }

function TBigDecimal.CompareTo(const B: TBigDecimal): Integer;
var
  sa, sb: Integer;
  va, vb: TMagView;
  la, lb: TLimbs;
  pa, pb: PLimb;
  na, nb, c: Integer;
  ea, eb: Int64;
  s: Int64;
begin
  sa := GetSign;
  sb := B.GetSign;
  if sa <> sb then
  begin
    if sa > sb then Exit(1) else Exit(-1);
  end;
  if sa = 0 then Exit(0);
  if (FLimbs = nil) and (B.FLimbs = nil) and (FScale = B.FScale) then
  begin
    if FSmall > B.FSmall then Exit(1);
    if FSmall < B.FSmall then Exit(-1);
    Exit(0);
  end;
  ea := Int64(PrecisionOf(Self)) - FScale;
  eb := Int64(PrecisionOf(B)) - B.FScale;
  if ea <> eb then
  begin
    if (ea > eb) = (sa > 0) then Exit(1) else Exit(-1);
  end;
  GetMagView(Self, va);
  GetMagView(B, vb);
  pa := va.P; na := va.N;
  pb := vb.P; nb := vb.N;
  if FScale > B.FScale then s := FScale else s := B.FScale;
  if FScale < s then
  begin
    na := ScaledMag(va, s - FScale, la);
    pa := @la[0];
  end;
  if B.FScale < s then
  begin
    nb := ScaledMag(vb, s - B.FScale, lb);
    pb := @lb[0];
  end;
  c := CmpMag(pa, na, pb, nb);
  if sa < 0 then c := -c;
  Result := c;
end;

function TBigDecimal.Identical(const B: TBigDecimal): Boolean;
var
  i: Integer;
begin
  if (FScale <> B.FScale) or (GetSign <> B.GetSign) then Exit(False);
  if (FLimbs = nil) <> (B.FLimbs = nil) then Exit(False);
  if FLimbs = nil then Exit(FSmall = B.FSmall);
  if Length(FLimbs) <> Length(B.FLimbs) then Exit(False);
  for i := 0 to High(FLimbs) do
    if FLimbs[i] <> B.FLimbs[i] then Exit(False);
  Result := True;
end;

function TBigDecimal.Hash: Cardinal;
var
  i: Integer;
  h: UInt64;
begin
  h := 1469598103934665603;
  h := (h xor Cardinal(FScale)) * 1099511628211;
  if FLimbs = nil then
    h := (h xor UInt64(FSmall)) * 1099511628211
  else
  begin
    h := (h xor Cardinal(FSign)) * 1099511628211;
    for i := 0 to High(FLimbs) do
      h := (h xor FLimbs[i]) * 1099511628211;
  end;
  Result := Cardinal(h xor (h shr 32));
end;

class function TBigDecimal.Min(const A, B: TBigDecimal): TBigDecimal;
begin
  if A.CompareTo(B) <= 0 then Result := A else Result := B;
end;

class function TBigDecimal.Max(const A, B: TBigDecimal): TBigDecimal;
begin
  if A.CompareTo(B) >= 0 then Result := A else Result := B;
end;

class operator TBigDecimal.=(const A, B: TBigDecimal): Boolean;
begin
  Result := A.CompareTo(B) = 0;
end;

class operator TBigDecimal.<>(const A, B: TBigDecimal): Boolean;
begin
  Result := A.CompareTo(B) <> 0;
end;

class operator TBigDecimal.>(const A, B: TBigDecimal): Boolean;
begin
  Result := A.CompareTo(B) > 0;
end;

class operator TBigDecimal.<(const A, B: TBigDecimal): Boolean;
begin
  Result := A.CompareTo(B) < 0;
end;

class operator TBigDecimal.>=(const A, B: TBigDecimal): Boolean;
begin
  Result := A.CompareTo(B) >= 0;
end;

class operator TBigDecimal.<=(const A, B: TBigDecimal): Boolean;
begin
  Result := A.CompareTo(B) <= 0;
end;

class operator TBigDecimal.:=(Value: Int64): TBigDecimal;
begin
  Result := SmallResult(Value, 0);
end;

class operator TBigDecimal.:=(Value: Integer): TBigDecimal;
begin
  Result := SmallResult(Value, 0);
end;

class operator TBigDecimal.Explicit(const Value: TBigDecimal): Double;
begin
  Result := Value.ToDouble;
end;

class operator TBigDecimal.Explicit(const Value: TBigDecimal): string;
begin
  Result := Value.ToString;
end;

{ ----- text ----- }

function DigitsOf(const X: TBigDecimal): string;
var
  v: TMagView;
begin
  GetMagView(X, v);
  Result := RawDigits(v.P, v.N);
end;

function TBigDecimal.ToPlainString: string;
var
  d, z: string;
  sc, len: Integer;
  neg: Boolean;
begin
  d := DigitsOf(Self);
  neg := Sign < 0;
  sc := FScale;
  len := Length(d);
  if sc <= 0 then
  begin
    if (len = 1) and (d = '0') then
      Result := '0'
    else
    begin
      SetLength(z, -sc);
      FillChar(z[1], -sc, '0');
      Result := d + z;
    end;
  end
  else if len > sc then
    Result := Copy(d, 1, len - sc) + '.' + Copy(d, len - sc + 1, sc)
  else
  begin
    SetLength(z, sc - len);
    if sc - len > 0 then FillChar(z[1], sc - len, '0');
    Result := '0.' + z + d;
  end;
  if neg then Result := '-' + Result;
end;

function TBigDecimal.ToString: string;
var
  d: string;
  adj: Int64;
  len: Integer;
begin
  d := DigitsOf(Self);
  len := Length(d);
  adj := -Int64(FScale) + (len - 1);
  if (FScale >= 0) and (adj >= -6) then Exit(ToPlainString);
  if len > 1 then
    Result := d[1] + '.' + Copy(d, 2, len - 1)
  else
    Result := d;
  if adj <> 0 then
  begin
    Result += 'E';
    if adj > 0 then Result += '+';
    Result += IntToStr(adj);
  end;
  if Sign < 0 then Result := '-' + Result;
end;

function TBigDecimal.ToEngineeringString: string;
var
  d: string;
  adj: Int64;
  len, sig, i: Integer;
begin
  d := DigitsOf(Self);
  len := Length(d);
  adj := -Int64(FScale) + (len - 1);
  if (FScale >= 0) and (adj >= -6) then Exit(ToPlainString);
  sig := Integer(adj mod 3);
  if sig < 0 then sig += 3;
  adj -= sig;
  Inc(sig);
  if IsZero then
  begin
    case sig of
      1: Result := '0';
      2: begin Result := '0.00'; adj += 3; end;
      3: begin Result := '0.0'; adj += 3; end;
    end;
  end
  else if sig >= len then
  begin
    Result := d;
    for i := 1 to sig - len do Result += '0';
  end
  else
    Result := Copy(d, 1, sig) + '.' + Copy(d, sig + 1, len - sig);
  if adj <> 0 then
  begin
    Result += 'E';
    if adj > 0 then Result += '+';
    Result += IntToStr(adj);
  end;
  if Sign < 0 then Result := '-' + Result;
end;

function TBigDecimal.ToDouble: Double;
var
  v: TMagView;
begin
  GetMagView(Self, v);
  Result := RawToDouble(v.Neg, v.P, v.N, FScale);
end;

function TBigDecimal.ToInt64: Int64;
var
  t: TBigDecimal;
  v: TMagView;
  m: UInt64;
  i: Integer;
begin
  t := SetScale(0, rmDown);
  if t.FLimbs <> nil then
    raise EBigDecimalOverflow.Create('value does not fit in Int64');
  Result := t.FSmall;
end;

{ ----- division ----- }

{ Integer quotient of a*10^e (or a / 10^-e) by b with rounding by remainder.
  Returns the quotient limbs (trimmed) and whether the remainder was non-zero. }
procedure DivInts(const A, B: TMagView; e: Int64; Mode: TRoundingMode;
  Neg: Boolean; DoRound: Boolean; out Q: TLimbs; out nq: Integer;
  out Inexact: Boolean);
var
  num, den, rem, two, tmp: TLimbs;
  pn, pd: PLimb;
  nn, nd, nr, n2, c: Integer;
  cls: TDiscard;
  odd: Boolean;
  s: UInt32;
  i: Integer;
  carry: UInt32;
begin
  pn := A.P; nn := A.N;
  pd := B.P; nd := B.N;
  if e > 0 then
  begin
    nn := ScaledMag(A, e, num);
    pn := @num[0];
  end
  else if e < 0 then
  begin
    nd := ScaledMag(B, -e, den);
    pd := @den[0];
  end;
  if nn = 0 then
  begin
    Q := nil;
    nq := 0;
    Inexact := False;
    Exit;
  end;
  if CmpMag(pn, nn, pd, nd) < 0 then
  begin
    SetLength(rem, nn);
    Move(pn^, rem[0], nn * SizeOf(TLimb));
    nr := nn;
    Q := nil;
    nq := 0;
  end
  else
  begin
    SetLength(Q, nn - nd + 1);
    SetLength(rem, nd);
    DivRemMag(pn, nn, pd, nd, @Q[0], nq, @rem[0], nr);
  end;
  Inexact := nr > 0;
  if not Inexact then Exit;
  if not DoRound then Exit;
  // classify the remainder against half of the divisor
  SetLength(two, nr + 1);
  n2 := AddMag(@rem[0], nr, @rem[0], nr, @two[0]);
  c := CmpMag(@two[0], n2, pd, nd);
  if c < 0 then cls := dcBelowHalf
  else if c = 0 then cls := dcHalf
  else cls := dcAboveHalf;
  odd := (nq > 0) and ((Q[0] and 1) = 1);
  if RoundIncrement(Mode, Neg, cls, odd) then
  begin
    if nq = 0 then
    begin
      SetLength(Q, 1);
      Q[0] := 1;
      nq := 1;
    end
    else
    begin
      if Length(Q) < nq + 1 then SetLength(Q, nq + 1);
      carry := 1;
      i := 0;
      while (carry <> 0) and (i < nq) do
      begin
        s := Q[i] + carry;
        if s >= LimbBase then begin s -= LimbBase; carry := 1; end else carry := 0;
        Q[i] := s;
        Inc(i);
      end;
      if carry <> 0 then
      begin
        Q[nq] := 1;
        Inc(nq);
      end;
    end;
  end;
  tmp := nil;
end;

function DivScaled(const A, B: TBigDecimal; TargetScale: Int64;
  Mode: TRoundingMode): TBigDecimal;
var
  va, vb: TMagView;
  q: TLimbs;
  nq: Integer;
  inexact: Boolean;
begin
  if B.IsZero then raise EBigDecimalDivByZero.Create('division by zero');
  GetMagView(A, va);
  GetMagView(B, vb);
  DivInts(va, vb, TargetScale + B.FScale - A.FScale, Mode, va.Neg <> vb.Neg,
    True, q, nq, inexact);
  Result := MakeFromMag(va.Neg <> vb.Neg, q, nq, TargetScale);
end;

function TBigDecimal.Divide(const B: TBigDecimal; AScale: Integer;
  Mode: TRoundingMode): TBigDecimal;
begin
  Result := DivScaled(Self, B, AScale, Mode);
end;

{ Removes trailing zeros while the scale stays above Preferred. }
function StripToScale(const X: TBigDecimal; Preferred: Int64): TBigDecimal;
var
  v: TMagView;
  r: TLimbs;
  nr, i: Integer;
  zeros, maxStrip: Int64;
  t: UInt32;
begin
  if X.IsZero then Exit(X);
  maxStrip := Int64(X.FScale) - Preferred;
  if maxStrip <= 0 then Exit(X);
  GetMagView(X, v);
  zeros := 0;
  i := 0;
  while (i < v.N) and (v.P[i] = 0) and (zeros < maxStrip) do
  begin
    zeros += LimbDigits;
    Inc(i);
  end;
  if zeros < maxStrip then
  begin
    t := v.P[i];
    while ((t mod 10) = 0) and (zeros < maxStrip) do
    begin
      t := t div 10;
      Inc(zeros);
    end;
  end;
  if zeros > maxStrip then zeros := maxStrip;
  if zeros = 0 then Exit(X);
  SetLength(r, v.N);
  nr := DivPow10(v.P, v.N, zeros, @r[0]);
  Result := MakeFromMag(v.Neg, r, nr, Int64(X.FScale) - zeros);
end;

function ClampScale(S: Int64): Int32;
begin
  if S > High(Int32) then Result := High(Int32)
  else if S < Low(Int32) then Result := Low(Int32)
  else Result := Int32(S);
end;

{ Fast path of A / B rounded to the context: magnitudes of up to MaxStackLimbs
  limbs after scaling, in stack buffers. Returns False when it does not apply
  (zero operands and a context without a precision go the general way). R holds
  no array yet. The routine has no managed local, so it needs no finalization. }
function TryDivideFast(const A, B: TBigDecimal; const C: TMathContext;
  var R: TBigDecimal): Boolean;
var
  va, vb: TMagView;
  nn, nq, nr: Integer;
  e, da, db, pref: Int64;
  neg, inexact: Boolean;
  nb2, qb, rb: array[0..MaxStackLimbs] of TLimb;
  pn: PLimb;
begin
  Result := False;
  if (C.Precision <= 0) or A.IsZero or B.IsZero then Exit;
  GetMagView(A, va);
  GetMagView(B, vb);
  da := MagDigits(va.P, va.N);
  db := MagDigits(vb.P, vb.N);
  e := db + C.Precision + 1 - da;
  if e < 0 then e := 0;
  if e >= 9 * MaxStackLimbs then Exit;
  nn := va.N + Integer(e div LimbDigits) + 2;
  if (nn > MaxStackLimbs) or (vb.N > va.N + Integer(e div LimbDigits)) then Exit;
  pn := va.P;
  nn := va.N;
  if e > 0 then
  begin
    nn := MulPow10(pn, nn, e, @nb2[0]);
    pn := @nb2[0];
  end;
  if nn < vb.N then Exit;
  neg := va.Neg <> vb.Neg;
  pref := Int64(A.FScale) - B.FScale;
  DivRemMag(pn, nn, vb.P, vb.N, @qb[0], nq, @rb[0], nr);
  PutRounded(R, neg, @qb[0], nq, pref + e, C, nr > 0, inexact);
  if not inexact then
    R := StripToScale(R, pref);
  Result := True;
end;

function TBigDecimal.Divide(const B: TBigDecimal; const C: TMathContext): TBigDecimal;
var
  va, vb: TMagView;
  q: TLimbs;
  nq, nr, tn: Integer;
  inexact, sticky: Boolean;
  da, db, e, drop, sc, pref: Int64;
  tmp, r: TLimbs;
  num, den, rem: TLimbs;
  pn, pd: PLimb;
  nn, nd: Integer;
  neg: Boolean;
  p: Integer;
begin
  if C.Precision = 0 then Exit(Divide(B));
  if TryDivideFast(Self, B, C, Result) then Exit;
  if B.IsZero then raise EBigDecimalDivByZero.Create('division by zero');
  pref := Int64(FScale) - B.FScale;
  if IsZero then
  begin
    r := nil;
    Exit(MakeFromMag(False, r, 0, ClampScale(pref)));
  end;
  p := C.Precision;
  GetMagView(Self, va);
  GetMagView(B, vb);
  neg := va.Neg <> vb.Neg;
  da := MagDigits(va.P, va.N);
  db := MagDigits(vb.P, vb.N);
  e := db + p + 1 - da;
  if e < 0 then e := 0;
  pn := va.P; nn := va.N;
  if e > 0 then
  begin
    nn := ScaledMag(va, e, num);
    pn := @num[0];
  end;
  pd := vb.P; nd := vb.N;
  SetLength(q, nn - nd + 1);
  SetLength(rem, nd);
  DivRemMag(pn, nn, pd, nd, @q[0], nq, @rem[0], nr);
  sticky := nr > 0;
  drop := MagDigits(@q[0], nq) - p;
  sc := pref + e;
  SetLength(r, nq + 1);
  RoundMagDrop(@q[0], nq, drop, C.RoundingMode, neg, sticky, @r[0], tn, inexact);
  sc -= drop;
  if MagDigits(@r[0], tn) > p then
  begin
    SetLength(tmp, tn);
    tn := DivPow10(@r[0], tn, 1, @tmp[0]);
    r := tmp;
    Dec(sc);
  end;
  Result := MakeFromMag(neg, r, tn, sc);
  if not inexact then
    Result := StripToScale(Result, pref);
end;

function TBigDecimal.Divide(const B: TBigDecimal): TBigDecimal;
var
  va, vb: TMagView;
  bb, qa, tmp, rem, f: TLimbs;
  nb, nq, nr, a2, b5, m, i, nf: Integer;
  pref: Int64;
  neg: Boolean;
  r: TLimbs;
  nn: Integer;
  fct: UInt32;
  k5: Integer;
begin
  if B.IsZero then raise EBigDecimalDivByZero.Create('division by zero');
  pref := Int64(FScale) - B.FScale;
  if IsZero then
  begin
    r := nil;
    Exit(MakeFromMag(False, r, 0, ClampScale(pref)));
  end;
  GetMagView(Self, va);
  GetMagView(B, vb);
  neg := va.Neg <> vb.Neg;
  // strip the factors 2 and 5 from the divisor
  SetLength(bb, vb.N);
  Move(vb.P^, bb[0], vb.N * SizeOf(TLimb));
  nb := vb.N;
  a2 := 0;
  b5 := 0;
  while (bb[0] mod 2) = 0 do
  begin
    DivSmall(@bb[0], nb, 2, @bb[0]);
    nb := NormLen(@bb[0], nb);
    Inc(a2);
  end;
  while (bb[0] mod 5) = 0 do
  begin
    DivSmall(@bb[0], nb, 5, @bb[0]);
    nb := NormLen(@bb[0], nb);
    Inc(b5);
  end;
  // quotient of the magnitudes by the stripped divisor
  if (nb = 1) and (bb[0] = 1) then
  begin
    SetLength(qa, va.N);
    Move(va.P^, qa[0], va.N * SizeOf(TLimb));
    nq := va.N;
  end
  else
  begin
    if CmpMag(va.P, va.N, @bb[0], nb) < 0 then
      raise EBigDecimalNonTerminating.Create('non-terminating decimal expansion');
    SetLength(qa, va.N - nb + 1);
    SetLength(rem, nb);
    DivRemMag(va.P, va.N, @bb[0], nb, @qa[0], nq, @rem[0], nr);
    if nr <> 0 then
      raise EBigDecimalNonTerminating.Create('non-terminating decimal expansion');
  end;
  m := a2;
  if b5 > m then m := b5;
  // multiply by 2^(m-a2) * 5^(m-b5)
  SetLength(f, nq + (m div 3) + 8);
  Move(qa[0], f[0], nq * SizeOf(TLimb));
  nf := nq;
  nf := MulPow2(@f[0], nf, m - a2, @f[0]);
  i := m - b5;
  while i > 0 do
  begin
    // 5^k in steps of 5^13
    nn := i;
    if nn > 13 then nn := 13;
    fct := 1;
    for k5 := 1 to nn do fct *= 5;
    nf := MulSmall(@f[0], nf, fct, @f[0]);
    i -= nn;
  end;
  Result := MakeFromMag(neg, f, nf, pref + m);
  Result := StripToScale(Result, pref);
  tmp := nil;
end;

class operator TBigDecimal./(const A, B: TBigDecimal): TBigDecimal;
var
  c: TMathContext;
begin
  if EffectiveContext(c) and (c.Precision > 0) then
    Result := A.Divide(B, c)
  else
    Result := A.Divide(B);
end;

function TBigDecimal.DivideToIntegralValue(const B: TBigDecimal): TBigDecimal;
var
  pref: Int64;
begin
  if B.IsZero then raise EBigDecimalDivByZero.Create('division by zero');
  pref := Int64(FScale) - B.FScale;
  if Abs.CompareTo(B.Abs) < 0 then
  begin
    Result := SmallResult(0, ClampScale(pref));
    Exit;
  end;
  Result := DivScaled(Self, B, 0, rmDown);
  if pref > 0 then
    Result := Result.SetScale(ClampScale(pref), rmUnnecessary)
  else if pref < 0 then
    Result := StripToScale(Result, pref);
end;

function TBigDecimal.Remainder(const B: TBigDecimal): TBigDecimal;
var
  q: TBigDecimal;
begin
  if B.IsZero then raise EBigDecimalDivByZero.Create('division by zero');
  if Abs.CompareTo(B.Abs) < 0 then
  begin
    if FScale >= B.FScale then Exit(Self);
    Exit(SetScale(B.FScale, rmUnnecessary));
  end;
  q := DivScaled(Self, B, 0, rmDown);
  Result := AddCore(Self, MulCore(q, B), True);
end;

procedure TBigDecimal.DivRem(const B: TBigDecimal; out Quotient, Rem: TBigDecimal);
begin
  Quotient := DivideToIntegralValue(B);
  Rem := AddCore(Self, MulCore(Quotient, B), True);
end;

end.
