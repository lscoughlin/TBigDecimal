# FPC 3.2.4 management operators: reference counting faults

This document records faults in the reference counting that the Free Pascal
compiler (FPC) 3.2.4 generates for records with management operators. It
contains the background of the discovery, a description of each fault, a
self-contained test case, and the output of that test case. The text is
written so that it can serve as the body of a bug report.

## 1. Background

### 1.1 The project

`TBigDecimal` is an arbitrary-precision decimal type for FPC. It is an
advanced record. A value holds an `Int64` for small numbers, a 32-bit scale, a
sign, and a dynamic array of 32-bit limbs for large numbers
(`FLimbs: array of UInt32`). The record is a managed type, because it holds a
dynamic array.

### 1.2 The performance work

The library was tuned for speed. A sampling profile (macOS `sample`) of
34-digit addition, multiplication and division showed that the arithmetic was
not the main cost. The largest entries were the runtime routines that FPC
calls for a record with a managed field: `fpc_initialize`, `fpc_finalize`,
`fpc_copy` and `SYSTEM_$$_RECORDRTTI`. Together they took about half of the
samples of the addition profile. A function that returns a record, and an
assignment of that result to a variable, each pass through these routines,
which walk the run-time type information (RTTI) of the record.

A micro-benchmark compared two layouts of the same record. The operation was
`Z := Add(X, Y)` on values without a limb array, 20 million repetitions, best of
five, `-O3`, aarch64:

| Layout | Time per operation |
|--------|-------------------:|
| `FLimbs: array of UInt32` (managed field, RTTI routines) | 38.6 ns |
| `FBlock: pointer` to a reference counted block, with `Initialize`, `Finalize`, `AddRef` and `Copy` operators | 8.2 ns |

The second layout is 4.7 times faster. The fixed overhead of a small operation
(about 80 ns) is large enough that this difference matters for financial
arithmetic, where most values have 1 to 10 limbs. Management operators
(FPC 3.1.1 and later) are the documented way to give a record its own
lifetime code without RTTI, so the library was changed to use them: the
dynamic array became a pointer to a block with a header that holds a reference
count and the limb count, and the record got the four operators. Only 35
places in one unit referred to the field.

### 1.3 The discovery

The changed library compiled. The test suite then failed in two ways. One
suite did not end and kept a processor core busy for ten minutes. Another
produced wrong numbers (for example `lngamma(1.5)` returned a different value
at 60 digits). The symptoms looked like a reference count that was too low
(a block freed while still in use) or too high (a block that is never freed
and a count that later releases corrupt).

A stand-alone program then traced the counts of a record with the same four
operators, with a counter in each operator and a live-block counter. The trace
showed that the compiler does not call the operators in the way that the
documentation describes (section 3). The test case in section 5 is the
reduced form of that program. The library change was reverted. The library
keeps the dynamic array, and the performance gain of section 1.2 is not
available on this compiler.

## 2. Environment

| Item | Value |
|------|-------|
| Compiler | Free Pascal 3.2.4 (`fpc -iV` prints `3.2.4`; release candidate 2 build of 2026/08/26) |
| Target | aarch64, macOS (Darwin 27.0.0) |
| Mode | `-MObjFPC`, `{$modeswitch advancedrecords}` |
| Optimization | the results are the same at `-O-` and at `-O3` |
| Not tested | other targets, other operating systems, FPC 3.3.x (trunk), `-Cr`, `-Co` and `-gh` combinations |

## 3. What the documentation promises

