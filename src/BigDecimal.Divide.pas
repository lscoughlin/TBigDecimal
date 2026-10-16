{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: divide, knuth algorithm d, newton reciprocal
documentation: doc/design.md
notes:
  - Knuth Algorithm D in base 10^9
  - a Newton reciprocal path serves divisors above a size threshold
---
}
unit BigDecimal.Divide;

{$mode objfpc}{$H+}
{$R-}{$Q-}
{$coperators on}
{$inline on}

interface

uses
  BigDecimal.Limbs;

var
  { Count of Newton divisions that fell back to Algorithm D (for tests). }
  NewtonFallbacks: Integer = 0;
  { Divisor size in limbs above which the Newton reciprocal path runs. }
  NewtonDivThreshold: Integer = 4096;  // bench/RESULTS.md: Knuth wins up to 2048 limbs, tie at 4096

{ q := a div b, rem := a mod b. a and b are normalized, b is not empty.
  q needs na - nb + 1 limbs (at least 1), rem needs nb limbs.
  Returns the normalized length of q in nq and of rem in nr. }
procedure DivRemMag(a: PLimb; na: Integer; b: PLimb; nb: Integer;
  q: PLimb; out nq: Integer; rem: PLimb; out nr: Integer);

{ Knuth Algorithm D only, for tests and comparison with the Newton path. }
procedure DivRemKnuth(a: PLimb; na: Integer; b: PLimb; nb: Integer;
  q: PLimb; out nq: Integer; rem: PLimb; out nr: Integer);

{ Approximate reciprocal B^(2n) / D of a normalized n-limb divisor (tests). }
procedure Reciprocal(D: PLimb; n: Integer; Y: PLimb; out ny: Integer);

{ Newton reciprocal division only, for tests and benchmarks. }
procedure DivRemNewton(a: PLimb; na: Integer; b: PLimb; nb: Integer;
  q: PLimb; out nq: Integer; rem: PLimb; out nr: Integer);

implementation

uses
  Math, BigDecimal.Multiply;

{ u[0..nb] -= qhat * v[0..nb). Returns 1 when the result is negative (the top
  limb u[nb] then holds the value plus the base). This is a separate routine
  because FPC keeps the locals of a routine with a try block in memory; here
  they stay in registers. The split of each product and the normalization of
  each limb do not depend on the previous limb, so the dependent chain is one
  subtraction, one compare and one masked addition, all without branches. }
function MulSubRow(u, v: PLimb; nb: Integer; qhat: UInt64): Int64;
var
  i: Integer;
  p, pq: UInt64;
  t, x, borrow, carry, c1, c2, e: Int64;
  lo: UInt32;
begin
  borrow := 0;
  carry := 0;
  for i := 0 to nb - 1 do
  begin
    p := qhat * v[i];
    pq := p div LimbBase;
    lo := UInt32(p - pq * LimbBase);
    // x does not depend on the borrow: bring it into 0..LimbBase-1 and count
    // the borrowed bases in c1 + c2
    x := Int64(u[i]) - lo - carry;
    carry := Int64(pq);
    c1 := Ord(x < 0);
    x += c1 * Int64(LimbBase);
    c2 := Ord(x < 0);
    x += c2 * Int64(LimbBase);
    // the chain: one subtraction, one compare, one masked add
    t := x - borrow;
    e := Ord(t < 0);
    t += (-e) and Int64(LimbBase);
    borrow := c1 + c2 + e;
    u[i] := UInt32(t);
  end;
  t := Int64(u[nb]) - carry - borrow;
  if t < 0 then begin t += LimbBase; borrow := 1; end else borrow := 0;
  u[nb] := UInt32(t);
  Result := borrow;
end;

procedure DivRemKnuth(a: PLimb; na: Integer; b: PLimb; nb: Integer;
  q: PLimb; out nq: Integer; rem: PLimb; out nr: Integer);
var
  u, v: PLimb;
  d: UInt32;
  j, i, k: Integer;
  qhat, rhat, num, p, pq: UInt64;
  borrow, carry, b1, b2: Int64;
  t: Int64;
  lo: UInt32;
  vt, vs: UInt64;
  nu: Integer;
