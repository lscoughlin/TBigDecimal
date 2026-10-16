{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: rounding, rounding modes
documentation: doc/design.md
notes:
  - one routine rounds a magnitude by dropping low decimal digits
  - the decision function serves integer division with a remainder too
---
}
unit BigDecimal.Rounding;

{$mode objfpc}{$H+}
{$R-}{$Q-}
{$coperators on}

interface

uses
  BigDecimal.Types, BigDecimal.Limbs;

type
  { Classification of the discarded part relative to one half unit. }
  TDiscard = (dcZero, dcBelowHalf, dcHalf, dcAboveHalf);

{ Decides whether the kept part increments. Raises EBigDecimalRounding for
  rmUnnecessary when the discarded part is not zero. }
function RoundIncrement(Mode: TRoundingMode; Negative: Boolean;
  Cls: TDiscard; OddLast: Boolean): Boolean;

{ Drops the low Drop decimal digits of the magnitude a[0..na), rounds in the
  given mode, and writes the kept digits to r (capacity na + 1).
  Sticky means that a non-zero amount lies below all digits of a.
  Inexact reports a non-zero discarded part. Drop is at least 1. }
procedure RoundMagDrop(a: PLimb; na: Integer; Drop: Int64; Mode: TRoundingMode;
  Negative: Boolean; Sticky: Boolean; r: PLimb; out nr: Integer;
  out Inexact: Boolean);

implementation

function RoundIncrement(Mode: TRoundingMode; Negative: Boolean;
  Cls: TDiscard; OddLast: Boolean): Boolean;
begin
  case Mode of
    rmUp: Result := Cls <> dcZero;
    rmDown: Result := False;
    rmCeiling: Result := (Cls <> dcZero) and (not Negative);
    rmFloor: Result := (Cls <> dcZero) and Negative;
    rmHalfUp: Result := Cls in [dcHalf, dcAboveHalf];
    rmHalfDown: Result := Cls = dcAboveHalf;
    rmHalfEven: Result := (Cls = dcAboveHalf) or ((Cls = dcHalf) and OddLast);
    rmUnnecessary:
      begin
        if Cls <> dcZero then
          raise EBigDecimalRounding.Create('rounding is necessary');
        Result := False;
      end;
  else
    Result := False;
  end;
end;

procedure RoundMagDrop(a: PLimb; na: Integer; Drop: Int64; Mode: TRoundingMode;
  Negative: Boolean; Sticky: Boolean; r: PLimb; out nr: Integer;
  out Inexact: Boolean);
var
  top: Integer;
  lowZero: Boolean;
  cls: TDiscard;
  odd: Boolean;
  i: Integer;
  c: UInt32;
  s: UInt32;
begin
  top := MagDigitAt(a, na, Drop - 1);
  lowZero := MagLowZero(a, na, Drop - 1) and (not Sticky);
  if (top = 0) and lowZero then cls := dcZero
  else if top > 5 then cls := dcAboveHalf
  else if top = 5 then
  begin
    if lowZero then cls := dcHalf else cls := dcAboveHalf;
  end
  else cls := dcBelowHalf;
  Inexact := cls <> dcZero;
  odd := (MagDigitAt(a, na, Drop) and 1) = 1;
  nr := DivPow10(a, na, Drop, r);
  if RoundIncrement(Mode, Negative, cls, odd) then
  begin
    c := 1;
    i := 0;
    while (c <> 0) and (i < nr) do
    begin
      s := r[i] + c;
      if s >= LimbBase then begin s -= LimbBase; c := 1; end else c := 0;
      r[i] := s;
      Inc(i);
    end;
    if c <> 0 then
    begin
      r[nr] := 1;
      Inc(nr);
    end;
  end;
end;

end.
