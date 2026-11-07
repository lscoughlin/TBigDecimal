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
{ Counts memory manager calls and bytes during small-value arithmetic and
  times the read of the thread-local default context. The counting hook is
  installed before the first TBigDecimal call. Run: make benchsmall }
{$mode objfpc}{$H+}
{$coperators on}
uses
  SysUtils, BigDecimal.Types, BigDecimal, BigDecimal.Elementary;

var
  OldMM, CountMM: TMemoryManager;
  GetCount, AllocCount, ReallocCount, FreeCount: Int64;
  ByteCount: Int64;

function CountGetMem(Size: PtrUInt): Pointer;
begin
  Inc(GetCount); Inc(ByteCount, Int64(Size));
  Result := OldMM.GetMem(Size);
end;

function CountAllocMem(Size: PtrUInt): Pointer;
begin
  Inc(AllocCount); Inc(ByteCount, Int64(Size));
  Result := OldMM.AllocMem(Size);
end;

function CountReallocMem(var P: Pointer; Size: PtrUInt): Pointer;
begin
  Inc(ReallocCount); Inc(ByteCount, Int64(Size));
  Result := OldMM.ReallocMem(P, Size);
end;

function CountFreeMem(P: Pointer): PtrUInt;
begin
  Inc(FreeCount);
  Result := OldMM.FreeMem(P);
end;

function Secs: Double;
begin
  Result := Double(GetTickCount64) / 1000.0;
end;

const
  N = 5000000;

var
  A, B, C, BigA, BigB: TBigDecimal;
  S: string;
  I: Integer;
  T0, T1, T2, T3: Double;
  SGet, SAlloc, SRealloc, SFree, SBytes: Int64;
  Flag: Boolean;
  Sink: Integer;
  Ctx: TMathContext;

procedure Snap;
begin
  SGet := GetCount; SAlloc := AllocCount; SRealloc := ReallocCount;
  SFree := FreeCount; SBytes := ByteCount;
end;

procedure Report(const Name: string; Count: Integer);
var
  calls: Int64;
begin
  calls := (GetCount - SGet) + (AllocCount - SAlloc) + (ReallocCount - SRealloc);
  WriteLn(Format('allocations, %d %-22s: get=%d alloc=%d realloc=%d free=%d calls=%d bytes=%d',
    [Count, Name, GetCount - SGet, AllocCount - SAlloc, ReallocCount - SRealloc,
     FreeCount - SFree, calls, ByteCount - SBytes]));
end;

function DigitsStr(P: Integer): string;
var
  i: Integer;
begin
  SetLength(Result, P);
  for i := 1 to P do Result[i] := Chr(Ord('0') + ((i * 7 + (i * i) mod 11) mod 10));
  Result[1] := '1';
end;

begin
  GetMemoryManager(OldMM);
  CountMM := OldMM;
  CountMM.GetMem := @CountGetMem;
  CountMM.AllocMem := @CountAllocMem;
  CountMM.ReallocMem := @CountReallocMem;
  CountMM.FreeMem := @CountFreeMem;
  SetMemoryManager(CountMM);

  A := TBigDecimal.Create('12345.678');
  B := TBigDecimal.Create('9876.5');
  S := '12345.678';
  BigA := TBigDecimal.Create(DigitsStr(1000));
  BigB := TBigDecimal.Create(DigitsStr(1000));
  Ctx := TMathContext.Make(34, rmHalfEven);

  Snap; for I := 1 to 1000 do C := A + B; Report('adds', 1000);
  Snap; for I := 1 to 1000 do C := A * B; Report('multiplies', 1000);
  Snap; for I := 1 to 1000 do C := A - B; Report('subtracts', 1000);
  Snap; for I := 1 to 1000 do Flag := A < B; Report('compares', 1000);
  Snap; for I := 1 to 1000 do C := A.Divide(B, Ctx); Report('divides', 1000);
  Snap; for I := 1 to 1000 do C := Sqrt(A, Ctx); Report('sqrts', 1000);
  Snap; for I := 1 to 1000 do C := TBigDecimal.Create(S); Report('parses', 1000);
  Snap; for I := 1 to 1000 do S := A.ToString; Report('formats', 1000);
  Snap; for I := 1 to 1000 do C := BigA * BigB; Report('1000-digit multiplies', 1000);
  SetMemoryManager(OldMM);
  if Length(S) = 0 then WriteLn(Flag);

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
  WriteLn('sink: ', C.Precision + Sink);
end.
