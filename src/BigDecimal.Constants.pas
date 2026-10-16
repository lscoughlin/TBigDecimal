{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: constants, pi, e, ln2, ln10, cache
documentation: doc/design.md
notes:
  - the constants use atanh and atan series of small rational arguments
  - one shared cache holds the highest precision computed, guarded by a lock
  - series use single-limb divisions, so the cost is quadratic in the precision
---
}
unit BigDecimal.Constants;

{$mode objfpc}{$H+}
{$coperators on}

interface

uses
  SysUtils, BigDecimal.Types, BigDecimal, BigDecimal.Fixed;

{ Fixed-point constants at W digits after the point, with error bounds. }
function ConstPi(W: Integer): TFx;
function ConstE(W: Integer): TFx;
{ Natural logarithm of the prime 2, 3, 5 or 7. }
function ConstLnPrime(P: Integer; W: Integer): TFx;
function ConstLn10(W: Integer): TFx;

{ Rounded to the context (Ziv check on the stored interval). }
function BigPi(const C: TMathContext): TBigDecimal; overload;
function BigE(const C: TMathContext): TBigDecimal; overload;
function BigLn2(const C: TMathContext): TBigDecimal; overload;
function BigLn10(const C: TMathContext): TBigDecimal; overload;
function BigPi: TBigDecimal; overload;
function BigE: TBigDecimal; overload;

implementation

type
  TConstCache = record
    W: Integer;
    A251, A449, A4801, A8749: TFx;
    Pi, E: TFx;
    Valid: Boolean;
  end;

var
  GCache: TConstCache;
  GLock: TRTLCriticalSection;

function AtanhInv(N: Integer; W: Integer): TFx;
var
  t, sum, term: TFx;
  n2: Int64;
  k: Integer;
begin
  n2 := Int64(N) * N;
  t := FxDivInt(FxFromInt(1, W), N);
  sum := t;
  k := 1;
  while not FxTiny(t) do
  begin
    t := FxDivInt(t, n2);
    term := FxDivInt(t, 2 * k + 1);
    sum := FxAdd(sum, term);
    Inc(k);
  end;
  sum.E += 2;
  Result := sum;
end;

function AtanInv(N: Integer; W: Integer): TFx;
var
  t, sum, term: TFx;
  n2: Int64;
  k: Integer;
begin
  n2 := Int64(N) * N;
  t := FxDivInt(FxFromInt(1, W), N);
  sum := t;
  k := 1;
  while not FxTiny(t) do
  begin
    t := FxDivInt(t, n2);
    term := FxDivInt(t, 2 * k + 1);
    if (k and 1) = 1 then sum := FxSub(sum, term) else sum := FxAdd(sum, term);
    Inc(k);
  end;
  sum.E += 2;
  Result := sum;
end;

function ComputeE(W: Integer): TFx;
var
  t, sum: TFx;
  k: Integer;
begin
  sum := FxFromInt(1, W);
  t := sum;
  k := 1;
  while not FxTiny(t) do
  begin
    t := FxDivInt(t, k);
    sum := FxAdd(sum, t);
    Inc(k);
  end;
  sum.E += 2;
  Result := sum;
end;

function ComputePi(W: Integer): TFx;
var
  a, b: TFx;
begin
  // pi = 16 atan(1/5) - 4 atan(1/239)
  a := FxMulInt(AtanInv(5, W), 16);
  b := FxMulInt(AtanInv(239, W), 4);
  Result := FxSub(a, b);
end;

{ Returns a cache entry with at least W + Margin digits. }
procedure GetCache(W: Integer; out C: TConstCache);
var
  W2: Integer;
  nc: TConstCache;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  EnterCriticalSection(GLock);
  try
    if GCache.Valid and (GCache.W >= W + 12) then
    begin
      C := GCache;
      Exit;
    end;
  finally
    LeaveCriticalSection(GLock);
  end;
  W2 := W + W div 2 + 24;
  nc.W := W2;
  nc.A251 := AtanhInv(251, W2);
  nc.A449 := AtanhInv(449, W2);
  nc.A4801 := AtanhInv(4801, W2);
  nc.A8749 := AtanhInv(8749, W2);
  nc.Pi := ComputePi(W2);
  nc.E := ComputeE(W2);
  nc.Valid := True;
  EnterCriticalSection(GLock);
  try
    if (not GCache.Valid) or (GCache.W < W2) then
      GCache := nc;
    C := GCache;
  finally
    LeaveCriticalSection(GLock);
  end;
end;

function ConstPi(W: Integer): TFx;
var
  c: TConstCache;
