{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: tests, identities, reference files, default context
---
}
unit TestLibrary;

{$mode objfpc}{$H+}
{$coperators on}

interface

uses
  Classes, SysUtils, Math, fpcunit, testregistry, BigDecimal.Types,
  BigDecimal,
  BigDecimal.Fixed, BigDecimal.Elementary, BigDecimal.Trig,
  BigDecimal.Constants, BigDecimal.Combinatorics, BigDecimal.Gamma,
  BigDecimal.Financial, BigDecimal.Limbs, BigDecimal.Multiply,
  BigDecimal.Divide;

type
  TLibraryTests = class(TTestCase)
  private
    function Ref(const Name: string): string;
    procedure CheckClose(const Msg: string; const Got, Want: TBigDecimal; P: Integer);
  published
    // text and basic operations
    procedure TestJavaToStringExamples;
    procedure TestEngineeringString;
    procedure TestScaleAndStrip;
    procedure TestMovePoint;
    procedure TestHashIdentical;
    procedure TestToInt64;
    procedure TestIntegerConversions;
    // default context
    procedure TestDefaultContextArithmetic;
    procedure TestDefaultContextOverride;
    procedure TestDefaultContextIsolation;
    procedure TestUnlimitedDefaultIsExact;
    procedure TestNoContextRaises;
    procedure TestNoContextFallback128;
    // reference files
    procedure TestPiDigits;
    procedure TestPiDirectedModes;
    procedure TestOeisFactorials;
    procedure TestOeisDoubleFactorials;
    procedure TestOeisCentralBinomial;
    procedure TestOeisCatalan;
    procedure TestOeisPrimes;
    // identities
    procedure TestFactorialLegendreEqualsSwing;
    procedure TestBinomialPathsAgree;
    procedure TestPascalRule;
    procedure TestRowSum;
    procedure TestGammaIntegerIsFactorial;
    procedure TestFallingFactorial;
    procedure TestSinCosIdentity;
    procedure TestHighPrecisionRoundTrip;
    procedure TestVersion;
    procedure TestExpTaylorSplit;
    procedure TestAtanhSplit;
    procedure TestApproxAbsLargeMagnitude;
    procedure TestExpBitBurstAgreement;
    procedure TestExpBitBurstWired;
    procedure TestLnSplitWired;
    procedure TestSqrtFastPathEqualsGeneral;
    procedure TestStackPathBoundaries;
    procedure TestBZKernelAgreement;
    procedure TestBZRoutedDivide;
    procedure TestExpLnRoundTrip;
    procedure TestPowSquare;
    procedure TestTangentNumbers;
    procedure TestRoundingTable;
    procedure TestAlgebraicProperties;
    procedure TestConstantsFromThreads;
    // financial and constants vectors
    procedure TestFinancialExample;
    procedure TestConstantVectors;
    procedure TestFinancialVectors;
    // Excel annuity and rate functions
    procedure TestExcelTypes;
    procedure TestExcelValues;
    procedure TestExcelIdentities;
    procedure TestExcelEdges;
    procedure TestExcelErrors;
    procedure TestExcelCoreVectors;
    procedure TestExcelSplitVectors;
    procedure TestPeriodicRate;
    procedure TestExcelDefaultContext;
  end;

implementation

uses
  TestVectors;

