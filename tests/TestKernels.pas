{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: tests, kernels
---
}
unit TestKernels;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  BigDecimal.Types, BigDecimal.Limbs, BigDecimal.Multiply, BigDecimal.Divide;

type
  TKernelTests = class(TTestCase)
  published
    procedure TestDigitCount;
    procedure TestAddSubCarry;
    procedure TestKaratsubaEqualsSchoolbook;
    procedure TestSchoolbookEqualsRowMultiply;
    procedure TestSquareEqualsMultiply;
    procedure TestDivisionIdentity;
    procedure TestDivisionAddBack;
    procedure TestNewtonEqualsKnuth;
    procedure TestScopeRestores;
    procedure TestThreadsHaveSeparateDefaults;
  end;

implementation

function RandLimbs(n: Integer; Mode: Integer): TLimbs;
var
  i: Integer;
begin
  SetLength(Result, n);
  for i := 0 to n - 1 do
    case Mode of
      0: Result[i] := Random(LimbBase);
      1: Result[i] := LimbBase - 1;
      2: if Random(2) = 0 then Result[i] := 0 else Result[i] := LimbBase - 1;
    end;
  if Result[n - 1] = 0 then Result[n - 1] := 1;
end;

procedure TKernelTests.TestDigitCount;
var
  i: Integer;
begin
  AssertEquals(1, DigitCount(0));
  AssertEquals(1, DigitCount(9));
  AssertEquals(2, DigitCount(10));
  AssertEquals(9, DigitCount(999999999));
  AssertEquals(10, DigitCount(1000000000));
  for i := 0 to 9 do
    AssertEquals(i + 1, DigitCount(Pow10_32[i]));
  AssertEquals(19, DigitCount64(UInt64(Pow10_64[18])));
end;

procedure TKernelTests.TestAddSubCarry;
var
  a, b, r, s: TLimbs;
  nr, ns: Integer;
begin
  a := RandLimbs(5, 1);
  SetLength(b, 1);
  b[0] := 1;
  SetLength(r, 6);
  nr := AddMag(@a[0], 5, @b[0], 1, @r[0]);
  AssertEquals(6, nr);
  AssertEquals(1, r[5]);
  AssertEquals(0, r[0]);
  SetLength(s, 6);
  ns := SubMag(@r[0], nr, @b[0], 1, @s[0]);
  AssertEquals(5, ns);
  AssertEquals(LimbBase - 1, s[0]);
  AssertEquals(0, CmpMag(@s[0], ns, @a[0], 5));
end;

procedure TKernelTests.TestKaratsubaEqualsSchoolbook;
var
  i, na, nb, mode: Integer;
  a, b, r1, r2: TLimbs;
  n1, n2: Integer;
begin
  Randomize;
  for i := 1 to 300 do
  begin
    na := 1 + Random(600);
    nb := 1 + Random(600);
    if i mod 5 = 0 then nb := 1 + Random(8);
    mode := Random(3);
    a := RandLimbs(na, mode);
    b := RandLimbs(nb, mode);
    SetLength(r1, na + nb);
    SetLength(r2, na + nb);
    n1 := MulMagForce(@a[0], na, @b[0], nb, @r1[0], False);
    n2 := MulMagForce(@a[0], na, @b[0], nb, @r2[0], True);
    AssertEquals('length', n1, n2);
    AssertEquals('equal ' + IntToStr(na) + 'x' + IntToStr(nb), 0, CmpMag(@r1[0], n1, @r2[0], n2));
  end;
end;

procedure TKernelTests.TestSchoolbookEqualsRowMultiply;
var
  i, j, k, na, nb, mode: Integer;
  a, b, r1, r2: TLimbs;
  t, carry: UInt64;
begin
  // independent reference: one division by 10^9 for every product
  for k := 1 to 400 do
  begin
    na := 1 + Random(70);
    nb := 1 + Random(70);
    mode := Random(3);
    a := RandLimbs(na, mode);
    b := RandLimbs(nb, mode);
    SetLength(r1, na + nb);
    SetLength(r2, na + nb);
    for i := 0 to na + nb - 1 do r2[i] := 0;
    for i := 0 to na - 1 do
    begin
      carry := 0;
      for j := 0 to nb - 1 do
      begin
        t := UInt64(r2[i + j]) + UInt64(a[i]) * b[j] + carry;
        carry := t div LimbBase;
        r2[i + j] := UInt32(t mod LimbBase);
      end;
      r2[i + nb] := UInt32(carry);
    end;
    MulSchool(@a[0], na, @b[0], nb, @r1[0]);
    for i := 0 to na + nb - 1 do
      AssertEquals('limb ' + IntToStr(i) + ' of ' + IntToStr(na) + 'x' + IntToStr(nb),
        r2[i], r1[i]);
  end;
end;

procedure TKernelTests.TestSquareEqualsMultiply;
var
  i, n, mode: Integer;
  a, r1, r2: TLimbs;
  n1, n2: Integer;
