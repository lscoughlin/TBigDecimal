{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: limbs, kernels, base 1e9
documentation: doc/design.md
notes:
  - magnitude kernels on base 10^9 limbs, least significant limb first
  - kernels work on pointers and lengths and never allocate
---
}
unit BigDecimal.Limbs;

{$mode objfpc}{$H+}
{$R-}{$Q-}
{$coperators on}
{$inline on}

interface

type
  TLimb = UInt32;
  PLimb = ^TLimb;
  TLimbs = array of TLimb;

const
  LimbBase = 1000000000;
  LimbDigits = 9;

var
  Pow10_32: array[0..9] of UInt32;
  Pow10_64: array[0..18] of UInt64;

{ Quotient and remainder of x by 10^9. x must be below 2^64. }
function DivMod1e9(x: UInt64; out r: UInt32): UInt64;

function DigitCount(x: UInt32): Integer; inline;
function DigitCount64(x: UInt64): Integer;

{ Strips high zero limbs and returns the new length. }
function NormLen(a: PLimb; n: Integer): Integer; inline;

{ Compares two normalized magnitudes. Returns -1, 0 or 1. }
function CmpMag(a: PLimb; na: Integer; b: PLimb; nb: Integer): Integer;

{ r := a + b. r needs max(na, nb) + 1 limbs. Returns the normalized length. }
function AddMag(a: PLimb; na: Integer; b: PLimb; nb: Integer; r: PLimb): Integer;

{ r := a - b with a >= b. r needs na limbs. Returns the normalized length. }
function SubMag(a: PLimb; na: Integer; b: PLimb; nb: Integer; r: PLimb): Integer;

{ r := a * m with m < 2^32. r needs na + 2 limbs. Returns normalized length. }
function MulSmall(a: PLimb; na: Integer; m: UInt32; r: PLimb): Integer;

{ r := a * m + c. Same as MulSmall with a carry-in below 10^9 for the first limb. }
function MulAddSmall(a: PLimb; na: Integer; m: UInt32; c: UInt32; r: PLimb): Integer;

{ q := a div d, returns the remainder. d is in 1..10^9-1 (or any UInt32 below
  2^32 when the value r*10^9 + limb fits in UInt64). q may alias a. }
function DivSmall(a: PLimb; na: Integer; d: UInt32; q: PLimb): UInt32;

{ r := a * 10^k (k >= 0). r needs na + k div 9 + 1 limbs. Returns length. }
function MulPow10(a: PLimb; na: Integer; k: Int64; r: PLimb): Integer;

{ Number of decimal digits of a normalized, non-zero magnitude. }
function MagDigits(a: PLimb; na: Integer): Int64;

{ Returns the decimal digit (0..9) at position pos (0 = least significant). }
function MagDigitAt(a: PLimb; na: Integer; pos: Int64): Integer;

{ True when digits 0..cnt-1 (the low cnt digits) are all zero. }
function MagLowZero(a: PLimb; na: Integer; cnt: Int64): Boolean;

{ r := a div 10^k (truncated). r needs na limbs. Returns normalized length. }
function DivPow10(a: PLimb; na: Integer; k: Int64; r: PLimb): Integer;

implementation

{$ifdef CPUAARCH64}
{ High 64 bits of the 128-bit product. A benchmark (bench/BenchDivMod.lpr) on
  FPC 3.2.4 aarch64 shows the compiler emitting a hardware udiv for x div 10^9.
  In a carry chain the multiply-high form is about 38% faster. }
function MulHi64(a, b: UInt64): UInt64; assembler; nostackframe;
asm
  umulh x0, x0, x1
end;

const
  { ceil(2^75 / 5^9): (x shr 9) * RecipM shr 75 = x div 10^9, exact for x < 2^64 }
  RecipM = UInt64(19342813113834067);