begin
  if CmpMag(a, na, b, nb) < 0 then
  begin
    for i := 0 to na - 1 do rem[i] := a[i];
    nr := na;
    q[0] := 0;
    nq := 0;
    Exit;
  end;
  if nb = 1 then
  begin
    lo := DivSmall(a, na, b[0], q);
    nq := NormLen(q, na);
    rem[0] := lo;
    if lo = 0 then nr := 0 else nr := 1;
    Exit;
  end;
  GetMem(u, (na + 1) * SizeOf(TLimb));
  GetMem(v, nb * SizeOf(TLimb));
  try
    d := UInt32(LimbBase div (UInt64(b[nb - 1]) + 1));
    if d = 1 then
    begin
      for i := 0 to na - 1 do u[i] := a[i];
      u[na] := 0;
      for i := 0 to nb - 1 do v[i] := b[i];
    end
    else
    begin
      // u := a * d, v := b * d (v keeps nb limbs: the top carry is zero)
      carry := 0;
      for i := 0 to na - 1 do
      begin
        p := UInt64(a[i]) * d + UInt64(carry);
        carry := DivMod1e9(p, lo);
        u[i] := lo;
      end;
      u[na] := UInt32(carry);
      carry := 0;
      for i := 0 to nb - 1 do
      begin
        p := UInt64(b[i]) * d + UInt64(carry);
        carry := DivMod1e9(p, lo);
        v[i] := lo;
      end;
    end;
    nu := na + 1;
    vt := v[nb - 1];
    vs := v[nb - 2];
    for j := na - nb downto 0 do
    begin
      num := UInt64(u[j + nb]) * LimbBase + u[j + nb - 1];
      qhat := num div vt;
      rhat := num - qhat * vt;
      while (qhat >= LimbBase) or
            (qhat * vs > rhat * LimbBase + u[j + nb - 2]) do
      begin
        Dec(qhat);
        rhat += vt;
        if rhat >= LimbBase then Break;
      end;
      borrow := MulSubRow(u + j, v, nb, qhat);
      if borrow <> 0 then
      begin
        // add back
        Dec(qhat);
        carry := 0;
        for i := 0 to nb - 1 do
        begin
          t := Int64(u[i + j]) + v[i] + carry;
          if t >= LimbBase then begin t -= LimbBase; carry := 1; end else carry := 0;
          u[i + j] := UInt32(t);
        end;
        t := Int64(u[j + nb]) + carry;
        if t >= LimbBase then t -= LimbBase;
        u[j + nb] := UInt32(t);
      end;
      q[j] := UInt32(qhat);
    end;
    nq := NormLen(q, na - nb + 1);
    // remainder = u[0..nb) / d
    if d = 1 then
      for i := 0 to nb - 1 do rem[i] := u[i]
    else
      DivSmall(u, nb, d, rem);
    nr := NormLen(rem, nb);
  finally
    FreeMem(u);
    FreeMem(v);
  end;
end;

{ Approximate reciprocal of a normalized divisor D (n limbs, top limb at least
  half the base). Y receives about B^(2n) / D in n + 1 limbs (capacity n + 3).
  The error is a few units in the last place. }
procedure Reciprocal(D: PLimb; n: Integer; Y: PLimb; out ny: Integer);
var
  h, i, ne, nq0, nr0, nz, np, ncorr, nm: Integer;
  yh, z0, p, e, c, tmp, one, rr: TLimbs;
  nyh: Integer;
  negE: Boolean;
  cmpv: Integer;
  nnum: Integer;
