program minic;

uses
  Lexer,
  gminic;

var
  SourceFile: String;

begin
  if ParamCount <> 1 then
  begin
    Writeln('Usage: minic.exe <source_file>');
    Halt(1);
  end;

  SourceFile := ParamStr(1);
  Writeln('Compiling ', SourceFile, '...');

  InitLexer(SourceFile);
  
  InitParser;

  if parse_Program then
  begin
    Writeln('Parsing completed successfully!');
  end else begin
    Writeln('Syntax Error at line ', CurrLine);
  end;

  DoneParser;
  DoneLexer;
end.

