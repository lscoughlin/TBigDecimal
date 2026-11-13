{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: ntt, number theoretic transform, convolution
documentation: doc/design/algorithms/multiplication.md
notes:
  - 64-bit number-theoretic transform with two moduli for base 10^9 limbs
  - decimation-in-frequency forward and decimation-in-time inverse transforms
  - Garner Chinese Remainder Theorem reconstruction with two-word carry pass
---
}
unit BigDecimal.Ntt;

{$mode objfpc}{$H+}
{$R-}{$Q-}
{$coperators on}
{$inline on}

interface

uses
  BigDecimal.Types, BigDecimal.Limbs;

type
  PUInt64 = ^UInt64;

const
  { Prime 1: 2^64 - 2^32 + 1 = 18446744069414584321 }
  P1: UInt64 = 18446744069414584321;
  { Prime 2: 2^64 - 2^34 + 1 = 18446744056529682433 }
  P2: UInt64 = 18446744056529682433;
  { Primitive root for P1 }
  G1: UInt64 = 7;
  { Primitive root for P2 }
  G2: UInt64 = 10;
  { Modular inverse of P1 modulo P2: (P1 * INV_P1_MOD_P2) mod P2 = 1 }
  INV_P1_MOD_P2: UInt64 = 18446744055098026669;

  { Coefficient bound and CRT range:
    For operand lengths na and nb in base 10^9, each convolution sum is bounded by
    min(na, nb) * (10^9 - 1)^2 < min(na, nb) * 10^18.
    The modulus product P1 * P2 ~= 3.4028 * 10^38, which is exact for all
    min(na, nb) < 3.4 * 10^20 limbs. }

{ Modular multiplication (a * b) mod P1 for a, b < P1. }
function MulModP1(a, b: UInt64): UInt64; inline;

{ Modular multiplication (a * b) mod P2 for a, b < P2. }
function MulModP2(a, b: UInt64): UInt64; inline;

{ Modular addition (a + b) mod P1 for a, b < P1. }
function AddModP1(a, b: UInt64): UInt64; inline;

{ Modular subtraction (a - b) mod P1 for a, b < P1. }
function SubModP1(a, b: UInt64): UInt64; inline;

{ Modular addition (a + b) mod P2 for a, b < P2. }
function AddModP2(a, b: UInt64): UInt64; inline;

{ Modular subtraction (a - b) mod P2 for a, b < P2. }
function SubModP2(a, b: UInt64): UInt64; inline;

{ Modular exponentiation (base^exp) mod P1. }
function PowModP1(base, exp: UInt64): UInt64;

{ Modular exponentiation (base^exp) mod P2. }
function PowModP2(base, exp: UInt64): UInt64;

{ Smallest power of two greater than or equal to n. }
function NextPowerOfTwo(n: Integer): Integer; inline;

{ Builds forward twiddle table wTable and inverse twiddle table wInvTable of length n for P1. }
procedure BuildTablesP1(n: Integer; wTable, wInvTable: PUInt64);

{ Builds forward twiddle table wTable and inverse twiddle table wInvTable of length n for P2. }
procedure BuildTablesP2(n: Integer; wTable, wInvTable: PUInt64);

{ In-place Radix-2 Decimation-in-Frequency forward NTT for P1. }
procedure DifTransformP1(a: PUInt64; n: Integer; wTable: PUInt64);

{ In-place Radix-2 Decimation-in-Time inverse NTT for P1. }
procedure DitTransformP1(a: PUInt64; n: Integer; wInvTable: PUInt64);

{ In-place Radix-2 Decimation-in-Frequency forward NTT for P2. }
procedure DifTransformP2(a: PUInt64; n: Integer; wTable: PUInt64);

{ In-place Radix-2 Decimation-in-Time inverse NTT for P2. }
procedure DitTransformP2(a: PUInt64; n: Integer; wInvTable: PUInt64);

{ Multiplies two limb arrays using two-prime NTT convolution with CRT and carry pass.
  r must have room for at least na + nb limbs. Returns normalized length. }
function NttMulMag(a: PLimb; na: Integer; b: PLimb; nb: Integer; r: PLimb): Integer;

{ Squares a limb array using two-prime NTT convolution with a single forward transform.
  r must have room for at least 2 * na limbs. Returns normalized length. }
function NttSqrMag(a: PLimb; na: Integer; r: PLimb): Integer;

implementation

function MulModP1(a, b: UInt64): UInt64; inline;
var
  hi, lo, x, y: UInt64;
