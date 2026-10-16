{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: types, rounding, context, exceptions
documentation: doc/design.md
notes:
  - this unit holds the enums, the math context, the thread-local default context and the exceptions
---
}
unit BigDecimal.Types;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils;

type
  EBigDecimal = class(Exception);
  EBigDecimalDivByZero = class(EBigDecimal);
  EBigDecimalNonTerminating = class(EBigDecimal);
  EBigDecimalRounding = class(EBigDecimal);
  EBigDecimalOverflow = class(EBigDecimal);
  EBigDecimalParse = class(EBigDecimal);
  EBigDecimalNoContext = class(EBigDecimal);
  EBigDecimalPrecision = class(EBigDecimal);
  EBigDecimalDomain = class(EBigDecimal);

  TRoundingMode = (rmUp, rmDown, rmCeiling, rmFloor,
                   rmHalfUp, rmHalfDown, rmHalfEven, rmUnnecessary);

  { TMathContext }

  TMathContext = record
    Precision: Integer;           // 0 means exact
    RoundingMode: TRoundingMode;
    class function Make(APrecision: Integer; AMode: TRoundingMode): TMathContext; static;
    class function Default: TMathContext; static;
    class function HasDefault: Boolean; static;
    class procedure SetDefault(const C: TMathContext); static;
    class procedure ClearDefault; static;
  end;

  { TMathContextScope saves the default context at Enter and restores it at
    Finalize. Enter is a procedure on a variable, because a function that
    returns a managed record can finalize a temporary twice in FPC 3.2.4. }

  TMathContextScope = record
  private
    FPrev: TMathContext;
    FHadPrev: Boolean;
    FActive: Boolean;
  public
    procedure Enter(const C: TMathContext);
    class operator Initialize(var S: TMathContextScope);
    class operator Finalize(var S: TMathContextScope);
  end;

  { TSuspendDefault clears the default context of the calling thread while a
    library function runs, and restores it at Finalize. Library internals use
    the operators of TBigDecimal, which must stay exact inside a function. }

  TSuspendDefault = record
  private
    FPrev: TMathContext;
    FHad: Boolean;
    FActive: Boolean;
  public
    procedure Suspend;
    class operator Initialize(var S: TSuspendDefault);
    class operator Finalize(var S: TSuspendDefault);
  end;

const
  { Version of the library (major.minor.release). The Lazarus package
    lazarus/TBigDecimal.lpk carries the same number. }
  BigDecimalVersion = '0.2.0';
  BigDecimalVersionMajor = 0;
  BigDecimalVersionMinor = 2;
  BigDecimalVersionRelease = 0;

  Decimal32: TMathContext = (Precision: 7; RoundingMode: rmHalfEven);
  Decimal64: TMathContext = (Precision: 16; RoundingMode: rmHalfEven);
  Decimal128: TMathContext = (Precision: 34; RoundingMode: rmHalfEven);
  Unlimited: TMathContext = (Precision: 0; RoundingMode: rmHalfUp);

var
  { Largest digit count that an exact result may have (Pow, Factorial, ...). }
  MaxExactDigits: Int64 = 10000000;

{ Returns the default context of the calling thread, or Unlimited-with-flag
  semantics through HasDefault. }
function EffectiveContext(out C: TMathContext): Boolean; inline;

implementation

threadvar
  GDefaultContext: TMathContext;
  GHasDefaultContext: Boolean;

function EffectiveContext(out C: TMathContext): Boolean; inline;
begin
  Result := GHasDefaultContext;
  if Result then
    C := GDefaultContext;
end;

class function TMathContext.Make(APrecision: Integer; AMode: TRoundingMode): TMathContext;
begin
  Result.Precision := APrecision;
  Result.RoundingMode := AMode;
end;

class function TMathContext.Default: TMathContext;
begin
  if not GHasDefaultContext then
    raise EBigDecimalNoContext.Create('no default math context is set');
  Result := GDefaultContext;
end;

class function TMathContext.HasDefault: Boolean;
begin
  Result := GHasDefaultContext;
end;

class procedure TMathContext.SetDefault(const C: TMathContext);
begin
  if C.Precision < 0 then
    raise EBigDecimalDomain.Create('precision must not be negative');
  GDefaultContext := C;
  GHasDefaultContext := True;
end;

class procedure TMathContext.ClearDefault;
begin
  GHasDefaultContext := False;
end;

procedure TSuspendDefault.Suspend;
begin
  if FActive then Exit;
  FHad := GHasDefaultContext;
  FPrev := GDefaultContext;
  FActive := True;
  GHasDefaultContext := False;
end;

class operator TSuspendDefault.Initialize(var S: TSuspendDefault);
begin
  S.FActive := False;
end;

class operator TSuspendDefault.Finalize(var S: TSuspendDefault);
begin
  if S.FActive then
  begin
    S.FActive := False;
    GDefaultContext := S.FPrev;
    GHasDefaultContext := S.FHad;
  end;
end;

procedure TMathContextScope.Enter(const C: TMathContext);
begin
  if FActive then
    Exit;
  FHadPrev := GHasDefaultContext;
  FPrev := GDefaultContext;
  FActive := True;
  TMathContext.SetDefault(C);
end;

class operator TMathContextScope.Initialize(var S: TMathContextScope);
begin
  S.FActive := False;
end;

class operator TMathContextScope.Finalize(var S: TMathContextScope);
begin
  if S.FActive then
  begin
    S.FActive := False;
    GDefaultContext := S.FPrev;
    GHasDefaultContext := S.FHadPrev;
  end;
end;

end.