begin
  GetCache(W, c);
  Result := FxRescale(c.Pi, W);
end;

function ConstE(W: Integer): TFx;
var
  c: TConstCache;
begin
  GetCache(W, c);
  Result := FxRescale(c.E, W);
end;

function ConstLnPrime(P: Integer; W: Integer): TFx;
var
  c: TConstCache;
  k: array[0..3] of Int64;
  r: TFx;
begin
  GetCache(W, c);
  case P of
    2: begin k[0] := 144; k[1] := 54; k[2] := -38; k[3] := 62; end;
    3: begin k[0] := 228; k[1] := 86; k[2] := -60; k[3] := 98; end;
    5: begin k[0] := 334; k[1] := 126; k[2] := -88; k[3] := 144; end;
    7: begin k[0] := 404; k[1] := 152; k[2] := -106; k[3] := 174; end;
  else
    raise EBigDecimalDomain.Create('no logarithm constant for this prime');
  end;
  r := FxMulInt(c.A251, k[0]);
  r := FxAdd(r, FxMulInt(c.A449, k[1]));
  r := FxAdd(r, FxMulInt(c.A4801, k[2]));
  r := FxAdd(r, FxMulInt(c.A8749, k[3]));
  Result := FxRescale(r, W);
end;

function ConstLn10(W: Integer): TFx;
begin
  Result := FxAdd(ConstLnPrime(2, W), ConstLnPrime(5, W));
end;

function Rounded(const F: TFx; W: Integer; const C: TMathContext): TBigDecimal;
var
  w2: Integer;
  fx: TFx;
begin
  if C.Precision = 0 then
    raise EBigDecimalDomain.Create('a constant needs a finite precision');
  w2 := C.Precision + 10;
  repeat
    fx := FxRescale(F, W);
    if FxRound(fx, C, Result) then Exit;
    w2 += w2 div 2 + 10;
    if w2 > 20 * C.Precision + 2000 then
      raise EBigDecimalPrecision.Create('constant could not be rounded');
    W := w2;
  until False;
end;

function BigPi(const C: TMathContext): TBigDecimal;
var
  w: Integer;
  f: TFx;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  if C.Precision = 0 then raise EBigDecimalDomain.Create('Pi needs a finite precision');
  w := C.Precision + 10;
  repeat
    f := ConstPi(w);
    if FxRound(f, C, Result) then Exit;
    w += w div 2 + 10;
    if w > 20 * C.Precision + 2000 then raise EBigDecimalPrecision.Create('Pi');
  until False;
end;

function BigE(const C: TMathContext): TBigDecimal;
var
  w: Integer;
  f: TFx;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  if C.Precision = 0 then raise EBigDecimalDomain.Create('E needs a finite precision');
  w := C.Precision + 10;
  repeat
    f := ConstE(w);
    if FxRound(f, C, Result) then Exit;
    w += w div 2 + 10;
    if w > 20 * C.Precision + 2000 then raise EBigDecimalPrecision.Create('E');
  until False;
end;

function BigLn2(const C: TMathContext): TBigDecimal;
var
  w: Integer;
  f: TFx;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  if C.Precision = 0 then raise EBigDecimalDomain.Create('Ln2 needs a finite precision');
  w := C.Precision + 10;
  repeat
    f := ConstLnPrime(2, w);
    if FxRound(f, C, Result) then Exit;
    w += w div 2 + 10;
    if w > 20 * C.Precision + 2000 then raise EBigDecimalPrecision.Create('Ln2');
  until False;
end;

function BigLn10(const C: TMathContext): TBigDecimal;
var
  w: Integer;
  f: TFx;
  GDefaultGuard: TSuspendDefault;
begin
  GDefaultGuard.Suspend;
  if C.Precision = 0 then raise EBigDecimalDomain.Create('Ln10 needs a finite precision');
  w := C.Precision + 10;
  repeat
    f := ConstLn10(w);
    if FxRound(f, C, Result) then Exit;
    w += w div 2 + 10;
    if w > 20 * C.Precision + 2000 then raise EBigDecimalPrecision.Create('Ln10');
  until False;
end;

function BigPi: TBigDecimal;
var
  c: TMathContext;
begin
  if not EffectiveContext(c) then raise EBigDecimalNoContext.Create('Pi needs a context');
  Result := BigPi(c);
end;

function BigE: TBigDecimal;
var
  c: TMathContext;
begin
  if not EffectiveContext(c) then raise EBigDecimalNoContext.Create('E needs a context');
  Result := BigE(c);
end;

initialization
  InitCriticalSection(GLock);
finalization
  DoneCriticalSection(GLock);
end.
