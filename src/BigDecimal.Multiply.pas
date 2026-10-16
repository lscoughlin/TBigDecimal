{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: multiply, karatsuba, squaring
documentation: doc/design.md
notes:
  - schoolbook, squaring and Karatsuba kernels on base 10^9 limbs
  - the unbalanced case splits the long operand into chunks
---
}
unit BigDecimal.Multiply;

{$mode objfpc}{$H+}
{$R-}{$Q-}
{$coperators on}
{$inline on}

interface

uses
  BigDecimal.Limbs;

var
  { Limb count at which Karatsuba replaces schoolbook. Set from bench/BenchMul. }
  KaratsubaThreshold: Integer = 160;  // bench/RESULTS.md: tie between 128 and 160 limbs, 15% faster at 256

{ r := a * b. r needs na + nb limbs and must not overlap a or b.
  Returns the normalized length. Both operands are normalized and non-empty. }
function MulMag(a: PLimb; na: Integer; b: PLimb; nb: Integer; r: PLimb): Integer;

{ r := a * a. r needs 2 * na limbs. Returns the normalized length. }
function SqrMag(a: PLimb; na: Integer; r: PLimb): Integer;

{ Schoolbook kernels, exported for tests and benchmarks. r gets na + nb limbs.
  MulSchool sums the products of one column in a UInt64 and divides by 10^9
  once for each 16 products (Comba's column order). }
procedure MulSchool(a: PLimb; na: Integer; b: PLimb; nb: Integer; r: PLimb);
procedure SqrSchool(a: PLimb; na: Integer; r: PLimb);

{ Forces schoolbook or Karatsuba regardless of the threshold, for tests. }
function MulMagForce(a: PLimb; na: Integer; b: PLimb; nb: Integer; r: PLimb;
  UseKaratsuba: Boolean): Integer;

implementation

procedure MulSchool(a: PLimb; na: Integer; b: PLimb; nb: Integer; r: PLimb);
var
  k, i, i0, i1, cnt: Integer;
  acc, carry, q: UInt64;
  lo: UInt32;
begin
  carry := 0;
  for k := 0 to na + nb - 2 do
  begin
    if k >= nb then i0 := k - nb + 1 else i0 := 0;
    if k < na then i1 := k else i1 := na - 1;
    acc := carry;
    carry := 0;
    cnt := 0;
    for i := i0 to i1 do
    begin
      acc += UInt64(a[i]) * b[k - i];
      Inc(cnt);
      if cnt = 16 then
      begin
        q := DivMod1e9(acc, lo);
        carry += q;
        acc := lo;
        cnt := 0;
      end;
    end;
    q := DivMod1e9(acc, lo);
    r[k] := lo;
    carry += q;
  end;
  r[na + nb - 1] := UInt32(carry);
end;

procedure SqrSchool(a: PLimb; na: Integer; r: PLimb);
begin
  // the column loop with both operands equal measured faster than a loop
  // that computes each cross product once and doubles the sum
  MulSchool(a, na, a, na, r);
end;

{ r[0..nr) += x[0..nx). The caller guarantees no carry out of r. }
procedure AddInto(r: PLimb; nr: Integer; x: PLimb; nx: Integer);
var
  i: Integer;
  s: UInt32;
  c: UInt32;
begin
  c := 0;
  for i := 0 to nx - 1 do
  begin
    s := r[i] + x[i] + c;
    if s >= LimbBase then begin s -= LimbBase; c := 1; end else c := 0;
    r[i] := s;
  end;
  i := nx;
  while (c <> 0) and (i < nr) do
  begin
    s := r[i] + c;
    if s >= LimbBase then begin s -= LimbBase; c := 1; end else c := 0;
    r[i] := s;
    Inc(i);
  end;
end;

{ r[0..nr) -= x[0..nx). The caller guarantees r >= x. }
procedure SubFrom(r: PLimb; nr: Integer; x: PLimb; nx: Integer);
var
  i: Integer;
  d: Int64;
  b: Int64;
begin
  b := 0;
  for i := 0 to nx - 1 do
  begin
    d := Int64(r[i]) - x[i] - b;
    if d < 0 then begin d += LimbBase; b := 1; end else b := 0;
    r[i] := UInt32(d);
  end;
  i := nx;
  while (b <> 0) and (i < nr) do
  begin
    d := Int64(r[i]) - b;
    if d < 0 then begin d += LimbBase; b := 1; end else b := 0;
    r[i] := UInt32(d);
    Inc(i);
  end;
end;

{ s[0..m) := a0 + a1, where a0 has h limbs and a1 has n-h limbs, m = n-h+1. }
procedure SumHalves(a: PLimb; n, h: Integer; s: PLimb);
var
  i, hi, m: Integer;
  t: UInt32;
  c: UInt32;
begin
  hi := n - h;
  m := hi + 1;
  c := 0;
  for i := 0 to hi - 1 do
  begin
    t := a[h + i] + c;
    if i < h then t += a[i];
    if t >= LimbBase then begin t -= LimbBase; c := 1; end else c := 0;
    s[i] := t;
  end;
  s[hi] := c;
end;

function ScratchSize(n: Integer): Integer;
var
  total, h, m: Integer;
begin
  total := 0;
  while n >= KaratsubaThreshold do
  begin
    h := n div 2;
    m := n - h + 1;
    total += 4 * m;
    n := m;
  end;
  Result := total + 8;
end;

{ r (2n limbs) := a * b where both have exactly n limbs (high zeros allowed). }
procedure KaraRec(a, b: PLimb; n: Integer; r: PLimb; scr: PLimb; UseK: Boolean);
var
  h, hi, m: Integer;
  sa, sb, z1: PLimb;
begin
  if (n < KaratsubaThreshold) or (n < 4) or (not UseK) then
  begin
    MulSchool(a, n, b, n, r);
    Exit;
  end;
  h := n div 2;
  hi := n - h;
  m := hi + 1;
  KaraRec(a, b, h, r, scr, UseK);              // z0 -> r[0..2h)
  KaraRec(a + h, b + h, hi, r + 2 * h, scr, UseK); // z2 -> r[2h..2n)
  sa := scr;
  sb := scr + m;
  z1 := scr + 2 * m;
  SumHalves(a, n, h, sa);
  SumHalves(b, n, h, sb);
  KaraRec(sa, sb, m, z1, scr + 4 * m, UseK);   // z1 has 2m limbs
  SubFrom(z1, 2 * m, r, 2 * h);                // z1 -= z0
  SubFrom(z1, 2 * m, r + 2 * h, 2 * hi);       // z1 -= z2
  AddInto(r + h, 2 * n - h, z1, 2 * m);
end;

procedure SqrRec(a: PLimb; n: Integer; r: PLimb; scr: PLimb; UseK: Boolean);
var
  h, hi, m: Integer;
  sa, z1: PLimb;
begin
  if (n < KaratsubaThreshold) or (n < 4) or (not UseK) then
  begin
    SqrSchool(a, n, r);
    Exit;
  end;
  h := n div 2;
  hi := n - h;
  m := hi + 1;
  SqrRec(a, h, r, scr, UseK);
  SqrRec(a + h, hi, r + 2 * h, scr, UseK);
  sa := scr;
  z1 := scr + m;
  SumHalves(a, n, h, sa);
  SqrRec(sa, m, z1, scr + 3 * m, UseK);
  SubFrom(z1, 2 * m, r, 2 * h);
  SubFrom(z1, 2 * m, r + 2 * h, 2 * hi);
  AddInto(r + h, 2 * n - h, z1, 2 * m);
end;

function MulBalanced(a: PLimb; na: Integer; b: PLimb; nb: Integer; r: PLimb;
  UseK: Boolean): Integer;
var
  n, i: Integer;
  pa, pb, scr: PLimb;
  buf: PLimb;
  total: Integer;
begin
  // pads the shorter operand with zeros to the length n of the longer one
  n := na;
  if nb > n then n := nb;
  total := 2 * n + ScratchSize(n) + 2 * n;
  GetMem(buf, total * SizeOf(TLimb));
  try
    pa := buf;
    pb := buf + n;
    scr := buf + 2 * n;
    for i := 0 to n - 1 do
    begin
      if i < na then pa[i] := a[i] else pa[i] := 0;
      if i < nb then pb[i] := b[i] else pb[i] := 0;
    end;
    KaraRec(pa, pb, n, buf + 2 * n + ScratchSize(n), scr, UseK);
    // result sits at buf + 2n + ScratchSize(n), 2n limbs; KaraRec writes r directly
    for i := 0 to na + nb - 1 do
      r[i] := (buf + 2 * n + ScratchSize(n))[i];
  finally
    FreeMem(buf);
  end;
  Result := NormLen(r, na + nb);
end;

function MulMagImpl(a: PLimb; na: Integer; b: PLimb; nb: Integer; r: PLimb;
  UseK: Boolean): Integer;
var
  t: PLimb;
  tn: Integer;
  i, off, chunk: Integer;
  tmp: PLimb;
  c: Integer;
begin
  if na < nb then
  begin
    t := a; a := b; b := t;
    tn := na; na := nb; nb := tn;
  end;
  // now na >= nb
  if (nb < KaratsubaThreshold) or (not UseK) then
  begin
    MulSchool(a, na, b, nb, r);
    Exit(NormLen(r, na + nb));
  end;
  if na < 2 * nb then
    Exit(MulBalanced(a, na, b, nb, r, UseK));
  // unbalanced: chunks of nb limbs of the long operand
  for i := 0 to na + nb - 1 do
    r[i] := 0;
  GetMem(tmp, 2 * nb * SizeOf(TLimb));
  try
    off := 0;
    while off < na do
    begin
      chunk := na - off;
      if chunk > nb then chunk := nb;
      if chunk = nb then
        c := MulBalanced(a + off, chunk, b, nb, tmp, UseK)
      else
      begin
        // short last chunk: swap roles
        c := MulMagImpl(b, nb, a + off, chunk, tmp, UseK);
      end;
      AddInto(r + off, na + nb - off, tmp, c);
      off += chunk;
    end;
  finally
    FreeMem(tmp);
  end;
  Result := NormLen(r, na + nb);
end;

function MulMag(a: PLimb; na: Integer; b: PLimb; nb: Integer; r: PLimb): Integer;
begin
  Result := MulMagImpl(a, na, b, nb, r, True);
end;

function MulMagForce(a: PLimb; na: Integer; b: PLimb; nb: Integer; r: PLimb;
  UseKaratsuba: Boolean): Integer;
begin
  Result := MulMagImpl(a, na, b, nb, r, UseKaratsuba);
end;

function SqrMag(a: PLimb; na: Integer; r: PLimb): Integer;
var
  scr, buf: PLimb;
  total: Integer;
  i: Integer;
begin
  if na < KaratsubaThreshold then
  begin
    SqrSchool(a, na, r);
    Exit(NormLen(r, 2 * na));
  end;
  total := ScratchSize(na) + 2 * na;
  GetMem(buf, total * SizeOf(TLimb));
  try
    scr := buf + 2 * na;
    SqrRec(a, na, buf, scr, True);
    for i := 0 to 2 * na - 1 do
      r[i] := buf[i];
  finally
    FreeMem(buf);
  end;
  Result := NormLen(r, 2 * na);
end;

end.