function TLibraryTests.Ref(const Name: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '../tests/refs/' + Name;
end;

function D(const S: string): TBigDecimal;
begin
  Result := TBigDecimal.Create(S);
end;

procedure TLibraryTests.CheckClose(const Msg: string; const Got, Want: TBigDecimal; P: Integer);
var
  d, bound: TBigDecimal;
begin
  d := (Got - Want).Abs;
  if Want.IsZero then
    bound := TBigDecimal.Create(TBigDecimal.One, P)
  else
    bound := Want.Abs.ScaleByPowerOfTen(5 - P);
  AssertTrue(Msg + ' got ' + Got.ToString + ' want ' + Want.ToString,
    d.CompareTo(bound) <= 0);
end;

function TimingOf(const S: string): TPaymentTiming;
begin
  if S = '1' then Result := ptBegin else Result := ptEnd;
end;

{ Vector values compare as strings, except that any spelling of zero
  matches: the scale of an exact zero is cosmetic. }
function SameVec(const Got, Exp: string): Boolean;
begin
  Result := (Got = Exp) or (D(Got).IsZero and D(Exp).IsZero);
end;

procedure TLibraryTests.TestJavaToStringExamples;
begin
  AssertEquals('0E+3', D('0E+3').ToString);
  AssertEquals('1E-7', D('1E-7').ToString);
  AssertEquals('1.23E+7', D('123E+5').ToString);
  AssertEquals('0.000001', D('0.000001').ToString);
  AssertEquals('0.0000001', D('1E-7').ToPlainString);
  AssertEquals('12300000', D('123E+5').ToPlainString);
  AssertEquals('-1.5', D('-1.5').ToString);
  AssertEquals('100', D('100').ToString);
  AssertEquals('1E+2', D('1E+2').ToString);
end;

procedure TLibraryTests.TestEngineeringString;
begin
  AssertEquals('123E+3', D('123E+3').ToEngineeringString);
  AssertEquals('12.3E+6', D('123E+5').ToEngineeringString);
  AssertEquals('1.23E+9', D('1.23E+9').ToEngineeringString);
  AssertEquals('0.00', D('0.00').ToEngineeringString);
end;

procedure TLibraryTests.TestScaleAndStrip;
begin
  AssertEquals('1.2', D('1.2000').StripTrailingZeros.ToString);
  AssertEquals('1E+2', D('100').StripTrailingZeros.ToString);
  AssertEquals('0', D('0.000').StripTrailingZeros.ToString);
  AssertEquals('1.23', D('1.2345').SetScale(2, rmHalfUp).ToString);
  AssertEquals('1.24', D('1.2350').SetScale(2, rmHalfUp).ToString);
  AssertEquals('1.24', D('1.2350').SetScale(2, rmHalfEven).ToString);
  AssertEquals('1.22', D('1.2250').SetScale(2, rmHalfEven).ToString);
  AssertEquals('-1.3', D('-1.25').SetScale(1, rmHalfUp).ToString);
  AssertEquals('-1.2', D('-1.25').SetScale(1, rmHalfDown).ToString);
  AssertEquals('-1.3', D('-1.21').SetScale(1, rmFloor).ToString);
  AssertEquals('-1.2', D('-1.21').SetScale(1, rmCeiling).ToString);
  AssertEquals('1000', D('999.5').Round(TMathContext.Make(3, rmHalfUp)).ToPlainString);
  AssertEquals('1.00E+3', D('999.5').Round(TMathContext.Make(3, rmHalfUp)).ToString);
  try
    D('1.5').SetScale(0, rmUnnecessary);
    Fail('rmUnnecessary should raise');
  except
    on EBigDecimalRounding do ;
  end;
end;

procedure TLibraryTests.TestMovePoint;
begin
  AssertEquals('0.0123', D('12.3').MovePointLeft(3).ToString);
  AssertEquals('12300', D('12.3').MovePointRight(3).ToString);
  AssertEquals('1.23E+4', D('12.3').ScaleByPowerOfTen(3).ToString.Replace('E+3', 'E+3'));
  AssertEquals('12300', D('12.3').ScaleByPowerOfTen(3).ToPlainString);
end;

procedure TLibraryTests.TestHashIdentical;
begin
  AssertTrue(D('1.0') = D('1.00'));
  AssertFalse(D('1.0').Identical(D('1.00')));
  AssertTrue(D('1.0').Identical(D('1.0')));
  AssertTrue(D('1.0').Hash <> D('1.00').Hash);
  AssertTrue(D('2') > D('1.999999999999999999999999999999'));
  AssertTrue(D('-2') < D('-1.999999999999999999999999999999'));
  AssertTrue(TBigDecimal.Max(D('1'), D('2')) = D('2'));
  AssertTrue(TBigDecimal.Min(D('1'), D('2')) = D('1'));
end;

procedure TLibraryTests.TestToInt64;
begin
  AssertEquals(12, D('12.99').ToInt64);
  AssertEquals(-12, D('-12.99').ToInt64);
  AssertEquals(High(Int64), D('9223372036854775807').ToInt64);
  AssertEquals(Low(Int64), D('-9223372036854775808').ToInt64);
  try
    D('9223372036854775808').ToInt64;
    Fail('overflow expected');
  except
    on EBigDecimalOverflow do ;
  end;
end;

procedure TLibraryTests.TestIntegerConversions;
var
  x: TBigDecimal;
begin
  x := 5;
  AssertEquals('5', x.ToString);
  x := x + 7;
  AssertEquals('12', x.ToString);
  x := Int64(High(Int64));
  x := x + 1;
  AssertEquals('9223372036854775808', x.ToString);
  x := -x - 1;
  AssertEquals('-9223372036854775809', x.ToString);
  AssertEquals('9223372036854775808', (D('-9223372036854775808').Negate).ToString);
  AssertEquals('0.1', TBigDecimal.FromDouble(0.1).ToString);
  AssertEquals('0.1000000000000000055511151231257827021181583404541015625',
    TBigDecimal.FromDoubleExact(0.1).ToString);
  AssertTrue(D('0.1').ToDouble = 0.1);
end;

procedure TLibraryTests.TestDefaultContextArithmetic;
var
  S: TMathContextScope;
begin
  TMathContext.ClearDefault;
  AssertEquals('0.3333333333333333333333333333333333', D('1').Divide(D('3'), Decimal128).ToString);
  AssertEquals('0.3333333333333333333333333333333333', (D('1') / D('3')).ToString);
  S.Enter(Decimal32);
  AssertEquals('0.3333333', (D('1') / D('3')).ToString);
  AssertEquals('1234568', (D('1234567.89') + D('0')).ToString);
  AssertEquals('1.524158E+12', (D('1234567.89') * D('1234567.89')).ToString);
  AssertEquals('1.000000', (D('0.9999999') + D('0.0000001')).ToString);
  AssertEquals('1.414214', Sqrt(D('2')).ToString);
end;

procedure TLibraryTests.TestDefaultContextOverride;
var
  S: TMathContextScope;
begin
  S.Enter(Decimal32);
  AssertEquals('0.33333333333333', D('1').Divide(D('3'), TMathContext.Make(14, rmHalfUp)).ToString);
  AssertEquals('1.4142135623731', Sqrt(D('2'), TMathContext.Make(14, rmHalfUp)).ToString);
end;

function IsolationCase(Idx: Integer): TBigDecimal;
var
  c: TMathContext;
  x: TBigDecimal;
begin
  c := TMathContext.Make(40, rmHalfEven);
  x := D('1.23456789012345678901234567890123456789');
  case Idx of
    0: Result := Sqrt(x, c);
    1: Result := Root(x, 5, c);
    2: Result := Exp(x, c);
    3: Result := Ln(x, c);
    4: Result := Log10(x, c);
    5: Result := Log(D('7'), x, c);
    6: Result := Pow(x, 17, c);
    7: Result := Pow(x, -9, c);
    8: Result := Pow(x, D('2.5'), c);
    9: Result := Sin(x, c);
    10: Result := Cos(x, c);
    11: Result := Tan(x, c);
    12: Result := Gamma(x, c);
    13: Result := LnGamma(x, c);
    14: Result := Factorial(x, c);
    15: Result := Binomial(x, 5, c);
    16: Result := BigPi(c);
    17: Result := BigE(c);
    18: Result := BigLn2(c);
    19: Result := BigLn10(c);
    20: Result := Factorial(40);
    21: Result := Binomial(60, 30);
    22: Result := DoubleFactorial(33);
    23: Result := Catalan(40);
    24: Result := FallingFactorial(30, 5);
    25: Result := RisingFactorial(x, 4);
    26: Result := Multinomial([3, 4, 5]);
    27: Result := Primorial(60);
    28: Result := CompoundFactor(D('0.0123456789'), D('7.25'), c);
    29: Result := PresentValue(D('1000'), D('0.0123456789'), D('7.25'), c);
    30: Result := FutureValue(D('1000'), D('0.0123456789'), D('7.25'), c);
    31: Result := AnnuityFactor(D('0.0123456789'), D('7'), c);
    32: Result := AnnualizedRate(D('1.7'), D('3.5'), c);
    33: Result := Exp(x, c).Divide(D('3'), c);
    34: Result := PowExact(x, 6);
    35: Result := PaymentXL(D('0.05'), 10, D('1000'), c);
  else
    Result := TBigDecimal.Zero;
  end;
end;

procedure TLibraryTests.TestDefaultContextIsolation;
const
  Cases = 36;
var
  i: Integer;
  plain: array[0..Cases - 1] of TBigDecimal;
  S: TMathContextScope;
  inside: TBigDecimal;
begin
  TMathContext.ClearDefault;
  for i := 0 to Cases - 1 do plain[i] := IsolationCase(i);
  S.Enter(TMathContext.Make(5, rmDown));
  for i := 0 to Cases - 1 do
  begin
    inside := IsolationCase(i);
    AssertTrue('case ' + IntToStr(i) + ' differs under a default context: ' +
      plain[i].ToString + ' versus ' + inside.ToString, plain[i].Identical(inside));
  end;
end;

procedure TLibraryTests.TestUnlimitedDefaultIsExact;
var
  S: TMathContextScope;
begin
  S.Enter(Unlimited);
  AssertEquals('0.25', (D('1') / D('4')).ToString);
  AssertEquals('1.2345678901234567890123456789', (D('1.2345678901234567890123456789') + D('0')).ToString);
end;

procedure TLibraryTests.TestNoContextRaises;
begin
  TMathContext.ClearDefault;
  try
    Sqrt(D('2'));
    Fail('Sqrt without context should raise');
  except
    on EBigDecimalNoContext do ;
  end;
  try
    Ln(D('2'));
    Fail('Ln without context should raise');
  except
    on EBigDecimalNoContext do ;
  end;
  AssertEquals('1.5', (D('1.2') + D('0.3')).ToString);
end;

procedure TLibraryTests.TestNoContextFallback128;
var
  Saved: Boolean;
  c: TMathContext;
  q, onResult, offResult: TBigDecimal;
begin
  TMathContext.ClearDefault;
  Saved := NoContextFallback128;
  try
    NoContextFallback128 := True;
    AssertEquals('0.3333333333333333333333333333333333', (D('1') / D('3')).ToString);
    AssertEquals('12.19326311370217952261850327338668',
      (D('1.234567890123456789012345678901234567890123') *
       D('9.876543210987654321098765432109876543210987')).ToString);
    try
      q := D('1').Divide(D('3'));
      Fail('exact Divide should raise ' + q.ToString);
    except
      on EBigDecimalNonTerminating do ;
    end;
    NoContextFallback128 := False;
    try
      q := D('1') / D('3');
      Fail('exact division should raise ' + q.ToString);
    except
      on EBigDecimalNonTerminating do ;
    end;
    AssertEquals('12.193263113702179522618503273386678859451145419856126256664487797134336296860222381401',
      (D('1.234567890123456789012345678901234567890123') *
       D('9.876543210987654321098765432109876543210987')).ToString);
    c := TMathContext.Make(40, rmHalfEven);
    NoContextFallback128 := True;
    onResult := Sqrt(D('2'), c);
    NoContextFallback128 := False;
    offResult := Sqrt(D('2'), c);
    AssertTrue(onResult.Identical(offResult));
  finally
    NoContextFallback128 := Saved;
  end;
end;

function LoadFirstLine(const FileName: string): string;
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FileName);
    Result := Trim(sl[0]);
  finally
    sl.Free;
  end;
end;

function Oeis20000Pi(const FileName: string): string;
var
  sl: TStringList;
  i: Integer;
  p: Integer;
begin
  Result := '';
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FileName);
    for i := 0 to sl.Count - 1 do
    begin
      if (sl[i] = '') or (sl[i][1] = '#') then Continue;
      p := Pos(' ', sl[i]);
      Result += Copy(sl[i], p + 1, 1);
    end;
  finally
    sl.Free;
  end;
end;

procedure TLibraryTests.TestPiDigits;
var
  a, b, got: string;
  p: Integer;
  ps: array of Integer;
  k: Integer;
begin
  a := LoadFirstLine(Ref('pi10000.txt'));        // 3.14159...
  b := Oeis20000Pi(Ref('b000796.txt'));          // 314159... without the point
  AssertEquals('reference files agree', StringReplace(Copy(a, 1, 10001), '.', '', []), Copy(b, 1, 10000));
  ps := [5, 50, 100, 400, 1000, 2000];
  for k := 0 to High(ps) do
  begin
    p := ps[k];
    got := BigPi(TMathContext.Make(p, rmDown)).ToString;
    AssertEquals('pi at ' + IntToStr(p), Copy(a, 1, p + 1), got);
  end;
end;

procedure TLibraryTests.TestPiDirectedModes;
var
  a, up, dn: string;
begin
  a := LoadFirstLine(Ref('pi10000.txt'));
  up := BigPi(TMathContext.Make(300, rmUp)).ToString;
  dn := BigPi(TMathContext.Make(300, rmDown)).ToString;
  AssertEquals(Copy(a, 1, 301), dn);
  AssertTrue('up differs from down by one unit in the last place',
    D(up) - D(dn) = D('1E-299'));
end;

function LoadPairs(const FileName: string; out Idx: TInt64Array; out Vals: TStringList): Integer;
var
  sl: TStringList;
  i, p, n: Integer;
begin
  sl := TStringList.Create;
  Vals := TStringList.Create;
  try
    sl.LoadFromFile(FileName);
    n := 0;
    SetLength(Idx, sl.Count);
    for i := 0 to sl.Count - 1 do
    begin
      if (Trim(sl[i]) = '') or (sl[i][1] = '#') then Continue;
      p := Pos(' ', Trim(sl[i]));
      Idx[n] := StrToInt64(Copy(Trim(sl[i]), 1, p - 1));
      Vals.Add(Trim(Copy(Trim(sl[i]), p + 1, MaxInt)));
      Inc(n);
    end;
    Result := n;
  finally
    sl.Free;
  end;
end;

procedure TLibraryTests.TestOeisFactorials;
var
  idx: TInt64Array;
  vals: TStringList;
  i, n: Integer;
begin
  n := LoadPairs(Ref('b000142.txt'), idx, vals);
  AssertTrue(n >= 100);
  for i := 0 to n - 1 do
    AssertEquals('n=' + IntToStr(idx[i]), vals[i], Factorial(idx[i]).ToString);
  vals.Free;
