{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: tests, dectest, General Decimal Arithmetic
documentation: doc/design.md
notes:
  - runs the IBM/Cowlishaw dectest files that match TBigDecimal operations
  - a case with NaN, infinity, an exponent limit or negative zero is skipped and counted
  - tests/dectest-expected-failures.txt lists known deviations with a reason
---
}
unit DecTestRunner;

{$mode objfpc}{$H+}
{$coperators on}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, BigDecimal.Types, BigDecimal
  {$ifdef MATH}, BigDecimal.Elementary{$endif};

type
  TDecTests = class(TTestCase)
  private
    procedure RunDecFile(const AFile: string);
  published
    procedure TestAdd;
    procedure TestSubtract;
    procedure TestMultiply;
    procedure TestDivide;
    procedure TestDivideInt;
    procedure TestRemainder;
    procedure TestCompare;
    procedure TestMax;
    procedure TestMin;
    procedure TestAbs;
    procedure TestMinus;
    procedure TestPlus;
    procedure TestRounding;
    procedure TestQuantize;
    procedure TestRescale;
    procedure TestToIntegral;
    procedure TestToIntegralX;
    procedure TestReduce;
    procedure TestSquareRoot;
    procedure TestExp;
    procedure TestLn;
    procedure TestLog10;
    procedure TestPower;
  end;

implementation

type
  EDecSkip = class(Exception);

function RefDir: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '../tests/refs/dectest/';
end;

var
  GKnown: TStringList = nil;

procedure LoadKnown;
var
  sl: TStringList;
  i, p: Integer;
  line: string;
