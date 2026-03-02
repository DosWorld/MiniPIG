{ ******************************************************************
  MiniPIG - Strict LL(1) Parser Generator for TP.
  Copyright (c) 2026 by DosWorld, GNU GPLv3 License
  https://github.com/DosWorld/
  ****************************************************************** }
{$M 64000,128000,650000}
{$I+,S-,X+,R-,O-,G-}
Program MiniPIG;

Const 
  GRAMMAR_MAX_SIZE = 65000;
  MAX_NESTING = 32;
  MAX_TOKENS = 255;

Type 
  TTokenName = string[32];
  TRuleName  = string[64];
  TAction    = string;

  PTokenDecl = ^TTokenDecl;
  PElement   = ^TElement;
  PAlt       = ^TAlt;
  PGroup     = ^TGroup;
  PRule      = ^TRule;

  TQuant    = (qNone, qStar, qPlus, qQMark);
  TElemKind = (ekNonterm, ekGroup, ekEmpty, ekPredicate, ekToken);

  TTokenSet = set Of 0..MAX_TOKENS;

  TTokenDecl = Record
    Name: TTokenName;
    ID: Integer;
    Next: PTokenDecl;
  End;

  TGroup = Record
    ID: Integer;
    FirstAlt: PAlt;
    Quant: TQuant;
    Action: TAction;
    Next: PGroup;
    IsNullable: Boolean;
    FirstSet: TTokenSet;
  End;

  TElement = Record
    Kind: TElemKind;
    Action: TAction;
    Next: PElement;
    Case TElemKind Of 
      ekToken:   (TokenName: TTokenName; TokenID: Integer);
      ekNonterm: (Nonterm: TRuleName; RulePtr: PRule);
      ekGroup:   (Group: PGroup);
  End;

  TAlt = Record
    FirstElem: PElement;
    Action: TAction;
    Next: PAlt;
    IsNullable: Boolean;
    FirstSet: TTokenSet;
  End;

  TRule = Record
    Name: TRuleName;
    FirstAlt: PAlt;
    Next: PRule;
    IsNullable: Boolean;
    FirstSet: TTokenSet;
    FollowSet: TTokenSet;
    RecActive: Boolean;
    RecChecked: Boolean;
  End;

Var 
  FirstToken: PTokenDecl;
  FirstRule, LastRule: PRule;
  FirstGroup, LastGroup: PGroup;

  GrammarBuffer: PChar;
  BufferLen: LongInt;
  Cursor: LongInt;
  LineNum: LongInt;
  GroupIDCounter: Integer;
  TokenCounter: Integer;

  GlobalUses: string;
  GlobalUnitStart: string;

  CfgTokenType: string;
  CfgTokenNext: string;
  CfgTokenKind: string;
  CfgTokenValue: string;
  CfgTokenLine: string;
  CfgTokenEof: string;
  EofTokenID: Integer;

  OutFile: Text;
  IndentLevel: Integer;

  CurrentProcessingRule: string;
  CurrentGenRule: string;

Procedure ResolveGroupRefs(Grp: PGroup);
forward;
Procedure CheckRecursion(R: PRule);
forward;
Procedure GenInlineGroup(G: PGroup; Depth: Integer; Follow: TTokenSet);
forward;
Function FindRule(Const Name: String): PRule;
forward;
Procedure UpdateFollows(El: PElement; ContextFollow: TTokenSet; Var Changed: Boolean);
forward;
Procedure GetFirstOfSeq(StartEl: PElement; Var Result: TTokenSet);
forward;
Function IsSeqNullable(StartEl: PElement): Boolean;
forward;

Procedure Error(Const Msg: String);
Begin
  Write('Error');
  If CurrentProcessingRule <> '' Then Write(' [Rule: ', CurrentProcessingRule, ']');
  Writeln(' (Line ', LineNum, '): ', Msg);
  Halt(1);
End;

Procedure Warning(Const Msg: String);
Begin
  Write('Warning');
  If CurrentProcessingRule <> '' Then Write(' [Rule: ', CurrentProcessingRule, ']');
  Writeln(': ', Msg);
End;

Function Trim(S: String): String;

Var I, L: Integer;
Begin
  L := Length(S);
  While (L > 0) And (S[L] <= ' ') Do
    Dec(L);
  I := 1;
  While (I <= L) And (S[I] <= ' ') Do
    Inc(I);
  If I > L Then Trim := ''
  Else Trim := Copy(S, I, L - I + 1);
End;

Function IntToStr(I: Longint): string;

Var S: string;
Begin
  Str(I, S);
  IntToStr := S;
End;

Procedure Indent;
Begin
  Inc(IndentLevel);
End;
Procedure Undent;
Begin
  Dec(IndentLevel);
End;

Procedure WriteIndent;

Var I: Integer;
Begin
  For I := 1 To IndentLevel * 2 Do
    Write(OutFile, ' ');
End;

Function Peek: Char;
Begin
  If Cursor > BufferLen Then Peek := #0
  Else Peek := GrammarBuffer[Cursor - 1];
End;

Function PeekNext: Char;
Begin
  If Cursor + 1 > BufferLen Then PeekNext := #0
  Else PeekNext := GrammarBuffer[Cursor];
End;

Procedure NextCh;
Begin
  If Cursor <= BufferLen Then
    Begin
      If GrammarBuffer[Cursor - 1] = #10 Then Inc(LineNum);
      Inc(Cursor);
    End;
End;

Procedure SkipWS;
Begin
  While Cursor <= BufferLen Do
    Begin
      If GrammarBuffer[Cursor - 1] <= ' ' Then NextCh
      Else If (GrammarBuffer[Cursor - 1] = '(') And (PeekNext = '*') Then
             Begin
               NextCh;
               NextCh;
               While (Cursor <= BufferLen) And Not ((GrammarBuffer[Cursor - 1] = '*') And (PeekNext
                     = ')')) Do
                 NextCh;
               If Cursor <= BufferLen Then
                 Begin
                   NextCh;
                   NextCh;
                 End;
             End
      Else Exit;
    End;
End;

Function GetTokenStr(StartPos: LongInt): string;

Var Len: LongInt;
  S: string;
