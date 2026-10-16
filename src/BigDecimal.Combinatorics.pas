{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: factorial, binomial, combinatorics, prime sieve, swing
documentation: doc/design.md
notes:
  - factorial uses binary splitting, then the swing recursion for large n
  - binomial coefficients use the multiplicative form, then Kummer prime factorization
  - exact functions ignore the thread-local default context
---
}
unit BigDecimal.Combinatorics;

{$mode objfpc}{$H+}
{$coperators on}

interface

uses
  SysUtils, BigDecimal.Types, BigDecimal;

type
  TInt64Array = array of Int64;

var
  { n at which Factorial switches from range splitting to the swing recursion. }
  FactorialSwingThreshold: Integer = 600;     // bench/RESULTS.md: swing wins from about 600
  { k at which Binomial switches from the multiplicative form to Kummer. }
  BinomialKummerThreshold: Integer = 12;      // Kummer wins from k = 13 (when n is moderate)
  { Largest n for which Binomial sieves primes (the sieve needs n/2 bytes). }
  BinomialSieveLimit: Int64 = 4000000;

{ Primes up to N in increasing order (sieve of Eratosthenes, odd numbers only). }
function PrimesUpTo(N: Int64): TInt64Array;

function Factorial(N: Int64): TBigDecimal;
function FactorialLegendre(N: Int64): TBigDecimal;   // oracle and benchmark candidate
function FactorialRange(N: Int64): TBigDecimal;       // plain binary splitting
function DoubleFactorial(N: Int64): TBigDecimal;
function Primorial(N: Int64): TBigDecimal;
function FallingFactorial(N, K: Int64): TBigDecimal;
function Permutations(N, K: Int64): TBigDecimal;
function RisingFactorial(const X: TBigDecimal; K: Int64): TBigDecimal;
function RisingFactorial(N, K: Int64): TBigDecimal;
function Binomial(N, K: Int64): TBigDecimal;
function BinomialMultiplicative(N, K: Int64): TBigDecimal;  // oracle and benchmark candidate
function BinomialKummer(N, K: Int64): TBigDecimal;          // oracle and benchmark candidate
function CentralBinomial(N: Int64): TBigDecimal;
function Catalan(N: Int64): TBigDecimal;
function Multinomial(const Parts: array of Int64): TBigDecimal;
{ x (x-1) ... (x-k+1) / k! for a decimal x, rounded to the context. }
function Binomial(const X: TBigDecimal; K: Int64; const C: TMathContext): TBigDecimal;
function FallingFactorial(const X: TBigDecimal; K: Int64): TBigDecimal;

{ Natural log of n! as a Double estimate (Stirling), for size guards. }
function LnFactorialApprox(N: Double): Double;

implementation

uses
  Math, BigDecimal.Math;

const
  SmallFactorials: array[0..20] of UInt64 = (
    1, 1, 2, 6, 24, 120, 720, 5040, 40320, 362880, 3628800, 39916800,
    479001600, 6227020800, 87178291200, 1307674368000, 20922789888000,
    355687428096000, 6402373705728000, 121645100408832000, 2432902008176640000);

function LnFactorialApprox(N: Double): Double;
begin
  if N < 2 then Exit(0.0);
  Result := N * Ln(N) - N + 0.5 * Ln(2 * Pi * N) + 1.0 / (12 * N);
end;

procedure CheckSize(Digits10: Double);
begin
  if Digits10 > MaxExactDigits then
    raise EBigDecimalOverflow.Create('result has too many digits');
end;

procedure CheckArg(N: Int64);
begin
  if N < 0 then raise EBigDecimalDomain.Create('argument must not be negative');
end;

function PrimesUpTo(N: Int64): TInt64Array;
var
  bits: array of Byte;
  half, i, j, cnt, lim: Int64;
begin
  Result := nil;
  if N < 2 then Exit;
  // index i stands for the odd number 2*i+1; index 0 is the number 1
  half := (N - 1) div 2 + 1;
  SetLength(bits, half);
  FillChar(bits[0], half, 0);
  bits[0] := 1;
  lim := Trunc(Sqrt(Double(N))) + 1;
  i := 1;
  while (2 * i + 1) <= lim do
  begin
    if bits[i] = 0 then
    begin
      j := ((2 * i + 1) * (2 * i + 1) - 1) div 2;
      while j < half do
      begin
        bits[j] := 1;
        j += 2 * i + 1;
      end;
    end;
    Inc(i);
  end;
  cnt := 1;
  for i := 1 to half - 1 do
    if bits[i] = 0 then Inc(cnt);
  SetLength(Result, cnt);
  Result[0] := 2;
  cnt := 1;
  for i := 1 to half - 1 do
    if bits[i] = 0 then
    begin
      Result[cnt] := 2 * i + 1;
      Inc(cnt);
    end;
end;

{ Product of F[Lo..Hi] by binary splitting. Factors are packed into UInt64
  words first, then the words multiply in a balanced tree. }
function TreeProduct(const F: array of UInt64; Lo, Hi: Integer): TBigDecimal;
var
  mid: Integer;
  acc: UInt64;
  i: Integer;
