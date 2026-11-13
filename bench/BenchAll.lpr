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
  SysUtils, BigDecimal.Types, BigDecimal.Limbs, BigDecimal.Multiply,
  BigDecimal.Divide, BigDecimal, BigDecimal.Elementary, BigDecimal.Trig,
  BigDecimal.Combinatorics, BigDecimal.Gamma, BigDecimal.Constants;

function Pick(B: Boolean; const S1, S2: string): string;
begin
  if B then Result := S1 else Result := S2;
end;

function Secs: Double;
begin
  Result := Double(GetTickCount64) / 1000.0;
end;

var
  GSink: Int64 = 0;
  GLastMedian, GLastSpread: Double;
  GMed1, GMed2, GSpread1, GSpread2: Double;

procedure SinkAdd(const X: TBigDecimal);
begin
  GSink := GSink + X.Precision + (X.Precision - X.Scale - 1);
end;

procedure SortD(var A: array of Double);
var
  i, j: Integer;
  t: Double;
begin
  for i := 1 to High(A) do
  begin
    t := A[i]; j := i - 1;
    while (j >= 0) and (A[j] > t) do begin A[j + 1] := A[j]; Dec(j); end;
    A[j + 1] := t;
  end;
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
  t0: Double;
  i, trial: Integer;
  samples: array[0..6] of Double;
begin
  for trial := 0 to 6 do
  begin
    t0 := Secs;
    for i := 1 to Reps do P();
    samples[trial] := (Secs - t0) / Reps * 1e6;   // microseconds
  end;
  SortD(samples);
  Result := samples[0];
  GLastMedian := samples[3];
  // spread is the interquartile range over the median, in percent
  if samples[3] > 0 then GLastSpread := (samples[5] - samples[1]) / samples[3] * 100 else GLastSpread := 0;
end;

{ Best of 15 alternating trials of two procedures. Alternation exposes both to
  the same load. }
procedure TimeBoth(Reps: Integer; const P1, P2: TProcedure; out T1, T2: Double);
var
  t0: Double;
  i, trial: Integer;
  s1, s2: array[0..14] of Double;
begin
  for trial := 0 to 14 do
  begin
    t0 := Secs;
    for i := 1 to Reps do P1();
    s1[trial] := (Secs - t0) / Reps * 1e6;
    t0 := Secs;
    for i := 1 to Reps do P2();
    s2[trial] := (Secs - t0) / Reps * 1e6;
  end;
  SortD(s1); SortD(s2);
  T1 := s1[0]; T2 := s2[0];
  GMed1 := s1[7]; GMed2 := s2[7];
  // spread is the interquartile range over the median, in percent
  if s1[7] > 0 then GSpread1 := (s1[11] - s1[3]) / s1[7] * 100 else GSpread1 := 0;
  if s2[7] > 0 then GSpread2 := (s2[11] - s2[3]) / s2[7] * 100 else GSpread2 := 0;
end;

var
  GNN: Int64;
  GFX, GFY, GFGamma: TBigDecimal;
  GC: TMathContext;
  GRD: TBigDecimal;

procedure DoFactRange; begin GRD := FactorialRange(GNN); SinkAdd(GRD); end;
procedure DoFactSwing; begin GRD := Factorial(GNN); SinkAdd(GRD); end;
procedure DoBinomMult; begin GRD := BinomialMultiplicative(2 * GNN, GNN); SinkAdd(GRD); end;
procedure DoBinomKummer; begin GRD := BinomialKummer(2 * GNN, GNN); SinkAdd(GRD); end;
procedure DoPerm; begin GRD := Permutations(2 * GNN, GNN); SinkAdd(GRD); end;
procedure DoSqrt; begin GRD := Sqrt(GFX, GC); SinkAdd(GRD); end;
procedure DoExp; begin GRD := Exp(GFX, GC); SinkAdd(GRD); end;
procedure DoLn; begin GRD := Ln(GFX, GC); SinkAdd(GRD); end;
procedure DoLog10; begin GRD := Log10(GFX, GC); SinkAdd(GRD); end;
procedure DoPow; begin GRD := Pow(GFX, GFY, GC); SinkAdd(GRD); end;
procedure DoSin; begin GRD := Sin(GFX, GC); SinkAdd(GRD); end;
procedure DoCos; begin GRD := Cos(GFX, GC); SinkAdd(GRD); end;
procedure DoTan; begin GRD := Tan(GFX, GC); SinkAdd(GRD); end;
procedure DoGamma; begin GRD := Gamma(GFGamma, GC); SinkAdd(GRD); end;
procedure DoLnGamma; begin GRD := LnGamma(GFGamma, GC); SinkAdd(GRD); end;
procedure DoAddSub; begin GRD := GFX + GFY; GRD := GRD - GFX; SinkAdd(GRD); end;
procedure DoMulSmall; begin GRD := GFX * GFX; SinkAdd(GRD); end;

