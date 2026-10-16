{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: benchmark
notes:
  - crossover tables for kernel thresholds and function timings
---
}
program BenchAll;
{ Benchmarks for the kernels and functions. Prints crossover tables used to set
  KaratsubaThreshold, NewtonDivThreshold, FactorialSwingThreshold and
  BinomialKummerThreshold. Run: make bench }
{$mode objfpc}{$H+}
{$coperators on}
uses
  SysUtils, DateUtils, BigDecimal.Types, BigDecimal.Limbs, BigDecimal.Multiply,
  BigDecimal.Divide, BigDecimal, BigDecimal.Math, BigDecimal.Trig,
  BigDecimal.Combinatorics, BigDecimal.Gamma, BigDecimal.Constants;

function Pick(B: Boolean; const S1, S2: string): string;
begin
  if B then Result := S1 else Result := S2;
end;

function Secs: Double;
begin
  Result := Now * 86400.0;
end;

function RandLimbs(n: Integer): TLimbs;
var
  i: Integer;
begin
  SetLength(Result, n);
  for i := 0 to n - 1 do Result[i] := Random(LimbBase);
  Result[n - 1] := 1 + Random(LimbBase - 1);
end;

{ Best of seven trials, which keeps a busy machine from skewing a table. }
function TimeIt(Reps: Integer; const P: TProcedure): Double;
var
  t0, best, t: Double;
  i, trial: Integer;
begin
  best := 1e30;
  for trial := 1 to 7 do
  begin
    t0 := Secs;
    for i := 1 to Reps do P();
    t := (Secs - t0) / Reps * 1e6;   // microseconds
    if t < best then best := t;
  end;
  Result := best;
end;

{ Best of 15 alternating trials of two procedures. Alternation exposes both to
  the same load. }
procedure TimeBoth(Reps: Integer; const P1, P2: TProcedure; out T1, T2: Double);
var
  t0, t: Double;
  i, trial: Integer;
begin
  T1 := 1e30;
  T2 := 1e30;
  for trial := 1 to 15 do
  begin
    t0 := Secs;
    for i := 1 to Reps do P1();
    t := (Secs - t0) / Reps * 1e6;
    if t < T1 then T1 := t;
    t0 := Secs;
    for i := 1 to Reps do P2();
    t := (Secs - t0) / Reps * 1e6;
    if t < T2 then T2 := t;
  end;
end;

var
  GA, GB, GR: TLimbs;
  GNA, GNB: Integer;
  GQ, GRem: TLimbs;
  GUseK: Boolean;

procedure DoMul;
begin
  MulMagForce(@GA[0], GNA, @GB[0], GNB, @GR[0], GUseK);
end;

procedure DoSchool;
begin
  MulMagForce(@GA[0], GNA, @GB[0], GNB, @GR[0], False);
end;

procedure DoKara;
begin
  MulMagForce(@GA[0], GNA, @GB[0], GNB, @GR[0], True);
end;

procedure DoKnuth;
var nq, nr: Integer;
begin
  DivRemKnuth(@GA[0], GNA, @GB[0], GNB, @GQ[0], nq, @GRem[0], nr);
end;

procedure DoNewton;
var nq, nr: Integer;
begin
  DivRemNewton(@GA[0], GNA, @GB[0], GNB, @GQ[0], nq, @GRem[0], nr);
end;

var
  n, reps, i, k: Integer;
  t1, t2: Double;
  sizes: array of Integer;
  c: TMathContext;
  x, y: TBigDecimal;
  nn: Int64;
  lst: array of Int64;
  ii: Integer;