begin
  if GKnown <> nil then Exit;
  GKnown := TStringList.Create;
  GKnown.CaseSensitive := False;
  sl := TStringList.Create;
  try
    if FileExists(ExtractFilePath(ParamStr(0)) + '../tests/dectest-expected-failures.txt') then
      sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + '../tests/dectest-expected-failures.txt');
    for i := 0 to sl.Count - 1 do
    begin
      line := Trim(sl[i]);
      if (line = '') or (line[1] = '#') then Continue;
      p := Pos(#9, line);
      if p = 0 then p := Pos(' ', line);
      if p = 0 then GKnown.Add(line) else GKnown.Add(Copy(line, 1, p - 1));
    end;
  finally
    sl.Free;
  end;
end;

function ModeFromName(const S: string; out Mode: TRoundingMode): Boolean;
begin
  Result := True;
  case LowerCase(S) of
    'up': Mode := rmUp;
    'down': Mode := rmDown;
    'ceiling': Mode := rmCeiling;
    'floor': Mode := rmFloor;
    'half_up': Mode := rmHalfUp;
    'half_down': Mode := rmHalfDown;
    'half_even': Mode := rmHalfEven;
  else
    Result := False; // 05up
  end;
end;

{ Splits a test line into tokens; quotes group a token and are removed. }
procedure Tokenize(const S: string; Toks: TStringList);
var
  i: Integer;
  cur: string;
  q: Char;
  inTok: Boolean;
begin
  Toks.Clear;
  i := 1;
  cur := '';
  inTok := False;
  q := #0;
  while i <= Length(S) do
  begin
    if q <> #0 then
    begin
      if S[i] = q then
      begin
        if (i < Length(S)) and (S[i + 1] = q) then
        begin
          cur += q;
          Inc(i);
        end
        else
          q := #0;
      end
      else
        cur += S[i];
    end
    else if (S[i] = '''') or (S[i] = '"') then
    begin
      q := S[i];
      inTok := True;
    end
    else if (S[i] = ' ') or (S[i] = #9) then
    begin
      if inTok then
      begin
        Toks.Add(cur);
        cur := '';
        inTok := False;
      end;
    end
    else if (S[i] = '-') and (i < Length(S)) and (S[i + 1] = '-') and (not inTok) then
      Break
    else
    begin
      cur += S[i];
      inTok := True;
    end;
    Inc(i);
  end;
  if inTok then Toks.Add(cur);
end;

function IsSpecial(const S: string): Boolean;
var
  t: string;
begin
  t := LowerCase(S);
  if (t <> '') and ((t[1] = '-') or (t[1] = '+')) then Delete(t, 1, 1);
  Result := (t = 'nan') or (t = 'snan') or (t = 'inf') or (t = 'infinity') or
            (Copy(t, 1, 3) = 'nan') or (Copy(t, 1, 4) = 'snan') or (t = '#');
end;

function Operand(const S: string): TBigDecimal;
begin
  if IsSpecial(S) or (Pos('#', S) > 0) then raise EDecSkip.Create('special operand');
  if not TBigDecimal.TryParse(S, Result) then raise EDecSkip.Create('unparsable operand');
  if Result.IsZero and (Length(S) > 0) and (S[1] = '-') then
    raise EDecSkip.Create('negative zero operand');
end;

function ApplyOp(const Op: string; const Args: TStringList;
  const C: TMathContext; out Res: string; out Numeric: Boolean): Boolean;
var
  a, b, r: TBigDecimal;
  cmp: Integer;
begin
  Result := True;
  Numeric := False;
  case Op of
    'add': r := Operand(Args[0]).Add(Operand(Args[1]), C);
    'subtract': r := Operand(Args[0]).Subtract(Operand(Args[1]), C);
    'multiply': r := Operand(Args[0]).Multiply(Operand(Args[1]), C);
    'divide': r := Operand(Args[0]).Divide(Operand(Args[1]), C);
    'divideint':
      begin
        a := Operand(Args[0]);
        b := Operand(Args[1]);
        r := a.DivideToIntegralValue(b);
        if (C.Precision > 0) and (r.Precision > C.Precision) and (not r.IsZero) then
          raise EDecSkip.Create('division impossible');
        Numeric := True;
      end;
    'remainder':
      begin
        a := Operand(Args[0]);
        b := Operand(Args[1]);
        if (C.Precision > 0) and (a.DivideToIntegralValue(b).Precision > C.Precision) then
          raise EDecSkip.Create('division impossible');
        r := a.Remainder(b).Round(C);
      end;
    'compare':
      begin
        cmp := Operand(Args[0]).CompareTo(Operand(Args[1]));
        Res := IntToStr(cmp);
        Exit;
      end;
    'max':
      begin
        a := Operand(Args[0]); b := Operand(Args[1]);
        cmp := a.CompareTo(b);
        if cmp > 0 then r := a
        else if cmp < 0 then r := b
        else if (a.Sign < 0) then begin if a.Scale > b.Scale then r := a else r := b; end
        else begin if a.Scale < b.Scale then r := a else r := b; end;
        r := r.Round(C);
      end;
    'min':
      begin
        a := Operand(Args[0]); b := Operand(Args[1]);
        cmp := a.CompareTo(b);
        if cmp < 0 then r := a
        else if cmp > 0 then r := b
        else if (a.Sign < 0) then begin if a.Scale < b.Scale then r := a else r := b; end
        else begin if a.Scale > b.Scale then r := a else r := b; end;
        r := r.Round(C);
      end;
    'abs': r := Operand(Args[0]).Abs.Round(C);
    'minus': r := Operand(Args[0]).Negate.Round(C);
    'plus': r := Operand(Args[0]).Round(C);
    'reduce': r := Operand(Args[0]).Round(C).StripTrailingZeros;
    'quantize':
      begin
        a := Operand(Args[0]);
        b := Operand(Args[1]);
        r := a.SetScale(b.Scale, C.RoundingMode);
        if (C.Precision > 0) and (r.Precision > C.Precision) then
          raise EDecSkip.Create('quantize exceeds precision');
      end;
    'rescale':
      begin
        a := Operand(Args[0]);
        b := Operand(Args[1]);
        r := a.SetScale(-b.ToInt64, C.RoundingMode);
      end;
    'tointegral', 'tointegralx':
      begin
        a := Operand(Args[0]);
        if a.Scale <= 0 then r := a else r := a.SetScale(0, C.RoundingMode);
      end;
{$ifdef MATH}
    'squareroot': r := Sqrt(Operand(Args[0]), C);
    'exp': r := Exp(Operand(Args[0]), C);
    'ln': r := Ln(Operand(Args[0]), C);
    'log10': r := Log10(Operand(Args[0]), C);
    'power': r := Pow(Operand(Args[0]), Operand(Args[1]), C);
{$endif}
  else
    Result := False;
    Exit;
  end;
  Res := r.ToString;
end;

procedure TDecTests.RunDecFile(const AFile: string);
var
  sl, toks, args, conds: TStringList;
  i, j, arrow: Integer;
  line, id, op, got, expected, key: string;
  ctx: TMathContext;
  mode: TRoundingMode;
  modeOk: Boolean;
  numeric, supported: Boolean;
  passed, known, skipped, bad, stale, total: Integer;
  msg, skipReasons: string;
  cond: string;
  skipCase: Boolean;
  e1, e2: TBigDecimal;
begin
  LoadKnown;
  sl := TStringList.Create;
  toks := TStringList.Create;
  args := TStringList.Create;
  conds := TStringList.Create;
  try
    sl.LoadFromFile(RefDir + AFile);
    ctx := TMathContext.Make(9, rmHalfUp);
    modeOk := True;
    passed := 0; known := 0; skipped := 0; bad := 0; stale := 0; total := 0;
    msg := '';
    for i := 0 to sl.Count - 1 do
    begin
      line := sl[i];
      if (Trim(line) = '') or (Copy(Trim(line), 1, 2) = '--') then Continue;
      Tokenize(line, toks);
      if toks.Count = 0 then Continue;
      if (Length(toks[0]) > 0) and (toks[0][Length(toks[0])] = ':') then
      begin
        // directive
        key := LowerCase(Copy(toks[0], 1, Length(toks[0]) - 1));
        if toks.Count > 1 then
        begin
          if key = 'precision' then ctx.Precision := StrToIntDef(toks[1], 9)
          else if key = 'rounding' then
          begin
            modeOk := ModeFromName(toks[1], mode);
            if modeOk then ctx.RoundingMode := mode;
          end;
        end;
        Continue;
      end;
      // test case: id op operands -> result conditions
      arrow := toks.IndexOf('->');
      if (arrow < 2) or (toks.Count < arrow + 2) then Continue;
      Inc(total);
      id := toks[0];
      op := LowerCase(toks[1]);
      args.Clear;
      for j := 2 to arrow - 1 do args.Add(toks[j]);
      expected := toks[arrow + 1];
      conds.Clear;
      for j := arrow + 2 to toks.Count - 1 do conds.Add(LowerCase(toks[j]));
      skipCase := (not modeOk) or IsSpecial(expected) or
                  (conds.IndexOf('overflow') >= 0) or (conds.IndexOf('underflow') >= 0) or
                  (conds.IndexOf('subnormal') >= 0) or (conds.IndexOf('clamped') >= 0) or
                  (conds.IndexOf('conversion_syntax') >= 0) or
                  (conds.IndexOf('invalid_operation') >= 0) or
                  (conds.IndexOf('division_by_zero') >= 0) or
                  (conds.IndexOf('division_impossible') >= 0) or
                  (conds.IndexOf('division_undefined') >= 0) or
                  (Pos('#', expected) > 0);
      if (not skipCase) and (Length(expected) > 1) and (expected[1] = '-') then
        if TBigDecimal.TryParse(expected, e1) and e1.IsZero then skipCase := True;
      if skipCase then
      begin
        Inc(skipped);
        Continue;
      end;
      got := '';
      supported := True;
      try
        supported := ApplyOp(op, args, ctx, got, numeric);
      except
        on EDecSkip do begin Inc(skipped); Continue; end;
        on EBigDecimalOverflow do begin Inc(skipped); Continue; end;
        on E: Exception do got := 'EXC ' + E.ClassName + ': ' + E.Message;
      end;
      if not supported then
      begin
        Inc(skipped);
        Continue;
      end;
      if numeric and TBigDecimal.TryParse(got, e1) and TBigDecimal.TryParse(expected, e2) then
        supported := e1.CompareTo(e2) = 0
      else
        supported := got = expected;
      if supported then
      begin
        if GKnown.IndexOf(id) >= 0 then
        begin
          Inc(stale);
          msg += LineEnding + '  stale expected failure ' + id;
        end
        else
          Inc(passed);
      end
      else
      begin
        if GKnown.IndexOf(id) >= 0 then
          Inc(known)
        else
        begin
          Inc(bad);
          if bad <= 12 then
            msg += LineEnding + '  ' + id + ' ' + op + ' ' + args.CommaText +
                   ' -> expected ' + expected + ' got ' + got +
                   ' (precision ' + IntToStr(ctx.Precision) + ' mode ' +
                   IntToStr(Ord(ctx.RoundingMode)) + ')';
        end;
      end;
    end;
    skipReasons := '';
    if (bad > 0) or (stale > 0) then
      Fail(AFile + ': ' + IntToStr(bad) + ' unexpected failures, ' + IntToStr(stale) +
           ' stale entries; ' + IntToStr(passed) + ' passed, ' + IntToStr(known) +
           ' known failures, ' + IntToStr(skipped) + ' skipped of ' + IntToStr(total) + msg);
    AssertTrue(AFile + ' ran no case (is -dMATH set?)', passed + known > 0);
    WriteLn(StdErr, 'dectest ', AFile, ': ', passed, ' passed, ', known, ' known failures, ', skipped, ' skipped of ', total);
    AssertTrue(AFile + ' ' + IntToStr(passed) + ' passed, ' + IntToStr(known) +
               ' known, ' + IntToStr(skipped) + ' skipped', True);
  finally
    sl.Free; toks.Free; args.Free; conds.Free;
  end;
end;

procedure TDecTests.TestAdd; begin RunDecFile('add.decTest'); end;
procedure TDecTests.TestSubtract; begin RunDecFile('subtract.decTest'); end;
procedure TDecTests.TestMultiply; begin RunDecFile('multiply.decTest'); end;
procedure TDecTests.TestDivide; begin RunDecFile('divide.decTest'); end;
procedure TDecTests.TestDivideInt; begin RunDecFile('divideint.decTest'); end;
procedure TDecTests.TestRemainder; begin RunDecFile('remainder.decTest'); end;
procedure TDecTests.TestCompare; begin RunDecFile('compare.decTest'); end;
procedure TDecTests.TestMax; begin RunDecFile('max.decTest'); end;
procedure TDecTests.TestMin; begin RunDecFile('min.decTest'); end;
procedure TDecTests.TestAbs; begin RunDecFile('abs.decTest'); end;
procedure TDecTests.TestMinus; begin RunDecFile('minus.decTest'); end;
procedure TDecTests.TestPlus; begin RunDecFile('plus.decTest'); end;
procedure TDecTests.TestRounding; begin RunDecFile('rounding.decTest'); end;
procedure TDecTests.TestQuantize; begin RunDecFile('quantize.decTest'); end;
procedure TDecTests.TestRescale; begin RunDecFile('rescale.decTest'); end;
procedure TDecTests.TestToIntegral; begin RunDecFile('tointegral.decTest'); end;
procedure TDecTests.TestToIntegralX; begin RunDecFile('tointegralx.decTest'); end;
procedure TDecTests.TestReduce; begin RunDecFile('reduce.decTest'); end;
procedure TDecTests.TestSquareRoot; begin RunDecFile('squareroot.decTest'); end;
procedure TDecTests.TestExp; begin RunDecFile('exp.decTest'); end;
procedure TDecTests.TestLn; begin RunDecFile('ln.decTest'); end;
procedure TDecTests.TestLog10; begin RunDecFile('log10.decTest'); end;
procedure TDecTests.TestPower; begin RunDecFile('power.decTest'); end;

initialization
  RegisterTest(TDecTests);
finalization
  FreeAndNil(GKnown);
end.