function DivMod1e9(x: UInt64; out r: UInt32): UInt64;
begin
  Result := MulHi64(x shr 9, RecipM) shr 11;
  r := UInt32(x - Result * LimbBase);
end;
{$else}
function DivMod1e9(x: UInt64; out r: UInt32): UInt64;
begin
  Result := x div LimbBase;
  r := UInt32(x - Result * LimbBase);
end;
{$endif}

function DigitCount(x: UInt32): Integer;
begin
  if x < 100000 then
  begin
    if x < 100 then
    begin
      if x < 10 then Exit(1) else Exit(2);
    end
    else if x < 1000 then Exit(3)
    else if x < 10000 then Exit(4)
    else Exit(5);
  end
  else if x < 10000000 then
  begin
    if x < 1000000 then Exit(6) else Exit(7);
  end
  else if x < 100000000 then Exit(8)
  else if x < 1000000000 then Exit(9)
  else Exit(10);
end;

function DigitCount64(x: UInt64): Integer;
var
  i: Integer;
begin
  for i := 18 downto 0 do
    if x >= Pow10_64[i] then
      Exit(i + 1);
  Result := 1;
end;

function NormLen(a: PLimb; n: Integer): Integer;
begin
  while (n > 0) and (a[n - 1] = 0) do
    Dec(n);
  Result := n;
end;

function CmpMag(a: PLimb; na: Integer; b: PLimb; nb: Integer): Integer;
var
  i: Integer;
begin
  if na <> nb then
  begin
    if na > nb then Exit(1) else Exit(-1);
  end;
  for i := na - 1 downto 0 do
    if a[i] <> b[i] then
    begin
      if a[i] > b[i] then Exit(1) else Exit(-1);
    end;
  Result := 0;
end;

function AddMag(a: PLimb; na: Integer; b: PLimb; nb: Integer; r: PLimb): Integer;
var
  i, n: Integer;
  s: UInt32;
  carry: UInt32;
  p: PLimb;
  m: Integer;
begin
  if na < nb then
  begin
    p := a; a := b; b := p;
    m := na; na := nb; nb := m;
  end;
  carry := 0;
  for i := 0 to nb - 1 do
  begin
    s := a[i] + b[i] + carry;
    if s >= LimbBase then
    begin
      s -= LimbBase;
      carry := 1;
    end
    else
      carry := 0;
    r[i] := s;
  end;
  for i := nb to na - 1 do
  begin
    s := a[i] + carry;
    if s >= LimbBase then
    begin
      s -= LimbBase;
      carry := 1;
    end
    else
      carry := 0;
    r[i] := s;
  end;
  n := na;
  if carry <> 0 then
  begin
    r[n] := 1;
    Inc(n);
  end;
  Result := n;
end;

function SubMag(a: PLimb; na: Integer; b: PLimb; nb: Integer; r: PLimb): Integer;
var
  i: Integer;
  d: Int64;
  borrow: Int64;
begin
  borrow := 0;
  for i := 0 to nb - 1 do
  begin
    d := Int64(a[i]) - Int64(b[i]) - borrow;
    if d < 0 then
    begin
      d += LimbBase;
      borrow := 1;
    end
    else
      borrow := 0;
    r[i] := UInt32(d);
  end;
  for i := nb to na - 1 do
  begin
    d := Int64(a[i]) - borrow;
    if d < 0 then
    begin
      d += LimbBase;
      borrow := 1;
    end
    else
      borrow := 0;
    r[i] := UInt32(d);
  end;
  Result := NormLen(r, na);
end;

function MulAddSmall(a: PLimb; na: Integer; m: UInt32; c: UInt32; r: PLimb): Integer;
var
  i: Integer;
  t: UInt64;
  lo: UInt32;
  carry: UInt64;
begin
  carry := c;
  for i := 0 to na - 1 do
  begin
    t := UInt64(a[i]) * m + carry;
    carry := DivMod1e9(t, lo);
    r[i] := lo;
  end;
  Result := na;
  while carry <> 0 do
  begin
    carry := DivMod1e9(carry, lo);
    r[Result] := lo;
    Inc(Result);
  end;