begin
  if n <= 6 then
  begin
    // direct division of B^(2n) by D
    SetLength(one, 2 * n + 1);
    for i := 0 to 2 * n - 1 do one[i] := 0;
    one[2 * n] := 1;
    SetLength(tmp, n + 3);
    SetLength(rr, n + 1);
    DivRemKnuth(@one[0], 2 * n + 1, D, n, @tmp[0], nq0, @rr[0], nr0);
    for i := 0 to n + 2 do Y[i] := 0;
    for i := 0 to nq0 - 1 do Y[i] := tmp[i];
    ny := nq0;
    Exit;
  end;
  h := n div 2 + 1;
  SetLength(yh, h + 3);
  Reciprocal(D + (n - h), h, @yh[0], nyh);
  // Z0 = Yh * B^(n-h), n + 1 limbs
  SetLength(z0, n + 2);
  for i := 0 to n + 1 do z0[i] := 0;
  for i := 0 to nyh - 1 do
    if i + n - h < n + 2 then z0[i + n - h] := yh[i];
  nz := NormLen(@z0[0], n + 2);
  // P = D * Z0
  SetLength(p, n + nz + 1);
  np := MulMag(D, n, @z0[0], nz, @p[0]);
  // E = B^(2n) - P
  SetLength(one, 2 * n + 2);
  for i := 0 to 2 * n + 1 do one[i] := 0;
  one[2 * n] := 1;
  cmpv := CmpMag(@one[0], 2 * n + 1, @p[0], np);
  SetLength(e, Max(np, 2 * n + 1) + 1);
  if cmpv >= 0 then
  begin
    negE := False;
    ne := SubMag(@one[0], 2 * n + 1, @p[0], np, @e[0]);
  end
  else
  begin
    negE := True;
    ne := SubMag(@p[0], np, @one[0], 2 * n + 1, @e[0]);
  end;
  // correction = (Z0 * |E|) div B^(2n)
  ncorr := 0;
  if ne > 0 then
  begin
    SetLength(c, nz + ne + 1);
    nm := MulMag(@z0[0], nz, @e[0], ne, @c[0]);
    if nm > 2 * n then
    begin
      ncorr := nm - 2 * n;
      SetLength(tmp, ncorr);
      for i := 0 to ncorr - 1 do tmp[i] := c[i + 2 * n];
    end;
  end;
  // Y = Z0 +/- correction
  SetLength(rr, Max(nz, ncorr) + 2);
  if ncorr = 0 then
  begin
    for i := 0 to nz - 1 do rr[i] := z0[i];
    nnum := nz;
  end
  else if not negE then
    nnum := AddMag(@z0[0], nz, @tmp[0], ncorr, @rr[0])
  else if CmpMag(@z0[0], nz, @tmp[0], ncorr) >= 0 then
    nnum := SubMag(@z0[0], nz, @tmp[0], ncorr, @rr[0])
  else
    nnum := 0;
  for i := 0 to n + 2 do Y[i] := 0;
  for i := 0 to nnum - 1 do
    if i < n + 3 then Y[i] := rr[i];
  ny := nnum;
end;

{ Quotient and remainder through a Newton reciprocal. The estimate is checked
  against the exact product and corrected, so the result is always exact.
  The quotient must have at most nb - 2 limbs for a good estimate. }
procedure DivRemNewtonCore(a: PLimb; na: Integer; b: PLimb; nb: Integer;
  q: PLimb; out nq: Integer; rem: PLimb; out nr: Integer);
var
  f: UInt32;
  an, bn, y, prod, aa, qq, diff, tmp: TLimbs;
  nan, nbn, n, s, nqe, ny, nprod, i, nd, nqq, cmpv, naa, k: Integer;
  carry: UInt64;
  lo: UInt32;