begin
  if Hi < Lo then Exit(TBigDecimal.One);
  if Hi - Lo < 24 then
  begin
    Result := TBigDecimal.One;
    acc := 1;
    for i := Lo to Hi do
    begin
      if (F[i] <> 0) and (acc > High(UInt64) div F[i]) then
      begin
        Result := Result * TBigDecimal.FromUInt64(acc);
        acc := F[i];
      end
      else
        acc *= F[i];
    end;
    Result := Result * TBigDecimal.FromUInt64(acc);
    Exit;
  end;
  mid := (Lo + Hi) div 2;
  Result := TreeProduct(F, Lo, mid) * TreeProduct(F, mid + 1, Hi);
end;

function FactorialRange(N: Int64): TBigDecimal;
var
  f: array of UInt64;
  i: Int64;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  CheckArg(N);
  if N <= 20 then Exit(TBigDecimal.FromUInt64(SmallFactorials[N]));
  CheckSize(LnFactorialApprox(N) / 2.302585 + 1);
  SetLength(f, N - 1);
  for i := 2 to N do f[i - 2] := UInt64(i);
  Result := TreeProduct(f, 0, High(f));
end;

function SwingNumber(N: Int64): TBigDecimal;
var
  primes: TInt64Array;
  f: array of UInt64;
  cnt: Integer;
  i: Integer;
  p, q, e, pw: Int64;
  j: Integer;
begin
  primes := PrimesUpTo(N);
  SetLength(f, Length(primes));
  cnt := 0;
  for i := 0 to High(primes) do
  begin
    p := primes[i];
    e := 0;
    q := N;
    while q > 0 do
    begin
      q := q div p;
      if (q and 1) = 1 then Inc(e);
    end;
    if e = 0 then Continue;
    pw := 1;
    for j := 1 to e do pw *= p;
    f[cnt] := UInt64(pw);
    Inc(cnt);
  end;
  Result := TreeProduct(f, 0, cnt - 1);
end;

function Factorial(N: Int64): TBigDecimal;
var
  h: TBigDecimal;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  CheckArg(N);
  if N <= 20 then Exit(TBigDecimal.FromUInt64(SmallFactorials[N]));
  CheckSize(LnFactorialApprox(N) / 2.302585 + 1);
  if N < FactorialSwingThreshold then Exit(FactorialRange(N));
  h := Factorial(N div 2);
  Result := h.Square * SwingNumber(N);
end;

function FactorialLegendre(N: Int64): TBigDecimal;
var
  primes: TInt64Array;
  i: Integer;
  p, q, e: Int64;
  parts: array of TBigDecimal;
  cnt, lo, hi, step: Integer;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  CheckArg(N);
  if N <= 20 then Exit(TBigDecimal.FromUInt64(SmallFactorials[N]));
  primes := PrimesUpTo(N);
  SetLength(parts, Length(primes));
  cnt := 0;
  for i := 0 to High(primes) do
  begin
    p := primes[i];
    e := 0;
    q := N;
    while q > 0 do begin q := q div p; e += q; end;
    parts[cnt] := PowExact(TBigDecimal.Create(p), e);
    Inc(cnt);
  end;
  // pairwise product tree
  step := 1;
  while step < cnt do
  begin
    lo := 0;
    while lo + step < cnt do
    begin
      parts[lo] := parts[lo] * parts[lo + step];
      lo += 2 * step;
    end;
    step *= 2;
  end;
  hi := 0;
  Result := parts[hi];
end;

function DoubleFactorial(N: Int64): TBigDecimal;
var
  f: array of UInt64;
  cnt: Integer;
  i: Int64;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  CheckArg(N);
  if N <= 1 then Exit(TBigDecimal.One);
  CheckSize(LnFactorialApprox(N) / 2.302585 / 2 + 2);
  SetLength(f, N div 2 + 1);
  cnt := 0;
  i := N;
  while i >= 2 do
  begin
    f[cnt] := UInt64(i);
    Inc(cnt);
    i -= 2;
  end;
  Result := TreeProduct(f, 0, cnt - 1);
end;

function Primorial(N: Int64): TBigDecimal;
var
  primes: TInt64Array;
  f: array of UInt64;
  i: Integer;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  CheckArg(N);
  if N < 2 then Exit(TBigDecimal.One);
  CheckSize(N / 2.302585 + 1);
  primes := PrimesUpTo(N);
  SetLength(f, Length(primes));
  for i := 0 to High(primes) do f[i] := UInt64(primes[i]);
  Result := TreeProduct(f, 0, High(f));
end;

function FallingFactorial(N, K: Int64): TBigDecimal;
var
  f: array of UInt64;
  i: Int64;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  CheckArg(N);
  CheckArg(K);
  if K = 0 then Exit(TBigDecimal.One);
  if K > N then Exit(TBigDecimal.Zero);
  CheckSize(K * Log10(Max(2.0, Double(N))) + 1);
  SetLength(f, K);
  for i := 0 to K - 1 do f[i] := UInt64(N - i);
  Result := TreeProduct(f, 0, K - 1);
end;

