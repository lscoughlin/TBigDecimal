{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: constants, values, financial, pi, e
documentation: doc/design/functions/constants.md
notes:
  - static constants and common values for financial and mathematical operations
  - exposed through BigDecimalValues, DecimalValues and TBigDecimalValues
---
}
unit BigDecimal.Values;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  BigDecimal.Types, BigDecimal, BigDecimal.Constants;

type
  { Static constants and common values for financial and mathematical calculations. }
  BigDecimalValues = record
  public
    // integer and power of ten constants
    class function MinusOne: TBigDecimal; static; inline;
    class function NegativeOne: TBigDecimal; static; inline;
    class function Zero: TBigDecimal; static; inline;
    class function One: TBigDecimal; static; inline;
    class function Two: TBigDecimal; static; inline;
    class function Three: TBigDecimal; static; inline;
    class function Four: TBigDecimal; static; inline;
    class function Five: TBigDecimal; static; inline;
    class function Ten: TBigDecimal; static; inline;
    class function Twelve: TBigDecimal; static; inline;
    class function TwentyFour: TBigDecimal; static; inline;
    class function FiftyTwo: TBigDecimal; static; inline;
    class function Hundred: TBigDecimal; static; inline;
    class function OneHundred: TBigDecimal; static; inline;
    class function ThreeHundredSixty: TBigDecimal; static; inline;
    class function ThreeHundredSixtyFive: TBigDecimal; static; inline;
    class function ThreeHundredSixtySix: TBigDecimal; static; inline;
    class function Days360: TBigDecimal; static; inline;
    class function Days365: TBigDecimal; static; inline;
    class function Days366: TBigDecimal; static; inline;
    class function Thousand: TBigDecimal; static; inline;
    class function OneThousand: TBigDecimal; static; inline;
    class function TenThousand: TBigDecimal; static; inline;
    class function HundredThousand: TBigDecimal; static; inline;
    class function Million: TBigDecimal; static; inline;
    class function OneMillion: TBigDecimal; static; inline;
    class function Billion: TBigDecimal; static; inline;
    class function OneBillion: TBigDecimal; static; inline;

    // fractional and financial basis constants
    class function Half: TBigDecimal; static; inline;
    class function Tenth: TBigDecimal; static; inline;
    class function Percent: TBigDecimal; static; inline;
    class function OnePercent: TBigDecimal; static; inline;
    class function Cent: TBigDecimal; static; inline;
    class function Permille: TBigDecimal; static; inline;
    class function OnePermille: TBigDecimal; static; inline;
    class function BasisPoint: TBigDecimal; static; inline;
    class function OneBasisPoint: TBigDecimal; static; inline;

    // mathematical constants
    class function Pi(const C: TMathContext): TBigDecimal; overload; static; inline;
    class function Pi: TBigDecimal; overload; static; inline;
    class function E(const C: TMathContext): TBigDecimal; overload; static; inline;
    class function E: TBigDecimal; overload; static; inline;
    class function Ln2(const C: TMathContext): TBigDecimal; overload; static; inline;
    class function Ln2: TBigDecimal; overload; static; inline;
    class function Ln10(const C: TMathContext): TBigDecimal; overload; static; inline;
    class function Ln10: TBigDecimal; overload; static; inline;
  end;

  DecimalValues = BigDecimalValues;
  TBigDecimalValues = BigDecimalValues;

implementation

class function BigDecimalValues.MinusOne: TBigDecimal;
begin
  Result := TBigDecimal.Create(-1);
end;

class function BigDecimalValues.NegativeOne: TBigDecimal;
begin
  Result := TBigDecimal.Create(-1);
end;

class function BigDecimalValues.Zero: TBigDecimal;
begin
  Result := TBigDecimal.Zero;
end;

class function BigDecimalValues.One: TBigDecimal;
begin
  Result := TBigDecimal.One;
end;

class function BigDecimalValues.Two: TBigDecimal;
begin
  Result := TBigDecimal.Create(2);
end;

class function BigDecimalValues.Three: TBigDecimal;
begin
  Result := TBigDecimal.Create(3);
end;

class function BigDecimalValues.Four: TBigDecimal;
begin
  Result := TBigDecimal.Create(4);
end;

class function BigDecimalValues.Five: TBigDecimal;
begin
  Result := TBigDecimal.Create(5);
end;

class function BigDecimalValues.Ten: TBigDecimal;
begin
  Result := TBigDecimal.Ten;
end;

class function BigDecimalValues.Twelve: TBigDecimal;
begin
  Result := TBigDecimal.Create(12);
end;