begin
  hi := MulHi64(a, b);
  lo := a * b;
  x := hi; y := hi; hi := hi shr 32;
  x := lo - x;
  if x > lo then Dec(hi);
  y := y shl 32;
  lo := y + x;
  if lo < y then Inc(hi);

  x := hi; y := hi; hi := hi shr 32;
  x := lo - x;
  if x > lo then Dec(hi);
  y := y shl 32;
  lo := y + x;
  if lo < y then Inc(hi);

  if (hi <> 0) or (lo >= P1) then Result := lo - P1 else Result := lo;
end;

function MulModP2(a, b: UInt64): UInt64; inline;
var
  hi, lo, x, y: UInt64;
  i: Integer;
begin
  hi := MulHi64(a, b);
  lo := a * b;
  for i := 1 to 3 do
  begin
    x := hi; y := hi; hi := hi shr 30;
    x := lo - x;
    if x > lo then Dec(hi);
    y := y shl 34;
    lo := y + x;
    if lo < y then Inc(hi);
  end;
  if (hi <> 0) or (lo >= P2) then Result := lo - P2 else Result := lo;
end;

function AddModP1(a, b: UInt64): UInt64; inline;
var
  s: UInt64;
begin
  s := a + b;
  if (s < a) or (s >= P1) then Result := s - P1 else Result := s;
end;

function SubModP1(a, b: UInt64): UInt64; inline;
begin
  if a >= b then Result := a - b else Result := a + (P1 - b);
end;

function AddModP2(a, b: UInt64): UInt64; inline;
var
  s: UInt64;
begin
  s := a + b;
  if (s < a) or (s >= P2) then Result := s - P2 else Result := s;
end;

function SubModP2(a, b: UInt64): UInt64; inline;
begin
  if a >= b then Result := a - b else Result := a + (P2 - b);
end;

function PowModP1(base, exp: UInt64): UInt64;
var
  b, res: UInt64;
begin
  res := 1;
  b := base;
  while exp > 0 do
  begin
    if (exp and 1) <> 0 then res := MulModP1(res, b);
    b := MulModP1(b, b);
    exp := exp shr 1;
  end;
  Result := res;
end;

function PowModP2(base, exp: UInt64): UInt64;
var
  b, res: UInt64;
begin
  res := 1;
  b := base;
  while exp > 0 do
  begin
    if (exp and 1) <> 0 then res := MulModP2(res, b);
    b := MulModP2(b, b);
    exp := exp shr 1;
  end;
  Result := res;
end;

function NextPowerOfTwo(n: Integer): Integer; inline;
begin
  Result := 1;
  while Result < n do Result := Result shl 1;
end;

procedure BuildTablesP1(n: Integer; wTable, wInvTable: PUInt64);
var
  root, rootInv, w, winv: UInt64;
  i: Integer;
begin
  root := PowModP1(G1, (P1 - 1) div UInt64(n));
  rootInv := PowModP1(root, P1 - 2);
  w := 1;
  winv := 1;
  for i := 0 to n - 1 do
  begin
    wTable[i] := w;
    wInvTable[i] := winv;
    w := MulModP1(w, root);
    winv := MulModP1(winv, rootInv);
  end;
end;

procedure BuildTablesP2(n: Integer; wTable, wInvTable: PUInt64);
var
  root, rootInv, w, winv: UInt64;
  i: Integer;
begin
  root := PowModP2(G2, (P2 - 1) div UInt64(n));
  rootInv := PowModP2(root, P2 - 2);
  w := 1;
  winv := 1;
  for i := 0 to n - 1 do
  begin
    wTable[i] := w;
    wInvTable[i] := winv;
    w := MulModP2(w, root);
    winv := MulModP2(winv, rootInv);
  end;
end;

procedure DifTransformP1(a: PUInt64; n: Integer; wTable: PUInt64);
var
  m, mhalf, r, j, wstep: Integer;
  u, v, w: UInt64;
begin
  m := n;
  wstep := 1;
  while m >= 2 do
  begin
    mhalf := m shr 1;
    r := 0;
    while r < n do
    begin
      u := a[r];
      v := a[r + mhalf];
      a[r] := AddModP1(u, v);
      a[r + mhalf] := SubModP1(u, v);
      for j := 1 to mhalf - 1 do
      begin
        w := wTable[j * wstep];
        u := a[r + j];
        v := a[r + j + mhalf];
        a[r + j] := AddModP1(u, v);
        a[r + j + mhalf] := MulModP1(SubModP1(u, v), w);
      end;
      r += m;
    end;
    m := mhalf;
    wstep := wstep shl 1;
  end;