begin
  for i := 1 to 200 do
  begin
    n := 1 + Random(600);
    mode := Random(3);
    a := RandLimbs(n, mode);
    SetLength(r1, 2 * n);
    SetLength(r2, 2 * n);
    n1 := SqrMag(@a[0], n, @r1[0]);
    n2 := MulMagForce(@a[0], n, @a[0], n, @r2[0], False);
    AssertEquals(n2, n1);
    AssertEquals('square ' + IntToStr(n), 0, CmpMag(@r1[0], n1, @r2[0], n2));
  end;
end;

procedure DivCheck(na, nb, mode: Integer; T: TTestCase);
var
  a, b, q, rem, prod, sum, back: TLimbs;
  nq, nr, np, ns: Integer;
begin
  a := RandLimbs(na, mode);
  b := RandLimbs(nb, mode);
  if CmpMag(@a[0], na, @b[0], nb) < 0 then Exit;
  SetLength(q, na - nb + 1);
  SetLength(rem, nb);
  DivRemMag(@a[0], na, @b[0], nb, @q[0], nq, @rem[0], nr);
  // a = q * b + rem
  SetLength(prod, nq + nb);
  np := MulMag(@q[0], nq, @b[0], nb, @prod[0]);
  SetLength(sum, np + 2);
  if nr > 0 then
    ns := AddMag(@prod[0], np, @rem[0], nr, @sum[0])
  else
  begin
    Move(prod[0], sum[0], np * SizeOf(TLimb));
    ns := np;
  end;
  back := nil;
  T.AssertEquals('identity ' + IntToStr(na) + '/' + IntToStr(nb), 0, CmpMag(@sum[0], ns, @a[0], na));
  T.AssertTrue('remainder below divisor', CmpMag(@rem[0], nr, @b[0], nb) < 0);
end;

procedure TKernelTests.TestDivisionIdentity;
var
  i: Integer;
begin
  for i := 1 to 400 do
    DivCheck(2 + Random(500), 1 + Random(250), Random(3), Self);
end;

procedure TKernelTests.TestDivisionAddBack;
var
  i: Integer;
begin
  // top limbs equal to the divisor top limb and all-nine patterns
  for i := 1 to 300 do
    DivCheck(10 + Random(6), 3 + Random(4), 2, Self);
  for i := 1 to 100 do
    DivCheck(12, 4, 1, Self);
end;

procedure TKernelTests.TestNewtonEqualsKnuth;
var
  i, na, nb, mode, nq1, nq2, nr1, nr2: Integer;
  a, b, q1, q2, r1, r2: TLimbs;
begin
  for i := 1 to 300 do
  begin
    nb := 2 + Random(150);
    na := nb + Random(200);
    mode := Random(3);
    a := RandLimbs(na, mode);
    b := RandLimbs(nb, mode);
    if CmpMag(@a[0], na, @b[0], nb) < 0 then Continue;
    SetLength(q1, na - nb + 2); SetLength(q2, na - nb + 2);
    SetLength(r1, nb + 1); SetLength(r2, nb + 1);
    DivRemKnuth(@a[0], na, @b[0], nb, @q1[0], nq1, @r1[0], nr1);
    DivRemNewton(@a[0], na, @b[0], nb, @q2[0], nq2, @r2[0], nr2);
    AssertEquals('q length ' + IntToStr(na) + '/' + IntToStr(nb), nq1, nq2);
    AssertEquals('quotient', 0, CmpMag(@q1[0], nq1, @q2[0], nq2));
    AssertEquals('r length', nr1, nr2);
    AssertEquals('remainder', 0, CmpMag(@r1[0], nr1, @r2[0], nr2));
  end;
end;

procedure TKernelTests.TestScopeRestores;
var
  S1, S2: TMathContextScope;
begin
  TMathContext.ClearDefault;
  AssertFalse(TMathContext.HasDefault);
  try
    S1.Enter(Decimal32);
    AssertEquals(7, TMathContext.Default.Precision);
    S2.Enter(Decimal64);
    AssertEquals(16, TMathContext.Default.Precision);
    raise Exception.Create('x');
  except
  end;
  // both scopes are still alive here (same procedure), so exit by function
  S1.Enter(Decimal32);
end;

type
  TThr = class(TThread)
  public
    Prec: Integer;
    Seen: Integer;
    Before: Boolean;
    procedure Execute; override;
  end;

procedure TThr.Execute;
var
  i: Integer;
begin
  Before := TMathContext.HasDefault;
  TMathContext.SetDefault(TMathContext.Make(Prec, rmHalfUp));
  for i := 1 to 100000 do
    if TMathContext.Default.Precision <> Prec then Seen := -1;
  if Seen = 0 then Seen := TMathContext.Default.Precision;
end;

procedure TKernelTests.TestThreadsHaveSeparateDefaults;
var
  a, b: TThr;
begin
  TMathContext.SetDefault(Decimal128);
  a := TThr.Create(True); a.Prec := 11;
  b := TThr.Create(True); b.Prec := 22;
  a.Start; b.Start; a.WaitFor; b.WaitFor;
  AssertFalse('new thread starts without default', a.Before);
  AssertFalse(b.Before);
  AssertEquals(11, a.Seen);
  AssertEquals(22, b.Seen);
  AssertEquals(34, TMathContext.Default.Precision);
  a.Free; b.Free;
  TMathContext.ClearDefault;
end;

initialization
  RegisterTest(TKernelTests);
end.
