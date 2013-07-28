program UnitTest;

{$APPTYPE CONSOLE}

{$I DelphiRest.inc}

//{$IFDEF DELPHI_7}
//FastMM4,
//{$ENDIF}

uses
  {$IFDEF DELPHI_7}
  FastMM4,
  {$ENDIF}
  Forms,
  TestFramework,
  GUITestRunner,
  TextTestRunner,
  SysUtils,
  TestHelloWorld in 'TestHelloWorld.pas',
  TestPeople in 'TestPeople.pas',
  BaseTestRest in 'BaseTestRest.pas',
  TestHeader in 'TestHeader.pas',
  TestResponseHandler in 'TestResponseHandler.pas',
  Person in 'Person.pas',
  DataSetUtils in '..\src\DataSetUtils.pas',
  RestClient in '..\src\RestClient.pas',
  HttpConnection in '..\src\HttpConnection.pas',
  HttpConnectionFactory in '..\src\HttpConnectionFactory.pas',
  WinHttp_TLB in '..\lib\WinHttp_TLB.pas',
  TestRegister in 'TestRegister.pas',
  TestRestClient in 'TestRestClient.pas',
  Wcrypt2 in '..\lib\Wcrypt2.pas',
  TypesToTest in 'TypesToTest.pas',
  DBXJsonUnMarshal in '..\src\DBXJsonUnMarshal.pas';

{$R *.RES}

begin
  Application.Initialize;

  {$IFNDEF DELPHI_7}
  ReportMemoryLeaksOnShutdown := True;
  {$ENDIF}

  if FindCmdLineSwitch('text', ['-', '/'], True) then
    with TextTestRunner.RunRegisteredTests do
      Free
  else
    GUITestRunner.RunRegisteredTests;
end.