end;

procedure TLibraryTests.TestOeisDoubleFactorials;
var
  idx: TInt64Array;
  vals: TStringList;
  i, n: Integer;
begin
  n := LoadPairs(Ref('b001147.txt'), idx, vals);
  AssertTrue(n >= 400);
  for i := 0 to n - 1 do
    if idx[i] >= 1 then
      AssertEquals('n=' + IntToStr(idx[i]), vals[i], DoubleFactorial(2 * idx[i] - 1).ToString);
  vals.Free;
end;

procedure TLibraryTests.TestOeisCentralBinomial;
var
  idx: TInt64Array;
  vals: TStringList;
  i, n: Integer;
begin
  n := LoadPairs(Ref('b000984.txt'), idx, vals);
  AssertTrue(n >= 1500);
  for i := 0 to n - 1 do
    AssertEquals('n=' + IntToStr(idx[i]), vals[i], CentralBinomial(idx[i]).ToString);
  vals.Free;
end;

procedure TLibraryTests.TestOeisCatalan;
var
  idx: TInt64Array;
  vals: TStringList;
  i, n: Integer;
begin
  n := LoadPairs(Ref('b000108.txt'), idx, vals);
  AssertTrue(n >= 1000);
  for i := 0 to n - 1 do
    AssertEquals('n=' + IntToStr(idx[i]), vals[i], Catalan(idx[i]).ToString);
  vals.Free;
end;

procedure TLibraryTests.TestOeisPrimes;
var
  idx: TInt64Array;
  vals: TStringList;
  i, n: Integer;
  pr: TInt64Array;
begin
  n := LoadPairs(Ref('b000040.txt'), idx, vals);
  AssertEquals(10000, n);
  pr := PrimesUpTo(StrToInt64(vals[n - 1]));
  AssertEquals(n, Length(pr));
  for i := 0 to n - 1 do
    AssertEquals(StrToInt64(vals[i]), pr[i]);
  vals.Free;
end;

procedure TLibraryTests.TestFactorialLegendreEqualsSwing;
var
  ns: array[0..8] of Int64 = (21, 22, 100, 599, 600, 601, 1000, 5001, 12345);
  i: Integer;
begin
  for i := 0 to High(ns) do
  begin
    AssertTrue('legendre ' + IntToStr(ns[i]), FactorialLegendre(ns[i]) = Factorial(ns[i]));
    AssertTrue('range ' + IntToStr(ns[i]), FactorialRange(ns[i]) = Factorial(ns[i]));
  end;
end;

procedure TLibraryTests.TestBinomialPathsAgree;
var
  i: Integer;
  n, k: Int64;
begin
  RandSeed := 12345;
  for i := 1 to 200 do
  begin
    n := Random(3000);
    k := Random(Integer(n) + 1);
    AssertTrue(Format('C(%d,%d)', [n, k]), BinomialMultiplicative(n, k) = BinomialKummer(n, k));
    AssertTrue('symmetry', Binomial(n, k) = Binomial(n, n - k));
  end;
end;

procedure TLibraryTests.TestPascalRule;
var
  i: Integer;
  n, k: Int64;
begin
  for i := 1 to 100 do
  begin
    n := 2 + Random(5000);
    k := 1 + Random(Integer(n) - 1);
    AssertTrue(Binomial(n, k) = Binomial(n - 1, k - 1) + Binomial(n - 1, k));
  end;
end;

procedure TLibraryTests.TestRowSum;
var
  s: TBigDecimal;
  k: Int64;
begin
  s := TBigDecimal.Zero;
  for k := 0 to 120 do s := s + Binomial(120, k);
  AssertTrue(s = PowExact(TBigDecimal.Create(2), 120));
end;

procedure TLibraryTests.TestGammaIntegerIsFactorial;
var
  c: TMathContext;
  GDefaultGuard: TSuspendDefault;
begin
  { Exact operator semantics for the recurrence check. }
  GDefaultGuard.Suspend;
  c := TMathContext.Make(80, rmHalfEven);
  AssertTrue(Gamma(D('30'), c) = Factorial(29).Round(c));
  AssertTrue(Gamma(D('1'), c) = D('1'));
  // non-integer through the series equals the recurrence Gamma(x+1) = x Gamma(x)
  AssertTrue(Gamma(D('4.25'), TMathContext.Make(60, rmHalfEven)) =
             (D('3.25') * Gamma(D('3.25'), TMathContext.Make(70, rmHalfEven))).Round(TMathContext.Make(60, rmHalfEven)));
  try
    Gamma(D('-3'), c);
    Fail('pole expected');
  except
    on EBigDecimalDomain do ;
  end;
end;

procedure TLibraryTests.TestFallingFactorial;
begin
  AssertTrue(FallingFactorial(50, 10) = Factorial(50).Divide(Factorial(40), 0, rmDown));
  AssertTrue(RisingFactorial(5, 10) = Factorial(14).Divide(Factorial(4), 0, rmDown));
  AssertTrue(Multinomial([3, 4, 5]) = Factorial(12).Divide(Factorial(3) * Factorial(4) * Factorial(5), 0, rmDown));
  AssertEquals('1', Binomial(D('5'), 0, Decimal64).ToString);
  AssertEquals('10', Binomial(D('5'), 2, Decimal64).ToString);
  AssertEquals('-0.125', Binomial(D('0.5'), 2, Decimal64).ToString);
end;

procedure TLibraryTests.TestSinCosIdentity;
var
  c, w: TMathContext;
  x, s, cs, one: TBigDecimal;
  i: Integer;
begin
  c := TMathContext.Make(40, rmHalfEven);
  w := TMathContext.Make(60, rmHalfEven);
  for i := 1 to 20 do
  begin
    x := TBigDecimal.Create(Int64(i * 37 - 300)).Divide(TBigDecimal.Create(Int64(7)), w);
    s := Sin(x, w);
    cs := Cos(x, w);
    one := (s.Square + cs.Square).Round(c);
    AssertEquals('sin^2+cos^2 at ' + x.ToString, '1.000000000000000000000000000000000000000', one.ToString);
  end;
end;

procedure TLibraryTests.TestExpLnRoundTrip;
var
  c, w: TMathContext;
  x, y: TBigDecimal;
begin
  c := TMathContext.Make(30, rmHalfEven);
  w := TMathContext.Make(50, rmHalfEven);
  x := D('12345.6789');
  y := Exp(Ln(x, w), c);
  AssertTrue(y = x.Round(c));
  y := Ln(Exp(D('-7.25'), w), c);
  AssertTrue(y.CompareTo(D('-7.25')) = 0);
end;

procedure TLibraryTests.TestHighPrecisionRoundTrip;
var
  c, w: TMathContext;
  x, y, d: TBigDecimal;
  i: Integer;
  t: string;
begin
  // 3000 digits: the squaring count of Exp and Sin must keep the error bound
  // small enough for the rounding test to end
  t := '1.';
  for i := 1 to 2999 do t += Chr(Ord('0') + (i * 7 + (i * i) mod 11) mod 10);
  x := TBigDecimal.Create(t);
  c := TMathContext.Make(3000, rmHalfEven);
  w := TMathContext.Make(3010, rmHalfEven);
  y := Ln(Exp(x, w), w);
  d := (y - x).Abs;
  AssertTrue('exp and ln agree', d.CompareTo(TBigDecimal.Create(1, 3000)) < 0);
  y := Sin(x, c);
  AssertTrue('sin has 3000 digits', y.Precision = 3000);
  y := Sin(x, w).Square + Cos(x, w).Square;
  d := (y - TBigDecimal.One).Abs;
  AssertTrue('sin and cos agree', d.CompareTo(TBigDecimal.Create(1, 3000)) < 0);
end;

procedure TLibraryTests.TestVersion;
begin
  AssertEquals('0.3.0', BigDecimalVersion);
  AssertEquals('0.3.0', Format('%d.%d.%d', [BigDecimalVersionMajor,
    BigDecimalVersionMinor, BigDecimalVersionRelease]));
end;

procedure TLibraryTests.TestExpTaylorSplit;
var
  T, Q, s1, s2, diff, tol: TBigDecimal;
  c: TMathContext;
begin
  c := TMathContext.Make(60, rmHalfEven);
  tol := D('1e-55');
  ExpTaylorSplit(D('1'), D('2'), 50, T, Q);
  AssertEquals(0, T.Scale);
  AssertEquals(0, Q.Scale);
  s1 := T.Divide(Q, c);
  s2 := Exp(D('0.5'), c);
  diff := (s1 - s2).Abs;
  AssertTrue('split vs series at 0.5: ' + diff.ToString, diff.CompareTo(tol) < 0);
  ExpTaylorSplit(D('-1'), D('2'), 50, T, Q);
  AssertEquals(0, T.Scale);
  s1 := T.Divide(Q, c);
  s2 := Exp(D('-0.5'), c);
  diff := (s1 - s2).Abs;
  AssertTrue('split vs series at -0.5: ' + diff.ToString, diff.CompareTo(tol) < 0);
  c := TMathContext.Make(100, rmHalfEven);
  ExpTaylorSplit(D('1'), D('1'), 200, T, Q);
  s1 := T.Divide(Q, c);
  s2 := Exp(D('1'), c);
  diff := (s1 - s2).Abs;
  AssertTrue('split vs series at 1: ' + diff.ToString,
    diff.CompareTo(D('1e-95')) < 0);
  try
    ExpTaylorSplit(D('1'), D('0'), 10, T, Q);
    Fail('q0 = 0 should raise');
  except
    on EBigDecimalDomain do ;
  end;
  try
    ExpTaylorSplit(D('1'), D('2'), 0, T, Q);
    Fail('N = 0 should raise');
  except
    on EBigDecimalDomain do ;
  end;