class function BigDecimalValues.TwentyFour: TBigDecimal;
begin
  Result := TBigDecimal.Create(24);
end;

class function BigDecimalValues.FiftyTwo: TBigDecimal;
begin
  Result := TBigDecimal.Create(52);
end;

class function BigDecimalValues.Hundred: TBigDecimal;
begin
  Result := TBigDecimal.Create(100);
end;

class function BigDecimalValues.OneHundred: TBigDecimal;
begin
  Result := TBigDecimal.Create(100);
end;

class function BigDecimalValues.ThreeHundredSixty: TBigDecimal;
begin
  Result := TBigDecimal.Create(360);
end;

class function BigDecimalValues.ThreeHundredSixtyFive: TBigDecimal;
begin
  Result := TBigDecimal.Create(365);
end;

class function BigDecimalValues.ThreeHundredSixtySix: TBigDecimal;
begin
  Result := TBigDecimal.Create(366);
end;

class function BigDecimalValues.Days360: TBigDecimal;
begin
  Result := TBigDecimal.Create(360);
end;

class function BigDecimalValues.Days365: TBigDecimal;
begin
  Result := TBigDecimal.Create(365);
end;

class function BigDecimalValues.Days366: TBigDecimal;
begin
  Result := TBigDecimal.Create(366);
end;

class function BigDecimalValues.Thousand: TBigDecimal;
begin
  Result := TBigDecimal.Create(1000);
end;

class function BigDecimalValues.OneThousand: TBigDecimal;
begin
  Result := TBigDecimal.Create(1000);
end;

class function BigDecimalValues.TenThousand: TBigDecimal;
begin
  Result := TBigDecimal.Create(10000);
end;

class function BigDecimalValues.HundredThousand: TBigDecimal;
begin
  Result := TBigDecimal.Create(100000);
end;

class function BigDecimalValues.Million: TBigDecimal;
begin
  Result := TBigDecimal.Create(1000000);
end;

class function BigDecimalValues.OneMillion: TBigDecimal;
begin
  Result := TBigDecimal.Create(1000000);
end;

class function BigDecimalValues.Billion: TBigDecimal;
begin
  Result := TBigDecimal.Create(1000000000);
end;

class function BigDecimalValues.OneBillion: TBigDecimal;
begin
  Result := TBigDecimal.Create(1000000000);
end;

class function BigDecimalValues.Half: TBigDecimal;
begin
  Result := TBigDecimal.Create(TBigDecimal.Create(5), 1);
end;

class function BigDecimalValues.Tenth: TBigDecimal;
begin
  Result := TBigDecimal.Create(TBigDecimal.One, 1);
end;

class function BigDecimalValues.Percent: TBigDecimal;
begin
  Result := TBigDecimal.Create(TBigDecimal.One, 2);
end;

class function BigDecimalValues.OnePercent: TBigDecimal;
begin
  Result := TBigDecimal.Create(TBigDecimal.One, 2);
end;

class function BigDecimalValues.Cent: TBigDecimal;
begin
  Result := TBigDecimal.Create(TBigDecimal.One, 2);
end;

class function BigDecimalValues.Permille: TBigDecimal;
begin
  Result := TBigDecimal.Create(TBigDecimal.One, 3);
end;

class function BigDecimalValues.OnePermille: TBigDecimal;
begin
  Result := TBigDecimal.Create(TBigDecimal.One, 3);
end;

class function BigDecimalValues.BasisPoint: TBigDecimal;
begin
  Result := TBigDecimal.Create(TBigDecimal.One, 4);
end;

class function BigDecimalValues.OneBasisPoint: TBigDecimal;
begin
  Result := TBigDecimal.Create(TBigDecimal.One, 4);
end;

class function BigDecimalValues.Pi(const C: TMathContext): TBigDecimal;
begin
  Result := BigPi(C);
end;

class function BigDecimalValues.Pi: TBigDecimal;
begin
  Result := BigPi;
end;

class function BigDecimalValues.E(const C: TMathContext): TBigDecimal;
begin
  Result := BigE(C);
end;

class function BigDecimalValues.E: TBigDecimal;
begin
  Result := BigE;
end;

class function BigDecimalValues.Ln2(const C: TMathContext): TBigDecimal;
begin
  Result := BigLn2(C);
end;

class function BigDecimalValues.Ln2: TBigDecimal;
begin
  Result := BigLn2;
end;

class function BigDecimalValues.Ln10(const C: TMathContext): TBigDecimal;
begin
  Result := BigLn10(C);
end;

class function BigDecimalValues.Ln10: TBigDecimal;
begin
  Result := BigLn10;
end;

end.
