{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: divide, knuth algorithm d, newton reciprocal, burnikel-ziegler
documentation: doc/design.md
notes:
  - Knuth Algorithm D in base 10^9
  - a Newton reciprocal path serves divisors above a size threshold
  - a Burnikel-Ziegler recursion serves mid-size divisors
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
  NewtonDivThreshold: Integer = 4096;  // doc/RESULTS.md: Knuth wins up to 2048 limbs, tie at 4096
  { Count of Burnikel-Ziegler divisions that fell back to Algorithm D (tests). }
  BZFallbacks: Integer = 0;
  { Divisor size in limbs at which the Burnikel-Ziegler recursion runs. }
  BZDivThreshold: Integer = 512;  // doc/RESULTS.md: wins at 512 divisor limbs, loses at 334

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

{ y := floor(sqrt(n)) for a normalized magnitude of nn limbs (1 <= nn <= 48).
  y needs nn div 2 + 2 limbs. Returns the normalized length of y, or 0 when
  the checked result is not the floor of the root (the caller then uses
  another method). Exact is True when y * y = n. }
function ISqrtMag(n: PLimb; nn: Integer; y: PLimb; out Exact: Boolean): Integer;

{ Newton reciprocal division only, for tests and benchmarks. }
procedure DivRemNewton(a: PLimb; na: Integer; b: PLimb; nb: Integer;
  q: PLimb; out nq: Integer; rem: PLimb; out nr: Integer);

{ Burnikel-Ziegler recursion. DivRemMag routes here when nb >= BZDivThreshold
  and na - nb >= nb - 256. Falls back to Algorithm D on any failed internal
  check and counts the fallback. }
procedure DivRemBZ(a: PLimb; na: Integer; b: PLimb; nb: Integer;
  q: PLimb; out nq: Integer; rem: PLimb; out nr: Integer);

implementation

uses
  Math, BigDecimal.Multiply;

const
  { Dividends up to this many limbs use stack scratch in DivRemKnuth. }
  SmallScratch = 96;

function ISqrtMag(n: PLimb; nn: Integer; y: PLimb; out Exact: Boolean): Integer;
var
  q, rem, z, sq: array[0..64] of TLimb;
  hi: UInt64;
  m, sv: Double;
  s: UInt64;
  e, h, ny, nq, nr, nz, i, c: Integer;
begin
  Exact := False;
  Result := 0;
  if (nn < 1) or (nn > 48) then Exit;
  // start value above the root, from the top two limbs
  if nn = 1 then
  begin
    hi := n[0];
    e := 0;
  end
  else
  begin
    hi := UInt64(n[nn - 1]) * LimbBase + n[nn - 2];
    e := nn - 2;
  end;
  m := Double(hi) + 1.0;
  if (e and 1) = 1 then
  begin
    m := m * 1e9;
    Dec(e);
  end;
  sv := Sqrt(m) * (1.0 + 1e-13) + 2.0;
  s := Trunc(sv);
  h := e div 2;
  for i := 0 to h - 1 do y[i] := 0;
  y[h] := UInt32(s mod LimbBase);
  s := s div LimbBase;
  if s <> 0 then
  begin
    y[h + 1] := UInt32(s);
    ny := h + 2;
  end
  else
    ny := h + 1;
  ny := NormLen(y, ny);
  repeat
    DivRemMag(n, nn, y, ny, @q[0], nq, @rem[0], nr);
    if nq = 0 then Break;
    nz := AddMag(y, ny, @q[0], nq, @z[0]);
    DivSmall(@z[0], nz, 2, @z[0]);
    nz := NormLen(@z[0], nz);
    if CmpMag(@z[0], nz, y, ny) >= 0 then Break;
    for i := 0 to nz - 1 do y[i] := z[i];
    ny := nz;
  until False;
  // check y*y <= n < (y+1)*(y+1)
  nz := MulMag(y, ny, y, ny, @sq[0]);
  c := CmpMag(@sq[0], nz, n, nn);
  if c > 0 then Exit;
  Exact := c = 0;
  if not Exact then
  begin
    // (y+1)^2 = y^2 + 2y + 1
    nq := MulSmall(y, ny, 2, @q[0]);
    q[nq] := 0;
    nq := AddMag(@sq[0], nz, @q[0], nq, @z[0]);
    q[0] := 1;
    nz := AddMag(@z[0], nq, @q[0], 1, @sq[0]);
    if CmpMag(@sq[0], nz, n, nn) <= 0 then Exit;
  end;
  Result := ny;
end;

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

{ Knuth algorithm D on the scratch buffers u (na + 1 limbs) and v (nb limbs).
  The routine has no try block, so FPC keeps its locals in registers. }
procedure DivRemKnuthCore(a: PLimb; na: Integer; b: PLimb; nb: Integer;
  q: PLimb; out nq: Integer; rem: PLimb; out nr: Integer; u, v: PLimb);
var
  d: UInt32;
  j, i, k: Integer;
  qhat, rhat, num, p, pq: UInt64;
  borrow, carry, b1, b2: Int64;
  t: Int64;
  lo: UInt32;
  vt, vs: UInt64;
  nu: Integer;
begin
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

end;

procedure DivRemKnuth(a: PLimb; na: Integer; b: PLimb; nb: Integer;
  q: PLimb; out nq: Integer; rem: PLimb; out nr: Integer);
var
  u, v: PLimb;
  ub: array[0..SmallScratch] of TLimb;
  vb: array[0..SmallScratch] of TLimb;
  lo: UInt32;
  i: Integer;
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
  if na <= SmallScratch then
    DivRemKnuthCore(a, na, b, nb, q, nq, rem, nr, @ub[0], @vb[0])
  else
  begin
    GetMem(u, (na + 1) * SizeOf(TLimb));
    GetMem(v, nb * SizeOf(TLimb));
    try
      DivRemKnuthCore(a, na, b, nb, q, nq, rem, nr, u, v);
    finally
      FreeMem(u);
      FreeMem(v);
    end;
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

{ Grows a buffer without shrinking it and keeps the content. }
procedure BZNeed(var b: TLimbs; n: Integer);
begin
  if Length(b) < Max(n, 1) then
    SetLength(b, Max(n, 1));
end;

{ Fresh zeroed buffer of n limbs (capacity at least 1). }
procedure BZZero(var b: TLimbs; n: Integer);
begin
  SetLength(b, Max(n, 1));
  if n > 0 then
    FillChar(b[0], n * SizeOf(TLimb), 0);
end;

{ q -= 1 for a normalized multi-limb value. Returns False on underflow. }
function BZDec1(q: PLimb; var nq: Integer): Boolean;
var
  i: Integer;
begin
  i := 0;
  while (i < nq) and (q[i] = 0) do
  begin
    q[i] := LimbBase - 1;
    Inc(i);
  end;
  if i >= nq then Exit(False);
  Dec(q[i]);
  nq := NormLen(q, nq);
  Result := True;
end;

{ acc += part * B^shift. acc has capacity cap (limbs), nacc is its live
  length. part has npart live limbs. Fails (Ok = False) when acc overflows. }
procedure BZAddShifted(acc: PLimb; var nacc: Integer; cap: Integer;
  part: PLimb; npart: Integer; shift: Integer; var tmp: TLimbs;
  var Ok: Boolean);
var
  i, nt: Integer;
begin
  if npart = 0 then Exit;
  BZNeed(tmp, shift + npart + 1);
  for i := 0 to shift + npart do
    tmp[i] := 0;
  for i := 0 to npart - 1 do
    tmp[shift + i] := part[i];
  nt := NormLen(@tmp[0], shift + npart);
  if nt = 0 then Exit;
  if shift + nt + 1 > cap then
  begin
    Ok := False;
    Exit;
  end;
  nacc := AddMag(acc, nacc, @tmp[0], nt, acc);
end;

{ Recursive 2n-by-n kernel. D has nd normalized limbs (top limb at least
  Base/2), X has value below B^(2*nd). Q needs nx + 2 limbs, R needs nd + 1
  limbs. Sets Ok = False on any failed internal check; the caller then falls
  back to Algorithm D. }
procedure BZDivHalf(X: PLimb; nx: Integer; D: PLimb; nd: Integer;
  Q: PLimb; out nq: Integer; R: PLimb; out nr: Integer; var Ok: Boolean);
var
  n1, n0, sPre, nxp, s1, i, nqp, nrp, nq1, nr1, nt, np, ns, nu1, ndcur: Integer;
  nq0, nr0, nt2, ns2, nw, nq2, nr2, L, Lcur, off: Integer;
  Xh, qp1, rp, Xp, U, Q1, R1, T, P, S, U1, Dcur, V, Q0, R0: TLimbs;
  T2, P2, S2, U2, W, q2, r2, sum: TLimbs;
  tmp: TLimbs;
  qh: PLimb;
  nd2, c: Integer;
begin
  nx := NormLen(X, nx);
  nd := NormLen(D, nd);
  if (nd <= BZDivThreshold) or (nx <= nd) or (nd < 2) then
  begin
    DivRemKnuth(X, nx, D, nd, Q, nq, R, nr);
    Exit;
  end;
  { Single-limb pre-step on the top nd limbs: Rp < D afterwards. }
  sPre := nx - nd;
  BZZero(Xh, nd);
  for i := 0 to nd - 1 do
    Xh[i] := X[sPre + i];
  BZZero(qp1, 2);
  BZZero(rp, nd + 1);
  DivRemKnuth(@Xh[0], nd, D, nd, @qp1[0], nqp, @rp[0], nrp);
  BZZero(Xp, 2 * nd + 1);
  for i := 0 to sPre - 1 do
    Xp[i] := X[i];
  for i := 0 to nrp - 1 do
    Xp[sPre + i] := rp[i];
  nxp := NormLen(@Xp[0], sPre + nrp);
  for i := 0 to nx + 1 do
    Q[i] := 0;
  nq := 0;
  if nqp > 0 then
    BZAddShifted(Q, nq, nx + 2, @qp1[0], nqp, sPre, tmp, Ok);
  if not Ok then Exit;
  if nxp <= nd then
  begin
    { Xp is tiny: finish directly. }
    if CmpMag(@Xp[0], nxp, D, nd) < 0 then
    begin
      for i := 0 to nxp - 1 do
        R[i] := Xp[i];
      nr := nxp;
      Exit;
    end;
    BZZero(Q1, 4);
    BZZero(R1, nd + 1);
    DivRemKnuth(@Xp[0], nxp, D, nd, @Q1[0], nq1, @R1[0], nr1);
    BZAddShifted(Q, nq, nx + 2, @Q1[0], nq1, 0, tmp, Ok);
    if not Ok then Exit;
    for i := 0 to nr1 - 1 do
      R[i] := R1[i];
    nr := nr1;
    Exit;
  end;
  n1 := Min((nd + 1) div 2, nxp - nd);
  n0 := nd - n1;
  { Sub-step 1: top 2*n1 limbs against the high half D1. }
  BZZero(U, 2 * n1);
  for i := 0 to 2 * n1 - 1 do
    U[i] := Xp[nxp - 2 * n1 + i];
  BZZero(Q1, 2 * n1 + 2);
  BZZero(R1, n1 + 1);
  BZDivHalf(@U[0], 2 * n1, D + n0, n1, @Q1[0], nq1, @R1[0], nr1, Ok);
  if not Ok then Exit;
  { T = R1 * B^s1 + low s1 limbs of Xp; S = Q1 * D0 * B^(s1-n0). }
  s1 := nxp - 2 * n1;
  BZZero(T, 2 * nd + 4);
  for i := 0 to s1 - 1 do
    T[i] := Xp[i];
  for i := 0 to nr1 - 1 do
    T[s1 + i] := R1[i];
  nt := NormLen(@T[0], s1 + nr1);
  BZZero(P, nd + 2);
  if nq1 = 0 then
    np := 0
  else
    np := MulMag(@Q1[0], nq1, D, n0, @P[0]);
  BZZero(S, 2 * nd + 4);
  for i := 0 to np - 1 do
    S[s1 - n0 + i] := P[i];
  ns := NormLen(@S[0], s1 - n0 + np);
  BZZero(U1, 2 * nd + 2);
  for i := 0 to nd - 1 do
    U1[s1 - n0 + i] := D[i];
  nu1 := NormLen(@U1[0], nd + s1 - n0);
  c := 0;
  while CmpMag(@T[0], nt, @S[0], ns) < 0 do
  begin
    nt := AddMag(@T[0], nt, @U1[0], nu1, @T[0]);
    if not BZDec1(@Q1[0], nq1) then
    begin
      Ok := False;
      Exit;
    end;
    Inc(c);
    if c > 20 then
    begin
      Ok := False;
      Exit;
    end;
  end;
  BZZero(Dcur, 2 * nd + 4);
  ndcur := SubMag(@T[0], nt, @S[0], ns, @Dcur[0]);
  { Sub-step 2: top 2*n1 limbs of Dcur against D1. }
  Lcur := ndcur;
  if Lcur <= 2 * n1 then
    L := 0
  else
    L := Lcur - 2 * n1;
  BZZero(V, 2 * n1);
  for i := 0 to 2 * n1 - 1 do
    if i + L < Lcur then
      V[i] := Dcur[i + L];
  BZZero(Q0, 2 * n1 + 2);
  BZZero(R0, n1 + 1);
  BZDivHalf(@V[0], 2 * n1, D + n0, n1, @Q0[0], nq0, @R0[0], nr0, Ok);
  if not Ok then Exit;
  if L >= n0 then
  begin
    BZZero(T2, 2 * nd + 4);
    for i := 0 to L - 1 do
      T2[i] := Dcur[i];
    for i := 0 to nr0 - 1 do
      T2[L + i] := R0[i];
    nt2 := NormLen(@T2[0], L + nr0);
    BZZero(P2, nd + 2);
    if nq0 = 0 then
      np := 0
    else
      np := MulMag(@Q0[0], nq0, D, n0, @P2[0]);
    BZZero(S2, 2 * nd + 4);
    for i := 0 to np - 1 do
      S2[L - n0 + i] := P2[i];
    ns2 := NormLen(@S2[0], L - n0 + np);
    BZZero(U2, 2 * nd + 2);
    for i := 0 to nd - 1 do
      U2[L - n0 + i] := D[i];
    off := NormLen(@U2[0], nd + L - n0);
    c := 0;
    while CmpMag(@T2[0], nt2, @S2[0], ns2) < 0 do
    begin
      nt2 := AddMag(@T2[0], nt2, @U2[0], off, @T2[0]);
      if not BZDec1(@Q0[0], nq0) then
      begin
        Ok := False;
        Exit;
      end;
      Inc(c);
      if c > 20 then
      begin
        Ok := False;
        Exit;
      end;
    end;
    nr := SubMag(@T2[0], nt2, @S2[0], ns2, R);
    BZAddShifted(Q, nq, nx + 2, @Q1[0], nq1, s1 - n0, tmp, Ok);
    if not Ok then Exit;
    BZAddShifted(Q, nq, nx + 2, @Q0[0], nq0, L - n0, tmp, Ok);
    if not Ok then Exit;
    if L > n0 then
    begin
      { R_sub can reach D * B^(L - n0): reduce it exactly. }
      BZZero(q2, 4);
      BZZero(r2, nd + 2);
      DivRemKnuth(R, nr, D, nd, @q2[0], nq2, @r2[0], nr2);
      for i := 0 to nr2 - 1 do
        R[i] := r2[i];
      nr := nr2;
      BZAddShifted(Q, nq, nx + 2, @q2[0], nq2, 0, tmp, Ok);
      if not Ok then Exit;
    end;
  end
  else
  begin
    { L < n0: split Q0 * B^L at B^n0 into qh * B^n0 + ql, so
      W = Q0 * D1 * B^L = qh * D + E with signed E = ql * D1 - qh * D0.
      |E| stays below 3 * B^nd, so one tiny schoolbook division fixes it. }
    BZZero(T2, 2 * nd + 4);
    for i := 0 to L - 1 do
      T2[i] := Dcur[i];
    for i := 0 to nr0 - 1 do
      T2[L + i] := R0[i];
    nt2 := NormLen(@T2[0], L + nr0);
    BZZero(sum, nd + 2);
    for i := 0 to L - 1 do
      sum[i] := 0;
    for i := 0 to nq0 - 1 do
      sum[L + i] := Q0[i];
    nd2 := NormLen(@sum[0], L + nq0);
    { ql = low n0 limbs of sum in place; qh = limbs above n0. }
    qh := @sum[Min(nd2, n0)];
    BZZero(P2, nd + 2);
    BZZero(W, 2 * nd + 4);
    if Min(nd2, n0) = 0 then
      np := 0
    else
      np := MulMag(@sum[0], Min(nd2, n0), D + n0, n1, @P2[0]);
    if nd2 <= n0 then
      off := 0
    else
      off := MulMag(qh, nd2 - n0, D, n0, @W[0]);
    BZZero(S2, 2 * nd + 4);
    if CmpMag(@P2[0], np, @W[0], off) >= 0 then
    begin
      np := SubMag(@P2[0], np, @W[0], off, @S2[0]);
      nw := 0;
    end
    else
    begin
      np := SubMag(@W[0], off, @P2[0], np, @S2[0]);
      nw := 1;
    end;
    { Signed E (length np) is in S2; qh (length nd2 - n0 or 0) is in sum. }
    BZZero(q2, n1 + 3);
    BZZero(r2, nd + 2);
    if np = 0 then
    begin
      nq2 := 0;
      nr2 := 0;
    end
    else
      DivRemKnuth(@S2[0], np, D, nd, @q2[0], nq2, @r2[0], nr2);
    if nw = 0 then
    begin
      { q2 = qh + qe; r2 = re. }
      if nd2 > n0 then
        nq2 := AddMag(qh, nd2 - n0, @q2[0], nq2, @q2[0]);
    end
    else
    begin
      { q2 = qh - qe - (re > 0); r2 = (D - re) mod D. }
      if nd2 <= n0 then
      begin
        { qh = 0 with E < 0 is impossible: ql * D1 >= 0 forces qh >= 1. }
        Ok := False;
        Exit;
      end;
      nq2 := SubMag(qh, nd2 - n0, @q2[0], nq2, @q2[0]);
      if nr2 > 0 then
      begin
        if not BZDec1(@q2[0], nq2) then
        begin
          Ok := False;
          Exit;
        end;
        nr2 := SubMag(D, nd, @r2[0], nr2, @r2[0]);
      end;
    end;
    { R = r2 + T2base, normalized by a bounded loop. }
    nr := AddMag(@r2[0], nr2, @T2[0], nt2, R);
    c := 0;
    while CmpMag(R, nr, D, nd) >= 0 do
    begin
      nr := SubMag(R, nr, D, nd, R);
      i := 0;
      while (i < nq2) and (q2[i] = LimbBase - 1) do
      begin
        q2[i] := 0;
        Inc(i);
      end;
      if i > n1 + 2 then
      begin
        Ok := False;
        Exit;
      end;
      if i >= nq2 then
      begin
        q2[i] := 1;
        nq2 := i + 1;
      end
      else
        Inc(q2[i]);
      Inc(c);
      if c > 10 then
      begin
        Ok := False;
        Exit;
      end;
    end;
    BZAddShifted(Q, nq, nx + 2, @Q1[0], nq1, s1 - n0, tmp, Ok);
    if not Ok then Exit;
    BZAddShifted(Q, nq, nx + 2, @q2[0], nq2, 0, tmp, Ok);
    if not Ok then Exit;
  end;
  nq := NormLen(Q, nx + 2);
end;

procedure DivRemBZ(a: PLimb; na: Integer; b: PLimb; nb: Integer;
  q: PLimb; out nq: Integer; rem: PLimb; out nr: Integer);
var
  f: UInt32;
  An, Bn, D, qacc, DIVB, Qb, Rcur, Z: TLimbs;
  nan, nbn, remaining, chunk, divlen, nqb, nrc, ndiv, off, i, j: Integer;
  Ok: Boolean;
begin
  nan := NormLen(a, na);
  nbn := NormLen(b, nb);
  if (nbn = 0) or (nbn < BZDivThreshold) or (nan - nbn < nbn - 256) then
  begin
    DivRemKnuth(a, na, b, nb, q, nq, rem, nr);
    Exit;
  end;
  f := UInt32(LimbBase div (UInt64(b[nbn - 1]) + 1));
  if f = 1 then
  begin
    BZZero(An, nan + 1);
    for i := 0 to nan - 1 do
      An[i] := a[i];
    BZZero(Bn, nbn + 1);
    for i := 0 to nbn - 1 do
      Bn[i] := b[i];
  end
  else
  begin
    BZZero(An, na + 2);
    nan := MulSmall(a, na, f, @An[0]);
    BZZero(Bn, nb + 2);
    nbn := MulSmall(b, nb, f, @Bn[0]);
  end;
  BZZero(D, nbn);
  for i := 0 to nbn - 1 do
    D[i] := Bn[i];
  BZZero(qacc, na - nb + 4);
  for i := 0 to na - nb + 3 do
    qacc[i] := 0;
  BZZero(Rcur, nbn + 1);
  nrc := 0;
  BZZero(Z, na - nb + nbn + 6);
  Ok := True;
  remaining := nan;
  while remaining > 0 do
  begin
    chunk := remaining mod nbn;
    if (chunk = 0) or (chunk > remaining) then
      chunk := Min(nbn, remaining);
    divlen := nrc + chunk;
    BZZero(DIVB, 2 * nbn + 1);
    for i := 0 to chunk - 1 do
      DIVB[i] := An[remaining - chunk + i];
    for j := 0 to nrc - 1 do
      DIVB[chunk + j] := Rcur[j];
    ndiv := NormLen(@DIVB[0], divlen);
    BZZero(Qb, 2 * nbn + 2);
    BZDivHalf(@DIVB[0], ndiv, @D[0], nbn, @Qb[0], nqb, @Rcur[0], nrc, Ok);
    if not Ok then Break;
    off := remaining - chunk;
    { qacc += Qb * B^off }
    BZNeed(Z, off + nqb + 1);
    for i := 0 to off + nqb do
      Z[i] := 0;
    for i := 0 to nqb - 1 do
      Z[off + i] := Qb[i];
    nqb := NormLen(@Z[0], off + nqb);
    nq := NormLen(@qacc[0], na - nb + 4);
    nq := AddMag(@qacc[0], nq, @Z[0], nqb, @qacc[0]);
    remaining := remaining - chunk;
  end;
  if not Ok then
  begin
    Inc(BZFallbacks);
    DivRemKnuth(a, na, b, nb, q, nq, rem, nr);
    Exit;
  end;
  nq := NormLen(@qacc[0], na - nb + 4);
  if nq > na - nb + 1 then
  begin
    Inc(BZFallbacks);
    DivRemKnuth(a, na, b, nb, q, nq, rem, nr);
    Exit;
  end;
  for i := 0 to nq - 1 do
    q[i] := qacc[i];
  if f = 1 then
  begin
    if nrc > nb then
    begin
      Inc(BZFallbacks);
      DivRemKnuth(a, na, b, nb, q, nq, rem, nr);
      Exit;
    end;
    for i := 0 to nrc - 1 do
      rem[i] := Rcur[i];
    nr := nrc;
  end
  else
  begin
    BZZero(Z, nbn + 1);
    DivSmall(@Rcur[0], nrc, f, @Z[0]);
    nr := NormLen(@Z[0], nrc);
    if nr > nb then
    begin
      Inc(BZFallbacks);
      DivRemKnuth(a, na, b, nb, q, nq, rem, nr);
      Exit;
    end;
    for i := 0 to nr - 1 do
      rem[i] := Z[i];
  end;
end;

procedure DivRemMag(a: PLimb; na: Integer; b: PLimb; nb: Integer;
  q: PLimb; out nq: Integer; rem: PLimb; out nr: Integer);
begin
  if (nb >= NewtonDivThreshold) and (na - nb >= NewtonDivThreshold) then
    DivRemNewton(a, na, b, nb, q, nq, rem, nr)
  else if (nb >= BZDivThreshold) and (na - nb >= nb - 256) then
    DivRemBZ(a, na, b, nb, q, nq, rem, nr)
  else
    DivRemKnuth(a, na, b, nb, q, nq, rem, nr);
end;

end.
