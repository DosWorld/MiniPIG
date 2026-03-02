unit Lexer;

interface

type
  TTokenKind = (
    tokEOF,
    tokInt,
    tokChar,
    tokIf,
    tokElse,
    tokWhile,
    tokReturn,
    tokBreak,
    tokContinue,
    tokExtern,
    tokIdent,
    tokNumber,
    tokString,
    tokAssign,
    tokEqual,
    tokNotEqual,
    tokLess,
    tokLessEq,
    tokGreater,
    tokGreaterEq,
    tokPlus,
    tokMinus,
    tokStar,
    tokDiv,
    tokAmp,
    tokNot,
    tokLPar,
    tokRPar,
    tokLBrace,
    tokRBrace,
    tokSemi,
    tokComma,
    tokError
  );

var
  CurrToken:    TTokenKind;
  CurrTokenVal: String;
  CurrLine:     Integer;

procedure InitLexer(FileName: String);
procedure DoneLexer;
procedure NextToken;

implementation

var
  InFile: Text;
  LookChar: Char;
  EOFReached: Boolean;

const
  KW_COUNT = 9;
  Keywords: array[1..KW_COUNT] of String = (
    'int', 'char', 'if', 'else', 'while', 'return', 'break', 'continue', 'extern'
  );
  KeyTokens: array[1..KW_COUNT] of TTokenKind = (
    tokInt, tokChar, tokIf, tokElse, tokWhile, tokReturn, tokBreak, tokContinue, tokExtern
  );

procedure ReadChar;
begin
  if EOF(InFile) then begin
    EOFReached := True;
    LookChar := #0;
  end else begin
    Read(InFile, LookChar);
  end;
end;

procedure InitLexer(FileName: String);
begin
  Assign(InFile, FileName);
  Reset(InFile);
  CurrLine := 1;
  EOFReached := False;
  ReadChar;
end;

procedure DoneLexer;
begin
  Close(InFile);
end;

function IsAlpha(C: Char): Boolean;
begin
  IsAlpha := (C in ['a'..'z', 'A'..'Z', '_']);
end;

function IsDigit(C: Char): Boolean;
begin
  IsDigit := (C in ['0'..'9']);
end;

function IsAlNum(C: Char): Boolean;
begin
  IsAlNum := IsAlpha(C) or IsDigit(C);
end;

procedure SkipWhitespace;
begin
  while not EOFReached and (LookChar <= ' ') do begin
    if LookChar = #10 then Inc(CurrLine);
    ReadChar;
  end;
end;

procedure NextToken;
var
  I: Integer;
begin
  SkipWhitespace;

  CurrTokenVal := '';

  if EOFReached then begin
    CurrToken := tokEOF;
    Exit;
  end;

  if IsAlpha(LookChar) then begin
    while IsAlNum(LookChar) do begin
      CurrTokenVal := CurrTokenVal + LookChar;
      ReadChar;
    end;
    
    CurrToken := tokIdent;
    for I := 1 to KW_COUNT do begin
      if CurrTokenVal = Keywords[I] then begin
        CurrToken := KeyTokens[I];
        Exit;
      end;
    end;
    Exit;
  end;

  if IsDigit(LookChar) then begin
    while IsDigit(LookChar) do begin
      CurrTokenVal := CurrTokenVal + LookChar;
      ReadChar;
    end;
    CurrToken := tokNumber;
    Exit;
  end;

  case LookChar of
    '=': begin
           ReadChar;
           if LookChar = '=' then begin
             CurrToken := tokEqual;
             ReadChar;
           end else CurrToken := tokAssign;
         end;
    '!': begin
           ReadChar;
           if LookChar = '=' then begin
             CurrToken := tokNotEqual;
             ReadChar;
           end else CurrToken := tokNot;
         end;
    '<': begin
           ReadChar;
           if LookChar = '=' then begin
             CurrToken := tokLessEq;
             ReadChar;
           end else CurrToken := tokLess;
         end;
    '>': begin
           ReadChar;
           if LookChar = '=' then begin
             CurrToken := tokGreaterEq;
             ReadChar;
           end else CurrToken := tokGreater;
         end;
    '+': begin CurrToken := tokPlus;  ReadChar; end;
    '-': begin CurrToken := tokMinus; ReadChar; end;
    '*': begin CurrToken := tokStar;  ReadChar; end;
    '&': begin CurrToken := tokAmp;   ReadChar; end;
    '(': begin CurrToken := tokLPar;  ReadChar; end;
    ')': begin CurrToken := tokRPar;  ReadChar; end;
    '{': begin CurrToken := tokLBrace; ReadChar; end;
    '}': begin CurrToken := tokRBrace; ReadChar; end;
    ';': begin CurrToken := tokSemi;  ReadChar; end;
    ',': begin CurrToken := tokComma; ReadChar; end;
    
    '/': begin
           ReadChar;
           if LookChar = '/' then begin
             while (LookChar <> #10) and (LookChar <> #13) and not EOFReached do ReadChar;
             NextToken;
           end else begin
             CurrToken := tokDiv;
           end;
         end;

    '"': begin
           ReadChar;
           while (LookChar <> '"') and not EOFReached do begin
             CurrTokenVal := CurrTokenVal + LookChar;
             ReadChar;
           end;
           if LookChar = '"' then ReadChar;
           CurrToken := tokString;
         end;

    else begin
           CurrToken := tokError;
           ReadChar;
         end;
  end;
end;

end.