Begin
  Len := Cursor - StartPos;
  If Len > 255 Then Error('Identifier too long');
  S[0] := Chr(Len);
  If Len > 0 Then Move((GrammarBuffer + StartPos - 1)^, S[1], Len);
  GetTokenStr := S;
End;

Function IsIdentChar(C: Char): Boolean;
Begin
  IsIdentChar := (C In ['a'..'z', 'A'..'Z', '0'..'9', '_']);
End;

Function MatchKeyword(Const Kw: String): Boolean;

Var I: Integer;
  SavePos: LongInt;
Begin
  SavePos := Cursor;
  SkipWS;
  For I := 1 To Length(Kw) Do
    Begin
      If UpCase(Peek) <> UpCase(Kw[I]) Then
        Begin
          Cursor := SavePos;
          MatchKeyword := False;
          Exit;
        End;
      NextCh;
    End;
  If IsIdentChar(Peek) Then
    Begin
      Cursor := SavePos;
      MatchKeyword := False;
      Exit;
    End;
  MatchKeyword := True;
End;

Function ReadAction: string;

Var Start: LongInt;
Begin
  SkipWS;
  If (Peek <> '<') Or (PeekNext <> '?') Then
    Begin
      ReadAction := '';
      Exit;
    End;
  NextCh;
  NextCh;
  Start := Cursor;
  While (Cursor <= BufferLen) Do
    Begin
      If (Peek = '?') And (PeekNext = '>') Then Break;
      NextCh;
    End;
  If Cursor > BufferLen Then Error('Unclosed action block');
  ReadAction := GetTokenStr(Start);
  NextCh;
  NextCh;
End;

Function ParseAlts(IsGroup: Boolean): PAlt;
forward;

Procedure RegisterToken(Const Name: TTokenName);

Var P, Last: PTokenDecl;
Begin
  P := FirstToken;
  While P <> Nil Do
    Begin
      If P^.Name = Name Then Error('Duplicate token: ' + Name);
      P := P^.Next;
    End;
  If TokenCounter > MAX_TOKENS Then Error('Too many tokens (max 255)');
  New(P);
  P^.Name := Name;
  P^.ID := TokenCounter;
  P^.Next := Nil;
  Inc(TokenCounter);
  If FirstToken = Nil Then FirstToken := P
  Else
    Begin
      Last := FirstToken;
      While Last^.Next <> Nil Do
        Last := Last^.Next;
      Last^.Next := P;
    End;
End;

Function GetTokenID(Const Name: TTokenName): Integer;

Var P: PTokenDecl;
Begin
  P := FirstToken;
  While P <> Nil Do
    Begin
      If P^.Name = Name Then
        Begin
          GetTokenID := P^.ID;
          Exit;
        End;
      P := P^.Next;
    End;
  GetTokenID := -1;
End;

Function ParseElement: PElement;

Var El: PElement;
  Start: LongInt;
  Name: string;
  C, EndChar: Char;
  Level: Integer;
Begin
  New(El);
  El^.Next := Nil;
  El^.Action := '';
  SkipWS;
  C := Peek;
  If (C = '<') And (PeekNext = '?') Then
    Begin
      NextCh;
      NextCh;
      Start := Cursor;
      While (Cursor <= BufferLen) Do
        Begin
          If (Peek = '?') And (PeekNext = '>') Then Break;
          NextCh;
        End;
      El^.Action := GetTokenStr(Start);
      NextCh;
      NextCh;
      El^.Kind := ekEmpty;
      ParseElement := El;
      Exit;
    End
  Else If (C = '?') And (PeekNext = '(') Then
         Begin
           NextCh;
           NextCh;
           Start := Cursor;
           Level := 1;
           While (Cursor <= BufferLen) And (Level > 0) Do
             Begin
               If Peek = '(' Then Inc(Level)
               Else If Peek = ')' Then Dec(Level);
               If Level > 0 Then NextCh;
             End;
           El^.Kind := ekPredicate;
           El^.Action := GetTokenStr(Start);
           NextCh;
           ParseElement := El;
           Exit;
         End
  Else If C In ['(', '[', '{'] Then
         Begin
           NextCh;
           El^.Kind := ekGroup;
           New(El^.Group);
           Inc(GroupIDCounter);
           El^.Group^.ID := GroupIDCounter;
           El^.Group^.Next := Nil;
           El^.Group^.IsNullable := False;
           El^.Group^.FirstSet := [];
           EndChar := ')';
           Case C Of 
             '(': El^.Group^.Quant := qNone;
             '[':
                  Begin
                    El^.Group^.Quant := qQMark;
                    EndChar := ']';
                  End;
             '{':
                  Begin
                    El^.Group^.Quant := qStar;
                    EndChar := '}';
                  End;
           End;
           If FirstGroup = Nil Then FirstGroup := El^.Group
           Else LastGroup^.Next := El^.Group;
           LastGroup := El^.Group;
           El^.Group^.FirstAlt := ParseAlts(True);
           SkipWS;
           If Peek <> EndChar Then Error('Expected "' + EndChar + '"');
           NextCh;
           El^.Group^.Action := ReadAction;
         End
  Else If IsIdentChar(C) Then
         Begin
           Start := Cursor;
           While IsIdentChar(Peek) Do
             NextCh;
           Name := GetTokenStr(Start);
           If GetTokenID(Name) <> -1 Then
             Begin
               El^.Kind := ekToken;
               El^.TokenName := Name;
               El^.TokenID := GetTokenID(Name);
             End
           Else
             Begin
               El^.Kind := ekNonterm;
               El^.Nonterm := Name;
               El^.RulePtr := Nil;
             End;
         End
  Else
    Begin
      Dispose(El);
      ParseElement := Nil;
      Exit;
    End;
  ParseElement := El;
End;

Function ParseSequence: PElement;

Var Head, Curr, NewEl: PElement;
Begin
  Head := Nil;
  Curr := Nil;
  While Cursor <= BufferLen Do
    Begin
      SkipWS;
      If Peek In ['|', ';', ')', ']', '}'] Then Break;
      NewEl := ParseElement;
      If NewEl = Nil Then Break;
      If NewEl^.Kind <> ekPredicate Then
        Begin
          SkipWS;
          If (Peek = '<') And (PeekNext = '?') Then NewEl^.Action := ReadAction;
        End;
      If Head = Nil Then Head := NewEl
      Else Curr^.Next := NewEl;
      Curr := NewEl;
    End;
  ParseSequence := Head;