function Permutations(N, K: Int64): TBigDecimal;
begin
  Result := FallingFactorial(N, K);
end;

function RisingFactorial(N, K: Int64): TBigDecimal;
var
  f: array of UInt64;
  i: Int64;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  CheckArg(N);
  CheckArg(K);
  if K = 0 then Exit(TBigDecimal.One);
  CheckSize(K * Log10(Max(2.0, Double(N + K))) + 1);
  SetLength(f, K);
  for i := 0 to K - 1 do f[i] := UInt64(N + i);
  Result := TreeProduct(f, 0, K - 1);
end;

function DecimalTree(const F: array of TBigDecimal; Lo, Hi: Integer): TBigDecimal;
var
  mid: Integer;
begin
  if Hi < Lo then Exit(TBigDecimal.One);
  if Lo = Hi then Exit(F[Lo]);
  mid := (Lo + Hi) div 2;
  Result := DecimalTree(F, Lo, mid) * DecimalTree(F, mid + 1, Hi);
end;

function RisingFactorial(const X: TBigDecimal; K: Int64): TBigDecimal;
var
  f: array of TBigDecimal;
  i: Int64;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  CheckArg(K);
  if K = 0 then Exit(TBigDecimal.One);
  SetLength(f, K);
  for i := 0 to K - 1 do f[i] := X + TBigDecimal.Create(i);
  Result := DecimalTree(f, 0, K - 1);
end;

function FallingFactorial(const X: TBigDecimal; K: Int64): TBigDecimal;
var
  f: array of TBigDecimal;
  i: Int64;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  CheckArg(K);
  if K = 0 then Exit(TBigDecimal.One);
  SetLength(f, K);
  for i := 0 to K - 1 do f[i] := X - TBigDecimal.Create(i);
  Result := DecimalTree(f, 0, K - 1);
end;

function BinomialMultiplicative(N, K: Int64): TBigDecimal;
var
  i: Int64;
  r: TBigDecimal;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  CheckArg(N);
  CheckArg(K);
  if K > N then Exit(TBigDecimal.Zero);
  if K > N - K then K := N - K;
  r := TBigDecimal.One;
  for i := 1 to K do
  begin
    r := r * TBigDecimal.Create(N - K + i);
    r := r.Divide(TBigDecimal.Create(i), 0, rmDown);
  end;
  Result := r;
end;

function BinomialKummer(N, K: Int64): TBigDecimal;
var
  primes: TInt64Array;
  f: array of UInt64;
  cnt, i, j: Integer;
  p, e, pn, pk, pr: Int64;
  pw: UInt64;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  CheckArg(N);
  CheckArg(K);
  if K > N then Exit(TBigDecimal.Zero);
  if K > N - K then K := N - K;
  if K = 0 then Exit(TBigDecimal.One);
  primes := PrimesUpTo(N);
  SetLength(f, Length(primes));
  cnt := 0;
  for i := 0 to High(primes) do
  begin
    p := primes[i];
    e := 0;
    pn := N;
    pk := K;
    pr := N - K;
    while pn > 0 do
    begin
      pn := pn div p;
      pk := pk div p;
      pr := pr div p;
      e += pn - pk - pr;
    end;
    if e = 0 then Continue;
    pw := 1;
    for j := 1 to e do pw *= UInt64(p);
    f[cnt] := pw;
    Inc(cnt);
  end;
  Result := TreeProduct(f, 0, cnt - 1);
end;

function Binomial(N, K: Int64): TBigDecimal;
var
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  CheckArg(N);
  CheckArg(K);
  if K > N then Exit(TBigDecimal.Zero);
  if K > N - K then K := N - K;
  if K = 0 then Exit(TBigDecimal.One);
  // size guard through the entropy bound ln C(n,k) <= k ln(e n / k)
  CheckSize(K * (Ln(Double(N) / K) + 1) / 2.302585 + 1);
  if (K <= BinomialKummerThreshold) or (N > BinomialSieveLimit) then
    Result := BinomialMultiplicative(N, K)
  else
    Result := BinomialKummer(N, K);
end;

function CentralBinomial(N: Int64): TBigDecimal;
begin
  CheckArg(N);
  Result := Binomial(2 * N, N);
end;

function Catalan(N: Int64): TBigDecimal;
begin
  CheckArg(N);
  Result := CentralBinomial(N).Divide(TBigDecimal.Create(N + 1), 0, rmDown);
end;

function Multinomial(const Parts: array of Int64): TBigDecimal;
var
  i: Integer;
  total: Int64;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  Result := TBigDecimal.One;
  total := 0;
  for i := 0 to High(Parts) do
  begin
    CheckArg(Parts[i]);
    total += Parts[i];
    Result := Result * Binomial(total, Parts[i]);
  end;
end;

function Binomial(const X: TBigDecimal; K: Int64; const C: TMathContext): TBigDecimal;
var
  num, den: TBigDecimal;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  CheckArg(K);
  if K = 0 then Exit(TBigDecimal.One);
  num := FallingFactorial(X, K);
  den := Factorial(K);
  if C.Precision = 0 then Result := num.Divide(den)
  else Result := num.Divide(den, C);
end;

end.
