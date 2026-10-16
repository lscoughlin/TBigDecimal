{**
---
license: LGPL-2.1-only WITH Independent-modules-exception
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: tests, runner
notes:
  - console runner for the fpcunit suites
---
}
program RunTests;

{$mode objfpc}{$H+}

uses
  {$ifdef unix}cthreads,{$endif}
  Classes, consoletestrunner,
  TestKernels, TestVectors, TestLibrary, DecTestRunner;

type
  TMyRunner = class(TTestRunner)
  end;

var
  App: TMyRunner;

begin
  App := TMyRunner.Create(nil);
  App.Initialize;
  App.Title := 'TBigDecimal tests';
  App.Run;
  App.Free;
end.