end;

function MulSmall(a: PLimb; na: Integer; m: UInt32; r: PLimb): Integer;
begin
  Result := MulAddSmall(a, na, m, 0, r);
  Result := NormLen(r, Result);
end;

function DivSmall(a: PLimb; na: Integer; d: UInt32; q: PLimb): UInt32;
var
  i: Integer;
  cur, qq: UInt64;
  rem: UInt64;
begin
  rem := 0;
  for i := na - 1 downto 0 do
  begin
    cur := rem * LimbBase + a[i];
    qq := cur div d;
    rem := cur - qq * d;
    q[i] := UInt32(qq);
  end;
  Result := UInt32(rem);
end;

function MulPow10(a: PLimb; na: Integer; k: Int64; r: PLimb): Integer;
var
  whole, i: Integer;
  part: Integer;
  n: Integer;
begin
  whole := Integer(k div LimbDigits);
  part := Integer(k mod LimbDigits);
  if na = 0 then Exit(0);
  // shift limbs (a and r may overlap only when whole = 0 and in-place scaling)
  if part = 0 then
  begin
    for i := na - 1 downto 0 do
      r[i + whole] := a[i];
    n := na + whole;
  end
  else
  begin
    // process from the top to allow in-place use when whole = 0
    n := MulSmall(a, na, Pow10_32[part], r + whole);
    n += whole;
  end;
  for i := 0 to whole - 1 do
    r[i] := 0;
  Result := n;
end;

function MagDigits(a: PLimb; na: Integer): Int64;
begin
  Result := Int64(na - 1) * LimbDigits + DigitCount(a[na - 1]);
end;

function MagDigitAt(a: PLimb; na: Integer; pos: Int64): Integer;
var
  li: Int64;
begin
  li := pos div LimbDigits;
  if li >= na then Exit(0);
  Result := Integer((a[li] div Pow10_32[pos mod LimbDigits]) mod 10);
end;

function MagLowZero(a: PLimb; na: Integer; cnt: Int64): Boolean;
var
  whole, i: Integer;
  part: Integer;
begin
  if cnt <= 0 then Exit(True);
  whole := Integer(cnt div LimbDigits);
  part := Integer(cnt mod LimbDigits);
  for i := 0 to whole - 1 do
  begin
    if i >= na then Exit(True);
    if a[i] <> 0 then Exit(False);
  end;
  if (part > 0) and (whole < na) then
    Result := (a[whole] mod Pow10_32[part]) = 0
  else
    Result := True;
end;

function DivPow10(a: PLimb; na: Integer; k: Int64; r: PLimb): Integer;
var
  whole, part, i, n: Integer;
  lo, hi: UInt64;
begin
  whole := Integer(k div LimbDigits);
  part := Integer(k mod LimbDigits);
  if whole >= na then Exit(0);
  n := na - whole;
  if part = 0 then
  begin
    for i := 0 to n - 1 do
      r[i] := a[i + whole];
  end
  else
  begin
    for i := 0 to n - 1 do
    begin
      lo := a[i + whole] div Pow10_32[part];
      if i + whole + 1 < na then
        hi := UInt64(a[i + whole + 1] mod Pow10_32[part]) * Pow10_32[LimbDigits - part]
      else
        hi := 0;
      r[i] := UInt32(lo + hi);
    end;
  end;
  Result := NormLen(r, n);
end;

procedure InitTables;
var
  i: Integer;
begin
  Pow10_32[0] := 1;
  for i := 1 to 9 do Pow10_32[i] := Pow10_32[i - 1] * 10;
  Pow10_64[0] := 1;
  for i := 1 to 18 do Pow10_64[i] := Pow10_64[i - 1] * 10;
end;

initialization
  InitTables;
end.