function CalReps(const P: TProcedure; Target: Double = 0.05): Integer;
var
  t0: Double;
  i: Integer;
begin
  Result := 1;
  while Result <= 200000000 do
  begin
    t0 := Secs;
    for i := 1 to Result do P();
    if Secs - t0 >= Target then Break;
    Result := Result * 2;
  end;
end;

procedure PrintFunc(const Name: string; Digits: Integer; Reps: Integer; const P: TProcedure);
var
  t: Double;
begin
  t := TimeIt(CalReps(P), P);
  WriteLn(Format('%-8s %6d digits  min %12.1f us  median %12.1f us  spread %6.1f %%',
    [Name, Digits, t, GLastMedian, GLastSpread]));
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
  MulMagForce(@GA[0], GNA, @GB[0], GNB, @GR[0], mkSchool);
end;

procedure DoKara;
begin
  MulMagForce(@GA[0], GNA, @GB[0], GNB, @GR[0], mkKaratsuba);
end;

procedure DoNtt;
begin
  MulMagForce(@GA[0], GNA, @GB[0], GNB, @GR[0], mkNTT);
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
    reps := CalReps(@DoSchool);
    TimeBoth(reps, @DoSchool, @DoKara, t1, t2);
    WriteLn(n : 5, t1 : 12 : 2, t2 : 12 : 2, '   ', Pick(t2 < t1, 'karatsuba', 'schoolbook'),
      Format('  median %.2f/%.2f spread %.1f%%/%.1f%%', [GMed1, GMed2, GSpread1, GSpread2]));
  end;
  WriteLn;
  WriteLn('Multiplication, microseconds per product (Karatsuba vs NTT)');
  WriteLn('limbs   karatsuba    ntt          winner');
  sizes := [512, 1024, 2048, 4096, 8192, 16384, 65536];
  for ii := 0 to High(sizes) do
  begin
    n := sizes[ii];
    GNA := n; GNB := n;
    GA := RandLimbs(n); GB := RandLimbs(n);
    SetLength(GR, 2 * n);
    reps := CalReps(@DoKara);
    TimeBoth(reps, @DoKara, @DoNtt, t1, t2);
    WriteLn(n : 5, t1 : 12 : 2, t2 : 12 : 2, '   ', Pick(t2 < t1, 'ntt', 'karatsuba'),
      Format('  median %.2f/%.2f spread %.1f%%/%.1f%%', [GMed1, GMed2, GSpread1, GSpread2]));
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
    reps := CalReps(@DoKnuth);
    TimeBoth(reps, @DoKnuth, @DoNewton, t1, t2);
    WriteLn(n : 5, t1 : 12 : 2, t2 : 12 : 2, '   ', Pick(t2 < t1, 'newton', 'knuth'),
      Format('  median %.2f/%.2f spread %.1f%%/%.1f%%', [GMed1, GMed2, GSpread1, GSpread2]));
  end;
  WriteLn;
  WriteLn('Factorial, milliseconds (range splitting, swing; min / median / spread)');
  lst := [500, 600, 700, 800, 1000, 1500, 2000, 4000, 8000, 20000, 50000, 100000];
  for ii := 0 to High(lst) do
  begin
    nn := lst[ii]; GNN := nn;
    FactorialSwingThreshold := 1500;
    reps := CalReps(@DoFactRange);
    TimeBoth(reps, @DoFactRange, @DoFactSwing, t1, t2);
    WriteLn(Format('factorial %7d  range min %10.3f ms median %10.3f spread %5.1f %%  swing min %10.3f ms median %10.3f spread %5.1f %%',
      [nn, t1 / 1000, GMed1 / 1000, GSpread1, t2 / 1000, GMed2 / 1000, GSpread2]));
  end;
  WriteLn;
  WriteLn('Binomial C(2k, k), milliseconds (multiplicative, Kummer)');
  lst := [20, 50, 100, 200, 400, 1000, 3000, 10000];
  for ii := 0 to High(lst) do
  begin
    nn := lst[ii]; GNN := nn;
    t1 := TimeIt(CalReps(@DoBinomMult), @DoBinomMult);
    WriteLn(Format('binomial k=%7d multiplicative min %10.4f ms median %10.4f spread %5.1f %%',
      [nn, t1 / 1000, GLastMedian / 1000, GLastSpread]));
    t2 := TimeIt(CalReps(@DoBinomKummer), @DoBinomKummer);
    WriteLn(Format('binomial k=%7d kummer         min %10.4f ms median %10.4f spread %5.1f %%',
      [nn, t2 / 1000, GLastMedian / 1000, GLastSpread]));
    t1 := TimeIt(CalReps(@DoPerm), @DoPerm);
    WriteLn(Format('permutation k=%7d              min %10.4f ms median %10.4f spread %5.1f %%',
      [nn, t1 / 1000, GLastMedian / 1000, GLastSpread]));
  end;
  WriteLn;
  WriteLn('Functions, microseconds per call (HalfEven)');
  GFX := TBigDecimal.Create('2.718281828');
  GFY := TBigDecimal.Create('1.5');
  GFGamma := TBigDecimal.Create('7.5');
  x := GFX; y := GFY;
  lst := [16, 34, 100, 300, 1000];
  for ii := 0 to High(lst) do
  begin
    n := lst[ii];
    c := TMathContext.Make(n, rmHalfEven);
    GC := c;
    BigPi(c); // fills the constants cache
    reps := 5000 div (n + 1) + 3;
    PrintFunc('sqrt', n, reps, @DoSqrt);
    PrintFunc('exp', n, reps, @DoExp);
    PrintFunc('ln', n, reps, @DoLn);
    PrintFunc('log10', n, reps, @DoLog10);
    PrintFunc('pow', n, reps, @DoPow);
    PrintFunc('sin', n, reps, @DoSin);
    PrintFunc('cos', n, reps, @DoCos);
    PrintFunc('tan', n, reps, @DoTan);
    PrintFunc('gamma', n, reps, @DoGamma);
    PrintFunc('lngamma', n, reps, @DoLnGamma);
  end;
  lst := [3000, 10000];
  for ii := 0 to High(lst) do
  begin
    n := lst[ii];
    c := TMathContext.Make(n, rmHalfEven);
    GC := c;
    PrintFunc('exp', n, 0, @DoExp);
    PrintFunc('ln', n, 0, @DoLn);
  end;
  WriteLn;
  WriteLn('Small-value path, nanoseconds per operation');
  GFX := TBigDecimal.Create('123456.78');
  GFY := TBigDecimal.Create('0.0345');
  x := GFX; y := GFY;
  t1 := TimeIt(CalReps(@DoAddSub), @DoAddSub);
  WriteLn(Format('add+subtract  min %.1f ns median %.1f ns spread %.1f %%', [t1 * 500, GLastMedian * 500, GLastSpread]));
  t1 := TimeIt(CalReps(@DoMulSmall), @DoMulSmall);
  WriteLn(Format('multiply      min %.1f ns median %.1f ns spread %.1f %%', [t1 * 1000, GLastMedian * 1000, GLastSpread]));
  TMathContext.SetDefault(Decimal64);
  t1 := TimeIt(CalReps(@DoMulSmall), @DoMulSmall);
  WriteLn(Format('multiply, default context set  min %.1f ns median %.1f ns spread %.1f %%', [t1 * 1000, GLastMedian * 1000, GLastSpread]));
  TMathContext.ClearDefault;
  WriteLn('sink checksum (precision+exponent): ', GSink);
end.
