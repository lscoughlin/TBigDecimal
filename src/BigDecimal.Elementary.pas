{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: sqrt, root, exp, ln, log, pow
documentation: doc/design.md
notes:
  - results are correctly rounded in every rounding mode (Ziv strategy with error bounds)
  - an exact result is detected before the Ziv loop
  - a function without a context argument reads the thread-local default context
---
}
unit BigDecimal.Elementary;

{$mode objfpc}{$H+}
{$coperators on}

interface

uses
  SysUtils, BigDecimal.Types, BigDecimal, BigDecimal.Fixed;

function Sqrt(const X: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function Sqrt(const X: TBigDecimal): TBigDecimal; overload;
function Root(const X: TBigDecimal; N: Integer; const C: TMathContext): TBigDecimal; overload;
function Root(const X: TBigDecimal; N: Integer): TBigDecimal; overload;
function Exp(const X: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function Exp(const X: TBigDecimal): TBigDecimal; overload;
function Ln(const X: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function Ln(const X: TBigDecimal): TBigDecimal; overload;
function Log10(const X: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function Log10(const X: TBigDecimal): TBigDecimal; overload;
function Log(const B, X: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function Log(const B, X: TBigDecimal): TBigDecimal; overload;
function Pow(const X: TBigDecimal; N: Int64; const C: TMathContext): TBigDecimal; overload;
function Pow(const X: TBigDecimal; N: Int64): TBigDecimal; overload;
function Pow(const X, Y: TBigDecimal; const C: TMathContext): TBigDecimal; overload;
function Pow(const X, Y: TBigDecimal): TBigDecimal; overload;

{ Exact integer power of a value (no rounding). Raises EBigDecimalOverflow when
  the result would exceed MaxExactDigits digits. }
function PowExact(const X: TBigDecimal; N: Int64): TBigDecimal;

var
  { False makes Sqrt use the general path only (for tests). }
  SqrtFastPath: Boolean = True;

  { Working precision at which ExpFxCore evaluates the reduced argument
    with the bit-burst core instead of the halved Taylor series. }
  ExpBitBurstDigits: Integer = 8000;  // doc/RESULTS.md: burst wins at 8000 digits (1.09x), loses at 6000 (0.86x)

  { Working precision at which LnFxCore evaluates the atanh series with
    binary splitting instead of the term loop. }
  LnSplitDigits: Integer = 1000;  // doc/RESULTS.md: split wins at 1000 digits (2.0x), ties at 300

  { Split top-size multiple: LnFxCore splits only when the operand limbs
    times the term count stay within this multiple of the working limbs. }
  LnSplitTopMul: Integer = 50;  // doc/RESULTS.md: wins at ratio 44, loses at 60

{ Floor of the K-th root of a non-negative integer (scale 0). }
function IRootFloor(const N: TBigDecimal; K: Integer): TBigDecimal;

{ Natural logarithm and exponential as fixed-point values, for sibling units.
  ExpFx returns exp(X) / 10^K. }
function LnFx(const X: TBigDecimal; W: Integer): TFx;
function ExpFx(const X: TFx; out K: Int64): TFx;

{ Bit-burst exponential of a reduced argument. R must satisfy
  |R| <= 1.2 at scale W > 0. Returns exp(R) at scale W with a tracked error
  bound. ExpFxCore uses it when the working precision reaches
  ExpBitBurstDigits. }
function ExpBitBurstCore(const R: TFx): TFx;

{ Binary splitting core for the Taylor series of exp at a rational point.
  Computes S = sum_{k=0}^{N-1} (p0/q0)^k / k! as exact integers T and Q
  with S = T / Q. p0 and q0 are exact integers (scale 0); p0 may be
  negative and q0 must be positive. N must be positive. Exact in every
  context: the routine suspends the default. }
procedure ExpTaylorSplit(const p0, q0: TBigDecimal; N: Integer;
  out T, Q: TBigDecimal);

{ Binary splitting core for sum_{k=0}^{N-1} (p0/q0)^k / (2k+1).
  Computes S as exact integers T and Q with S = T / Q. p0 and q0 are
  exact integers (scale 0); p0 may be negative and q0 must be positive.
  N must be positive. Exact in every context: the routine suspends
  the default. }
procedure AtanhSplit(const p0, q0: TBigDecimal; N: Integer;
  out T, Q: TBigDecimal);

{ Returns the default context of the calling thread. Raises
  EBigDecimalNoContext when there is none. }
function RequireContext(out C: TMathContext): TMathContext;

implementation

uses
  Math, BigDecimal.Constants, BigDecimal.Limbs, BigDecimal.Divide, BigDecimal.Multiply;

function RequireContext(out C: TMathContext): TMathContext;
begin
  if not EffectiveContext(C) then
    raise EBigDecimalNoContext.Create('no math context is available');
  Result := C;
end;

procedure CheckFinite(const C: TMathContext; const What: string);
begin
  if C.Precision <= 0 then
    raise EBigDecimalDomain.Create(What + ' needs a finite precision');
end;

{ Next working precision; False when the cap is exceeded. }
function NextW(var W: Integer; P: Integer): Boolean;
begin
  W += W div 3 + 12;
  Result := W <= 6 * P + 1500;
end;

function FloorDiv(A, B: Int64): Int64;
begin
  Result := A div B;
  if ((A mod B) <> 0) and ((A < 0) <> (B < 0)) then Dec(Result);
end;

function CeilDiv(A, B: Int64): Int64;
begin
  Result := -FloorDiv(-A, B);
end;

function SignedApprox(const X: TBigDecimal): Double;
begin
  Result := ApproxAbs(X);
  if X.Sign < 0 then Result := -Result;
end;

function IntPow10(K: Int64): TBigDecimal;
begin
  Result := TBigDecimal.One.ScaleByPowerOfTen(Integer(K)).SetScale(0, rmUnnecessary);
end;

{ ----- exact powers and integer roots ----- }

function PowExact(const X: TBigDecimal; N: Int64): TBigDecimal;
var
  base: TBigDecimal;
  e: Int64;
  est: Double;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  if N < 0 then
    raise EBigDecimalDomain.Create('negative exponent for an exact power');
  if N = 0 then Exit(TBigDecimal.One);
  est := Double(X.Precision) * N;
  if est > MaxExactDigits then
    raise EBigDecimalOverflow.Create('exact power is too large');
  Result := TBigDecimal.One;
  base := X;
  e := N;
  while e > 0 do
  begin
    if (e and 1) = 1 then Result := Result * base;
    e := e shr 1;
    if e > 0 then base := base.Square;
  end;
end;

{ Newton iteration for floor(N^(1/K)) from a start value Y0 that is not below
  the root. The sequence decreases until it reaches the floor. }
function IRootNewton(const N: TBigDecimal; K: Integer; const Y0: TBigDecimal): TBigDecimal;
var
  y, z, yk1, t, kk, km1: TBigDecimal;
  i: Integer;
begin
  y := Y0;
  kk := TBigDecimal.Create(K);
  km1 := TBigDecimal.Create(K - 1);
  repeat
    yk1 := y;
    for i := 2 to K - 1 do yk1 := yk1 * y;
    t := N.Divide(yk1, 0, rmDown);
    z := (y * km1 + t).Divide(kk, 0, rmDown);
    if z.CompareTo(y) >= 0 then Break;
    y := z;
  until False;
  Result := y;
end;

function IRootFloor(const N: TBigDecimal; K: Integer): TBigDecimal;
var
  m: Int64;
  nh, rh: TBigDecimal;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  if N.IsZero then Exit(N);
  if K = 1 then Exit(N);
  if N.Precision <= 40 * K then
    Exit(IRootNewton(N, K, IntPow10(CeilDiv(N.Precision, K))));
  // The root of the leading digits, rounded up and shifted, is a start value
  // above the root with about half of the digits right. One or two Newton
  // steps at full size then finish the job.
  m := CeilDiv(N.Precision, K) div 2;
  nh := N.ScaleByPowerOfTen(Integer(-K * m)).SetScale(0, rmDown);
  rh := IRootFloor(nh, K);
  Result := IRootNewton(N, K,
    (rh + TBigDecimal.One).ScaleByPowerOfTen(Integer(m)).SetScale(0, rmUnnecessary));
end;

{ ----- square root and general roots ----- }

function RootCore(const X: TBigDecimal; K: Integer; const C: TMathContext): TBigDecimal;
var
  s0, s, sm, t, rscale, pref: Int64;
  u, n, r, rk, r2: TBigDecimal;
  d, p: Int64;
  exact: Boolean;
  q: TBigDecimal;
  target: Int64;
begin
  if X.IsZero then
    Exit(TBigDecimal.Zero.SetScale(Integer(CeilDiv(X.Scale, K)), rmUnnecessary));
  s0 := X.Scale;
  s := s0;
  u := X.UnscaledValue;
  sm := (((-s) mod K) + K) mod K;
  if sm <> 0 then
  begin
    u := u.ScaleByPowerOfTen(Integer(sm)).SetScale(0, rmUnnecessary);
    s += sm;
  end;
  p := C.Precision;
  if p = 0 then p := 0;
  d := u.Precision;
  if p > 0 then
    t := Max(0, CeilDiv(Int64(K) * (p + 1) + 1 - d, K))
  else
    t := 0;
  n := u;
  if t > 0 then n := u.ScaleByPowerOfTen(Integer(K * t)).SetScale(0, rmUnnecessary);
  r := IRootFloor(n, K);
  if K = 2 then rk := r.Square else rk := PowExact(r, K);
  exact := rk.CompareTo(n) = 0;
  rscale := s div K + t;
  pref := CeilDiv(s0, K);
  r := TBigDecimal.Create(r.UnscaledValue, Integer(rscale));
  if p = 0 then
  begin
    if not exact then
      raise EBigDecimalRounding.Create('root is not exact and no precision was given');
    q := r.StripTrailingZeros;
    if q.Scale < pref then q := q.SetScale(Integer(pref), rmUnnecessary);
    Exit(q);
  end;
  if exact then
  begin
    q := r.StripTrailingZeros;
    if q.Precision <= p then
    begin
      target := Min(pref, Int64(q.Scale) + (p - q.Precision));
      if target > q.Scale then q := q.SetScale(Integer(target), rmUnnecessary);
      Exit(q);
    end;
    Exit(r.Round(C));
  end;
  // inexact: append a sticky digit 1 so that every mode sees a value above r
  r2 := TBigDecimal.Create(r.UnscaledValue * TBigDecimal.Ten + TBigDecimal.One,
    Integer(rscale + 1));
  Result := r2.Round(C);
end;

{ Square root of a short, non-negative value in stack buffers, rounded once.
  Returns False when it does not apply: zero, a result that is exact (the
  general path pads it to the preferred scale), an unlimited context, or
  operands beyond the buffers. R holds no array yet. The routine has no
  managed local, so it needs no finalization. }
function TrySqrtFast(const X: TBigDecimal; const C: TMathContext;
  var R: TBigDecimal): Boolean;
var
  v: TMagView;
  nbuf, ybuf: array[0..MaxStackLimbs + 2] of TLimb;
  s, rscale: Int64;
  p, d, t, nn, ny, sm: Integer;
  exact, inexact: Boolean;
begin
  Result := False;
  p := C.Precision;
  if (p <= 0) or X.IsZero or (X.Sign < 0) then Exit;
  GetMagView(X, v);
  s := X.Scale;
  sm := Integer(((-s) mod 2 + 2) mod 2);
  d := Integer(MagDigits(v.P, v.N)) + sm;
  t := (2 * (p + 1) + 1 - d + 1) div 2;
  if t < 0 then t := 0;
  // the scaled value has d + 2t digits
  if (d + 2 * t) div LimbDigits + 3 > MaxStackLimbs then Exit;
  nn := MulPow10(v.P, v.N, sm + 2 * t, @nbuf[0]);
  ny := ISqrtMag(@nbuf[0], nn, @ybuf[0], exact);
  if (ny = 0) or exact then Exit;
  s += sm;
  rscale := s div 2 + t;
  // inexact: append a sticky digit 1 so that every mode sees a value above the root
  ny := MulSmall(@ybuf[0], ny, 10, @nbuf[0]);
  nbuf[0] += 1;
  PutRounded(R, False, @nbuf[0], ny, rscale + 1, C, False, inexact);
  Result := True;
end;

function Sqrt(const X: TBigDecimal; const C: TMathContext): TBigDecimal;
var
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  if X.Sign < 0 then raise EBigDecimalDomain.Create('square root of a negative value');
  if SqrtFastPath and TrySqrtFast(X, C, Result) then Exit;
  Result := RootCore(X, 2, C);
end;

function Sqrt(const X: TBigDecimal): TBigDecimal;
var
  c: TMathContext;
begin
  RequireContext(c);
  Result := Sqrt(X, c);
end;

function Root(const X: TBigDecimal; N: Integer; const C: TMathContext): TBigDecimal;
var
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  if N < 1 then raise EBigDecimalDomain.Create('root index must be positive');
  if X.Sign < 0 then
  begin
    if (N and 1) = 0 then raise EBigDecimalDomain.Create('even root of a negative value');
    Exit(RootCore(X.Negate, N, C).Negate);
  end;
  Result := RootCore(X, N, C);
end;

function Root(const X: TBigDecimal; N: Integer): TBigDecimal;
var
  c: TMathContext;
begin
  RequireContext(c);
  Result := Root(X, N, c);
end;

{ ----- exp ----- }

type
  TBSNode = record
    T, P, R, Y: TBigDecimal;
  end;

{ Recursive worker for ExpTaylorSplit. T(a,b) / P(a,b) / R(a,b) holds the
  partial sum over [a, b) scaled by a!; Y(a,b) holds p0^(b-a). All values
  are exact integers. }
procedure ExpTaylorRange(const p0, q0: TBigDecimal; a, b: Integer;
  out N: TBSNode);
var
  m: Integer;
  L, Rr: TBSNode;
begin
  if b - a = 1 then
  begin
    { Single term k = a contributes P(a,a+1) * q0. }
    N.P := TBigDecimal.Create(Int64(a) + 1);
    N.R := q0;
    N.T := N.P * N.R;
    N.Y := p0;
  end
  else
  begin
    m := a + (b - a) div 2;
    ExpTaylorRange(p0, q0, a, m, L);
    ExpTaylorRange(p0, q0, m, b, Rr);
    N.P := L.P * Rr.P;
    N.R := L.R * Rr.R;
    N.Y := L.Y * Rr.Y;
    N.T := L.T * Rr.P * Rr.R + L.Y * Rr.T;
  end;
end;

procedure ExpTaylorSplit(const p0, q0: TBigDecimal; N: Integer;
  out T, Q: TBigDecimal);
var
  S: TBSNode;
  GDefaultGuard: TSuspendDefault;
begin
  if (q0.Sign <= 0) or (N <= 0) then
    raise EBigDecimalDomain.Create('binary split needs q0 > 0 and N > 0');
  GDefaultGuard.Suspend;
  ExpTaylorRange(p0, q0, 0, N, S);
  T := S.T;
  Q := S.P * S.R;
end;

type
  TAtanhNode = record
    T, P, Q, D: TBigDecimal;
  end;

{ Recursive worker for AtanhSplit. T(a,b) / Q(a,b) holds the partial sum of
  (p0/q0)^k / (2k+1) over [a, b). P(a,b) holds p0^(b-a), Q(a,b) holds
  q0^(b-a) times the odd denominators, and D(a,b) holds the odd
  denominators (2a+1)(2a+3)...(2b-1). All values are exact. }
procedure AtanhRange(const p0, q0: TBigDecimal; a, b: Integer;
  out Nd: TAtanhNode);
var
  m: Integer;
  L, Rr: TAtanhNode;
begin
  if b - a = 1 then
  begin
    { Single term k = a contributes q0 / (q0 * (2a+1)). }
    Nd.P := p0;
    Nd.D := TBigDecimal.Create(Int64(2 * a + 1));
    Nd.Q := q0 * Nd.D;
    Nd.T := q0;
  end
  else
  begin
    m := a + (b - a) div 2;
    AtanhRange(p0, q0, a, m, L);
    AtanhRange(p0, q0, m, b, Rr);
    Nd.P := L.P * Rr.P;
    Nd.Q := L.Q * Rr.Q;
    Nd.D := L.D * Rr.D;
    Nd.T := L.T * Rr.Q + L.P * L.D * Rr.T;
  end;
end;

procedure AtanhSplit(const p0, q0: TBigDecimal; N: Integer;
  out T, Q: TBigDecimal);
var
  S: TAtanhNode;
  GDefaultGuard: TSuspendDefault;
begin
  if (q0.Sign <= 0) or (N <= 0) then
    raise EBigDecimalDomain.Create('binary split needs q0 > 0 and N > 0');
  GDefaultGuard.Suspend;
  AtanhRange(p0, q0, 0, N, S);
  T := S.T;
  Q := S.Q;
end;

{ Log10 of the chunk value Int(part) / 10^sExp. part holds decimal digits
  (leading zeros allowed). }
function ChunkLog10(const part: string; sExp: Int64): Double;
var
  m: string;
  v: Int64;
  code: Integer;
begin
  m := part;
  while (Length(m) > 1) and (m[1] = '0') do Delete(m, 1, 1);
  if Length(m) > 15 then
    Result := Ln(StrToInt64(Copy(m, 1, 15))) / Ln(10) + (Length(m) - 15)
  else
  begin
    Val(m, v, code);
    if (code <> 0) or (v <= 0) then
      raise EBigDecimalDomain.Create('bad chunk digits');
    Result := Log10(v);
  end;
  Result := Result - sExp;
end;

function ExpBitBurstCore(const R: TFx): TFx;
var
  W, Lu, f, idx, grp, take, k, N: Integer;
  digits, part: string;
  p: Integer;
  sExp: Int64;
  p0, q0, T, Q: TBigDecimal;
  acc, term: TFx;
  logc, logt: Double;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  W := R.W;
  if W <= 0 then
    raise EBigDecimalDomain.Create('bit-burst needs scale above 0');
  if R.V.IsZero then Exit(FxFromInt(1, W));
  if Abs(SignedApprox(R.V)) > 1.2 then
    raise EBigDecimalDomain.Create('bit-burst needs a reduced argument');
  digits := R.V.Abs.ToPlainString;
  p := Pos('.', digits);
  if p > 0 then Delete(digits, p, 1);
  Lu := Length(digits);
  f := 1;
  while (f <= Lu) and (digits[f] = '0') do Inc(f);
  if f > Lu then Exit(FxFromInt(1, W));
  acc := FxFromInt(1, W + 25);
  idx := f;
  grp := 1;
  while idx <= Lu do
  begin
    take := grp;
    if take > Lu - idx + 1 then take := Lu - idx + 1;
    part := Copy(digits, idx, take);
    { Chunk value = Int(part) / 10^sExp with sExp = W - Lu + (idx + take - 1). }
    sExp := Int64(W) - Lu + (idx + take - 1);
    p0 := TBigDecimal.Create(part);
    if not p0.IsZero then
    begin
      if sExp <= 0 then
      begin
        if sExp < 0 then
          p0 := p0.Multiply(IntPow10(-sExp), Unlimited);
        q0 := TBigDecimal.One;
      end
      else
        q0 := IntPow10(sExp);
      if R.V.Sign < 0 then p0 := -p0;
      logc := ChunkLog10(part, sExp);
      logt := 0.0;
      N := 0;
      while True do
      begin
        Inc(N);
        logt := logt + logc - Log10(N);
        if logt < -(W + 35) then Break;
        if N > 1000000 then
          raise EBigDecimalPrecision.Create('bit-burst term count overflow');
      end;
      Inc(N, 3);
      ExpTaylorSplit(p0, q0, N, T, Q);
      term := FxDiv(FxFromDecimal(T, W + 25), FxFromDecimal(Q, W + 25));
      term.E := term.E + Power(10.0, logt + (W + 25) + 0.30103) + 2.0;
      acc := FxMul(acc, term);
    end;
    idx := idx + take;
    grp := grp * 2;
  end;
  Result := FxRescale(acc, W);
end;

{ exp(X) = Result * 10^K. W is the scale of X. }
function ExpFxCore(const X: TFx; out K: Int64): TFx;
var
  W, s, i: Integer;
  xd, kd: Double;
  r, rp, t, sum, y, kl: TFx;
  scaleLimit: Double;
begin
  W := X.W;
  xd := SignedApprox(X.V);
  kd := xd / 2.302585092994046;
  if Abs(kd) > 2.0e9 then
    raise EBigDecimalOverflow.Create('exponent is out of range');
  K := Round(kd);
  if K <> 0 then
  begin
    kl := FxMulInt(ConstLn10(W), K);
    r := FxSub(X, kl);
  end
  else
    r := X;
  if (W >= ExpBitBurstDigits) and (Abs(SignedApprox(r.V)) <= 1.2) then
  begin
    Result := ExpBitBurstCore(r);
    Exit;
  end;
  s := Min(40, Trunc(Sqrt(Double(W))));
  if s < 1 then s := 1;
  rp := FxDivInt(r, Int64(1) shl s);
  sum := FxFromInt(1, W);
  t := rp;
  sum := FxAdd(sum, t);
  i := 2;
  while not FxTiny(t) do
  begin
    t := FxDivInt(FxMul(t, rp), i);
    sum := FxAdd(sum, t);
    Inc(i);
  end;
  sum.E += 3;
  y := sum;
  for i := 1 to s do
    y := FxSqr(y);
  Result := y;
end;

function Exp(const X: TBigDecimal; const C: TMathContext): TBigDecimal;
var
  w, p: Integer;
  fx, y: TFx;
  k: Int64;
  r: TBigDecimal;
  dk: Integer;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  CheckFinite(C, 'Exp');
  p := C.Precision;
  if X.IsZero then Exit(TBigDecimal.One.Round(C));
  dk := Trunc(Log10(Abs(SignedApprox(X)) / 2.3 + 10)) + 1;
  w := p + 14 + Trunc(0.31 * Min(40, Trunc(Sqrt(Double(p + 20))))) + dk;
  repeat
    fx := FxFromDecimal(X, w);
    y := ExpFxCore(fx, k);
    if FxRoundShifted(y, k, C, r) then Exit(r);
    if not NextW(w, p) then
      raise EBigDecimalPrecision.Create('Exp could not be rounded');
  until False;
end;

function Exp(const X: TBigDecimal): TBigDecimal;
var
  c: TMathContext;
begin
  RequireContext(c);
  Result := Exp(X, c);
end;

{ ----- ln ----- }

type
  TLnCand = record
    A, B: Integer;                // c = a / b
    Ex: array[0..3] of Integer;   // exponents of 2, 3, 5, 7
  end;

const
  LnTable: array[0..11] of TLnCand = (
    (A: 1; B: 1; Ex: (0, 0, 0, 0)),
    (A: 6; B: 5; Ex: (1, 1, -1, 0)),
    (A: 3; B: 2; Ex: (-1, 1, 0, 0)),
    (A: 2; B: 1; Ex: (1, 0, 0, 0)),
    (A: 5; B: 2; Ex: (-1, 0, 1, 0)),
    (A: 3; B: 1; Ex: (0, 1, 0, 0)),
    (A: 4; B: 1; Ex: (2, 0, 0, 0)),
    (A: 5; B: 1; Ex: (0, 0, 1, 0)),
    (A: 6; B: 1; Ex: (1, 1, 0, 0)),
    (A: 7; B: 1; Ex: (0, 0, 0, 1)),
    (A: 8; B: 1; Ex: (3, 0, 0, 0)),
    (A: 9; B: 1; Ex: (0, 2, 0, 0)));

{ Count of atanh series terms below W + 35 digits for 2*atanh(zne/zde).
  Term k holds (z^2)^k / (2k+1); its log is k * logc - log10(2k+1) with a
  single denominator factor. }
function LnAtanhCount(const zne, zde: TBigDecimal; W: Integer): Integer;
var
  zd, logc, logt: Double;
  N: Integer;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  zd := ApproxAbs(zne) / ApproxAbs(zde);
  logc := 2 * Math.Log10(Abs(zd));
  N := 0;
  logt := 0.0;
  while True do
  begin
    Inc(N);
    logt := N * logc - Math.Log10(2 * N + 1);
    if logt < -(W + 35) then Break;
    if N > 1000000 then
      raise EBigDecimalPrecision.Create('atanh term count overflow');
  end;
  Result := N + 3;
end;

{ True when binary splitting beats the term loop: the split top size,
  in limbs, stays within LnSplitTopMul multiples of the working size. }
function LnSplitUseful(const zne, zde: TBigDecimal; W: Integer): Boolean;
var
  va, vb: TMagView;
  N: Integer;
begin
  N := LnAtanhCount(zne, zde, W);
  GetMagView(zne, va);
  GetMagView(zde, vb);
  Result := Int64(va.N + vb.N) * Int64(N) <=
    Int64(LnSplitTopMul) * Int64(W div 9 + 1);
end;

{ 2 * atanh(zne / zde) as a fixed-point value at scale W, by binary
  splitting the atanh series. zne and zde are exact. }
function LnAtanhFx(const zne, zde: TBigDecimal; W: Integer): TFx;
var
  p0, q0, T, Q, num, den: TBigDecimal;
  N: Integer;
  logt: Double;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  N := LnAtanhCount(zne, zde, W);
  p0 := zne * zne;
  q0 := zde * zde;
  AtanhSplit(p0, q0, N, T, Q);
  num := TBigDecimal.Create(2) * zne * T;
  den := zde * Q;
  Result := FxDiv(FxFromDecimal(num, W), FxFromDecimal(den, W));
  { The omitted tail sits below the count bound; the term tracks it here. }
  logt := -(W + 35);
  Result.E := Result.E + Power(10.0, logt + W + 0.30103) + 2.0;
end;

{ ln(X) for X > 0 as a fixed-point value at scale W. }
function LnFxCore(const X: TBigDecimal; W: Integer): TFx;
var
  e: Int64;
  m: TBigDecimal;
  md, best, dist: Double;
  ci, i, j, kterm: Integer;
  zn, zd, z, z2, t, sum, term, res, cl: TFx;
  mb, zne, zde: TBigDecimal;
  W2: Integer;
  primes: array[0..3] of Integer = (2, 3, 5, 7);
  lim: Double;
begin
  e := Int64(X.Precision) - X.Scale - 1;
  m := X.ScaleByPowerOfTen(Integer(-e));          // 1 <= m < 10
  md := ApproxAbs(m);
  if md >= 9.5 then
  begin
    // use m' = m / 10 near 1 with one more power of ten
    Inc(e);
    m := m.ScaleByPowerOfTen(-1);
    ci := 0;
  end
  else
  begin
    best := 1e300;
    ci := 0;
    for i := 0 to High(LnTable) do
    begin
      dist := Abs(md * LnTable[i].B / LnTable[i].A - 1.0);
      if dist < best then begin best := dist; ci := i; end;
    end;
  end;
  W2 := W + 8 + Length(IntToStr(Abs(e)));
  mb := m * TBigDecimal.Create(LnTable[ci].B);
  zn := FxFromDecimal(mb - TBigDecimal.Create(LnTable[ci].A), W);
  zd := FxFromDecimal(mb + TBigDecimal.Create(LnTable[ci].A), W);
  if zn.V.IsZero then
    sum := FxFromInt(0, W)
  else
  begin
    zne := mb - TBigDecimal.Create(LnTable[ci].A);
    zde := mb + TBigDecimal.Create(LnTable[ci].A);
    if (W >= LnSplitDigits) and LnSplitUseful(zne, zde, W) then
      sum := LnAtanhFx(zne, zde, W)
    else
    begin
      z := FxDiv(zn, zd);
      z2 := FxSqr(z);
      t := z;
      sum := z;
      kterm := 1;
      while not FxTiny(t) do
      begin
        t := FxMul(t, z2);
        term := FxDivInt(t, 2 * kterm + 1);
        sum := FxAdd(sum, term);
        Inc(kterm);
      end;
      sum.E += 2;
      sum := FxMulInt(sum, 2);
    end;
  end;
  res := sum;
  // + ln c
  for j := 0 to 3 do
    if LnTable[ci].Ex[j] <> 0 then
    begin
      cl := FxMulInt(ConstLnPrime(primes[j], W2), LnTable[ci].Ex[j]);
      res := FxAdd(res, FxRescale(cl, W));
    end;
  // + e * ln 10
  if e <> 0 then
  begin
    cl := FxMulInt(ConstLn10(W2), e);
    res := FxAdd(res, FxRescale(cl, W));
  end;
  Result := res;
end;

function LnLead(const X: TBigDecimal): Integer;
var
  d: TBigDecimal;
  adj: Int64;
begin
  // extra digits when X is close to 1 (cancellation in the result)
  d := X - TBigDecimal.One;
  if d.IsZero then Exit(0);
  adj := Int64(d.Precision) - d.Scale - 1;
  if adj >= -1 then Exit(0);
  if adj < -100000000 then Exit(100000000);
  Result := Integer(-adj);
end;

function Ln(const X: TBigDecimal; const C: TMathContext): TBigDecimal;
var
  w, p: Integer;
  y: TFx;
  r: TBigDecimal;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  if X.Sign <= 0 then raise EBigDecimalDomain.Create('logarithm of a non-positive value');
  CheckFinite(C, 'Ln');
  p := C.Precision;
  if X.CompareTo(TBigDecimal.One) = 0 then Exit(TBigDecimal.Zero);
  w := p + 16 + LnLead(X) + Length(IntToStr(Abs(Int64(X.Precision) - X.Scale)));
  repeat
    y := LnFxCore(X, w);
    if FxRound(y, C, r) then Exit(r);
    if not NextW(w, p) then
      raise EBigDecimalPrecision.Create('Ln could not be rounded');
  until False;
end;

function Ln(const X: TBigDecimal): TBigDecimal;
var
  c: TMathContext;
begin
  RequireContext(c);
  Result := Ln(X, c);
end;

{ ----- log10, log, exact power detection ----- }

function IsPowerOfTen(const X: TBigDecimal; out K: Int64): Boolean;
var
  s: TBigDecimal;
begin
  Result := False;
  if X.Sign <= 0 then Exit;
  s := X.StripTrailingZeros;
  if s.UnscaledValue.CompareTo(TBigDecimal.One) = 0 then
  begin
    K := -Int64(s.Scale);
    Result := True;
  end;
end;

function Log10(const X: TBigDecimal; const C: TMathContext): TBigDecimal;
var
  w, p: Integer;
  k: Int64;
  l, d, q: TFx;
  r: TBigDecimal;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  if X.Sign <= 0 then raise EBigDecimalDomain.Create('logarithm of a non-positive value');
  if IsPowerOfTen(X, k) then Exit(TBigDecimal.Create(k).Round(C));
  CheckFinite(C, 'Log10');
  p := C.Precision;
  w := p + 16 + LnLead(X) + Length(IntToStr(Abs(Int64(X.Precision) - X.Scale)));
  repeat
    l := LnFxCore(X, w);
    d := ConstLn10(w);
    q := FxDiv(l, d);
    if FxRound(q, C, r) then Exit(r);
    if not NextW(w, p) then
      raise EBigDecimalPrecision.Create('Log10 could not be rounded');
  until False;
end;

function Log10(const X: TBigDecimal): TBigDecimal;
var
  c: TMathContext;
begin
  RequireContext(c);
  Result := Log10(X, c);
end;

function ExactRational(const V: TBigDecimal; MaxDen: Integer; out A: Int64;
  out Q: Integer): Boolean;
var
  u: TBigDecimal;
  s: Integer;
  num, den: Int64;
  g: Int64;
begin
  // value = unscaled * 10^-scale, reduced to a / q with q a product of 2 and 5
  Result := False;
  u := V.StripTrailingZeros;
  s := u.Scale;
  if s <= 0 then
  begin
    Result := False;
    Exit;
  end;
  if (u.UnscaledValue.Precision > 18) or (s > 18) then Exit;
  num := u.UnscaledValue.ToInt64;
  den := 1;
  while s > 0 do begin den *= 10; Dec(s); end;
  g := 1;
  while ((num mod 2) = 0) and ((den mod 2) = 0) do begin num := num div 2; den := den div 2; end;
  while ((num mod 5) = 0) and ((den mod 5) = 0) do begin num := num div 5; den := den div 5; end;
  if den > MaxDen then Exit;
  A := num;
  Q := Integer(den);
  Result := True;
end;

{ Perfect K-th power test for a positive decimal. }
function ExactRoot(const X: TBigDecimal; K: Integer; out R: TBigDecimal): Boolean;
var
  s: TBigDecimal;
  u, root: TBigDecimal;
  sc, t, f: Int64;
begin
  Result := False;
  s := X.StripTrailingZeros;
  u := s.UnscaledValue;
  sc := s.Scale;                       // value = u * 10^-sc
  // choose t so that (-sc - t) is divisible by K
  t := (((-sc) mod K) + K) mod K;
  if t <> 0 then
    u := u.ScaleByPowerOfTen(Integer(t)).SetScale(0, rmUnnecessary);
  f := (-sc - t) div K;
  if Double(u.Precision) > 100000 then Exit;
  root := IRootFloor(u, K);
  if PowExact(root, K).CompareTo(u) <> 0 then Exit;
  R := TBigDecimal.Create(root, Integer(-f));
  R := R.SetScale(R.Scale, rmUnnecessary);
  Result := True;
end;

function Log(const B, X: TBigDecimal; const C: TMathContext): TBigDecimal;
var
  w, p, q, a, qq: Integer;
  lx, lb, qf: TFx;
  r, v, vq, near, cand: TBigDecimal;
  ctx: TMathContext;
  k: Int64;
  ex, x1, b1: TBigDecimal;
  aa: Int64;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  if (X.Sign <= 0) or (B.Sign <= 0) then
    raise EBigDecimalDomain.Create('logarithm domain error');
  if B.CompareTo(TBigDecimal.One) = 0 then
    raise EBigDecimalDomain.Create('logarithm base is one');
  if IsPowerOfTen(B, k) and (k = 1) then Exit(Log10(X, C));
  if X.CompareTo(TBigDecimal.One) = 0 then Exit(TBigDecimal.Zero);
  CheckFinite(C, 'Log');
  p := C.Precision;
  // exact rational results: log_b(x) = a/q when x^q = b^a
  ctx := TMathContext.Make(40, rmHalfEven);
  v := Ln(X, ctx).Divide(Ln(B, ctx), ctx);
  for qq := 1 to 8 do
  begin
    vq := v * TBigDecimal.Create(qq);
    near := vq.SetScale(0, rmHalfEven);
    if (vq - near).Abs.CompareTo(TBigDecimal.Create('1E-25')) < 0 then
    begin
      aa := near.ToInt64;
      if aa = 0 then Continue;
      if (Double(X.Precision) * qq > 3000) or (Double(B.Precision) * Abs(aa) > 3000) then Continue;
      try
        x1 := PowExact(X, qq);
        b1 := PowExact(B, Abs(aa));
        if aa > 0 then ex := x1.CompareTo(b1)
          else ex := (x1 * b1).CompareTo(TBigDecimal.One);
        if aa > 0 then a := Ord(x1.CompareTo(b1) = 0)
          else a := Ord((x1 * b1).CompareTo(TBigDecimal.One) = 0);
        if a = 1 then
        begin
          try
            cand := TBigDecimal.Create(aa).Divide(TBigDecimal.Create(qq));
            Exit(cand.Round(C));
          except
            on EBigDecimalNonTerminating do Break;
          end;
        end;
      except
        on EBigDecimalOverflow do Continue;
      end;
    end;
  end;
  w := p + 18 + Max(LnLead(X), LnLead(B)) +
       Length(IntToStr(Abs(Int64(X.Precision) - X.Scale)));
  repeat
    lx := LnFxCore(X, w);
    lb := LnFxCore(B, w);
    qf := FxDiv(lx, lb);
    if FxRound(qf, C, r) then Exit(r);
    if not NextW(w, p) then
      raise EBigDecimalPrecision.Create('Log could not be rounded');
  until False;
end;

function Log(const B, X: TBigDecimal): TBigDecimal;
var
  c: TMathContext;
begin
  RequireContext(c);
  Result := Log(B, X, c);
end;

{ ----- pow ----- }

function Pow(const X: TBigDecimal; N: Int64; const C: TMathContext): TBigDecimal;
var
  w, p, extra: Integer;
  base, y, err, lo, hi, r1, r2: TBigDecimal;
  e: Int64;
  wc: TMathContext;
  digitsEst: Double;
  neg: Boolean;
  relErr: TBigDecimal;
  exactAll: Boolean;
  xs, v: TBigDecimal;
  pad: Int64;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  if N = 0 then Exit(TBigDecimal.One);
  if X.IsZero then
  begin
    if N > 0 then Exit(TBigDecimal.Zero);
    raise EBigDecimalDivByZero.Create('zero to a negative power');
  end;
  neg := N < 0;
  if neg then N := -N;
  xs := X.StripTrailingZeros;
  digitsEst := Ln(Max(1.0, ApproxAbs(xs.UnscaledValue))) / 2.302585 * N + 1;
  if (digitsEst <= 20000) or (C.Precision = 0) then
  begin
    v := PowExact(xs, N);
    if neg then
    begin
      if C.Precision = 0 then Exit(TBigDecimal.One.Divide(v));
      Exit(TBigDecimal.One.Divide(v, C));
    end;
    if C.Precision = 0 then
      Exit(v.SetScale(Integer(Int64(X.Scale) * N), rmUnnecessary));
    p := C.Precision;
    if v.Precision > p then Exit(v.Round(C));
    pad := Int64(X.Scale) * N - v.Scale;
    if pad < 0 then pad := 0;
    Exit(v.SetScale(Integer(Int64(v.Scale) + Min(pad, p - v.Precision)), rmUnnecessary));
  end;
  p := C.Precision;
  // large: rounded square-and-multiply at a raised precision
  extra := Length(IntToStr(N)) + 6;
  w := p + extra;
  repeat
    wc := TMathContext.Make(w, rmHalfEven);
    y := TBigDecimal.One;
    base := X;
    if base.Precision > w then begin base := base.Round(wc); exactAll := False; end
    else exactAll := True;
    e := N;
    while e > 0 do
    begin
      if (e and 1) = 1 then
      begin
        y := y * base;
        if y.Precision > w then begin y := y.Round(wc); exactAll := False; end;
      end;
      e := e shr 1;
      if e > 0 then
      begin
        base := base.Square;
        if base.Precision > w then begin base := base.Round(wc); exactAll := False; end;
      end;
    end;
    if exactAll then
    begin
      if neg then Exit(TBigDecimal.One.Divide(y, C));
      Exit(y.Round(C));
    end;
    if neg then y := TBigDecimal.One.Divide(y, wc);
    // relative error bound: 3 * N * 10^(1-w), doubled for the reciprocal
    relErr := TBigDecimal.Create(6 * N).ScaleByPowerOfTen(1 - w);
    err := y.Abs * relErr;
    lo := y - err;
    hi := y + err;
    r1 := lo.Round(C);
    r2 := hi.Round(C);
    if r1.Identical(r2) then Exit(r1);
    if not NextW(w, p) then
      raise EBigDecimalPrecision.Create('Pow could not be rounded');
  until False;
end;

function Pow(const X: TBigDecimal; N: Int64): TBigDecimal;
var
  c: TMathContext;
begin
  if EffectiveContext(c) then Result := Pow(X, N, c)
  else Result := Pow(X, N, Unlimited);
end;

function Pow(const X, Y: TBigDecimal; const C: TMathContext): TBigDecimal;
var
  w, p, dk: Integer;
  a: Int64;
  q: Integer;
  root, rp: TBigDecimal;
  yi: TBigDecimal;
  l, t, ey, yf: TFx;
  k: Int64;
  r: TBigDecimal;
  td: Double;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  if Y.IsZero then Exit(TBigDecimal.One);
  if Y.IsInteger then
  begin
    yi := Y.SetScale(0, rmUnnecessary);
    if yi.Precision > 18 then raise EBigDecimalOverflow.Create('exponent is too large');
    Exit(Pow(X, yi.ToInt64, C));
  end;
  if X.IsZero then
  begin
    if Y.Sign > 0 then Exit(TBigDecimal.Zero);
    raise EBigDecimalDivByZero.Create('zero to a negative power');
  end;
  if X.Sign < 0 then raise EBigDecimalDomain.Create('negative base with a fractional exponent');
  if X.CompareTo(TBigDecimal.One) = 0 then
  begin
    if C.Precision > 1 then Exit(TBigDecimal.One.SetScale(C.Precision - 1, rmUnnecessary));
    Exit(TBigDecimal.One);
  end;
  // exact result through a perfect root
  if ExactRational(Y, 64, a, q) and (q > 1) then
  begin
    if ExactRoot(X, q, root) then
    begin
      try
        if a > 0 then rp := PowExact(root, a)
        else rp := TBigDecimal.One.Divide(PowExact(root, -a));
        if C.Precision > 0 then
        begin
          rp := rp.Round(C);
          // a fractional exponent gives a result of full precision, as in the
          // General Decimal Arithmetic power operation
          if rp.Precision < C.Precision then
            rp := rp.SetScale(rp.Scale + C.Precision - rp.Precision, rmUnnecessary);
          Exit(rp);
        end;
        Exit(rp);
      except
        on EBigDecimalNonTerminating do ;
        on EBigDecimalOverflow do ;
      end;
    end;
  end;
  CheckFinite(C, 'Pow');
  p := C.Precision;
  td := SignedApprox(Y) * (Int64(X.Precision) - X.Scale) * 2.302585;
  dk := Length(IntToStr(Abs(Trunc(Min(1e15, Abs(td)))))) + 2;
  w := p + 20 + dk + LnLead(X) + 10;
  repeat
    l := LnFxCore(X, w);
    yf := FxFromDecimal(Y, w);
    t := FxMul(yf, l);
    ey := ExpFxCore(t, k);
    if FxRoundShifted(ey, k, C, r) then Exit(r);
    if not NextW(w, p) then
      raise EBigDecimalPrecision.Create('Pow could not be rounded');
  until False;
end;

function Pow(const X, Y: TBigDecimal): TBigDecimal;
var
  c: TMathContext;
begin
  RequireContext(c);
  Result := Pow(X, Y, c);
end;

function LnFx(const X: TBigDecimal; W: Integer): TFx;
var
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  Result := LnFxCore(X, W);
end;

function ExpFx(const X: TFx; out K: Int64): TFx;
var
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  Result := ExpFxCore(X, K);
end;

end.
