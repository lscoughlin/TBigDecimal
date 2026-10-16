{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: tests, oracle vectors
---
}
unit TestVectors;

{$mode objfpc}{$H+}
{$coperators on}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, BigDecimal.Types, BigDecimal, BigDecimal.Elementary, BigDecimal.Trig,
  BigDecimal.Combinatorics, BigDecimal.Gamma;

type
  TVectorTests = class(TTestCase)
  private
    procedure RunFile(const Name: string);
  published
    procedure TestAdd;
    procedure TestSub;
    procedure TestMul;
    procedure TestSqr;
    procedure TestCmp;
    procedure TestRound;
    procedure TestSetScale;
    procedure TestDivCtx;
    procedure TestDivExact;
    procedure TestDivInt;
    procedure TestStrip;
    procedure TestToDouble;
    procedure TestFromDouble;
    procedure TestSqrt;
    procedure TestRoot;
    procedure TestExp;
    procedure TestLn;
    procedure TestLog10;
    procedure TestLog;
    procedure TestPow;
    procedure TestSin;
    procedure TestCos;
    procedure TestTan;
    procedure TestFact;
    procedure TestBinom;
    procedure TestPerm;
    procedure TestDFact;
    procedure TestCatalan;
    procedure TestPrimorial;
    procedure TestRising;
    procedure TestGamma;
    procedure TestLnGamma;
  end;

function ParseMode(const S: string): TRoundingMode;

implementation

function ParseMode(const S: string): TRoundingMode;
begin
  if S = 'rmUp' then Result := rmUp
  else if S = 'rmDown' then Result := rmDown
  else if S = 'rmCeiling' then Result := rmCeiling
  else if S = 'rmFloor' then Result := rmFloor
  else if S = 'rmHalfUp' then Result := rmHalfUp
  else if S = 'rmHalfDown' then Result := rmHalfDown
  else if S = 'rmHalfEven' then Result := rmHalfEven
  else Result := rmUnnecessary;
end;