end;

procedure DitTransformP1(a: PUInt64; n: Integer; wInvTable: PUInt64);
var
  m, mhalf, r, j, wstep: Integer;
  u, v, w: UInt64;
begin
  m := 2;
  wstep := n shr 1;
  while m <= n do
  begin
    mhalf := m shr 1;
    r := 0;
    while r < n do
    begin
      u := a[r];
      v := a[r + mhalf];
      a[r] := AddModP1(u, v);
      a[r + mhalf] := SubModP1(u, v);
      for j := 1 to mhalf - 1 do
      begin
        w := wInvTable[j * wstep];
        u := a[r + j];
        v := MulModP1(a[r + j + mhalf], w);
        a[r + j] := AddModP1(u, v);
        a[r + j + mhalf] := SubModP1(u, v);
      end;
      r += m;
    end;
    m := m shl 1;
    wstep := wstep shr 1;
  end;
end;

procedure DifTransformP2(a: PUInt64; n: Integer; wTable: PUInt64);
var
  m, mhalf, r, j, wstep: Integer;
  u, v, w: UInt64;
begin
  m := n;
  wstep := 1;
  while m >= 2 do
  begin
    mhalf := m shr 1;
    r := 0;
    while r < n do
    begin
      u := a[r];
      v := a[r + mhalf];
      a[r] := AddModP2(u, v);
      a[r + mhalf] := SubModP2(u, v);
      for j := 1 to mhalf - 1 do
      begin
        w := wTable[j * wstep];
        u := a[r + j];
        v := a[r + j + mhalf];
        a[r + j] := AddModP2(u, v);
        a[r + j + mhalf] := MulModP2(SubModP2(u, v), w);
      end;
      r += m;
    end;
    m := mhalf;
    wstep := wstep shl 1;
  end;
end;

procedure DitTransformP2(a: PUInt64; n: Integer; wInvTable: PUInt64);
var
  m, mhalf, r, j, wstep: Integer;
  u, v, w: UInt64;
begin
  m := 2;
  wstep := n shr 1;
  while m <= n do
  begin
    mhalf := m shr 1;
    r := 0;
    while r < n do
    begin
      u := a[r];
      v := a[r + mhalf];
      a[r] := AddModP2(u, v);
      a[r + mhalf] := SubModP2(u, v);
      for j := 1 to mhalf - 1 do
      begin
        w := wInvTable[j * wstep];
        u := a[r + j];
        v := MulModP2(a[r + j + mhalf], w);
        a[r + j] := AddModP2(u, v);
        a[r + j + mhalf] := SubModP2(u, v);
      end;
      r += m;
    end;
    m := m shl 1;
    wstep := wstep shr 1;
  end;
end;

procedure NttReconstructAndCarry(res1, res2: PUInt64; totalLimbs: Integer; r: PLimb);
var
  i: Integer;
  r1, r2, r1_p2, diff, t: UInt64;
  p_lo, p_hi, total_lo, total_hi: UInt64;
  carry, rem1, lo_hi, lo_lo, w1, q1, rem2, w0, q0, q_lo: UInt64;
  d: UInt64;
begin
  d := LimbBase;
  carry := 0;
  for i := 0 to totalLimbs - 1 do
  begin
    r1 := res1[i];
    r2 := res2[i];
    if r1 >= P2 then r1_p2 := r1 - P2 else r1_p2 := r1;
    diff := SubModP2(r2, r1_p2);
    t := MulModP2(diff, INV_P1_MOD_P2);

    p_lo := t * P1;
    p_hi := MulHi64(t, P1);

    total_lo := p_lo + r1;
    total_hi := p_hi;
    if total_lo < p_lo then Inc(total_hi);

    total_lo += carry;
    if total_lo < carry then Inc(total_hi);

    rem1 := total_hi mod d;
    lo_hi := total_lo shr 32;
    lo_lo := total_lo and $FFFFFFFF;

    w1 := (rem1 shl 32) or lo_hi;
    q1 := w1 div d;
    rem2 := w1 mod d;

    w0 := (rem2 shl 32) or lo_lo;
    q0 := w0 div d;
    r[i] := UInt32(w0 mod d);

    q_lo := (q1 shl 32) or q0;
    carry := q_lo;
  end;
end;

