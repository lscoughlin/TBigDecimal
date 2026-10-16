{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: benchmark
notes:
  - counts heap allocations on the small-value path
  - times the thread-local default context read
---
}
program BenchSmall;
{ Counts memory manager calls during small-value arithmetic and times the
  read of the thread-local default context. Run: make benchsmall }
{$mode objfpc}{$H+}
{$coperators on}
uses
  SysUtils, BigDecimal.Types, BigDecimal;

var
  OldMM, CountMM: TMemoryManager;
  GetCount: Int64 = 0;

function CountGetMem(Size: PtrUInt): Pointer;
begin
  Inc(GetCount);
  Result := OldMM.GetMem(Size);
end;

function CountAllocMem(Size: PtrUInt): Pointer;
begin
  Inc(GetCount);
  Result := OldMM.AllocMem(Size);
end;

function CountReallocMem(var P: Pointer; Size: PtrUInt): Pointer;
begin
  Inc(GetCount);
  Result := OldMM.ReallocMem(P, Size);
end;

function Secs: Double;
begin
  Result := Now * 86400.0;
end;

const
  N = 5000000;

var
  A, B, C: TBigDecimal;
  I: Integer;
  T0, T1, T2, T3: Double;
  Before: Int64;
  Flag: Boolean;
  Sink: Integer;
  Scope: TMathContextScope;
begin
  A := TBigDecimal.Create('12345.678');
  B := TBigDecimal.Create('9876.5');
  GetMemoryManager(OldMM);
  CountMM := OldMM;
  CountMM.GetMem := @CountGetMem;
  CountMM.AllocMem := @CountAllocMem;
  CountMM.ReallocMem := @CountReallocMem;
  SetMemoryManager(CountMM);

  Before := GetCount;
  for I := 1 to 1000 do C := A + B;
  WriteLn('allocations, 1000 adds       : ', GetCount - Before);
  Before := GetCount;
  for I := 1 to 1000 do C := A * B;
  WriteLn('allocations, 1000 multiplies : ', GetCount - Before);
  Before := GetCount;
  for I := 1 to 1000 do C := A - B;
  WriteLn('allocations, 1000 subtracts  : ', GetCount - Before);
  Before := GetCount;
  for I := 1 to 1000 do Flag := A < B;
  WriteLn('allocations, 1000 compares   : ', GetCount - Before);
  SetMemoryManager(OldMM);

  T0 := Secs;
  for I := 1 to N do C := A + B;
  T1 := Secs;
  for I := 1 to N do C := A * B;
  T2 := Secs;
  Sink := 0;
  for I := 1 to N do if TMathContext.HasDefault then Inc(Sink);
  T3 := Secs;
  WriteLn(Format('add %.1f ns, multiply %.1f ns, HasDefault read %.2f ns',
    [(T1 - T0) / N * 1e9, (T2 - T1) / N * 1e9, (T3 - T2) / N * 1e9]));

  TMathContext.SetDefault(Decimal128);
  T0 := Secs;
  for I := 1 to N do C := A + B;
  T1 := Secs;
  for I := 1 to N do C := A * B;
  T2 := Secs;
  TMathContext.ClearDefault;
  WriteLn(Format('with default Decimal128: add %.1f ns, multiply %.1f ns',
    [(T1 - T0) / N * 1e9, (T2 - T1) / N * 1e9]));
  TMathContext.SetDefault(Decimal64);
  T0 := Secs;
  for I := 1 to N do C := A + B;
  T1 := Secs;
  for I := 1 to N do C := A * B;
  T2 := Secs;
  TMathContext.ClearDefault;
  WriteLn(Format('with default Decimal64 (16 digits): add %.1f ns, multiply %.1f ns',
    [(T1 - T0) / N * 1e9, (T2 - T1) / N * 1e9]));
  if Sink < 0 then WriteLn(Flag);
end.