begin
  nq := na - nb + 1;
  f := UInt32(LimbBase div (UInt64(b[nb - 1]) + 1));
  SetLength(an, na + 2);
  SetLength(bn, nb + 1);
  if f = 1 then
  begin
    for i := 0 to na - 1 do an[i] := a[i];
    nan := na;
    for i := 0 to nb - 1 do bn[i] := b[i];
    nbn := nb;
  end
  else
  begin
    nan := MulSmall(a, na, f, @an[0]);
    nbn := MulSmall(b, nb, f, @bn[0]);
  end;
  nqe := nan - nbn + 1;
  if nqe < 1 then nqe := 1;
  n := nqe + 2;
  if n > nbn then n := nbn;
  s := nbn - n;
  SetLength(y, n + 4);
  Reciprocal(@bn[s], n, @y[0], ny);
  // a' = a_norm div B^s
  naa := nan - s;
  if naa < 1 then naa := 0;
  SetLength(aa, Max(naa, 1));
  for i := 0 to naa - 1 do aa[i] := an[i + s];
  SetLength(prod, naa + ny + 1);
  nprod := 0;
  if (naa > 0) and (ny > 0) then
    nprod := MulMag(@aa[0], naa, @y[0], ny, @prod[0]);
  // q = prod div B^(2n)
  nqq := nprod - 2 * n;
  SetLength(qq, Max(nqe + 3, Max(nqq, 1) + 3));
  for i := 0 to High(qq) do qq[i] := 0;
  if nqq > 0 then
    for i := 0 to nqq - 1 do qq[i] := prod[i + 2 * n];
  nd := NormLen(@qq[0], Length(qq));
  // exact check: r = a_norm - q * b_norm, corrected by +/- b
  SetLength(diff, nan + nbn + 4);
  SetLength(tmp, nan + nbn + 4);
  k := 0;
  repeat
    if k > 6 then
    begin
      // the estimate was poor: fall back to Algorithm D (always exact)
      Inc(NewtonFallbacks);
      DivRemKnuth(a, na, b, nb, q, nq, rem, nr);
      Exit;
    end;
    // tmp = q * b_norm
    if nd > 0 then
      nprod := MulMag(@qq[0], nd, @bn[0], nbn, @tmp[0])
    else
      nprod := 0;
    cmpv := CmpMag(@tmp[0], nprod, @an[0], nan);
    if cmpv > 0 then
    begin
      // q too large: decrement
      carry := 1;
      i := 0;
      while carry <> 0 do
      begin
        if qq[i] >= carry then begin qq[i] -= UInt32(carry); carry := 0; end
        else begin qq[i] := UInt32(qq[i] + LimbBase - carry); carry := 1; end;
        Inc(i);
      end;
      nd := NormLen(@qq[0], Length(qq));
      Inc(k);
      Continue;
    end;
    nr := SubMag(@an[0], nan, @tmp[0], nprod, @diff[0]);
    if CmpMag(@diff[0], nr, @bn[0], nbn) >= 0 then
    begin
      // q too small: increment
      carry := 1;
      i := 0;
      while carry <> 0 do
      begin
        lo := qq[i] + UInt32(carry);
        if lo >= LimbBase then begin lo -= LimbBase; carry := 1; end else carry := 0;
        qq[i] := lo;
        Inc(i);
      end;
      nd := NormLen(@qq[0], Length(qq));
      Inc(k);
      Continue;
    end;
    Break;
  until False;
  nq := nd;
  for i := 0 to nd - 1 do q[i] := qq[i];
  for i := nd to na - nb do q[i] := 0;
  // remainder / f
  if f = 1 then
    for i := 0 to nr - 1 do rem[i] := diff[i]
  else
  begin
    DivSmall(@diff[0], nr, f, rem);
    nr := NormLen(rem, nr);
  end;
end;

procedure DivRemNewton(a: PLimb; na: Integer; b: PLimb; nb: Integer;
  q: PLimb; out nq: Integer; rem: PLimb; out nr: Integer);
var
  take, pos, i, nc, nqp, nrp, ncur: Integer;
  cur, qp, rp: TLimbs;
begin
  nq := na - nb + 1;
  if (nb < 8) or (CmpMag(a, na, b, nb) < 0) then
  begin
    DivRemKnuth(a, na, b, nb, q, nq, rem, nr);
    Exit;
  end;
  if nq <= nb - 2 then
  begin
    DivRemNewtonCore(a, na, b, nb, q, nq, rem, nr);
    Exit;
  end;
  // long division in blocks of take limbs, each divided through the reciprocal
  take := nb - 2;
  for i := 0 to na - nb do q[i] := 0;
  SetLength(cur, nb + take + 2);
  SetLength(qp, take + 4);
  SetLength(rp, nb + 2);
  nrp := 0;
  pos := na;
  while pos > 0 do
  begin
    nc := take;
    if nc > pos then nc := pos;
    // cur = rp * B^nc + a[pos-nc .. pos-1]
    for i := 0 to nc - 1 do cur[i] := a[pos - nc + i];
    for i := 0 to nrp - 1 do cur[nc + i] := rp[i];
    ncur := NormLen(@cur[0], nc + nrp);
    if CmpMag(@cur[0], ncur, b, nb) < 0 then
    begin
      for i := 0 to ncur - 1 do rp[i] := cur[i];
      nrp := ncur;
    end
    else
    begin
      DivRemNewtonCore(@cur[0], ncur, b, nb, @qp[0], nqp, @rp[0], nrp);
      for i := 0 to nqp - 1 do
        if pos - nc + i <= na - nb then q[pos - nc + i] := qp[i];
    end;
    pos -= nc;
  end;
  nq := NormLen(q, na - nb + 1);
  for i := 0 to nrp - 1 do rem[i] := rp[i];
  nr := nrp;
end;

procedure DivRemMag(a: PLimb; na: Integer; b: PLimb; nb: Integer;
  q: PLimb; out nq: Integer; rem: PLimb; out nr: Integer);
begin
  if (nb >= NewtonDivThreshold) and (na - nb >= NewtonDivThreshold) then
    DivRemNewton(a, na, b, nb, q, nq, rem, nr)
  else
    DivRemKnuth(a, na, b, nb, q, nq, rem, nr);
end;

end.