begin
  Randomize;
  WriteLn('Multiplication, microseconds per product (balanced operands)');
  WriteLn('limbs   schoolbook   karatsuba   winner');
  sizes := [64, 96, 112, 128, 144, 160, 192, 256, 512, 1024, 2048];
  for ii := 0 to High(sizes) do
  begin
    n := sizes[ii];
    GNA := n; GNB := n;
    GA := RandLimbs(n); GB := RandLimbs(n);
    SetLength(GR, 2 * n);
    reps := 400000 div (n * n div 16 + 1) + 3;
    TimeBoth(reps, @DoSchool, @DoKara, t1, t2);
    WriteLn(n : 5, t1 : 12 : 2, t2 : 12 : 2, '   ', Pick(t2 < t1, 'karatsuba', 'schoolbook'));
  end;
  WriteLn;
  WriteLn('Division of a 2n-limb number by an n-limb number, microseconds');
  WriteLn('limbs   knuth        newton       winner');
  sizes := [96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048, 4096];
  for ii := 0 to High(sizes) do
  begin
    n := sizes[ii];
    GNA := 2 * n; GNB := n;
    GA := RandLimbs(2 * n); GB := RandLimbs(n);
    SetLength(GQ, n + 4); SetLength(GRem, n + 2);
    reps := 200000 div (n * n div 16 + 1) + 2;
    TimeBoth(reps, @DoKnuth, @DoNewton, t1, t2);
    WriteLn(n : 5, t1 : 12 : 2, t2 : 12 : 2, '   ', Pick(t2 < t1, 'newton', 'knuth'));
  end;
  WriteLn;
  WriteLn('Factorial, milliseconds (range splitting, swing, Legendre)');
  WriteLn('n        range      swing     legendre');
  lst := [500, 600, 700, 800, 1000, 1500, 2000, 4000, 8000, 20000, 50000, 100000];
  for ii := 0 to High(lst) do
  begin
    nn := lst[ii];
    reps := Integer(2000000 div (nn + 1)) + 1;
    t1 := Secs; for i := 1 to reps do FactorialRange(nn); t1 := (Secs - t1) / reps * 1000;
    FactorialSwingThreshold := 1;
    t2 := Secs; for i := 1 to reps do Factorial(nn); t2 := (Secs - t2) / reps * 1000;
    FactorialSwingThreshold := 1500;
    k := 0;
    x := TBigDecimal.Zero;
    y := TBigDecimal.Zero;
    WriteLn(nn : 7, t1 : 11 : 3, t2 : 11 : 3);
  end;
  WriteLn;
  WriteLn('Binomial C(2k, k), milliseconds (multiplicative, Kummer)');
  WriteLn('k        multiplicative  kummer');
  lst := [20, 50, 100, 200, 400, 1000, 3000, 10000];
  for ii := 0 to High(lst) do
  begin
    nn := lst[ii];
    reps := Integer(300000 div (nn * 4)) + 2;
    t1 := Secs; for i := 1 to reps do BinomialMultiplicative(2 * nn, nn); t1 := (Secs - t1) / reps * 1000;
    t2 := Secs; for i := 1 to reps do BinomialKummer(2 * nn, nn); t2 := (Secs - t2) / reps * 1000;
    WriteLn(nn : 7, t1 : 14 : 4, t2 : 11 : 4);
  end;
  WriteLn;
  WriteLn('Functions, microseconds per call (HalfEven)');
  WriteLn('digits       sqrt        exp         ln         pow(x,y)    sin        gamma(x.5)');
  x := TBigDecimal.Create('2.718281828');
  y := TBigDecimal.Create('1.5');
  lst := [16, 34, 100, 300, 1000];
  for ii := 0 to High(lst) do
  begin
    n := lst[ii];
    c := TMathContext.Make(n, rmHalfEven);
    BigPi(c); // fills the constants cache
    reps := 4000 div (n + 1) + 2;
    t1 := Secs; for i := 1 to reps do Sqrt(x, c); Write(n : 6, ((Secs - t1) / reps * 1e6) : 12 : 1);
    t1 := Secs; for i := 1 to reps do Exp(x, c); Write(((Secs - t1) / reps * 1e6) : 12 : 1);
    t1 := Secs; for i := 1 to reps do Ln(x, c); Write(((Secs - t1) / reps * 1e6) : 12 : 1);
    t1 := Secs; for i := 1 to reps do Pow(x, y, c); Write(((Secs - t1) / reps * 1e6) : 12 : 1);
    t1 := Secs; for i := 1 to reps do Sin(x, c); Write(((Secs - t1) / reps * 1e6) : 12 : 1);
    t1 := Secs; for i := 1 to reps do Gamma(TBigDecimal.Create('7.5'), c); WriteLn(((Secs - t1) / reps * 1e6) : 12 : 1);
  end;
  WriteLn;
  WriteLn('Small-value path, nanoseconds per operation');
  x := TBigDecimal.Create('123456.78');
  y := TBigDecimal.Create('0.0345');
  t1 := Secs; for i := 1 to 2000000 do begin c := TMathContext.Make(10, rmHalfUp); GR := nil; end;
  t1 := Secs;
  for i := 1 to 2000000 do begin y := x + y; y := y - x; end;
  WriteLn('add+subtract  ', ((Secs - t1) / 4000000 * 1e9) : 8 : 1);
  t1 := Secs;
  for i := 1 to 2000000 do y := x * x;
  WriteLn('multiply      ', ((Secs - t1) / 2000000 * 1e9) : 8 : 1);
  TMathContext.SetDefault(Decimal64);
  t1 := Secs;
  for i := 1 to 2000000 do y := x * x;
  WriteLn('multiply, default context set  ', ((Secs - t1) / 2000000 * 1e9) : 8 : 1);
  TMathContext.ClearDefault;
end.