The wiki page for management operators
(<https://wiki.lazarus.freepascal.org/management_operators>) states:

- Management operators are called implicitly for variable assignment (Copy),
  and for the parameters of routines (AddRef, Finalize or none, depending on
  the modifiers `var`, `constref` and `const`).
- "AddRef is called after the contents of a record have been duplicated by a
  bitwise copy (for example after, not during, an assignment)."
- "The Copy operator, if implemented, is called instead of the default copy
  behavior."
- Initialize and Finalize are called for local and global variables, and for
  fields of records, objects and classes.

From these statements, a record with `Initialize`, `Finalize` and `AddRef`
but without `Copy` is expected to behave as follows. An assignment copies the
bytes, then calls `AddRef` on the target. The previous value of the target is
finalized before the copy. A record with all four operators is expected to
call `Copy` for an assignment, and to finalize any temporary that holds a
function result.

## 4. Observed faults

The test case builds, for each pattern, a value that owns a slot with a
reference count of one, runs one statement, and reads the count. The counts
live in a global array, so the program never touches freed memory.

| Fault | Record type | Statement | Expected | Observed |
|-------|-------------|-----------|----------|----------|
| F1 | no `Copy` operator | `B := A` (variable to variable) | `AddRef` is called, count 2 | `AddRef` is not called, count stays 1. When both variables are finalized the count reaches -1 (a double release). |
| F2 | no `Copy` operator | `A := Default(T)` | `Finalize` runs on the old value of `A`, count 0 | `Finalize` does not run, count stays 1 (leak). |
| F3 | no `Copy` operator | `B := A` when `B` already holds a value | `Finalize` runs on the old value of `B` | `Finalize` does not run for the old value (leak). |
| F4 | all four operators | `GA := MakeC(6)` where `GA` is a variable of the main program block and `MakeC` returns a record through `Result` | count 1 | count 2: the temporary that holds the function result is not finalized after `Copy` ran (leak). The same statement with a local variable of a procedure gives the expected count 1. |

Controls that behave as documented: with all four operators, `B := A` between
variables (count 2), `B := IdentC(A)` where the function does `Result := X`
(count 2), and release at the end of a procedure (count 0). Without `Copy`, a
by-value parameter (`AddRef` then `Finalize`, net zero) and the release of a
local variable at the end of a procedure.

### 4.1 Consequences

- Without a `Copy` operator, the compiler does a plain bitwise copy on
  assignment. A record that uses `AddRef` to share a resource then has two
  owners and one count. The first release frees the resource, and the second
  owner holds a dangling reference. This is the double free that crashed or
  corrupted the test suite.
- With a `Copy` operator, a function result that is assigned to a variable of
  the main program block leaks one count each time. A library that returns such
  records from every operator then never frees its blocks when it is used from
  the main block.
- A record cannot be written to be correct under both behaviors, because the
  operator that fixes F1 (`Copy`) is the one that shows F4, and the
  alternative (`AddRef` only) shows F1, F2 and F3.

## 5. Test case

The program is a single file, `tests/fpcbugs/ManagementOperators.lpr` in this
repository. Its source follows. It builds with
`fpc -MObjFPC ManagementOperators.lpr` and needs only the RTL.

```pascal

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
```

### 5.1 Output

The output below was produced with FPC 3.2.4rc2 on aarch64 macOS. It is
identical at `-O-` and at `-O3`. Eight lines start with `FAIL`, and the exit
code is 1.

```
ok    1 TWithCopy: A := MakeC(1) (count while owned): count 1
ok    1 TWithCopy: after the procedure returned: count 0
ok    2 TWithCopy: B := A (count while shared): count 2
ok    2 TWithCopy: after the procedure returned: count 0
ok    3 TWithCopy: B := IdentC(A) (count while shared): count 2
ok    3 TWithCopy: after the procedure returned: count 0
FAIL  4 TNoCopy: B := A (count while shared): expected count 2, got 1
FAIL  4 TNoCopy: after the procedure returned: expected count 0, got -1
ok    5 TNoCopy: ByValueN(A) (count after the call): count 1
ok    5 TNoCopy: after the procedure returned: count 0
FAIL  8 TNoCopy: A := Default(TNoCopy) (count after the assignment): expected count 0, got 1
FAIL  9 TNoCopy: B := A (count of the old value of B): expected count 0, got 1
FAIL  6 TWithCopy global: GA := MakeC(6) (count while owned): expected count 1, got 2
FAIL  6 TWithCopy global: GB := GA (count while shared): expected count 2, got 3
FAIL  6 TWithCopy global: both set to Default: expected count 0, got 1
ok    7 TNoCopy global: GN := MakeN(7) (count while owned): count 1
FAIL  7 TNoCopy global: GN set to Default: expected count 0, got 1
result: the compiler fails at least one reference counting case
```

## 6. Related reports

The FPC issue tracker holds a report with a different symptom in the same
area: "management operators double free after nested function"
(<https://gitlab.com/freepascal.org/fpc/source/-/issues/40392>). It describes
`Finalize` that runs twice for a record that passes through several local
variables in a function with a nested procedure, on FPC 3.3.1. Whether it
shares a cause with F1 to F4 is not established. The mailing list thread
"Management operators AddRef and Copy vs Copy"
(<https://lists.freepascal.org/fpc-devel/2016-April/037104.html>) discusses
the intended split of duties between the two operators.