function NttMulMag(a: PLimb; na: Integer; b: PLimb; nb: Integer; r: PLimb): Integer;
var
  n, i: Integer;
  wTable, wInvTable: PUInt64;
  bufA, bufB, res1, res2: PUInt64;
  buf: PUInt64;
  ninv1, ninv2: UInt64;
begin
  if (na <= 0) or (nb <= 0) then Exit(0);

  n := NextPowerOfTwo(na + nb);

  GetMem(buf, 6 * n * SizeOf(UInt64));
  try
    wTable := buf;
    wInvTable := buf + n;
    bufA := buf + 2 * n;
    bufB := buf + 3 * n;
    res1 := buf + 4 * n;
    res2 := buf + 5 * n;

    // === PRIME 1 ===
    BuildTablesP1(n, wTable, wInvTable);
    for i := 0 to na - 1 do bufA[i] := a[i];
    for i := na to n - 1 do bufA[i] := 0;
    DifTransformP1(bufA, n, wTable);

    for i := 0 to nb - 1 do bufB[i] := b[i];
    for i := nb to n - 1 do bufB[i] := 0;
    DifTransformP1(bufB, n, wTable);

    for i := 0 to n - 1 do
      res1[i] := MulModP1(bufA[i], bufB[i]);

    DitTransformP1(res1, n, wInvTable);
    ninv1 := PowModP1(n, P1 - 2);
    for i := 0 to n - 1 do
      res1[i] := MulModP1(res1[i], ninv1);

    // === PRIME 2 ===
    BuildTablesP2(n, wTable, wInvTable);
    for i := 0 to na - 1 do bufA[i] := a[i];
    for i := na to n - 1 do bufA[i] := 0;
    DifTransformP2(bufA, n, wTable);

    for i := 0 to nb - 1 do bufB[i] := b[i];
    for i := nb to n - 1 do bufB[i] := 0;
    DifTransformP2(bufB, n, wTable);

    for i := 0 to n - 1 do
      res2[i] := MulModP2(bufA[i], bufB[i]);

    DitTransformP2(res2, n, wInvTable);
    ninv2 := PowModP2(n, P2 - 2);
    for i := 0 to n - 1 do
      res2[i] := MulModP2(res2[i], ninv2);

    // === CRT & CARRY PASS ===
    NttReconstructAndCarry(res1, res2, na + nb, r);
  finally
    FreeMem(buf);
  end;
  Result := NormLen(r, na + nb);
end;

function NttSqrMag(a: PLimb; na: Integer; r: PLimb): Integer;
var
  n, i: Integer;
  wTable, wInvTable: PUInt64;
  bufA, res1, res2: PUInt64;
  buf: PUInt64;
  ninv1, ninv2: UInt64;
begin
  if na <= 0 then Exit(0);

  n := NextPowerOfTwo(2 * na);

  GetMem(buf, 5 * n * SizeOf(UInt64));
  try
    wTable := buf;
    wInvTable := buf + n;
    bufA := buf + 2 * n;
    res1 := buf + 3 * n;
    res2 := buf + 4 * n;

    // === PRIME 1 ===
    BuildTablesP1(n, wTable, wInvTable);
    for i := 0 to na - 1 do bufA[i] := a[i];
    for i := na to n - 1 do bufA[i] := 0;
    DifTransformP1(bufA, n, wTable);

    for i := 0 to n - 1 do
      res1[i] := MulModP1(bufA[i], bufA[i]);

    DitTransformP1(res1, n, wInvTable);
    ninv1 := PowModP1(n, P1 - 2);
    for i := 0 to n - 1 do
      res1[i] := MulModP1(res1[i], ninv1);

    // === PRIME 2 ===
    BuildTablesP2(n, wTable, wInvTable);
    for i := 0 to na - 1 do bufA[i] := a[i];
    for i := na to n - 1 do bufA[i] := 0;
    DifTransformP2(bufA, n, wTable);

    for i := 0 to n - 1 do
      res2[i] := MulModP2(bufA[i], bufA[i]);

    DitTransformP2(res2, n, wInvTable);
    ninv2 := PowModP2(n, P2 - 2);
    for i := 0 to n - 1 do
      res2[i] := MulModP2(res2[i], ninv2);

    // === CRT & CARRY PASS ===
    NttReconstructAndCarry(res1, res2, 2 * na, r);
  finally
    FreeMem(buf);
  end;
  Result := NormLen(r, 2 * na);
end;

end.
