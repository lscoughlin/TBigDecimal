{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: compiler bug, management operators
documentation: doc/management-operators.md
notes:
  - minimal test case for the reference counting faults of FPC 3.2.4 management operators
  - not part of the test suite; it reports faults of the compiler, not of the library
---
}
program ManagementOperators;
{ Each case builds a reference counted value in a fresh slot, runs one statement
  pattern, releases every variable, and then reads the count of the slot. A
  correct compiler leaves every count at zero. A count above zero is a leak. A
  count below zero is a release of a value that had no owner (a double free in a
  real program). The counts live in a global array, so the program itself never
  touches freed memory. Build: fpc -MObjFPC ManagementOperators.lpr }
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

type
  { TWithCopy defines Initialize, Finalize, AddRef and Copy. }
  TWithCopy = record
    Slot: Integer;                 // 0 means no value
    class operator Initialize(var X: TWithCopy);
    class operator Finalize(var X: TWithCopy);
    class operator AddRef(var X: TWithCopy);
    class operator Copy(constref Src: TWithCopy; var Dst: TWithCopy);
  end;

  { TNoCopy defines Initialize, Finalize and AddRef only. }
  TNoCopy = record
    Slot: Integer;
    class operator Initialize(var X: TNoCopy);
    class operator Finalize(var X: TNoCopy);
    class operator AddRef(var X: TNoCopy);
  end;

var
  CountsC: array[1..12] of Integer;  // reference counts of the TWithCopy slots
  CountsN: array[1..12] of Integer;  // reference counts of the TNoCopy slots
  Failed: Boolean = False;

class operator TWithCopy.Initialize(var X: TWithCopy);
begin
  X.Slot := 0;
end;

class operator TWithCopy.Finalize(var X: TWithCopy);
begin
  if X.Slot <> 0 then
  begin
    Dec(CountsC[X.Slot]);
    X.Slot := 0;
  end;
end;

class operator TWithCopy.AddRef(var X: TWithCopy);
begin
  if X.Slot <> 0 then Inc(CountsC[X.Slot]);
end;

class operator TWithCopy.Copy(constref Src: TWithCopy; var Dst: TWithCopy);
var
  Old: Integer;
begin
  if Src.Slot <> 0 then Inc(CountsC[Src.Slot]);
  Old := Dst.Slot;
  Dst.Slot := Src.Slot;
  if Old <> 0 then Dec(CountsC[Old]);
end;

class operator TNoCopy.Initialize(var X: TNoCopy);
begin
  X.Slot := 0;
end;

class operator TNoCopy.Finalize(var X: TNoCopy);
begin
  if X.Slot <> 0 then
  begin
    Dec(CountsN[X.Slot]);
    X.Slot := 0;
  end;
end;

class operator TNoCopy.AddRef(var X: TNoCopy);
begin
  if X.Slot <> 0 then Inc(CountsN[X.Slot]);
end;

{ Functions that return a value that owns slot S with a count of one. }
function MakeC(S: Integer): TWithCopy;
begin
  Result.Slot := S;
  CountsC[S] := 1;
end;

function MakeN(S: Integer): TNoCopy;
begin
  Result.Slot := S;
  CountsN[S] := 1;
end;

function IdentC(const X: TWithCopy): TWithCopy;
begin
  Result := X;
end;

procedure ByValueN(X: TNoCopy);
begin
end;

procedure Check(const Name: string; Expected, Got: Integer);
begin
  if Expected = Got then
    WriteLn('ok    ', Name, ': count ', Got)
  else
  begin
    WriteLn('FAIL  ', Name, ': expected count ', Expected, ', got ', Got);
    Failed := True;
  end;
end;

{ The cases release their variables by leaving the procedure. The main block
  reads the count after the return. }

procedure Case1_ResultAssignedWithCopy;
var
  A: TWithCopy;
begin
  A := MakeC(1);
  Check('1 TWithCopy: A := MakeC(1) (count while owned)', 1, CountsC[1]);
end;

procedure Case2_VarAssignedWithCopy;
var
  A, B: TWithCopy;
begin
  A := MakeC(2);
  B := A;
  Check('2 TWithCopy: B := A (count while shared)', 2, CountsC[2]);
end;

procedure Case3_FunctionResultCopiedWithCopy;
var
  A, B: TWithCopy;
begin
  A := MakeC(3);
  B := IdentC(A);
  Check('3 TWithCopy: B := IdentC(A) (count while shared)', 2, CountsC[3]);
end;

procedure Case4_AssignmentWithoutCopy;
var
  A, B: TNoCopy;
begin
  A := MakeN(4);
  B := A;
  Check('4 TNoCopy: B := A (count while shared)', 2, CountsN[4]);
end;

procedure Case5_ValueParameterWithoutCopy;
var
  A: TNoCopy;
begin
  A := MakeN(5);
  ByValueN(A);
  Check('5 TNoCopy: ByValueN(A) (count after the call)', 1, CountsN[5]);
end;

procedure Case8_DefaultAssignedWithoutCopy;
var
  A: TNoCopy;
begin
  A := MakeN(8);
  A := Default(TNoCopy);
  Check('8 TNoCopy: A := Default(TNoCopy) (count after the assignment)', 0, CountsN[8]);
end;

procedure Case9_OldTargetValueWithoutCopy;
var
  A, B: TNoCopy;
begin
  A := MakeN(9);
  B := MakeN(10);
  B := A;
  Check('9 TNoCopy: B := A (count of the old value of B)', 0, CountsN[10]);
end;

var
  GA, GB: TWithCopy;
  GN: TNoCopy;

begin
  Case1_ResultAssignedWithCopy;
  Check('1 TWithCopy: after the procedure returned', 0, CountsC[1]);
  Case2_VarAssignedWithCopy;
  Check('2 TWithCopy: after the procedure returned', 0, CountsC[2]);
  Case3_FunctionResultCopiedWithCopy;
  Check('3 TWithCopy: after the procedure returned', 0, CountsC[3]);
  Case4_AssignmentWithoutCopy;
  Check('4 TNoCopy: after the procedure returned', 0, CountsN[4]);
  Case5_ValueParameterWithoutCopy;
  Check('5 TNoCopy: after the procedure returned', 0, CountsN[5]);
  Case8_DefaultAssignedWithoutCopy;
  Case9_OldTargetValueWithoutCopy;
  // global variables of the main block
  GA := MakeC(6);
  Check('6 TWithCopy global: GA := MakeC(6) (count while owned)', 1, CountsC[6]);
  GB := GA;
  Check('6 TWithCopy global: GB := GA (count while shared)', 2, CountsC[6]);
  GA := Default(TWithCopy);
  GB := Default(TWithCopy);
  Check('6 TWithCopy global: both set to Default', 0, CountsC[6]);
  GN := MakeN(7);
  Check('7 TNoCopy global: GN := MakeN(7) (count while owned)', 1, CountsN[7]);
  GN := Default(TNoCopy);
  Check('7 TNoCopy global: GN set to Default', 0, CountsN[7]);
  if Failed then
  begin
    WriteLn('result: the compiler fails at least one reference counting case');
    Halt(1);
  end;
  WriteLn('result: all cases pass');
end.
