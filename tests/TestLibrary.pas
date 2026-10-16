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
  Classes, SysUtils, fpcunit, testregistry, BigDecimal.Types, BigDecimal,
  BigDecimal.Elementary, BigDecimal.Trig, BigDecimal.Constants,
  BigDecimal.Combinatorics, BigDecimal.Gamma, BigDecimal.Financial;

type
  TLibraryTests = class(TTestCase)
  private
    function Ref(const Name: string): string;
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
    procedure TestSqrtFastPathEqualsGeneral;
    procedure TestStackPathBoundaries;
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
  q: TBigDecimal;
begin
  TMathContext.ClearDefault;
  AssertEquals('0.3333333333333333333333333333333333', D('1').Divide(D('3'), Decimal128).ToString);
  try
    q := D('1') / D('3');
    Fail('exact division should raise ' + q.ToString);
  except
    on EBigDecimalNonTerminating do ;
  end;
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
  else
    Result := TBigDecimal.Zero;
  end;
end;

procedure TLibraryTests.TestDefaultContextIsolation;
const
  Cases = 35;
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
begin
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
  AssertEquals('0.2.0', BigDecimalVersion);
  AssertEquals('0.2.0', Format('%d.%d.%d', [BigDecimalVersionMajor,
    BigDecimalVersionMinor, BigDecimalVersionRelease]));
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
begin
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

initialization
  RegisterTest(TLibraryTests);
end.