End;

Function ParseAlts(IsGroup: Boolean): PAlt;

Var Head, Curr, NewAlt: PAlt;
Begin
  Head := Nil;
  Curr := Nil;
  While Cursor <= BufferLen Do
    Begin
      New(NewAlt);
      NewAlt^.Next := Nil;
      NewAlt^.FirstElem := ParseSequence;
      NewAlt^.Action := ReadAction;
      NewAlt^.IsNullable := False;
      NewAlt^.FirstSet := [];
      If Head = Nil Then Head := NewAlt
      Else Curr^.Next := NewAlt;
      Curr := NewAlt;
      SkipWS;
      If Peek = '|' Then
        Begin
          NextCh;
          SkipWS;
        End
      Else Break;
    End;
  ParseAlts := Head;
End;

Procedure ParseRule;

Var Start: LongInt;
  Name: TRuleName;
  Rule, Iter: PRule;
Begin
  SkipWS;
  Start := Cursor;
  While IsIdentChar(Peek) Do
    NextCh;
  Name := GetTokenStr(Start);
  If Name = '' Then Exit;
  CurrentProcessingRule := Name;
  Iter := FirstRule;
  While Iter <> Nil Do
    Begin
      If Iter^.Name = Name Then Error('Duplicate rule');
      Iter := Iter^.Next;
    End;
  SkipWS;
  If (Peek = ':') And (PeekNext = ':') Then
    Begin
      NextCh;
      NextCh;
      If Peek = '=' Then NextCh
      Else Error('Expected "::="');
    End
  Else Error('Expected "::=" after rule name');
  New(Rule);
  Rule^.Name := Name;
  Rule^.Next := Nil;
  Rule^.IsNullable := False;
  Rule^.FirstSet := [];
  Rule^.FollowSet := [];
  Rule^.RecActive := False;
  Rule^.RecChecked := False;
  Rule^.FirstAlt := ParseAlts(False);
  SkipWS;
  If Peek <> ';' Then Error('Expected ";"');
  NextCh;
  If FirstRule = Nil Then FirstRule := Rule
  Else LastRule^.Next := Rule;
  LastRule := Rule;
  CurrentProcessingRule := '';
End;

function RemoveComments(const S: string): string;
var
  i, Len: Integer;
  InComment: Boolean;
  Res: string;
begin
  Res := '';
  i := 1;
  Len := Length(S);
  InComment := False;
  while i <= Len do
  begin
    if not InComment and (i < Len) and (S[i] = '(') and (S[i+1] = '*') then
    begin
      InComment := True;
      Inc(i, 2);
    end
    else if InComment and (i < Len) and (S[i] = '*') and (S[i+1] = ')') then
    begin
      InComment := False;
      Inc(i, 2);
    end
    else if not InComment then
    begin
      Res := Res + S[i];
      Inc(i);
    end
    else
      Inc(i);
  end;
  if InComment then
    Warning('Unclosed comment in directive');
  RemoveComments := Res;
end;