end;

procedure TLibraryTests.TestApproxAbsLargeMagnitude;
var
  v: TBigDecimal;
  a: Double;
  saved: TFPUExceptionMask;
begin
  { A 45-limb magnitude at scale 125 drives (N - 2) * 9 - scale into the
    256..300 range, where Math.IntPower traps on targets that leave the
    overflow trap unmasked. The console runner masks it, so the test
    unmasks first to prove the approximation scales without Power. }
  saved := GetExceptionMask;
  SetExceptionMask(saved - [exOverflow, exInvalidOp, exZeroDivide]);
  try
    v := TBigDecimal.One.ScaleByPowerOfTen(276).SetScale(125, rmDown);
    a := ApproxAbs(v);
    AssertTrue('approx is finite', not IsNan(a) and (Abs(a) < 1e308));
    AssertTrue('approx has the keynote magnitude: ' + FloatToStr(a),
      (a > 1e270) and (a < 1e290));
    v := TBigDecimal.One.ScaleByPowerOfTen(320);
    AssertTrue('clamp high', ApproxAbs(v) = 1e300);
    v := TBigDecimal.One.ScaleByPowerOfTen(-320);
    AssertTrue('clamp low', ApproxAbs(v) = 1e-300);
  finally
    SetExceptionMask(saved);
  end;
end;

procedure TLibraryTests.TestExpBitBurstAgreement;
var
  r, bb: TFx;
  c: TMathContext;
  want, diff, tol: TBigDecimal;
  saved: TFPUExceptionMask;
begin
  { The three-chunk input exercised an error-bound call over a 45-limb
    quotient and trapped before the bound fix. The runner masks the
    overflow trap, so the test unmasks first. }
  saved := GetExceptionMask;
  SetExceptionMask(saved - [exOverflow, exInvalidOp, exZeroDivide]);
  try
    r := FxFromDecimal(D('0.4156'), 100);
    bb := ExpBitBurstCore(r);
    c := TMathContext.Make(140, rmHalfEven);
    want := Exp(D('0.4156'), c);
    diff := (FxRescale(bb, 140).V - want).Abs;
    tol := TBigDecimal.Create(TBigDecimal.One, 90);
    AssertTrue('bit-burst agrees: ' + diff.ToString, diff.CompareTo(tol) < 0);
  finally
    SetExceptionMask(saved);
  end;
end;

procedure TLibraryTests.TestExpBitBurstWired;
var
  saved: Integer;
  c: TMathContext;
  got, want, diff, tol: TBigDecimal;
begin
  { Lower the threshold to route a 300-digit Exp through the wired
    bit-burst branch, then compare against the Taylor path. }
  saved := ExpBitBurstDigits;
  ExpBitBurstDigits := 100;
  try
    c := TMathContext.Make(300, rmHalfEven);
    got := Exp(D('2.7182818284590452353602874713527'), c);
    ExpBitBurstDigits := MaxInt;
    want := Exp(D('2.7182818284590452353602874713527'), c);
    diff := (got - want).Abs;
    tol := TBigDecimal.Create(TBigDecimal.One, 295);
    AssertTrue('wired burst agrees: ' + diff.ToString, diff.CompareTo(tol) < 0);
  finally
    ExpBitBurstDigits := saved;
  end;
end;

procedure TLibraryTests.TestLnSplitWired;
var
  saved: Integer;
  c: TMathContext;
  got, want, diff, tol: TBigDecimal;
begin
  { Lower the threshold to route a 300-digit Ln through the split
    atanh branch, then compare against the term loop. }
  saved := LnSplitDigits;
  LnSplitDigits := 100;
  try
    c := TMathContext.Make(300, rmHalfEven);
    got := Ln(D('2.7182818284590452353602874713527'), c);
    LnSplitDigits := MaxInt;
    want := Ln(D('2.7182818284590452353602874713527'), c);
    diff := (got - want).Abs;
    tol := TBigDecimal.Create(TBigDecimal.One, 295);
    AssertTrue('split ln agrees: ' + diff.ToString, diff.CompareTo(tol) < 0);
  finally
    LnSplitDigits := saved;
  end;
end;

procedure TLibraryTests.TestAtanhSplit;
var
  T, Q, s, naive, pw, diff, tol: TBigDecimal;
  c: TMathContext;
  k: Integer;
begin
  c := TMathContext.Make(60, rmHalfEven);
  tol := D('1e-55');
  AtanhSplit(D('1'), D('16'), 60, T, Q);
  s := T.Divide(Q, c);
  naive := D('0');
  pw := D('1');
  for k := 0 to 200 do
  begin
    naive := naive + pw.Divide(D(IntToStr(2 * k + 1)), c);
    pw := pw.Divide(D('16'), c);
  end;
  diff := (s - naive).Abs;
  AssertTrue('atanh split at 1/16: ' + diff.ToString, diff.CompareTo(tol) < 0);
  AtanhSplit(D('-1'), D('16'), 60, T, Q);
  s := T.Divide(Q, c);
  naive := D('0');
  pw := D('1');
  for k := 0 to 200 do
  begin
    naive := naive + pw.Divide(D(IntToStr(2 * k + 1)), c);
    pw := pw.Divide(D('-16'), c);
  end;
  diff := (s - naive).Abs;
  AssertTrue('atanh split at -1/16: ' + diff.ToString, diff.CompareTo(tol) < 0);
  try
    AtanhSplit(D('1'), D('0'), 10, T, Q);
    Fail('q0 = 0 should raise');
  except
    on EBigDecimalDomain do ;
  end;
  try
    AtanhSplit(D('1'), D('2'), 0, T, Q);
    Fail('N = 0 should raise');
  except
    on EBigDecimalDomain do ;
  end;
end;

procedure TLibraryTests.TestSqrtFastPathEqualsGeneral;
var
  i, j, nd: Integer;
  t: string;
  x, fast, slow: TBigDecimal;
  c: TMathContext;
  m: TRoundingMode;
begin
  RandSeed := 4242;
  for i := 1 to 3000 do
  begin
    nd := 1 + Random(70);
    t := Chr(Ord('1') + Random(9));
    for j := 2 to nd do t += Chr(Ord('0') + Random(10));
    if i mod 7 = 0 then t := '1' + StringOfChar('0', nd);
    if i mod 11 = 0 then t := t + t;
    x := TBigDecimal.Create(TBigDecimal.Create(t), Random(60) - 10);
    for m := rmUp to rmHalfEven do
    begin
      c := TMathContext.Make(1 + Random(50), m);
      SqrtFastPath := True;
      fast := Sqrt(x, c);
      SqrtFastPath := False;
      slow := Sqrt(x, c);
      SqrtFastPath := True;
      AssertTrue('sqrt ' + x.ToString + ' p=' + IntToStr(c.Precision) + ': ' +
        fast.ToString + ' <> ' + slow.ToString, fast.Identical(slow));
    end;
  end;
end;

procedure TLibraryTests.TestStackPathBoundaries;
var
  i, j, nda, ndb, sca, scb: Integer;
  ta, tb: string;
  a, b, sum, prod, q, q2: TBigDecimal;
  c: TMathContext;
  m: TRoundingMode;
  GDefaultGuard: TSuspendDefault;
begin
  { Exact operator semantics for the stack-path checks. }
  GDefaultGuard.Suspend;
  // operand sizes around the limit of the stack buffers (48 limbs, 432 digits)
  RandSeed := 777;
  for i := 1 to 600 do
  begin
    nda := 150 + Random(300);
    ndb := 150 + Random(300);
    ta := Chr(Ord('1') + Random(9));
    for j := 2 to nda do ta += Chr(Ord('0') + Random(10));
    tb := Chr(Ord('1') + Random(9));
    for j := 2 to ndb do tb += Chr(Ord('0') + Random(10));
    sca := Random(120) - 40;
    scb := Random(120) - 40;
    a := TBigDecimal.Create(TBigDecimal.Create(ta), sca);
    b := TBigDecimal.Create(TBigDecimal.Create(tb), scb);
    if i mod 3 = 0 then b := -b;
    sum := a + b;
    AssertTrue('sum minus b', (sum - b).CompareTo(a) = 0);
    prod := a * b;
    AssertTrue('product over b', prod.Divide(b).CompareTo(a) = 0);
    for m := rmUp to rmHalfEven do
    begin
      c := TMathContext.Make(1 + Random(450), m);
      q := a.Divide(b, c);
      q2 := a.Divide(b, q.Scale, m);
      AssertTrue('divide ' + IntToStr(i) + ' p=' + IntToStr(c.Precision),
        q.CompareTo(q2) = 0);
      AssertTrue('multiply rounds once',
        a.Multiply(b, c).CompareTo(prod.Round(c)) = 0);
      AssertTrue('add rounds once', a.Add(b, c).CompareTo(sum.Round(c)) = 0);
    end;
  end;
end;