function Fields(const Line: string): TStringArray;
begin
  Result := Line.Split([#9]);
end;

function VecPath(const Name: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '../tests/vectors/' + Name + '.txt';
end;

procedure TVectorTests.RunFile(const Name: string);
var
  sl: TStringList;
  i, bad, total: Integer;
  f: TStringArray;
  got, msg: string;
  a, b, r: TBigDecimal;
  d: Double;
  bitsGot: UInt64;
  expIdx: Integer;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(VecPath(Name));
    bad := 0;
    total := 0;
    msg := '';
    for i := 0 to sl.Count - 1 do
    begin
      if sl[i] = '' then Continue;
      f := Fields(sl[i]);
      Inc(total);
      got := '';
      try
        case f[0] of
          'add': got := (TBigDecimal.Create(f[1]) + TBigDecimal.Create(f[2])).ToString;
          'sub': got := (TBigDecimal.Create(f[1]) - TBigDecimal.Create(f[2])).ToString;
          'mul': got := (TBigDecimal.Create(f[1]) * TBigDecimal.Create(f[2])).ToString;
          'sqr': got := TBigDecimal.Create(f[1]).Square.ToString;
          'cmp': got := IntToStr(TBigDecimal.Create(f[1]).CompareTo(TBigDecimal.Create(f[2])));
          'round': got := TBigDecimal.Create(f[1]).Round(
                     TMathContext.Make(StrToInt(f[2]), ParseMode(f[3]))).ToString;
          'setscale': got := TBigDecimal.Create(f[1]).SetScale(StrToInt(f[2]), ParseMode(f[3])).ToString;
          'divctx': got := TBigDecimal.Create(f[1]).Divide(TBigDecimal.Create(f[2]),
                      TMathContext.Make(StrToInt(f[3]), ParseMode(f[4]))).ToString;
          'divexact':
            try
              got := TBigDecimal.Create(f[1]).Divide(TBigDecimal.Create(f[2])).ToString;
            except
              on EBigDecimalNonTerminating do got := 'ERR';
            end;
          'divint':
            begin
              a := TBigDecimal.Create(f[1]);
              b := TBigDecimal.Create(f[2]);
              r := a.DivideToIntegralValue(b);
              if r.CompareTo(TBigDecimal.Create(f[3])) <> 0 then
                got := 'quotient ' + r.ToString
              else
              begin
                r := a.Remainder(b);
                if (r.CompareTo(TBigDecimal.Create(f[4])) <> 0) then
                  got := 'remainder ' + r.ToString
                else
                  got := f[3];
              end;
              f[2] := f[2]; // keep
              // expected is compared numerically above
              if got = f[3] then Continue;
            end;
          'sqrt': got := Sqrt(TBigDecimal.Create(f[1]), TMathContext.Make(StrToInt(f[2]), ParseMode(f[3]))).ToString;
          'exp': got := Exp(TBigDecimal.Create(f[1]), TMathContext.Make(StrToInt(f[2]), ParseMode(f[3]))).ToString;
          'ln': got := Ln(TBigDecimal.Create(f[1]), TMathContext.Make(StrToInt(f[2]), ParseMode(f[3]))).ToString;
          'log10': got := Log10(TBigDecimal.Create(f[1]), TMathContext.Make(StrToInt(f[2]), ParseMode(f[3]))).ToString;
          'sin': got := Sin(TBigDecimal.Create(f[1]), TMathContext.Make(StrToInt(f[2]), ParseMode(f[3]))).ToString;
          'cos': got := Cos(TBigDecimal.Create(f[1]), TMathContext.Make(StrToInt(f[2]), ParseMode(f[3]))).ToString;
          'tan': got := Tan(TBigDecimal.Create(f[1]), TMathContext.Make(StrToInt(f[2]), ParseMode(f[3]))).ToString;
          'root': got := Root(TBigDecimal.Create(f[1]), StrToInt(f[2]), TMathContext.Make(StrToInt(f[3]), ParseMode(f[4]))).ToString;
          'log': got := Log(TBigDecimal.Create(f[1]), TBigDecimal.Create(f[2]), TMathContext.Make(StrToInt(f[3]), ParseMode(f[4]))).ToString;
          'pow': got := Pow(TBigDecimal.Create(f[1]), TBigDecimal.Create(f[2]), TMathContext.Make(StrToInt(f[3]), ParseMode(f[4]))).ToString;
          'fact': got := Factorial(StrToInt64(f[1])).ToString;
          'binom': got := Binomial(StrToInt64(f[1]), StrToInt64(f[2])).ToString;
          'perm': got := Permutations(StrToInt64(f[1]), StrToInt64(f[2])).ToString;
          'dfact': got := DoubleFactorial(StrToInt64(f[1])).ToString;
          'catalan': got := Catalan(StrToInt64(f[1])).ToString;
          'primorial': got := Primorial(StrToInt64(f[1])).ToString;
          'rising': got := RisingFactorial(TBigDecimal.Create(f[1]), StrToInt64(f[2])).ToString;
          'gamma': got := Gamma(TBigDecimal.Create(f[1]), TMathContext.Make(StrToInt(f[2]), ParseMode(f[3]))).ToString;
          'lngamma': got := LnGamma(TBigDecimal.Create(f[1]), TMathContext.Make(StrToInt(f[2]), ParseMode(f[3]))).ToString;
          'strip': got := TBigDecimal.Create(f[1]).StripTrailingZeros.ToString;
          'todouble':
            begin
              d := TBigDecimal.Create(f[1]).ToDouble;
              bitsGot := PUInt64(@d)^;
              got := UIntToStr(bitsGot);
            end;
          'fromdouble':
            begin
              bitsGot := StrToQWord(f[1]);
              d := PDouble(@bitsGot)^;
              r := TBigDecimal.FromDouble(d);
              if r.ToDouble = d then Continue;
              got := 'no round trip ' + r.ToString;
            end;
        end;
      except
        on E: Exception do got := 'EXC ' + E.ClassName + ': ' + E.Message;
      end;
      case f[0] of
        'add', 'sub', 'mul', 'cmp', 'divexact', 'divint', 'binom', 'perm', 'rising': expIdx := 3;
        'sqr', 'strip', 'todouble', 'fact', 'dfact', 'catalan', 'primorial': expIdx := 2;
        'round', 'setscale', 'sqrt', 'exp', 'ln', 'log10', 'sin', 'cos', 'tan', 'gamma', 'lngamma': expIdx := 4;
        'divctx', 'root', 'log', 'pow': expIdx := 5;
      else
        expIdx := 1;
      end;
      if got = f[expIdx] then Continue;
      Inc(bad);
      if bad <= 6 then
        msg += LineEnding + '  ' + StringReplace(sl[i], #9, ' | ', [rfReplaceAll]) + '  GOT ' + got;
    end;
    if bad > 0 then
      Fail(Name + ': ' + IntToStr(bad) + ' of ' + IntToStr(total) + ' failed' + msg);
  finally
    sl.Free;
  end;
end;

procedure TVectorTests.TestAdd; begin RunFile('add'); end;
procedure TVectorTests.TestSub; begin RunFile('sub'); end;
procedure TVectorTests.TestMul; begin RunFile('mul'); end;
procedure TVectorTests.TestSqr; begin RunFile('sqr'); end;
procedure TVectorTests.TestCmp; begin RunFile('cmp'); end;
procedure TVectorTests.TestRound; begin RunFile('round'); end;
procedure TVectorTests.TestSetScale; begin RunFile('setscale'); end;
procedure TVectorTests.TestDivCtx; begin RunFile('divctx'); end;
procedure TVectorTests.TestDivExact; begin RunFile('divexact'); end;
procedure TVectorTests.TestDivInt; begin RunFile('divint'); end;
procedure TVectorTests.TestStrip; begin RunFile('strip'); end;
procedure TVectorTests.TestToDouble; begin RunFile('todouble'); end;
procedure TVectorTests.TestFromDouble; begin RunFile('fromdouble'); end;
procedure TVectorTests.TestSqrt; begin RunFile('sqrt'); end;
procedure TVectorTests.TestRoot; begin RunFile('root'); end;
procedure TVectorTests.TestExp; begin RunFile('exp'); end;
procedure TVectorTests.TestLn; begin RunFile('ln'); end;
procedure TVectorTests.TestLog10; begin RunFile('log10'); end;
procedure TVectorTests.TestLog; begin RunFile('log'); end;
procedure TVectorTests.TestPow; begin RunFile('pow'); end;
procedure TVectorTests.TestSin; begin RunFile('sin'); end;
procedure TVectorTests.TestCos; begin RunFile('cos'); end;
procedure TVectorTests.TestTan; begin RunFile('tan'); end;
procedure TVectorTests.TestFact; begin RunFile('fact'); end;
procedure TVectorTests.TestBinom; begin RunFile('binom'); end;
procedure TVectorTests.TestPerm; begin RunFile('perm'); end;
procedure TVectorTests.TestDFact; begin RunFile('dfact'); end;
procedure TVectorTests.TestCatalan; begin RunFile('catalan'); end;
procedure TVectorTests.TestPrimorial; begin RunFile('primorial'); end;
procedure TVectorTests.TestRising; begin RunFile('rising'); end;
procedure TVectorTests.TestGamma; begin RunFile('gamma'); end;
procedure TVectorTests.TestLnGamma; begin RunFile('lngamma'); end;

initialization
  RegisterTest(TVectorTests);
end.