function readToEol(var Start: LongInt): string;
begin
  SkipWS;
  Start := Cursor;
  while (Cursor <= BufferLen) and (Peek <> #10) do
    NextCh;
  readToEol := Trim(RemoveComments(GetTokenStr(Start)));
end;

Procedure ParseGrammar;

Var Start: LongInt;
Begin
  While Cursor <= BufferLen Do
    Begin
      SkipWS;
      If Cursor > BufferLen Then Break;
      If MatchKeyword('$unit_start') Then GlobalUnitStart := readToEol(Start)
      Else If MatchKeyword('$uses') Then GlobalUses := readToEol(Start)
      Else If MatchKeyword('$token') Then RegisterToken(readToEol(Start))
      Else If MatchKeyword('$token_type') Then CfgTokenType := readToEol(Start)
      Else If MatchKeyword('$token_next') Then CfgTokenNext := readToEol(Start)
      Else If MatchKeyword('$token_kind') Then CfgTokenKind := readToEol(Start)
      Else If MatchKeyword('$token_value') Then CfgTokenValue := readToEol(Start)
      Else If MatchKeyword('$token_line') Then CfgTokenLine := readToEol(Start)
      Else If MatchKeyword('$token_eof') Then CfgTokenEof := readToEol(Start)
      Else If Peek = '$' Then Error('Unknown keyword')
      Else ParseRule;
    End;
End;

Function FindRule(Const Name: String): PRule;

Var R: PRule;
Begin
  R := FirstRule;
  While R <> Nil Do
    Begin
      If R^.Name = Name Then
        Begin
          FindRule := R;
          Exit;
        End;
      R := R^.Next;
    End;
  FindRule := Nil;
End;

Procedure ResolveGroupRefs(Grp: PGroup);

Var A: PAlt;
  E: PElement;
Begin
  A := Grp^.FirstAlt;
  While A <> Nil Do
    Begin
      E := A^.FirstElem;
      While E <> Nil Do
        Begin
          If E^.Kind = ekNonterm Then
            Begin
              E^.RulePtr := FindRule(E^.Nonterm);
              If E^.RulePtr = Nil Then Error('Undefined rule: ' + E^.Nonterm);
            End
          Else If E^.Kind = ekGroup Then ResolveGroupRefs(E^.Group);
          E := E^.Next;
        End;
      A := A^.Next;
    End;
End;

Procedure ResolveReferences;

Var R: PRule;
  Alt: PAlt;
  El: PElement;
Begin
  R := FirstRule;
  While R <> Nil Do
    Begin
      CurrentProcessingRule := R^.Name;
      Alt := R^.FirstAlt;
      While Alt <> Nil Do
        Begin
          El := Alt^.FirstElem;
          While El <> Nil Do
            Begin
              If El^.Kind = ekNonterm Then
                Begin
                  El^.RulePtr := FindRule(El^.Nonterm);
                  If El^.RulePtr = Nil Then Error('Undefined rule: ' + El^.Nonterm);
                End
              Else If El^.Kind = ekGroup Then ResolveGroupRefs(El^.Group);
              El := El^.Next;
            End;
          Alt := Alt^.Next;
        End;
      R := R^.Next;
    End;
  CurrentProcessingRule := '';
End;

Procedure ComputeAnalysis;

Var Changed: Boolean;
  R: PRule;
  G: PGroup;
  Alt: PAlt;
  El: PElement;
  NewNull: Boolean;
  NewFirst: TTokenSet;
Begin
  Repeat
    Changed := False;

    G := FirstGroup;
    While G <> Nil Do
      Begin
        NewNull := (G^.Quant In [qStar, qQMark]);
        NewFirst := [];
        Alt := G^.FirstAlt;
        While Alt <> Nil Do
          Begin
            Alt^.IsNullable := True;
            Alt^.FirstSet := [];
            El := Alt^.FirstElem;
            While El <> Nil Do
              Begin
                Case El^.Kind Of 
                  ekToken:
                           Begin
                             Alt^.IsNullable := False;
                             Alt^.FirstSet := Alt^.FirstSet + [El^.TokenID];
                             Break;
                           End;
                  ekNonterm:
                             Begin
                               Alt^.FirstSet := Alt^.FirstSet + El^.RulePtr^.FirstSet;
                               If Not El^.RulePtr^.IsNullable Then
                                 Begin
                                   Alt^.IsNullable := False;
                                   Break;
                                 End;
                             End;
                  ekGroup:
                           Begin
                             Alt^.FirstSet := Alt^.FirstSet + El^.Group^.FirstSet;
                             If Not El^.Group^.IsNullable Then
                               Begin
                                 Alt^.IsNullable := False;
                                 Break;
                               End;
                           End;
                  ekPredicate, ekEmpty: ;
                End;
                El := El^.Next;
              End;
            If Alt^.IsNullable Then NewNull := True;
            NewFirst := NewFirst + Alt^.FirstSet;
            Alt := Alt^.Next;
          End;

        If G^.IsNullable <> NewNull Then
          Begin
            G^.IsNullable := NewNull;
            Changed := True;
          End;
        If G^.FirstSet <> NewFirst Then
          Begin
            G^.FirstSet := NewFirst;
            Changed := True;
          End;
        G := G^.Next;
      End;

    R := FirstRule;
    While R <> Nil Do
      Begin
        CurrentProcessingRule := R^.Name;
        NewNull := False;
        NewFirst := [];
        Alt := R^.FirstAlt;
        While Alt <> Nil Do
          Begin
            Alt^.IsNullable := True;
            Alt^.FirstSet := [];
            El := Alt^.FirstElem;
            While El <> Nil Do
              Begin
                Case El^.Kind Of 
                  ekToken:
                           Begin
                             Alt^.IsNullable := False;
                             Alt^.FirstSet := Alt^.FirstSet + [El^.TokenID];
                             Break;
                           End;
                  ekNonterm:
                             Begin
                               Alt^.FirstSet := Alt^.FirstSet + El^.RulePtr^.FirstSet;
                               If Not El^.RulePtr^.IsNullable Then
                                 Begin
                                   Alt^.IsNullable := False;
                                   Break;
                                 End;
                             End;
                  ekGroup:
                           Begin
                             Alt^.FirstSet := Alt^.FirstSet + El^.Group^.FirstSet;
                             If Not El^.Group^.IsNullable Then
                               Begin
                                 Alt^.IsNullable := False;
                                 Break;
                               End;
                           End;
                  ekPredicate, ekEmpty: ;
                End;
                El := El^.Next;
              End;
            If Alt^.IsNullable Then NewNull := True;
            NewFirst := NewFirst + Alt^.FirstSet;
            Alt := Alt^.Next;
          End;

        If R^.IsNullable <> NewNull Then
          Begin
            R^.IsNullable := NewNull;
            Changed := True;
          End;
        If R^.FirstSet <> NewFirst Then
          Begin
            R^.FirstSet := NewFirst;
            Changed := True;
          End;
        R := R^.Next;
      End;
  Until Not Changed;
  CurrentProcessingRule := '';
End;

Procedure GetFirstOfSeq(StartEl: PElement; Var Result: TTokenSet);

Var E: PElement;
Begin
  Result := [];
  E := StartEl;
  While E <> Nil Do
    Begin
      Case E^.Kind Of 
        ekToken:
                 Begin
                   Result := Result + [E^.TokenID];
                   Exit;
                 End;
        ekNonterm:
                   Begin
                     Result := Result + E^.RulePtr^.FirstSet;
                     If Not E^.RulePtr^.IsNullable Then Exit;
                   End;
        ekGroup:
                 Begin
                   Result := Result + E^.Group^.FirstSet;
                   If Not E^.Group^.IsNullable Then Exit;
                 End;
      End;
      E := E^.Next;
    End;
End;

Function IsSeqNullable(StartEl: PElement): Boolean;

Var E: PElement;
Begin
  E := StartEl;
  While E <> Nil Do
    Begin
      Case E^.Kind Of 
        ekToken:
                 Begin
                   IsSeqNullable := False;
                   Exit;
                 End;
        ekNonterm: If Not E^.RulePtr^.IsNullable Then
                     Begin
                       IsSeqNullable := False;
                       Exit;
                     End;
        ekGroup: If Not E^.Group^.IsNullable Then
                   Begin
                     IsSeqNullable := False;
                     Exit;
                   End;
      End;
      E := E^.Next;
    End;
  IsSeqNullable := True;
End;

Procedure UpdateFollows(El: PElement; ContextFollow: TTokenSet; Var Changed: Boolean);

Var 
  Trailer: TTokenSet;
  Alt: PAlt;
Begin
  While El <> Nil Do
    Begin
      If El^.Kind = ekNonterm Then
        Begin
          GetFirstOfSeq(El^.Next, Trailer);
          If IsSeqNullable(El^.Next) Then Trailer := Trailer + ContextFollow;

          If (Trailer - El^.RulePtr^.FollowSet) <> [] Then
            Begin
              El^.RulePtr^.FollowSet := El^.RulePtr^.FollowSet + Trailer;
              Changed := True;
            End;
        End
      Else If El^.Kind = ekGroup Then
             Begin
               GetFirstOfSeq(El^.Next, Trailer);
               If IsSeqNullable(El^.Next) Then Trailer := Trailer + ContextFollow;

               Alt := El^.Group^.FirstAlt;
               While Alt <> Nil Do
                 Begin
                   UpdateFollows(Alt^.FirstElem, Trailer, Changed);
                   Alt := Alt^.Next;
                 End;
             End;
      El := El^.Next;
    End;
End;

Procedure ComputeFollow;

Var 
  Changed: Boolean;
  R: PRule;
  Alt: PAlt;
Begin
  If (FirstRule <> Nil) And (EofTokenID <> -1) Then
    FirstRule^.FollowSet := [EofTokenID];

  Repeat
    Changed := False;
    R := FirstRule;
    While R <> Nil Do
      Begin
        CurrentProcessingRule := R^.Name;
        Alt := R^.FirstAlt;
        While Alt <> Nil Do
          Begin
            UpdateFollows(Alt^.FirstElem, R^.FollowSet, Changed);
            Alt := Alt^.Next;
          End;
        R := R^.Next;
      End;
  Until Not Changed;
  CurrentProcessingRule := '';
End;

Procedure CheckPath(El: PElement);
forward;

Procedure CheckGroupAlts(G: PGroup);

Var A: PAlt;
Begin
  A := G^.FirstAlt;
  While A <> Nil Do
    Begin
      CheckPath(A^.FirstElem);
      A := A^.Next;
    End;
End;

Procedure CheckPath(El: PElement);
Begin
  While El <> Nil Do
    Begin
      Case El^.Kind Of 
        ekToken: Exit;
        ekNonterm:
                   Begin
                     CheckRecursion(El^.RulePtr);
                     If Not El^.RulePtr^.IsNullable Then Exit;
                   End;
        ekGroup:
                 Begin
                   CheckGroupAlts(El^.Group);
                   If Not El^.Group^.IsNullable Then Exit;
                 End;
      End;
      El := El^.Next;
    End;
End;

Procedure CheckRecursion(R: PRule);

Var Alt: PAlt;
Begin
  If R^.RecActive Then Error('Left recursion detected');
  If R^.RecChecked Then Exit;
  R^.RecActive := True;

  Alt := R^.FirstAlt;
  While Alt <> Nil Do
    Begin
      CheckPath(Alt^.FirstElem);
      Alt := Alt^.Next;
    End;

  R^.RecActive := False;
  R^.RecChecked := True;
End;

Procedure GenElement(El: PElement; Depth: Integer; FollowContext: TTokenSet);

Var LocalFollow: TTokenSet;
Begin
  While El <> Nil Do
    Begin
      Case El^.Kind Of 
        ekToken:
                 Begin
                   WriteIndent;
                   Writeln(OutFile, 'if ok then begin');
                   Indent;
                   WriteIndent;
                   Writeln(OutFile, 'if not MiniPigMatch(' + El^.TokenName + ') then ok := False;');
                   Undent;
                   WriteIndent;
                   Writeln(OutFile, 'end;');
                 End;
        ekNonterm:
                   Begin
                     WriteIndent;
                     Writeln(OutFile, 'if ok then');
                     WriteIndent;
                     Writeln(OutFile, '  if not parse_' + El^.Nonterm + ' then ok := False;');
                   End;
        ekGroup:
                 Begin
                   GetFirstOfSeq(El^.Next, LocalFollow);
                   If IsSeqNullable(El^.Next) Then LocalFollow := LocalFollow + FollowContext;
                   GenInlineGroup(El^.Group, Depth + 1, LocalFollow);
                 End;
        ekPredicate:
                     Begin
                       WriteIndent;
                       Writeln(OutFile, 'if ok then begin');
                       WriteIndent;
                       Writeln(OutFile, '  SaveStack[' + IntToStr(Depth) + '] := MiniPigCursor;');
                       WriteIndent;
                       Writeln(OutFile, '  if not (' + Trim(El^.Action) + ') then begin');
                       WriteIndent;
                       Writeln(OutFile, '    MiniPigCursor := SaveStack[' + IntToStr(Depth) + '];');
                       WriteIndent;
                       Writeln(OutFile, '    ok := False;');
                       WriteIndent;
                       Writeln(OutFile, '  end;');
                       WriteIndent;
                       Writeln(OutFile, 'end;');
                     End;
      End;
      If (El^.Kind <> ekPredicate) And (El^.Action <> '') Then
        Begin
          WriteIndent;
          Writeln(OutFile, 'if ok then begin');
          Indent;
          WriteIndent;
          Writeln(OutFile, Trim(El^.Action) + ';');
          Undent;
          WriteIndent;
          Writeln(OutFile, 'end;');
        End;
      El := El^.Next;
    End;
End;

Procedure GenSequence(FirstEl: PElement; Depth: Integer; Follow: TTokenSet);
Begin
  GenElement(FirstEl, Depth, Follow);
End;

Procedure GenAlternativesLogic(FirstAlt: PAlt; Depth: Integer; FollowContext: TTokenSet);

Var 
  Alt: PAlt;
  IterTok: PTokenDecl;
  SelectSet, AccumSet, Intersect: TTokenSet;
  NeedComma: Boolean;
  AnyAlt: Boolean;
  FirstConflict: Boolean;
Begin
  AccumSet := [];
  Alt := FirstAlt;

  While Alt <> Nil Do
    Begin
      SelectSet := Alt^.FirstSet;
      If Alt^.IsNullable Then SelectSet := SelectSet + FollowContext;

      Intersect := SelectSet * AccumSet;
      If Intersect <> [] Then
        Begin
          Write('Error (Line ', LineNum, '): LL(1) Conflict detected in rule "', CurrentGenRule,
                '". Ambiguous tokens: ');
          IterTok := FirstToken;
          FirstConflict := True;
          While IterTok <> Nil Do
            Begin
              If IterTok^.ID In Intersect Then
                Begin
                  If Not FirstConflict Then Write(', ');
                  Write(IterTok^.Name);
                  FirstConflict := False;
                End;
              IterTok := IterTok^.Next;
            End;
          Writeln;
          Halt(1);
        End;

      AccumSet := AccumSet + SelectSet;
      Alt := Alt^.Next;
    End;

  WriteIndent;
  Writeln(OutFile, 'if ok then');
  WriteIndent;
  Writeln(OutFile, 'case MiniPigGetKind of');

  Alt := FirstAlt;
  AnyAlt := False;
  While Alt <> Nil Do
    Begin
      SelectSet := Alt^.FirstSet;
      If Alt^.IsNullable Then SelectSet := SelectSet + FollowContext;

      If SelectSet <> [] Then
        Begin
          AnyAlt := True;
          WriteIndent;
          Write(OutFile, '  ');
          NeedComma := False;
          IterTok := FirstToken;
          While IterTok <> Nil Do
            Begin
              If IterTok^.ID In SelectSet Then
                Begin
                  If NeedComma Then Write(OutFile, ', ');
                  Write(OutFile, IterTok^.Name);
                  NeedComma := True;
                End;
              IterTok := IterTok^.Next;
            End;
          Writeln(OutFile, ': begin');
          Indent;
          GenSequence(Alt^.FirstElem, Depth, FollowContext);
          If Alt^.Action <> '' Then
            Begin
              WriteIndent;
              Writeln(OutFile, Trim(Alt^.Action) + ';');
            End;
          Undent;
          WriteIndent;
          Writeln(OutFile, 'end;');
        End;
      Alt := Alt^.Next;
    End;

  WriteIndent;
  Writeln(OutFile, 'else');
  Indent;
  WriteIndent;
  Writeln(OutFile, 'ok := False;');
  Undent;
  WriteIndent;
  Writeln(OutFile, 'end;');
End;

Procedure GenSetExpression(S: TTokenSet);

Var IterTok: PTokenDecl;
  NeedComma: Boolean;
Begin
  Write(OutFile, 'MiniPigGetKind in [');
  IterTok := FirstToken;
  NeedComma := False;
  While IterTok <> Nil Do
    Begin
      If IterTok^.ID In S Then
        Begin
          If NeedComma Then Write(OutFile, ', ');
          Write(OutFile, IterTok^.Name);
          NeedComma := True;
        End;
      IterTok := IterTok^.Next;
    End;
  Write(OutFile, ']');
End;

Procedure GenInlineGroup(G: PGroup; Depth: Integer; Follow: TTokenSet);

Var 
  GrpFirst: TTokenSet;
  IterAlt: PAlt;
  BodyNullable: Boolean;
Begin
  If Depth > MAX_NESTING Then Error('Group nesting too deep');

  If G^.Quant In [qStar, qPlus] Then
    Begin
      BodyNullable := False;
      IterAlt := G^.FirstAlt;
      While IterAlt <> Nil Do
        Begin
          If IterAlt^.IsNullable Then BodyNullable := True;
          IterAlt := IterAlt^.Next;
        End;
      If BodyNullable Then
        Error('Nullable loop detected in rule "' + CurrentGenRule + '" (group ID ' + IntToStr(G^.ID)
        + '). Loop body matches empty string.');
    End;

  Case G^.Quant Of 
    qNone:
           Begin
             GenAlternativesLogic(G^.FirstAlt, Depth, Follow);
           End;

    qQMark:
            Begin
              GrpFirst := G^.FirstSet;
              WriteIndent;
              Writeln(OutFile, 'if ok then begin');
              Indent;
              WriteIndent;
              Write(OutFile, 'if ');
              GenSetExpression(GrpFirst);
              Writeln(OutFile, ' then begin');
              Indent;
              GenAlternativesLogic(G^.FirstAlt, Depth, Follow);
              Undent;
              WriteIndent;
              Writeln(OutFile, 'end;');
              Undent;
              WriteIndent;
              Writeln(OutFile, 'end;');
            End;

    qStar:
           Begin
             GrpFirst := G^.FirstSet;
             WriteIndent;
             Writeln(OutFile, 'if ok then begin');
             Indent;
             WriteIndent;
             Write(OutFile, 'while ok and (');
             GenSetExpression(GrpFirst);
             Writeln(OutFile, ') do begin');
             Indent;
             GenAlternativesLogic(G^.FirstAlt, Depth, Follow + GrpFirst);
             Undent;
             WriteIndent;
             Writeln(OutFile, 'end;');
             Undent;
             WriteIndent;
             Writeln(OutFile, 'end;');
           End;

    qPlus:
           Begin
             GenAlternativesLogic(G^.FirstAlt, Depth, Follow);
             GrpFirst := G^.FirstSet;
             WriteIndent;
             Writeln(OutFile, 'if ok then begin');
             Indent;
             WriteIndent;
             Write(OutFile, 'while ok and (');
             GenSetExpression(GrpFirst);
             Writeln(OutFile, ') do begin');
             Indent;
             GenAlternativesLogic(G^.FirstAlt, Depth, Follow + GrpFirst);
             Undent;
             WriteIndent;
             Writeln(OutFile, 'end;');
             Undent;
             WriteIndent;
             Writeln(OutFile, 'end;');
           End;
  End;

  If G^.Action <> '' Then
    Begin
      WriteIndent;
      Writeln(OutFile, 'if ok then begin');
      Indent;
      WriteIndent;
      Writeln(OutFile, Trim(G^.Action) + ';');
      Undent;
      WriteIndent;
      Writeln(OutFile, 'end;');
    End;
End;

Procedure GenRule(R: PRule);

Var FuncName: string;
Begin
  CurrentGenRule := R^.Name;
  FuncName := 'parse_' + R^.Name;
  WriteIndent;
  Writeln(OutFile, 'function ' + FuncName + ': Boolean;');
  WriteIndent;
  Writeln(OutFile, 'var ok: Boolean;');
  WriteIndent;
  Writeln(OutFile, 'begin');
  Indent;
  WriteIndent;
  Writeln(OutFile, 'ok := True;');

  If R^.FirstAlt <> Nil Then
    GenAlternativesLogic(R^.FirstAlt, 0, R^.FollowSet);

  WriteIndent;
  Writeln(OutFile, FuncName + ' := ok;');
  Undent;
  WriteIndent;
  Writeln(OutFile, 'end;');
  WriteIndent;
  Writeln(OutFile, '');
End;

Procedure GenerateFile(Const UnitName, FName: String);

Var R: PRule;
Begin
  Assign(OutFile, FName);
  Rewrite(OutFile);
  IndentLevel := 0;
  WriteIndent;
  Writeln(OutFile, '{ Generated by MiniPIG parser generator }');
  WriteIndent;
  Writeln(OutFile, '');
  If GlobalUnitStart <> '' Then
    Begin
      WriteIndent;
      Writeln(OutFile, GlobalUnitStart);
    End;
  WriteIndent;
  Writeln(OutFile, 'unit ' + UnitName + ';');
  WriteIndent;
  Writeln(OutFile, 'interface');
  WriteIndent;
  Writeln(OutFile, 'procedure InitParser;');
  WriteIndent;
  Writeln(OutFile, 'procedure DoneParser;');
  R := FirstRule;
  While R <> Nil Do
    Begin
      WriteIndent;
      Writeln(OutFile, 'function parse_' + R^.Name + ': Boolean;');
      R := R^.Next;
    End;
  WriteIndent;
  Writeln(OutFile, '');
  WriteIndent;
  Writeln(OutFile, 'implementation');
  If GlobalUses <> '' Then
    Begin
      Writeln(OutFile, '');
      WriteIndent;
      Writeln(OutFile, 'uses ' + GlobalUses + ';');
    End;
  WriteIndent;
  Writeln(OutFile, '');

  WriteIndent;
  Writeln(OutFile, 'type');
  WriteIndent;
  Writeln(OutFile, '  PString = ^String;');
  WriteIndent;
  Writeln(OutFile, '  PTokenNode = ^TTokenNode;');
  WriteIndent;
  Writeln(OutFile, '  TTokenNode = record');
  WriteIndent;
  Writeln(OutFile, '    Kind: ' + CfgTokenType + ';');
  WriteIndent;
  Writeln(OutFile, '    Val: PString;');
  WriteIndent;
  Writeln(OutFile, '    Line: Integer;');
  WriteIndent;
  Writeln(OutFile, '    Next: PTokenNode;');
  WriteIndent;
  Writeln(OutFile, '  end;');
  WriteIndent;
  Writeln(OutFile, '');
  WriteIndent;
  Writeln(OutFile, 'var MiniPigHead, MiniPigTail, MiniPigCursor: PTokenNode;');
  WriteIndent;
  Writeln(OutFile, '    SaveStack: array[0..' + IntToStr(MAX_NESTING) + '] of PTokenNode;');
  WriteIndent;
  Writeln(OutFile, '');

  WriteIndent;
  Writeln(OutFile, 'function StrToInt(const S: string): Integer;');
  WriteIndent;
  Writeln(OutFile, 'var V, Code: Integer;');
  WriteIndent;
  Writeln(OutFile, 'begin Val(S, V, Code); StrToInt := V; end;');
  WriteIndent;
  Writeln(OutFile, '');

  WriteIndent;
  Writeln(OutFile, 'procedure MiniPigEnsure;');
  WriteIndent;
  Writeln(OutFile, 'var NewNode: PTokenNode;');
  WriteIndent;
  Writeln(OutFile, 'begin');
  WriteIndent;
  Writeln(OutFile, '  if MiniPigCursor^.Next = nil then begin');
  If CfgTokenEof <> '' Then
    Begin
      WriteIndent;
      Writeln(OutFile, '    if (MiniPigTail <> MiniPigHead) and');
      WriteIndent;
      Writeln(OutFile, '       (MiniPigTail^.Kind = ' + CfgTokenEof + ') then Exit;');
    End;
  WriteIndent;
  Writeln(OutFile, '    ' + CfgTokenNext + ';');
  WriteIndent;
  Writeln(OutFile, '    New(NewNode);');
  WriteIndent;
  Writeln(OutFile, '    NewNode^.Kind := ' + CfgTokenKind + ';');
  WriteIndent;
  Writeln(OutFile, '    if ' + CfgTokenKind +
          ' in [tokIdent, tokNumber, tokString, tokCharConst] then begin');
  WriteIndent;
  Writeln(OutFile, '      New(NewNode^.Val); NewNode^.Val^ := ' + CfgTokenValue + ';');
  WriteIndent;
  Writeln(OutFile, '    end else NewNode^.Val := nil;');
  WriteIndent;
  Writeln(OutFile, '    NewNode^.Line := ' + CfgTokenLine + ';');
  WriteIndent;
  Writeln(OutFile, '    NewNode^.Next := nil;');
  WriteIndent;
  Writeln(OutFile, '    MiniPigTail^.Next := NewNode;');
  WriteIndent;
  Writeln(OutFile, '    MiniPigTail := NewNode;');
  WriteIndent;
  Writeln(OutFile, '  end;');
  WriteIndent;
  Writeln(OutFile, 'end;');
  WriteIndent;
  Writeln(OutFile, '');

  WriteIndent;
  Writeln(OutFile, 'function MiniPigMatch(K: ' + CfgTokenType + '): Boolean;');
  WriteIndent;
  Writeln(OutFile, 'begin');
  WriteIndent;
  Writeln(OutFile, '  MiniPigEnsure;');
  If CfgTokenEof <> '' Then
    Begin
      WriteIndent;
      Writeln(OutFile, '  if MiniPigCursor^.Next = nil then begin');
      WriteIndent;
      Writeln(OutFile, '    if K = ' + CfgTokenEof + ' then MiniPigMatch := True');
      WriteIndent;
      Writeln(OutFile, '    else MiniPigMatch := False;');
      WriteIndent;
      Writeln(OutFile, '    Exit;');
      WriteIndent;
      Writeln(OutFile, '  end;');
    End;
  WriteIndent;
  Writeln(OutFile, '  if MiniPigCursor^.Next^.Kind = K then begin');
  WriteIndent;
  Writeln(OutFile, '    MiniPigCursor := MiniPigCursor^.Next;');
  WriteIndent;
  Writeln(OutFile, '    MiniPigMatch := True;');
  WriteIndent;
  Writeln(OutFile, '  end else MiniPigMatch := False;');
  WriteIndent;
  Writeln(OutFile, 'end;');
  WriteIndent;
  Writeln(OutFile, '');

  WriteIndent;
  Writeln(OutFile, 'function MiniPigGetKind: ' + CfgTokenType + ';');
  WriteIndent;
  Writeln(OutFile, 'begin');
  WriteIndent;
  Writeln(OutFile, '  MiniPigEnsure;');
  If CfgTokenEof <> '' Then
    Begin
      WriteIndent;
      Writeln(OutFile, '  if MiniPigCursor^.Next = nil then');
      WriteIndent;
      Writeln(OutFile, '    MiniPigGetKind := ' + CfgTokenEof);
      WriteIndent;
      Writeln(OutFile, '  else MiniPigGetKind := MiniPigCursor^.Next^.Kind;');
    End
  Else
    Begin
      WriteIndent;
      Writeln(OutFile, '  MiniPigGetKind := MiniPigCursor^.Next^.Kind;');
    End;
  WriteIndent;
  Writeln(OutFile, 'end;');
  WriteIndent;
  Writeln(OutFile, '');

  WriteIndent;
  Writeln(OutFile, 'function MiniPigGetVal: String;');
  WriteIndent;
  Writeln(OutFile, 'begin');
  WriteIndent;
  Writeln(OutFile, '  if (MiniPigCursor <> MiniPigHead) and (MiniPigCursor^.Val <> nil) then');
  WriteIndent;
  Writeln(OutFile, '    MiniPigGetVal := MiniPigCursor^.Val^ else MiniPigGetVal := '''';');
  WriteIndent;
  Writeln(OutFile, 'end;');
  WriteIndent;
  Writeln(OutFile, '');

  WriteIndent;
  Writeln(OutFile, 'procedure InitParser;');
  WriteIndent;
  Writeln(OutFile, 'begin');
  WriteIndent;
  Writeln(OutFile, '  New(MiniPigHead); MiniPigHead^.Next := nil; MiniPigHead^.Val := nil;');
  WriteIndent;
  Writeln(OutFile, '  MiniPigTail := MiniPigHead; MiniPigCursor := MiniPigHead;');
  WriteIndent;
  Writeln(OutFile, 'end;');
  WriteIndent;
  Writeln(OutFile, '');

  WriteIndent;
  Writeln(OutFile, 'procedure DoneParser;');
  WriteIndent;
  Writeln(OutFile, 'var P, T: PTokenNode;');
  WriteIndent;
  Writeln(OutFile, 'begin');
  WriteIndent;
  Writeln(OutFile, '  P := MiniPigHead;');
  WriteIndent;
  Writeln(OutFile, '  while P <> nil do begin');
  WriteIndent;
  Writeln(OutFile, '    T := P; P := P^.Next;');
  WriteIndent;
  Writeln(OutFile, '    if T^.Val <> nil then Dispose(T^.Val); Dispose(T);');
  WriteIndent;
  Writeln(OutFile, '  end; MiniPigHead := nil;');
  WriteIndent;
  Writeln(OutFile, 'end;');
  WriteIndent;
  Writeln(OutFile, '');

  R := FirstRule;
  While R <> Nil Do
    Begin
      GenRule(R);
      R := R^.Next;
    End;
  WriteIndent;
  Writeln(OutFile, 'end.');
  Close(OutFile);
End;

Function BaseName(s: String): STRING;

Var i: INTEGER;
Begin
  For i := Length(s) Downto 1 Do
    If s[i] In ['\', '/', ':'] Then
      Begin
        BaseName := Copy(s, i + 1, 255);
        EXIT;
      End;
  BaseName := s;
End;

Function ChangeFileExt(Const old_name, ext: String): string;

Var dotPos, i: integer;
Begin
  dotPos := 0;
  i := Length(old_name);
  While i >= 1 Do
    Begin
      If old_name[i] = '.' Then
        Begin
          dotPos := i;
          break;
        End;
      dec(i);
    End;
  If dotPos > 0 Then ChangeFileExt := Copy(old_name, 1, dotPos - 1) + ext
  Else ChangeFileExt := old_name + ext;
End;

procedure MiniPigReset;
begin
  FirstToken := Nil;
  FirstRule := Nil;
  FirstGroup := Nil;
  GroupIDCounter := 0;
  TokenCounter := 0;
  GlobalUnitStart := '';
  CfgTokenType := 'TTokenKind';
  CfgTokenNext := 'NextToken';
  CfgTokenKind := 'CurrToken';
  CfgTokenValue := 'CurrTokenVal';
  CfgTokenLine := 'CurrLine';
  CfgTokenEof := '';
  CurrentProcessingRule := '';
end;

Var SrcName, DstName: string;
  InF: File;
  R: PRule;
  i : Integer;
Begin
  Writeln('MiniPIG - Strict LL(1) Parser Generator for TP.');
  Writeln('Copyright (c) 2026 by DosWorld, GNU GPLv3 License, https://github.com/DosWorld/');
  If ParamCount <> 1 Then
    Begin
      Writeln;
      Writeln('Usage: ');
      Writeln(#9, BaseName(ParamStr(0)), ' grammar.txt');
      Halt(1);
    End;
  MiniPigReset;
  SrcName := ParamStr(1);
  DstName := ChangeFileExt(SrcName, '.pas');
  Assign(InF, SrcName);
  {$I-}Reset(InF, 1); i := IOResult; {$I+}
  If i <> 0 Then
    Begin
      Writeln('Cannot read ', SrcName);
      Halt(1);
    End;
  If FileSize(inf) > 65520 Then
    Begin
      Writeln('Grammar too big');
      Halt(1);
    End;

  BufferLen := FileSize(inf);
  GetMem(GrammarBuffer, Word(BufferLen) + 1);
  BlockRead(inf, GrammarBuffer^, Word(BufferLen));
  Close(InF);
  GrammarBuffer[BufferLen] := #0;
  Cursor := 1;
  LineNum := 1;

  ParseGrammar;
  ResolveReferences;
  EofTokenID := GetTokenID(CfgTokenEof);
  ComputeAnalysis;
  ComputeFollow;

  R := FirstRule;
  While R <> Nil Do
    Begin
      CurrentProcessingRule := R^.Name;
      CheckRecursion(R);
      R := R^.Next;
    End;
  CurrentProcessingRule := '';

  Writeln('Generating ', BaseName(DstName));
  GenerateFile(BaseName(ChangeFileExt(SrcName, '')), DstName);
  FreeMem(GrammarBuffer, Word(BufferLen) + 1);
End.


