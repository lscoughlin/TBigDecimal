{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: benchmark, division by 10^9
notes:
  - compares forms of x div 10^9 in a carry chain
---
}
program BenchDivMod;
{ Dependent chain (a carry feeds the next division, as in a multiply loop).
  Compares three ways to compute x div 10^9 and x mod 10^9 for UInt64 x:
  the compiler divide, a Double estimate with one correction step, and an exact
  multiply-high by a reciprocal (x shr 9 divided by 5^9, M = ceil(2^75 / 5^9)). }
{$mode objfpc}{$H+}{$R-}{$Q-}
{$inline on}
{$coperators on}
uses SysUtils, DateUtils;

const
  Base = 1000000000;
  N = 1 shl 16;
  Magic = UInt64(19342813113834067);   // ceil(2^(64+11) / 1953125), exact for v < 2^55
  Shift = 11;

var
  xs: array[0..N - 1] of UInt64;

function MulHi(a, b: UInt64): UInt64; inline;
var
  a0, a1, b0, b1, p00, p01, p10, p11, mid: UInt64;
begin
  a0 := a and $FFFFFFFF; a1 := a shr 32;
  b0 := b and $FFFFFFFF; b1 := b shr 32;
  p00 := a0 * b0; p01 := a0 * b1; p10 := a1 * b0; p11 := a1 * b1;
  mid := (p00 shr 32) + (p01 and $FFFFFFFF) + (p10 and $FFFFFFFF);
  Result := p11 + (p01 shr 32) + (p10 shr 32) + (mid shr 32);
end;

{$ifdef CPUAARCH64}
function MulHiAsm(a, b: UInt64): UInt64; assembler; nostackframe;
asm
  umulh x0, x0, x1
end;
{$define HAVEASM}
{$endif}
{$ifdef CPUX86_64}
function MulHiAsm(a, b: UInt64): UInt64; assembler; nostackframe;
asm
  {$ifdef win64}
  mov rax, rcx
  mul rdx
  mov rax, rdx
  {$else}
  mov rax, rdi
  mul rsi
  mov rax, rdx
  {$endif}
end;
{$define HAVEASM}
{$endif}

function DivCompiler(x: UInt64; out r: UInt32): UInt64; inline;
begin
  Result := x div Base;
  r := UInt32(x - Result * Base);
end;

function DivDouble(x: UInt64; out r: UInt32): UInt64; inline;
var
  q: UInt64;
  t: Int64;
begin
  q := Trunc(Double(x) * 1e-9);
  t := Int64(x - q * Base);
  if t < 0 then begin Dec(q); t += Base; end
  else if t >= Base then begin Inc(q); t -= Base; end;
  r := UInt32(t);
  Result := q;
end;

function DivRecipPas(x: UInt64; out r: UInt32): UInt64; inline;
begin
  Result := MulHi(x shr 9, Magic) shr Shift;
  r := UInt32(x - Result * Base);
end;

{$ifdef HAVEASM}
function DivRecipAsm(x: UInt64; out r: UInt32): UInt64; inline;
begin
  Result := MulHiAsm(x shr 9, Magic) shr Shift;
  r := UInt32(x - Result * Base);
end;
{$endif}

function Secs: Double;
begin
  Result := Now * 86400.0;
end;

var
  i, rep: Integer;
  t0: Double;
  acc: UInt64;
  r: UInt32;
  bad: Int64;
  x, q: UInt64;
begin
  Randomize;
  for i := 0 to N - 1 do
  begin
    xs[i] := (UInt64(Random($7FFFFFFF)) shl 33) xor (UInt64(Random($7FFFFFFF)) shl 2) xor Random(4);
    if (i and 7) = 0 then xs[i] := (xs[i] mod 1000000000) * 1000000000 + Random(1000000000);
  end;
  // correctness of the exact reciprocal and the Double estimate
  bad := 0;
  for rep := 1 to 40 do
    for i := 0 to N - 1 do
    begin
      x := xs[i] xor UInt64(rep);
      q := x div Base;
      if DivRecipPas(x, r) <> q then Inc(bad);
      if DivDouble(x, r) <> q then Inc(bad);
    end;
  for x := 0 to 3000000 do
  begin
    if DivRecipPas(x * 6143, r) <> (x * 6143) div Base then Inc(bad);
  end;
  for x := UInt64(1) shl 63 to (UInt64(1) shl 63) + 100000 do
    if (DivRecipPas(x, r) <> x div Base) or (DivDouble(x, r) <> x div Base) then Inc(bad);
  WriteLn('mismatches: ', bad);
  acc := 0;
  t0 := Secs;
  for rep := 1 to 20000 do
    for i := 0 to N - 1 do begin acc := DivCompiler((xs[i] and $3FFFFFFFFFFFFFF) + acc, r); end;
  WriteLn('compiler divide   ', (Secs - t0) * 1000 : 0 : 0, ' ms  ', acc);
  acc := 0;
  t0 := Secs;
  for rep := 1 to 20000 do
    for i := 0 to N - 1 do begin acc := DivDouble((xs[i] and $3FFFFFFFFFFFFFF) + acc, r); end;
  WriteLn('double estimate   ', (Secs - t0) * 1000 : 0 : 0, ' ms  ', acc);
  acc := 0;
  t0 := Secs;
  for rep := 1 to 20000 do
    for i := 0 to N - 1 do begin acc := DivRecipPas((xs[i] and $3FFFFFFFFFFFFFF) + acc, r); end;
  WriteLn('mulhi pascal      ', (Secs - t0) * 1000 : 0 : 0, ' ms  ', acc);
  {$ifdef HAVEASM}
  acc := 0;
  t0 := Secs;
  for rep := 1 to 20000 do
    for i := 0 to N - 1 do begin acc := DivRecipAsm((xs[i] and $3FFFFFFFFFFFFFF) + acc, r); end;
  WriteLn('mulhi assembler   ', (Secs - t0) * 1000 : 0 : 0, ' ms  ', acc);
  {$endif}
end.