{ Raw-limb agreement between DivRemBZ and DivRemKnuth with the remainder
  proof on every shape. The two large shapes engage the recursion; the small
  ones cover the fallback to Algorithm D. }
procedure TLibraryTests.TestBZKernelAgreement;
var
  A, B, Qk, Qb, Rk, Rb, P, S: TLimbs;
  na, nb, nqk, nrk, nqb, nrb, np, ns, i, t: Integer;
begin
  BZFallbacks := 0;
  RandSeed := 4242;
  for t := 1 to 4 do
  begin
    case t of
      1: begin na := 100; nb := 40; end;
      2: begin na := 1056; nb := 523; end;
      3: begin na := 1024; nb := 512; end;
      4: begin na := 2048; nb := 1024; end;
    end;
    SetLength(A, na + 1);
    SetLength(B, nb + 1);
    for i := 0 to na - 1 do
      A[i] := UInt32(Random(LimbBase));
    A[na - 1] := 1 + UInt32(Random(LimbBase - 1));
    for i := 0 to nb - 1 do
      B[i] := UInt32(Random(LimbBase));
    B[nb - 1] := LimbBase div 2 + UInt32(Random(LimbBase - LimbBase div 2));
    SetLength(Qk, na - nb + 3);
    SetLength(Rk, nb + 1);
    SetLength(Qb, na - nb + 3);
    SetLength(Rb, nb + 1);
    DivRemKnuth(@A[0], na, @B[0], nb, @Qk[0], nqk, @Rk[0], nrk);
    DivRemBZ(@A[0], na, @B[0], nb, @Qb[0], nqb, @Rb[0], nrb);
    AssertEquals('quotient length shape ' + IntToStr(t), nqk, nqb);
    AssertEquals('remainder length shape ' + IntToStr(t), nrk, nrb);
    for i := 0 to nqk - 1 do
      AssertEquals('quotient limb ' + IntToStr(i) + ' shape ' + IntToStr(t),
        Qk[i], Qb[i]);
    for i := 0 to nrk - 1 do
      AssertEquals('remainder limb ' + IntToStr(i) + ' shape ' + IntToStr(t),
        Rk[i], Rb[i]);
    SetLength(P, nqb + nb + 1);
    SetLength(S, nqb + nb + 2);
    if nqb = 0 then
      np := 0
    else
      np := MulMag(@Qb[0], nqb, @B[0], nb, @P[0]);
    ns := AddMag(@P[0], np, @Rb[0], nrb, @S[0]);
    AssertEquals('Q * B + R = A shape ' + IntToStr(t), 0,
      CmpMag(@S[0], ns, @A[0], na));
    AssertEquals('R < B shape ' + IntToStr(t), -1,
      CmpMag(@Rb[0], nrb, @B[0], nb));
  end;
  AssertEquals('no BZ fallback', 0, BZFallbacks);
end;

{ End-to-end agreement between the routed Burnikel-Ziegler path and Algorithm
  D on a divide whose divisor passes the gate. }
procedure TLibraryTests.TestBZRoutedDivide;
var
  SX, SY: string;
  X, Y, Q1, Q2: TBigDecimal;
  Ctx: TMathContext;
  i, Save: Integer;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  SX := '1';
  for i := 2 to 11000 do
    SX += Chr(Ord('0') + ((i * 7 + 11) mod 10));
  SY := '1';
  for i := 2 to 4700 do
    SY += Chr(Ord('0') + ((i * 7 + 29) mod 10));
  X := D(SX);
  Y := D(SY);
  Ctx := TMathContext.Make(6400, rmHalfEven);
  Save := BZDivThreshold;
  BZFallbacks := 0;
  try
    Q1 := X.Divide(Y, Ctx);
    BZDivThreshold := MaxInt;
    Q2 := X.Divide(Y, Ctx);
  finally
    BZDivThreshold := Save;
  end;
  AssertEquals('BZ and Knuth agree', Q2.ToString, Q1.ToString);
  AssertEquals('no BZ fallback', 0, BZFallbacks);
end;

procedure TLibraryTests.TestPowSquare;
var
  c: TMathContext;
  x: TBigDecimal;
begin
  c := TMathContext.Make(50, rmHalfEven);
  x := D('1.234567891234567891');
  AssertTrue(Pow(x, 2, c) = x.Square.Round(c));
  AssertTrue(Pow(x, D('2'), c) = x.Square.Round(c));
  AssertTrue(Pow(D('2'), -3, c) = D('0.125'));
  AssertTrue(Pow(D('0.5'), D('0.5'), c) = Sqrt(D('0.5'), c));
end;

procedure TLibraryTests.TestTangentNumbers;
begin
  AssertEquals('1', TangentNumber(1).ToString);
  AssertEquals('2', TangentNumber(2).ToString);
  AssertEquals('16', TangentNumber(3).ToString);
  AssertEquals('272', TangentNumber(4).ToString);
  AssertEquals('7936', TangentNumber(5).ToString);
  AssertEquals('353792', TangentNumber(6).ToString);
end;

procedure TLibraryTests.TestRoundingTable;
const
  Inputs: array[0..9] of string = ('5.5', '2.5', '1.6', '1.1', '1.0', '-1.0', '-1.1', '-1.6', '-2.5', '-5.5');
  // expected results to scale 0, from the Java RoundingMode documentation
  Expected: array[TRoundingMode, 0..9] of string = (
    ('6', '3', '2', '2', '1', '-1', '-2', '-2', '-3', '-6'),     // UP
    ('5', '2', '1', '1', '1', '-1', '-1', '-1', '-2', '-5'),     // DOWN
    ('6', '3', '2', '2', '1', '-1', '-1', '-1', '-2', '-5'),     // CEILING
    ('5', '2', '1', '1', '1', '-1', '-2', '-2', '-3', '-6'),     // FLOOR
    ('6', '3', '2', '1', '1', '-1', '-1', '-2', '-3', '-6'),     // HALF_UP
    ('5', '2', '2', '1', '1', '-1', '-1', '-2', '-2', '-5'),     // HALF_DOWN
    ('6', '2', '2', '1', '1', '-1', '-1', '-2', '-2', '-6'),     // HALF_EVEN
    ('', '', '', '', '1', '-1', '', '', '', ''));                 // UNNECESSARY
var
  m: TRoundingMode;
  i: Integer;
  r: string;
begin
  for m := Low(TRoundingMode) to High(TRoundingMode) do
    for i := 0 to 9 do
    begin
      try
        r := D(Inputs[i]).SetScale(0, m).ToString;
      except
        on EBigDecimalRounding do r := '';
      end;
      AssertEquals(Format('mode %d input %s', [Ord(m), Inputs[i]]), Expected[m, i], r);
    end;
end;

procedure TLibraryTests.TestAlgebraicProperties;
var
  i: Integer;
  a, b, q, r: TBigDecimal;
  c: TMathContext;
begin
  RandSeed := 777;
  c := TMathContext.Make(60, rmHalfEven);
  for i := 1 to 300 do
  begin
    a := D(IntToStr(Random(1000000)) + IntToStr(Random(1000000000)) + '.' + IntToStr(Random(1000000)));
    b := D(IntToStr(1 + Random(1000000000)) + '.' + IntToStr(Random(1000)));
    if Random(2) = 0 then a := a.Negate;
    AssertTrue('(a+b)-b = a', (a + b) - b = a);
    AssertTrue('a*b/b = a', (a * b).Divide(b) = a);
    a.DivRem(b, q, r);
    AssertTrue('a = q*b + r', q * b + r = a);
    AssertTrue('|r| < |b|', r.Abs < b.Abs);
    AssertTrue('Sqrt(x^2) = |x|', Sqrt(a.Square, c) = a.Abs.Round(c));
  end;
end;

type
  TConstThread = class(TThread)
  public
    Ref: string;
    Bad: Integer;
    Idx: Integer;
    procedure Execute; override;
  end;

procedure TConstThread.Execute;
var
  i, p: Integer;
  got: string;
begin
  for i := 1 to 40 do
  begin
    p := 20 + ((i * 37 + Idx * 101) mod 600);
    got := BigPi(TMathContext.Make(p, rmDown)).ToString;
    if got <> Copy(Ref, 1, p + 1) then Inc(Bad);
    if BigLn2(TMathContext.Make(p, rmDown)).Precision <> p then Inc(Bad);
    if BigE(TMathContext.Make(p div 2 + 5, rmHalfEven)).Precision <> p div 2 + 5 then Inc(Bad);
  end;
end;

procedure TLibraryTests.TestConstantsFromThreads;
var
  t: array[0..7] of TConstThread;
  i: Integer;
  piRef: string;
  bad: Integer;
begin
  piRef := LoadFirstLine(Ref('pi10000.txt'));
  for i := 0 to 7 do
  begin
    t[i] := TConstThread.Create(True);
    t[i].Ref := piRef;
    t[i].Idx := i;
    t[i].Start;
  end;
  bad := 0;
  for i := 0 to 7 do
  begin
    t[i].WaitFor;
    bad += t[i].Bad;
    t[i].Free;
  end;
  AssertEquals('threads disagree with the reference digits', 0, bad);
end;

procedure TLibraryTests.TestFinancialExample;
var
  c: TMathContext;
begin
  c := TMathContext.Make(40, rmHalfEven);
  AssertEquals('1.62889462677744140625', CompoundFactor(D('0.05'), D('10'), c).ToString);
  AssertTrue(D('1628.89462677744140625') = FutureValue(D('1000'), D('0.05'), D('10'), c));
  AssertTrue(D('1000') = PresentValue(D('1628.89462677744140625'), D('0.05'), D('10'), c));
  AssertEquals('10', AnnuityFactor(D('0'), D('10'), c).ToString);
end;

procedure RunVector(const Name: string; T: TTestCase);
begin
end;

function VecFile(const Name: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '../tests/vectors/' + Name + '.txt';
end;

procedure TLibraryTests.TestConstantVectors;
var
  sl: TStringList;
  i, bad: Integer;
  f: TStringArray;
  got: string;
  c: TMathContext;
  names: array[0..3] of string = ('pi', 'e', 'ln2', 'ln10');
  j: Integer;
begin
  for j := 0 to 3 do
  begin
    sl := TStringList.Create;
    try
      sl.LoadFromFile(VecFile(names[j]));
      bad := 0;
      for i := 0 to sl.Count - 1 do
      begin
        if sl[i] = '' then Continue;
        f := sl[i].Split([#9]);
        c := TMathContext.Make(StrToInt(f[1]), ParseMode(f[2]));
        case j of
          0: got := BigPi(c).ToString;
          1: got := BigE(c).ToString;
          2: got := BigLn2(c).ToString;
        else
          got := BigLn10(c).ToString;
        end;
        if got <> f[3] then
        begin
          Inc(bad);
          if bad < 4 then Fail(names[j] + ' ' + sl[i] + ' GOT ' + got);
        end;
      end;
    finally
      sl.Free;
    end;
  end;
end;

procedure TLibraryTests.TestFinancialVectors;
var
  names: array[0..4] of string = ('compound', 'pv', 'fv', 'annuity', 'rate');
  sl: TStringList;
  i, j: Integer;
  f: TStringArray;
  got, exp: string;
  c: TMathContext;
begin
  for j := 0 to 4 do
  begin
    sl := TStringList.Create;
    try
      sl.LoadFromFile(VecFile(names[j]));
      for i := 0 to sl.Count - 1 do
      begin
        if sl[i] = '' then Continue;
        f := sl[i].Split([#9]);
        case j of
          0: begin c := TMathContext.Make(StrToInt(f[3]), ParseMode(f[4]));
               got := CompoundFactor(D(f[1]), D(f[2]), c).ToString; exp := f[5]; end;
          1: begin c := TMathContext.Make(StrToInt(f[4]), ParseMode(f[5]));
               got := PresentValue(D(f[1]), D(f[2]), D(f[3]), c).ToString; exp := f[6]; end;
          2: begin c := TMathContext.Make(StrToInt(f[4]), ParseMode(f[5]));
               got := FutureValue(D(f[1]), D(f[2]), D(f[3]), c).ToString; exp := f[6]; end;
          3: begin c := TMathContext.Make(StrToInt(f[3]), ParseMode(f[4]));
               got := AnnuityFactor(D(f[1]), D(f[2]), c).ToString; exp := f[5]; end;
        else
          begin c := TMathContext.Make(StrToInt(f[3]), ParseMode(f[4]));
               got := AnnualizedRate(D(f[1]), D(f[2]), c).ToString; exp := f[5]; end;
        end;
        if got <> exp then
          Fail(names[j] + ' ' + sl[i] + ' GOT ' + got);
      end;
    finally
      sl.Free;
    end;
  end;
end;

procedure TLibraryTests.TestExcelTypes;
begin
  AssertEquals(0, Ord(ptEnd));
  AssertEquals(1, Ord(ptBegin));
  AssertTrue(EBigDecimalNoConvergence.InheritsFrom(EBigDecimal));
end;

procedure TLibraryTests.TestExcelValues;
var
  c40, c15: TMathContext;
  r: TBigDecimal;
begin
  TMathContext.ClearDefault;
  c40 := TMathContext.Make(40, rmHalfEven);
  c15 := TMathContext.Make(15, rmHalfEven);
  r := D('0.08').Divide(D('12'), c40);
  AssertEquals('-1037.03208935915', PaymentXL(r, 10, D('10000'), c40).Round(c15).ToString);
  AssertEquals('-1030.16432717797',
    PaymentXL(r, 10, D('10000'), D('0'), ptBegin, c40).Round(c15).ToString);
  AssertEquals('-1037.03208935915',
    PaymentXL(r, 10, D('10000'), D('0'), c40).Round(c15).ToString);
  r := D('0.1').Divide(D('12'), c40);
  AssertEquals('-66.6666666666667', InterestPaymentXL(r, 1, 36, D('8000'), c40).Round(c15).ToString);
  AssertEquals('-191.470830884033', PrincipalPaymentXL(r, 1, 36, D('8000'), c40).Round(c15).ToString);
  AssertEquals('-66.6666666666667',
    InterestPaymentXL(r, 1, 36, D('8000'), D('0'), c40).Round(c15).ToString);
  r := D('0.08').Divide(D('12'), c40);
  AssertEquals('-59777.1458511880', PresentValueXL(r, 240, D('500'), c40).Round(c15).ToString);
  AssertEquals('-59777.1458511880',
    PresentValueXL(r, 240, D('500'), D('0'), c40).Round(c15).ToString);
  r := D('0.06').Divide(D('12'), c40);
  AssertEquals('2581.40337406018',
    FutureValueXL(r, 10, D('-200'), D('-500'), ptBegin, c40).Round(c15).ToString);
  AssertTrue(FutureValueXL(r, 10, D('-200'), D('-500'), c40) =
    FutureValueXL(r, 10, D('-200'), D('-500'), ptEnd, c40));
  r := D('0.12').Divide(D('12'), c40);
  AssertEquals('60.0821228537617',
    PeriodCountXL(r, D('-100'), D('-1000'), D('10000'), c40).Round(c15).ToString);
  AssertEquals('59.6738656742946',
    PeriodCountXL(r, D('-100'), D('-1000'), D('10000'), ptBegin, c40).Round(c15).ToString);
  AssertEquals('0.00770147248820204', PeriodicRateXL(48, D('-200'), D('8000'), c40).Round(c15).ToString);
  AssertEquals('0.00770147248820204',
    PeriodicRateXL(48, D('-200'), D('8000'), D('0'), c40).Round(c15).ToString);
  AssertEquals('0.0535426673707581', EffectiveRateXL(D('0.0525'), 4, c40).Round(c15).ToString);
  AssertEquals('0.0525003198683559', NominalRateXL(D('0.053543'), 4, c40).Round(c15).ToString);
end;

type
  TShape = record
    R: string;
    N: Int64;
    Pv, Fv: string;
    T: TPaymentTiming;
  end;

procedure TLibraryTests.TestExcelIdentities;
const
  Shapes: array[0..5] of TShape = (
    (R: '0.005'; N: 60; Pv: '100000'; Fv: '5000'; T: ptEnd),
    (R: '0.006666666666666667'; N: 360; Pv: '250000'; Fv: '0'; T: ptEnd),
    (R: '0.02'; N: 10; Pv: '10000'; Fv: '1000'; T: ptBegin),
    (R: '-0.01'; N: 12; Pv: '5000'; Fv: '0'; T: ptEnd),
    (R: '1E-30'; N: 100; Pv: '1000000'; Fv: '250'; T: ptEnd),
    (R: '0.1'; N: 5; Pv: '-7500'; Fv: '20000'; T: ptBegin));
  EffX: array[0..3] of string = ('0.0525', '1E-25', '2.5', '0.000001');
  EffK: array[0..3] of Int64 = (1, 4, 12, 365);
var
  si, pi, k, xi: Integer;
  m: TRoundingMode;
  c, w: TMathContext;
  r, pv, fv, pmt, nDec, e: TBigDecimal;
  per: Int64;
  sumI, sumP: TBigDecimal;
  ps: array[0..1] of Integer = (40, 200);
  GDefaultGuard: TSuspendDefault;
begin
  TMathContext.ClearDefault;
  { Exact operator semantics for the reference products. }
  GDefaultGuard.Suspend;
  for si := 0 to High(Shapes) do
    for pi := 0 to 1 do
      for m := rmUp to rmHalfEven do
      begin
        c := TMathContext.Make(ps[pi], m);
        w := TMathContext.Make(ps[pi] + 30, rmHalfEven);
        r := D(Shapes[si].R);
        pv := D(Shapes[si].Pv);
        fv := D(Shapes[si].Fv);
        nDec := TBigDecimal.Create(Shapes[si].N);
        pmt := PaymentXL(r, Shapes[si].N, pv, fv, Shapes[si].T, w);
        CheckClose('pv shape ' + IntToStr(si),
          PresentValueXL(r, Shapes[si].N, pmt, fv, Shapes[si].T, c), pv, ps[pi]);
        CheckClose('fv shape ' + IntToStr(si),
          FutureValueXL(r, Shapes[si].N, pmt, pv, Shapes[si].T, c), fv, ps[pi]);
        CheckClose('nper shape ' + IntToStr(si),
          PeriodCountXL(r, pmt, pv, fv, Shapes[si].T, c), nDec, ps[pi]);
        CheckClose('rate shape ' + IntToStr(si),
          PeriodicRateXL(Shapes[si].N, pmt, pv, fv, Shapes[si].T, D('0.1'), c), r, ps[pi]);
        if (fv.IsZero) and (ps[pi] = 40) then
        begin
          sumI := TBigDecimal.Zero;
          sumP := TBigDecimal.Zero;
          for per := 1 to Shapes[si].N do
          begin
            sumI := sumI + InterestPaymentXL(r, per, Shapes[si].N, pv, fv, Shapes[si].T, c);
            sumP := sumP + PrincipalPaymentXL(r, per, Shapes[si].N, pv, fv, Shapes[si].T, c);
          end;
          CheckClose('sumP shape ' + IntToStr(si), sumP, pv.Negate, ps[pi]);
          CheckClose('sumIP shape ' + IntToStr(si), sumI + sumP,
            PaymentXL(r, Shapes[si].N, pv, fv, Shapes[si].T, c) * nDec, ps[pi]);
        end;
      end;
  for xi := 0 to High(EffX) do
    for k := 0 to High(EffK) do
      for pi := 0 to 1 do
        for m := rmUp to rmHalfEven do
        begin
          c := TMathContext.Make(ps[pi], m);
          w := TMathContext.Make(ps[pi] + 30, rmHalfEven);
          e := EffectiveRateXL(D(EffX[xi]), EffK[k], w);
          CheckClose('nom-eff ' + EffX[xi] + '/' + IntToStr(EffK[k]),
            NominalRateXL(e, EffK[k], c), D(EffX[xi]), ps[pi]);
        end;
end;

procedure TLibraryTests.TestExcelEdges;
var
  c, c40, w70: TMathContext;
  r, pmt, i: TBigDecimal;
begin
  TMathContext.ClearDefault;
  c := TMathContext.Make(40, rmHalfEven);
  // zero rate for each payment function
  AssertTrue(PaymentXL(D('0'), 10, D('1000'), D('500'), c) = D('-150'));
  AssertTrue(PresentValueXL(D('0'), 12, D('-100'), D('-500'), c) = D('1700'));
  AssertTrue(FutureValueXL(D('0'), 12, D('-100'), D('2000'), c) = D('-800'));
  AssertTrue(PeriodCountXL(D('0'), D('-100'), D('-1000'), D('10000'), c) = D('90'));
  AssertTrue(InterestPaymentXL(D('0'), 3, 10, D('1000'), c).IsZero);
  AssertTrue(PrincipalPaymentXL(D('0'), 3, 10, D('1000'), D('500'), c) = D('-150'));
  AssertTrue(PeriodicRateXL(12, D('-100'), D('1000'), D('200'), c).IsZero);
  // one compounding period is the identity
  AssertTrue(EffectiveRateXL(D('0.0525'), 1, c) = D('0.0525'));
  AssertTrue(NominalRateXL(D('0.0535'), 1, c) = D('0.0535'));
  // first period of an annuity due
  r := D('0.006666666666666667');
  i := InterestPaymentXL(r, 1, 360, D('250000'), D('0'), ptBegin, c);
  AssertTrue(i.IsZero);
  AssertTrue(PrincipalPaymentXL(r, 1, 360, D('250000'), D('0'), ptBegin, c) =
    PaymentXL(r, 360, D('250000'), D('0'), ptBegin, c));
  // a single period has closed forms
  AssertTrue(PeriodicRateXL(1, D('-100'), D('1000'), D('-970'), ptEnd, c) = D('0.07'));
  AssertTrue(PeriodicRateXL(1, D('-100'), D('1000'), D('-855'), ptBegin, c) = D('-0.05'));
  pmt := PaymentXL(D('0.05'), 1, D('1000'), D('50'), ptEnd, c);
  CheckClose('nper n=1', PeriodCountXL(D('0.05'), pmt, D('1000'), D('50'), ptEnd, c),
    D('1'), 40);
  // a large period count round-trips
  c40 := TMathContext.Make(40, rmHalfEven);
  w70 := TMathContext.Make(70, rmHalfEven);
  pmt := PaymentXL(D('0.005'), 100000, D('100000'), w70);
  CheckClose('pv n=1e5', PresentValueXL(D('0.005'), 100000, pmt, w70).Round(c40),
    D('100000'), 40);
  pmt := PaymentXL(D('0.005'), 10000, D('100000'), w70);
  CheckClose('nper n=1e4', PeriodCountXL(D('0.005'), pmt, D('100000'), c40),
    TBigDecimal.Create(Int64(10000)), 40);
  // a tiny rate round-trips through the logarithm
  pmt := PaymentXL(D('1E-30'), 100, D('1000000'), D('250'), w70);
  CheckClose('nper tiny r',
    PeriodCountXL(D('1E-30'), pmt, D('1000000'), D('250'), c40), D('100'), 40);
  // a negative present value pays out
  pmt := PaymentXL(D('0.05'), 10, D('-1000'), c);
  AssertTrue(pmt.Sign > 0);
  CheckClose('pv negative', PresentValueXL(D('0.05'), 10, pmt, c), D('-1000'), 40);
end;

procedure TLibraryTests.TestExcelErrors;
var
  c: TMathContext;
begin
  TMathContext.ClearDefault;
  c := TMathContext.Make(20, rmHalfEven);
  try PaymentXL(D('0.05'), 0, D('1000'), c); Fail('nper 0');
  except on EBigDecimalDivByZero do; end;
  try PaymentXL(D('0.05'), -5, D('1000'), c); Fail('nper negative');
  except on EBigDecimalDomain do; end;
  try PeriodicRateXL(0, D('-100'), D('1000'), c); Fail('rate nper 0');
  except on EBigDecimalDivByZero do; end;
  try PeriodicRateXL(-3, D('-100'), D('1000'), c); Fail('rate nper negative');
  except on EBigDecimalDomain do; end;
  try InterestPaymentXL(D('0.05'), 0, 10, D('1000'), c); Fail('per 0');
  except on EBigDecimalDomain do; end;
  try InterestPaymentXL(D('0.05'), 11, 10, D('1000'), c); Fail('per over n');
  except on EBigDecimalDomain do; end;
  try PrincipalPaymentXL(D('0.05'), 0, 10, D('1000'), c); Fail('ppmt per 0');
  except on EBigDecimalDomain do; end;
  try PaymentXL(D('-1'), 10, D('1000'), c); Fail('rate -1 pmt');
  except on EBigDecimalDomain do; end;
  try PresentValueXL(D('-1.5'), 10, D('100'), c); Fail('rate below -1 pv');
  except on EBigDecimalDomain do; end;
  try FutureValueXL(D('-1'), 10, D('100'), c); Fail('rate -1 fv');
  except on EBigDecimalDomain do; end;
  try PeriodCountXL(D('-1'), D('-100'), D('1000'), c); Fail('rate -1 nper');
  except on EBigDecimalDomain do; end;
  try InterestPaymentXL(D('-1'), 1, 10, D('1000'), c); Fail('rate -1 ipmt');
  except on EBigDecimalDomain do; end;
  try PrincipalPaymentXL(D('-1'), 1, 10, D('1000'), c); Fail('rate -1 ppmt');
  except on EBigDecimalDomain do; end;
  try PeriodCountXL(D('0.01'), D('0'), D('1000'), D('1000'), c); Fail('nper no solution');
  except on EBigDecimalDomain do; end;
  try PeriodCountXL(D('0'), D('0'), D('1000'), c); Fail('nper zero pmt');
  except on EBigDecimalDivByZero do; end;
  try PeriodicRateXL(12, D('-100'), D('-1000'), D('-500'), c); Fail('rate same sign');
  except on EBigDecimalDomain do; end;
  try PeriodicRateXL(12, D('-100'), D('0'), D('0'), c); Fail('rate pv=fv=0');
  except on EBigDecimalDomain do; end;
  try PeriodicRateXL(10, D('0'), D('0'), D('100'), c); Fail('rate pmt=pv=0');
  except on EBigDecimalDomain do; end;
  try PeriodicRateXL(10, D('0'), D('1000'), D('500'), c); Fail('rate negative ratio');
  except on EBigDecimalDomain do; end;
  try PeriodicRateXL(2, D('1'), D('1'), D('-1'), ptEnd, D('0.1'), c);
    Fail('rate no convergence');
  except on EBigDecimalNoConvergence do; end;
  try EffectiveRateXL(D('0'), 4, c); Fail('effect zero');
  except on EBigDecimalDomain do; end;
  try EffectiveRateXL(D('-0.01'), 4, c); Fail('effect negative');
  except on EBigDecimalDomain do; end;
  try EffectiveRateXL(D('0.05'), 0, c); Fail('effect npery 0');
  except on EBigDecimalDomain do; end;
  try NominalRateXL(D('0'), 4, c); Fail('nominal zero');
  except on EBigDecimalDomain do; end;
  try NominalRateXL(D('-0.01'), 4, c); Fail('nominal negative');
  except on EBigDecimalDomain do; end;
  try NominalRateXL(D('0.05'), 0, c); Fail('nominal npery 0');
  except on EBigDecimalDomain do; end;
  try PaymentXL(D('0.05'), 10, D('1000'), Unlimited); Fail('unlimited pmt');
  except on EBigDecimalDomain do; end;
  try PeriodicRateXL(12, D('-100'), D('1000'), Unlimited); Fail('unlimited rate');
  except on EBigDecimalDomain do; end;
  try EffectiveRateXL(D('0.05'), 4, Unlimited); Fail('unlimited effect');
  except on EBigDecimalDomain do; end;
end;

procedure TLibraryTests.TestExcelCoreVectors;
var
  sl: TStringList;
  i: Integer;
  f: TStringArray;
  got, exp: string;
  cc: TMathContext;
begin
  TMathContext.ClearDefault;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(VecFile('pmt'));
    for i := 0 to sl.Count - 1 do
    begin
      if sl[i] = '' then Continue;
      f := sl[i].Split([#9]);
      cc := TMathContext.Make(StrToInt(f[6]), ParseMode(f[7]));
      got := PaymentXL(D(f[1]), StrToInt64(f[2]), D(f[3]), D(f[4]), TimingOf(f[5]), cc).ToString;
      exp := f[8];
      if not SameVec(got, exp) then Fail('pmt ' + sl[i] + ' GOT ' + got);
    end;
  finally
    sl.Free;
  end;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(VecFile('nper'));
    for i := 0 to sl.Count - 1 do
    begin
      if sl[i] = '' then Continue;
      f := sl[i].Split([#9]);
      cc := TMathContext.Make(StrToInt(f[6]), ParseMode(f[7]));
      got := PeriodCountXL(D(f[1]), D(f[2]), D(f[3]), D(f[4]), TimingOf(f[5]), cc).ToString;
      exp := f[8];
      if not SameVec(got, exp) then Fail('nper ' + sl[i] + ' GOT ' + got);
    end;
  finally
    sl.Free;
  end;
end;

procedure TLibraryTests.TestExcelSplitVectors;
var
  sl: TStringList;
  i: Integer;
  f: TStringArray;
  got, exp: string;
  cc: TMathContext;
begin
  TMathContext.ClearDefault;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(VecFile('effect'));
    for i := 0 to sl.Count - 1 do
    begin
      if sl[i] = '' then Continue;
      f := sl[i].Split([#9]);
      cc := TMathContext.Make(StrToInt(f[3]), ParseMode(f[4]));
      got := EffectiveRateXL(D(f[1]), StrToInt64(f[2]), cc).ToString;
      exp := f[5];
      if not SameVec(got, exp) then Fail('effect ' + sl[i] + ' GOT ' + got);
    end;
  finally
    sl.Free;
  end;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(VecFile('nominal'));
    for i := 0 to sl.Count - 1 do
    begin
      if sl[i] = '' then Continue;
      f := sl[i].Split([#9]);
      cc := TMathContext.Make(StrToInt(f[3]), ParseMode(f[4]));
      got := NominalRateXL(D(f[1]), StrToInt64(f[2]), cc).ToString;
      exp := f[5];
      if not SameVec(got, exp) then Fail('nominal ' + sl[i] + ' GOT ' + got);
    end;
  finally
    sl.Free;
  end;
end;

procedure TLibraryTests.TestPeriodicRate;
var
  sl: TStringList;
  i: Integer;
  f: TStringArray;
  got, exp: string;
  cc: TMathContext;
  c: TMathContext;
  r1, r2: TBigDecimal;
begin
  TMathContext.ClearDefault;
  c := TMathContext.Make(40, rmHalfEven);
  // two sign changes: the guess selects the root, both solve the equation
  r1 := PeriodicRateXL(2, D('-5'), D('2'), D('7'), ptEnd, D('0.1'), c);
  AssertTrue(r1 = D('-0.5'));
  r2 := PeriodicRateXL(2, D('-5'), D('2'), D('7'), ptEnd, D('0.9'), c);
  AssertTrue(r2 = D('1'));
  AssertTrue(FutureValueXL(r1, 2, D('-5'), D('2'), ptEnd, c) = D('7'));
  AssertTrue(FutureValueXL(r2, 2, D('-5'), D('2'), ptEnd, c) = D('7'));
  AssertTrue(PeriodicRateXL(2, D('-5'), D('2'), D('7'), ptEnd, c) = D('-0.5'));
  AssertTrue(PeriodicRateXL(2, D('-5'), D('2'), D('7'), c) = D('-0.5'));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(VecFile('ratexl'));
    for i := 0 to sl.Count - 1 do
    begin
      if sl[i] = '' then Continue;
      f := sl[i].Split([#9]);
      cc := TMathContext.Make(StrToInt(f[7]), ParseMode(f[8]));
      got := PeriodicRateXL(StrToInt64(f[1]), D(f[2]), D(f[3]), D(f[4]),
        TimingOf(f[5]), D(f[6]), cc).ToString;
      exp := f[9];
      if not SameVec(got, exp) then Fail('ratexl ' + sl[i] + ' GOT ' + got);
    end;
  finally
    sl.Free;
  end;
end;

procedure TLibraryTests.TestExcelDefaultContext;
var
  S: TMathContextScope;
  c: TMathContext;
  r: TBigDecimal;
begin
  c := TMathContext.Make(30, rmDown);
  S.Enter(c);
  r := D('0.006666666666666667');
  AssertTrue(PaymentXL(r, 360, D('250000')).Identical(PaymentXL(r, 360, D('250000'), c)));
  AssertTrue(PaymentXL(r, 360, D('250000'), D('100')).Identical(
    PaymentXL(r, 360, D('250000'), D('100'), c)));
  AssertTrue(PaymentXL(r, 360, D('250000'), D('100'), ptBegin).Identical(
    PaymentXL(r, 360, D('250000'), D('100'), ptBegin, c)));
  AssertTrue(PresentValueXL(r, 360, D('-1500')).Identical(PresentValueXL(r, 360, D('-1500'), c)));
  AssertTrue(PresentValueXL(r, 360, D('-1500'), D('100')).Identical(
    PresentValueXL(r, 360, D('-1500'), D('100'), c)));
  AssertTrue(PresentValueXL(r, 360, D('-1500'), D('100'), ptBegin).Identical(
    PresentValueXL(r, 360, D('-1500'), D('100'), ptBegin, c)));
  AssertTrue(FutureValueXL(r, 360, D('-1500')).Identical(FutureValueXL(r, 360, D('-1500'), c)));
  AssertTrue(FutureValueXL(r, 360, D('-1500'), D('5000')).Identical(
    FutureValueXL(r, 360, D('-1500'), D('5000'), c)));
  AssertTrue(FutureValueXL(r, 360, D('-1500'), D('5000'), ptBegin).Identical(
    FutureValueXL(r, 360, D('-1500'), D('5000'), ptBegin, c)));
  AssertTrue(PeriodCountXL(r, D('-1500'), D('200000')).Identical(
    PeriodCountXL(r, D('-1500'), D('200000'), c)));
  AssertTrue(PeriodCountXL(r, D('-1500'), D('200000'), D('100')).Identical(
    PeriodCountXL(r, D('-1500'), D('200000'), D('100'), c)));
  AssertTrue(PeriodCountXL(r, D('-1500'), D('200000'), D('100'), ptBegin).Identical(
    PeriodCountXL(r, D('-1500'), D('200000'), D('100'), ptBegin, c)));
  AssertTrue(InterestPaymentXL(r, 7, 360, D('250000')).Identical(
    InterestPaymentXL(r, 7, 360, D('250000'), c)));
  AssertTrue(InterestPaymentXL(r, 7, 360, D('250000'), D('100')).Identical(
    InterestPaymentXL(r, 7, 360, D('250000'), D('100'), c)));
  AssertTrue(InterestPaymentXL(r, 7, 360, D('250000'), D('100'), ptBegin).Identical(
    InterestPaymentXL(r, 7, 360, D('250000'), D('100'), ptBegin, c)));
  AssertTrue(PrincipalPaymentXL(r, 7, 360, D('250000')).Identical(
    PrincipalPaymentXL(r, 7, 360, D('250000'), c)));
  AssertTrue(PrincipalPaymentXL(r, 7, 360, D('250000'), D('100')).Identical(
    PrincipalPaymentXL(r, 7, 360, D('250000'), D('100'), c)));
  AssertTrue(PrincipalPaymentXL(r, 7, 360, D('250000'), D('100'), ptBegin).Identical(
    PrincipalPaymentXL(r, 7, 360, D('250000'), D('100'), ptBegin, c)));
  AssertTrue(PeriodicRateXL(48, D('-200'), D('8000')).Identical(
    PeriodicRateXL(48, D('-200'), D('8000'), c)));
  AssertTrue(PeriodicRateXL(48, D('-200'), D('8000'), D('100')).Identical(
    PeriodicRateXL(48, D('-200'), D('8000'), D('100'), c)));
  AssertTrue(PeriodicRateXL(48, D('-200'), D('8000'), D('100'), ptBegin).Identical(
    PeriodicRateXL(48, D('-200'), D('8000'), D('100'), ptBegin, c)));
  AssertTrue(PeriodicRateXL(48, D('-200'), D('8000'), D('100'), ptBegin, D('0.2')).Identical(
    PeriodicRateXL(48, D('-200'), D('8000'), D('100'), ptBegin, D('0.2'), c)));
  AssertTrue(EffectiveRateXL(D('0.0525'), 4).Identical(EffectiveRateXL(D('0.0525'), 4, c)));
  AssertTrue(NominalRateXL(D('0.0535'), 4).Identical(NominalRateXL(D('0.0535'), 4, c)));
end;

initialization
  RegisterTest(TLibraryTests);
end.
