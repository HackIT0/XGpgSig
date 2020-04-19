program XGpgSig;

{$APPTYPE CONSOLE}

uses
  Windows,
  Messages,
  SysUtils,
  Classes,
  Graphics,
  Controls,
  Forms,
  ExtCtrls,
  ShellAPI,
  iniFiles,
  oneonly in 'oneonly.pas';

{$R *.res}

const
  Trenner           = '//--------------------------------------------------------------------------------------------------------------------';
  X_PGP_SIG         = 'X-PGP-Sig:';
  X_SIGNED_HEADERS  = 'X-Signed-Headers:';

  //HEADERNAMES       = ':Subject:Control:Message-ID:Date:From:Sender:Newsgroups:'
  //                  + 'Approved:Followup-To:Supersedes:';

  BEGIN_PGP_SIG_MSG = '-----BEGIN PGP SIGNED MESSAGE-----';
  BEGIN_PGP_SIG     = '-----BEGIN PGP SIGNATURE-----';
  END_PGP_SIG       = '-----END PGP SIGNATURE-----';
  BEGIN_PGP_MSG     = '-----BEGIN PGP MESSAGE-----';

  CRLF              = #13#10;
var
  AppPath, PgpPath : String;
  FileIn, FileOut  : String;
  TempIn, TempOut  : String;
  Signer           : String;
  HEADERNAMES      : String;       // Selected Header for Signature
  RunGPG           : String;       // Parameter for Startup (Signature) GPG2.EXE
  GnuPG            : String;       // full Patch to GPG2.EXE
  KillTmp          : Boolean;      // Remove the internal Tempfiles - Default: YES
  Passphrase       : String;       // Passphrase for private Key
  wtimer           : Integer;      // Waiting period [ms] before sending the Passphrase
  ShowGPG          : Boolean;      // Show GPG-Window with Sign
  SigHash          : String;       // digest algorithm
  LogBadSig,
  LogGoodSig       : Boolean;       // Logeinträge
//---------------------------------------------------------------------------------------
function FindHdr( TS: TStrings; HdrName: String ) : Integer;
var  i : Integer;
begin
     Result := -1;

     for i:=0 to TS.Count-1 do begin
        if TS[i]='' then break; // end of header
        if Pos( Lowercase(HdrName), Lowercase(TS[i]) )=1 then begin
           Result := i;
           break;
        end;
     end;
end;

function FindTxt( TS: TStrings; HdrName: String ) : Integer;
var  i : Integer;
begin
     Result := -1;

     for i:=0 to TS.Count-1 do begin
        if Pos( Lowercase(HdrName), Lowercase(TS[i]) )=1 then begin
           Result := i;
           break;
        end;
     end;
end;

function HasLeadingWhSp( s : String ) : Boolean;
begin
     Result := False;
     if s='' then exit;
     if s[1]=' ' then Result:=True;
     if s[1]=#9  then Result:=True;
end;

function HasTrailingWhSp( s : String ) : Boolean;
begin
     Result := False;
     if s='' then exit;
     if s[length(s)]=' ' then Result:=True;
     if s[length(s)]=#9  then Result:=True;
end;

function TrimWhSp( s : String ) : String;
begin
     while HasLeadingWhSp(s)  do System.Delete(s,1,1);
     while HasTrailingWhSp(s) do System.Delete(s,length(s),1);
     Result := s;
end;

function PosWhSp( s : String ) : Integer;
var  i : Integer;
begin
     Result := Pos( ' ', s );
     i := Pos( #9, s );
     if i=0 then exit;
     if Result=0 then begin Result:=i; exit; end;
     if i<Result then Result:=i;
end;
//---------------------------------------------------------------------------------------
procedure ShowError( ErrMsg: String );
var  ErrName: String;
     ErrLog: Textfile;
begin
     // writeln( #13#10, '[XGpgSig] Error: ' + ErrMsg );

     try
        ErrName := ExtractFilePath( ParamStr(0) ) + 'XGpgSig.log';
        Assign( ErrLog, ErrName );
        if FileExists(ErrName) then Append(ErrLog) else Rewrite(ErrLog);
        If ErrMsg<>Trenner
        Then
            writeln( ErrLog, DateTimeToStr(Now) + ' ' + ErrMsg )
        Else
            writeln( ErrLog, ErrMsg );

        Close( ErrLog );
     except
        ;
     end;

end;
//----------------------------------------------------------------------------------------------

function WinExecAndWait(FileName:String; Visibility : integer):DWord;
var zAppName    : array[0..512] of char;
    zCurDir     : array[0..255] of char;
    WorkDir     : String;
    StartupInfo : TStartupInfo;
    ProcessInfo : TProcessInformation;
begin
  StrPCopy(zAppName,FileName);
  GetDir(0,WorkDir);
  StrPCopy(zCurDir,WorkDir);
  FillChar(StartupInfo,Sizeof(StartupInfo),#0);
  StartupInfo.cb := Sizeof(StartupInfo);
  StartupInfo.dwFlags := STARTF_USESHOWWINDOW;
  StartupInfo.wShowWindow := Visibility;
  if not CreateProcess(nil,
    zAppName,                      // Kommandozeile
    nil,                           // Zeiger auf Sicherheitsattribute Prozess
    nil,                           // Zeiger auf Sicherheitsattribute Thread
    false,                         // Behandlung Flag inheritance
    CREATE_NEW_CONSOLE or          // Create-Flags
    NORMAL_PRIORITY_CLASS,
    nil,                           // Zeiger auf Environment-Block
    nil,                           // Zeiger auf aktuelles Verzeichnis
    StartupInfo,                   // Startinformationen
    ProcessInfo) then Result := 1 // Prozessinformationen

  else begin
    WaitforSingleObject(ProcessInfo.hProcess,INFINITE);
    GetExitCodeProcess(ProcessInfo.hProcess,Result);
  end;
end;

//------------------------------------------------------------------------------------------------------
function ExecConsole(const ACommand: String;
                     var AOutput, AErrors: String;
                     var AExitCode: Cardinal): Boolean;
  var
    StartupInfo: TStartupInfo;
    ProcessInfo: TProcessInformation;
    SecurityAttr: TSecurityAttributes;
    PipeOutputRead, PipeOutputWrite,
    PipeErrorsRead, PipeErrorsWrite: THandle;

  // Pipe in einen String auslesen (speicherschonend)
  procedure ReadPipeToString(const hPipe: THandle; var Result: String);
    const
      MEM_CHUNK_SIZE = 32768; // Blockgröße, mit der Speicher angefordert wird
    var
      NumberOfBytesRead,
      NumberOfBytesTotal: Cardinal;
  begin
    Result := ''; // Standard-Ergebnis
    NumberOfBytesTotal := 0; // noch nichts gelesen
    repeat
      SetLength(Result,Length(Result) +MEM_CHUNK_SIZE); // mehr Platz machen
      // versuchen, aus der Pipe zu lesen
      if ReadFile(hPipe,(@Result[1+NumberOfBytesTotal])^,MEM_CHUNK_SIZE,
                  NumberOfBytesRead,NIL) then // hat geklappt
        Inc(NumberOfBytesTotal,NumberOfBytesRead); // Gesamtanzahl aktualisieren
      SetLength(Result,NumberOfBytesTotal); // überzählige Bytes abschneiden
    until (NumberOfBytesRead = 0); // bis die Pipe leer ist
  end;

begin
  // Win-API-Strukturen initialisieren/füllen
  FillChar(ProcessInfo,SizeOf(TProcessInformation),0);
  FillChar(SecurityAttr,SizeOf(TSecurityAttributes),0);
  SecurityAttr.nLength := SizeOf(SecurityAttr);
  SecurityAttr.bInheritHandle := TRUE;
  SecurityAttr.lpSecurityDescriptor := NIL;
  CreatePipe(PipeOutputRead,PipeOutputWrite,@SecurityAttr,0);
  CreatePipe(PipeErrorsRead,PipeErrorsWrite,@SecurityAttr,0);
  FillChar(StartupInfo,SizeOf(TStartupInfo),0);
  StartupInfo.cb := SizeOf(StartupInfo);
  StartupInfo.hStdInput := 0;
  StartupInfo.hStdOutput := PipeOutputWrite;
  StartupInfo.hStdError := PipeErrorsWrite;
  StartupInfo.wShowWindow := SW_HIDE;
  StartupInfo.dwFlags := STARTF_USESHOWWINDOW or STARTF_USESTDHANDLES;
  // http://msdn2.microsoft.com/en-us/library/ms682425.aspx
  Result := CreateProcess(NIL,PChar(ACommand),NIL,NIL,TRUE,
                          CREATE_DEFAULT_ERROR_MODE
                          or CREATE_NEW_CONSOLE
                          or NORMAL_PRIORITY_CLASS,
                          NIL,NIL,StartupInfo,ProcessInfo);
  // Write-Pipes schließen
  CloseHandle(PipeOutputWrite);
  CloseHandle(PipeErrorsWrite);
  if (Result) then begin // konnte der Befehl ausgeführt werden?
    ReadPipeToString(PipeOutputRead,AOutput); // Ausgabe-Read-Pipe auslesen
    ReadPipeToString(PipeErrorsRead,AErrors); // Fehler-Read-Pipe auslesen
    WaitForSingleObject(ProcessInfo.hProcess,INFINITE); // auf Prozessende warten
    GetExitCodeProcess(ProcessInfo.hProcess,AExitCode); // http://msdn2.microsoft.com/en-us/library/ms683189.aspx
    CloseHandle(ProcessInfo.hProcess); // und Handle freigeben
  end;
  // Read-Pipes schließen
  CloseHandle(PipeOutputRead);
  CloseHandle(PipeErrorsRead);
end;
//------------------------------------------------------------------------------------------------------
function ConvertCharacters(aString, FromStr, ToStr: AnsiString): AnsiString;
var
   I: Integer;
begin
  // check whether string are equal
   if FromStr = ToStr then
   begin
      Result := aString;
      Exit;
   end;
   Result := '';
  // find fromstr
   I := Pos(FromStr, aString);
   while I > 0 do
   begin
    // copy all characters prior fromstr
      if I > 1 then
         Result := Result + Copy(aString, 1, I - 1);
    // append tostr
      Result := Result + ToStr;
    // delete all until after fromstr
      Delete(aString, 1, I + Length(FromStr) - 1);
    // find next fromstr
      I := Pos(FromStr, aString);
   end;
   Result := Result + aString;
end;
//--------------------------------------------------------------------------------
function ASCII2ANSI(AText:string):string;
const MaxLength = 255;
var PText : PChar;
begin
  PText:=StrAlloc(MaxLength);
  StrPCopy(PText,AText);
  {$IFDEF WIN32}
  OEMToChar(PText,PText); {32Bit}
  {$ELSE}
  OEMToAnsi(PText,PText); {16Bit}
  {$ENDIF}
  Result:=StrPas(PText);
  StrDispose(PText);
end;
//------------------------------------------------------------------------------
procedure ConvertMsgToSign;
var  TempTxt, SigHdr : String;
     s, h            : String;
     i, j            : Integer;
     EndOfHdr        : Boolean;
     MsgLines        : TStringList;
begin
     MsgLines := TStringList.Create;
     MsgLines.LoadFromFile(FileIn);

     EndOfHdr := False;
     TempTxt  := '';
     SigHdr   := '';
     HEADERNAMES := '::' + HEADERNAMES;
     i := 0;

     while i<MsgLines.Count do begin
        s := MsgLines[i];
        if s='' then EndOfHdr:=True;

        if EndOfHdr then begin
           TempTxt := TempTxt + s + CRLF;
        end else begin
           j := Pos( ':', s );
           h := copy( s, 1, j );
           j := Pos( ':' + h, HEADERNAMES );
           if j>1 then begin
              if SigHdr<>'' then SigHdr := SigHdr + ',';
              SigHdr  := SigHdr + copy( h, 1, length(h)-1 );
              TempTxt := TempTxt + s + CRLF;
           end;
        end;

        inc( i );
     end;
     MsgLines.Clear;
     MsgLines.Text:= X_SIGNED_HEADERS + ' ' + SigHdr + CRLF + TempTxt + CRLF;
     MsgLines.SaveToFile( TempIn );
     MsgLines.Free;
end;

//----------------------------------------------------------------------------------------
procedure PgpSignMessage;
var  s,t        : String;
     r          : Integer;
     MsgLines   : TStringList;
begin
     MsgLines := TStringList.Create;
     DeleteFile( TempOut );
     IF (ShowGPG=FALSE) and (Passphrase='') then ShowGPG:=TRUE;

     s := ' ' + Trim(RunGPG) + ' ';
     IF Signer  <>'' then s := s + '-u ' + Signer + ' ';
     IF SigHash <>'' then s := s + '--digest-algo ' + SigHash + ' ';
     IF Passphrase<>'' then s := s + '--passphrase ' + Passphrase + ' ';

     t:= PgpPath  + s + '--clearsign ' + chr(34) + TempIn + chr(34);

     IF ShowGPG=TRUE  then r:=WinExecAndWait(t,1);
     IF (ShowGPG=FALSE) and (Passphrase<>'')  then r:=WinExecAndWait(t,0);
     ExitCode:= r;


     if FileExists( TempOut ) then begin
        MsgLines.LoadFromFile( TempOut );
        if MsgLines[0]=BEGIN_PGP_SIG_MSG then begin
           //Result := MsgLines.Text; // OK
        end else begin
           if MsgLines[0]=BEGIN_PGP_MSG then begin
              ShowError( 'GPG-call failed! PGP treated text as binary, ' +
                         'maybe due to a [very] long line of text.' );
           end else begin
              ShowError( 'GPG-call failed! Exitcode=' + inttostr(r) +
                       '; First line="' + MsgLines[0] + '"' );
           end;
        end;
     end else begin
        ShowError( 'GPG-call failed! Exitcode=' + inttostr(r));
     end;

MsgLines.Free;
end;


//---------------------------------------------------------------------------------------------

procedure ConvertPgpToXPgpSig;
var  SigHdr         : String;
     PgpVer, PgpSig : String;
     MsgPart, i, j  : Integer;
     MsgLines       : TStringList;

begin

     MsgLines := TStringList.Create;

     if FileExists(TempOut)=False then EXIT;
     MsgLines.LoadFromFile(TempOut);

     j := FindTxt( MsgLines, X_SIGNED_HEADERS );
     if j>=0 then begin
        SigHdr := TrimWhSp( copy( MsgLines[j], length(X_SIGNED_HEADERS) + 1, 255 ) );
     end;

     if SigHdr='' then begin MsgLines.Free; exit; end;
     SigHdr:=ConvertCharacters(SigHdr,' ','_');

     // get PGP-version and -signature

     PgpVer  := 'unknown';
     PgpSig  := '';
     MsgPart := 0;


     for i:=0 to MsgLines.Count-1 do begin
        if MsgPart=0 then begin
           if MsgLines[i]=BEGIN_PGP_SIG then MsgPart:=1;
        end else begin
           if MsgPart=1 then begin
              if Pos( 'version:', LowerCase(MsgLines[i]) )=1 then begin
                 PgpVer := TrimWhSp( copy( MsgLines[i], 9, 255 ) );
              end;
              if MsgLines[i]='' then MsgPart:=2;
           end else begin
              if MsgLines[i]=END_PGP_SIG then break;
              if MsgLines[i]<>'' then begin
                 if PgpSig<>'' then PgpSig := PgpSig + CRLF;
                 PgpSig := PgpSig + #9 + MsgLines[i];
              end;
           end;
        end;
     end;

     if PgpSig='' then begin MsgLines.Free; exit; end;
     PgpVer:= ConvertCharacters(PgpVer,' ','_');

     // add "X-PGP-Sig:"-header to original message

     MsgLines.LoadFromFile(FileIn);
     for i:=0 to MsgLines.Count-1 do begin
        if MsgLines[i]='' then begin
           MsgLines.Insert(  i , X_PGP_SIG + ' ' + PgpVer + ' ' + SigHdr );
           MsgLines.Insert( i+1, PgpSig );
           MsgLines.Insert( i+2,'X-PGP-Hash: ' + SigHash);
           break;
        end;
     end;

     MsgLines.SaveToFile(FileOut);
     MsgLines.Free;
end;

//------------------------------------------------------------------------------------------
procedure ConvertXPgpSigToPgp;
var  NewTxt, NewSig : String;
     SigVer, SigHdr : String;
     Txt            : String;
     i, k           : Integer;
     MsgLines       : TStringList;
begin


     MsgLines := TStringList.Create;


     MsgLines.LoadFromFile(FileIn); 

     k := FindHdr( MsgLines, X_PGP_SIG ); // "X-PGP-Sig:"?
     if k<0 then begin
        ShowError( 'No "X-PGP-Sig:"-header found!' );
        MsgLines.Free;
        exit;
     end;

     i := FindHdr( MsgLines, 'X-PGP-Hash:');  // "X-PGP-Hash"?
     if i>=0 then begin                       // Extract from Header
        txt := MsgLines[i];
        System.Delete( txt, 1, Length('X-PGP-Hash:') );
        SigHash:=Trim(txt);
     end;  

     // convert PGP-signature

     NewSig := '';

     Txt := MsgLines[k];
     System.Delete( Txt, 1, Length(X_PGP_SIG) );
     while HasLeadingWhSp(Txt) do System.Delete(Txt,1,1);

     i := PosWhSp( Txt );
     SigVer := copy( Txt, 1, i-1 );

     System.Delete( Txt, 1, i );
     while HasLeadingWhSp(Txt) do System.Delete(Txt,1,1);
     SigHdr := Txt;

     NewSig := NewSig + CRLF;
     NewSig := NewSig + BEGIN_PGP_SIG + CRLF;
     NewSig := NewSig + 'Version: ' + SigVer + CRLF;
     //NewSig := NewSig + 'Charset: latin1'  + CRLF; // <- wg. DOS-PGP ergänzt
     NewSig := NewSig + CRLF;

     while HasLeadingWhSp(MsgLines[k+1]) do begin
        inc( k );
        Txt := MsgLines[k];
        while HasLeadingWhSp(Txt) do System.Delete(Txt,1,1);
        NewSig := NewSig + Txt + CRLF;
     end;

     NewSig := NewSig + END_PGP_SIG + CRLF;

     // create PGP-signed message

     NewTxt := '';

     NewTxt := NewTxt + BEGIN_PGP_SIG_MSG + CRLF;

     If SigHash<>'MD5' then begin
     NewTxt := NewTxt + 'Hash: ' + SigHash + CRLF;
     end;
     
     NewTxt := NewTxt + CRLF;
     NewTxt := NewTxt + X_SIGNED_HEADERS + ' ' + SigHdr + CRLF;

     while SigHdr<>'' do begin
        i := Pos( ',', SigHdr );
        if i=0 then begin
           Txt := SigHdr;
           SigHdr := '';
        end else begin
           Txt := copy( SigHdr, 1, i-1 );
           System.Delete( SigHdr, 1, i );
        end;

        k := FindHdr( MsgLines, Txt );
        if k>=0 then NewTxt := NewTxt + MsgLines[k] + CRLF
                else NewTxt := NewTxt + Txt + ': ' + CRLF;
     end;

     NewTxt := NewTxt + CRLF; // end of headers

     k := 0; // find end of headers
     while MsgLines[k]<>'' do inc(k);

     for i:=k+1 to MsgLines.Count-1 do begin // append body
        Txt := MsgLines[i];
        if copy(Txt,1,1)='-' then Txt := '- ' + Txt; // quote dashes
        NewTxt := NewTxt + Txt + CRLF;
     end;


     MsgLines.Clear;
     MsgLines.Text:= NewTxt + NewSig;
     MsgLines.SaveToFile(TempIn + '.asc');
     MsgLines.Free;
end;

//-------------------------------------------------------------------------------------
procedure PgpVerifyMessage;
var  MsgLines : TStringList;
     i        : Integer;
     s        : String;
     Output, Errors : String;
     RC        : Cardinal;
     InfoLines : TStringList;
     Mid       : String;
begin
     MsgLines := TStringList.Create;
     InfoLines:= TStringList.Create;

     DeleteFile( TempIn );
     s:= PgpPath + ' --digest-algo ' + SigHash + ' '  + chr(34) + TempIn + '.asc' + chr(34) ;
     
try
   ExecConsole(s,Output,Errors,RC);
  finally

  end;

ExitCode:= RC;

InfoLines.Text:= ASCII2ANSI(Errors);
IF RC >0 then begin
MsgLines.LoadFromFile(FileIn);
If LogBadSig=True Then
Begin
    for i:=0 to MsgLines.Count-1 do begin
        if Pos('Message-ID:',MsgLines[i])=1 then
         begin
           Mid:=MsgLines[i];
           break;
        end;
     end;
    ShowError('[Verify-Error] ' + InfoLines.Strings[0]);
    ShowError('[Verify-Error] ' + InfoLines.Strings[1]);
    ShowError('[Verify-Error] ' + Mid);
    ShowError(Trenner);
End;


     for i:=0 to MsgLines.Count-1 do begin
        if MsgLines[i]='' then begin
           MsgLines.Insert(  i , 'X-PGP-CHECK: Bad Sig :-(');
           break;
        end;
     end;

     MsgLines.SaveToFile(FileOut);
     MsgLines.Free;
     InfoLines.Free;
     EXIT;
end;
      // add "X-PGP-CHECK:"-header to original message
     MsgLines.LoadFromFile(FileIn);
     for i:=0 to MsgLines.Count-1 do begin
        if MsgLines[i]='' then begin
           MsgLines.Insert(  i , 'X-PGP-CHECK: Good Sig :-)');
            // + Copy(InfoLines.Strings[0],6,255) +CRLF + #9 + Copy(InfoLines.Strings[1],6,255)  );
           If LogGoodSig=True Then
           Begin
                  ShowError('X-PGP-CHECK: ' + Copy(InfoLines.Strings[0],6,255) );
                  ShowError('X-PGP-CHECK: ' + Copy(InfoLines.Strings[1],6,255) );
                  ShowError(Trenner);
           end;
           break;
        end;
     end;

     MsgLines.SaveToFile(FileOut);
     MsgLines.Free;
     InfoLines.Free;
 end;
 // ------------------------------------------------------------------------------------
procedure GoSign;
begin
// ConvertMsgToSign: Filein (Orginal) -> TempIn
ConvertMsgToSign;
// PgpSignMessage: Tempin -> Tempout
PgpSignMessage;
// ConvertPgpToXPgpSig: TempOut -> FileOut
ConvertPgpToXPgpSig;
end;
// --------------------------------------------------------------------------------------------

procedure TSign;
begin
//ConvertXPgpSigToPgp: Filein (Orginal) -> TempIn
ConvertXPgpSigToPgp;
//PgpVerifyMessage: TempIn
PgpVerifyMessage;
end;

//-----------------------------------------------------------------------------------------
procedure ReadINI;
var
ini      : TInifile;
INIPatch : String;
FExist   : Boolean;

begin
INIPatch    := ExtractFilePath(ParamStr(0)) + 'XGpgSig.ini';
FExist      := FileExists(INIPatch);

if FExist=True then begin
   // File "XGpgSig.ini" found and read
   ini:=TIniFile.Create(INIPatch);
   HEADERNAMES := ini.ReadString('XGpgSig','SigHeader',':Subject:Control:Message-ID:Date:From:Sender:Newsgroups:Approved:Followup-To:Supersedes:');
   RunGPG      := ini.ReadString('XGpgSig','RunGPG','--batch --no-comments');
   GnuPG       := ini.ReadString('XGpgSig','GnuPG','');
   SigHash     := ini.ReadString('XGpgSig','SigHash','');
   KillTmp     := ini.ReadBool  ('XGpgSig','KillTmp',TRUE);
   wtimer      := ini.ReadInteger('XGpgSig','PWait',300);
   ShowGPG     := ini.ReadBool('XGpgSig','ShowGPG',True);
   LogBadSig   := ini.ReadBool('Log','LogBadSig',True);
   LogGoodSig  := ini.ReadBool('Log','LogGoodSig',True);
   Passphrase  := ini.ReadString('PW','Passwort','XGpgSig');
   Signer      := ini.ReadString('PW','KeyID','') ;
   ini.Free;
   end;

If FExist=False then begin
   // File "XGpgSig.ini" not found - Set Defaults
   HEADERNAMES :=':Subject:Control:Message-ID:Date:From:Sender:Newsgroups:Approved:Followup-To:Supersedes:';
   RunGPG      :='--batch --no-comments';
   KillTmp     := True;
   wtimer      := 300;
   ShowGPG     := TRUE;
   SigHash     := 'MD5';
   LogBadSig   := True;
   LogGoodSig  := True;
   Passphrase  := 'XGpgSig';
   end;

end;

//------------------------------------------------------------------------------------------

procedure FuncHelp;
begin
     writeln;
     writeln( 'XGpgSig Version 0.1.0.0' );
     writeln( 'From Orginal: XPgpSig Vr. 1.1, http://www.elbiah.de');
     writeln;
     writeln( 'Usage:        XGpgSig function [options]' );
     writeln;
     writeln( 'Functions:' );
     writeln( '  help / ?    Show this help-text.' );
     writeln( '  verify      Verify message with "X-PGP-Sig:"-header.' );
     writeln( '  sign        Sign message with a "X-PGP-Sig:"-header.' );
     writeln;
     writeln( 'Options:' );
     writeln( '  -iFilename  Input-file;  default=XPgpSig.in' );
     writeln( '  -oFilename  Output-file; default=XPgpSig.out' );
     writeln( '  -pPathname  Path to GPG2.EXE' );
     writeln( '  -sSigner    User-ID to use for signing the message with "sign"-function.' );
     writeln( '  -k<Pass>    Send Password to use for Signing' );
     writeln( '  -h<name>    Digest Algorithm used for Signing and Verify');
     writeln;
     writeln( 'Examples:' );
     writeln( '  xpgpsig verify -iC:\Temp\Test.msg -oC:\Temp\Output.msg' );
     writeln( '  xpgpsig sign -iC:\Temp\Input.msg -oC:\Temp\Output.msg -pC:\GnuPG\ -sMeMyselfI' );
     writeln( '  xpgpsig sign -iC:\Temp\Input.msg -oC:\Temp\Output.msg' );

end;

const
  ValidFunctions = '|?|help|sign|verify|';

var
  WhatToDo : String;
  s,s2       : String;
  i        : Integer;
  MsgLines : TStringList;


begin


     ExitCode := 100;
     // get function
     if ParamCount<1 then begin
        WhatToDo := '?';
     end else begin
        WhatToDo := LowerCase( ParamStr(1) );
        if WhatToDo[1] in ['-','/'] then System.Delete( WhatToDo, 1, 1 );
        if Pos( '|'+WhatToDo+'|', ValidFunctions )=0 then begin
           ShowError( 'Invalid function "' + ParamStr(1) + '"!' );
           halt(255);
        end;
     end;

     // get options
     PgpPath    := '';
     FileIn     := '';
     FileOut    := '';
     Signer     := '';
     Passphrase := '';
     SigHash    := '';
     ReadINI;  // Voreingestellte Werte - werden vom Script überschrieben.
     I:=ParamCount;
     Repeat
        s := LowerCase( ParamStr(i) );
        s2:=s[1]+s[2];
        If s2='-i' Then FileIn  := copy( ParamStr(i), 3, 255 );
        If s2='-o' Then FileOut := copy( ParamStr(i), 3, 255 );
        If s2='-p' Then PgpPath := copy( ParamStr(i), 3, 255 );
        if s2='-s' Then Signer  := copy( ParamStr(i), 3, 255 );
        if s2='-h' Then SigHash := copy( ParamStr(i), 3, 255 );
        if s2='-k' Then Passphrase  := copy( ParamStr(i), 3, 255 ) ;
     I:=I-1;
     Until I=1;

     If FileExists(FileIn) Then FileIn  := ExtractShortPathName(FileIn);
                                                       // Read INI-File
     MsgLines := TStringList.Create  ;                  // Check - '--pgp2'
     MsgLines.Add(RunGPG);
     i:= FindTxt(MsgLines,'--pgp2');
     IF i >=0 then SigHash:= 'MD5';
     MsgLines.Free;

     // check options; use defaults if not set
     AppPath := GetCurrentDir;
     if copy(AppPath,length(AppPath),1)<>'\' then AppPath:=AppPath+'\';


     if PgpPath='' then PgpPath := GnuPG;
     if copy(PgpPath,length(PgpPath),1)<>'\' then PgpPath:=PgpPath+'\';
     PgpPath:= PgpPath + 'gpg2.exe';

     if FileIn ='' then FileIn  := AppPath + 'XPgpSig.in';
     if FileOut='' then FileOut := AppPath + 'XPgpSig.out';

     // init temporary files used for pgp-calls
     TempIn  := ExtractFilePath(FileIn) + 'XPgpSig.$$i';
     TempOut := ExtractFilePath(FileOut) + 'XPgpSig.$$i.asc';

     // execute functions
     if WhatToDo='?'        then FuncHelp;
     if WhatToDo='help'     then FuncHelp;
     if WhatToDo='verify'   then TSign;
     //if WhatToDo='xsig2pgp' then FuncVerify( False );
     if WhatToDo='sign'     then GoSign;
     //if WhatToDo='msg2sign' then FuncSign( True,  False, False );
     //if WhatToDo='pgp2xsig' then FuncSign( False, False, True  );

     // remove temporary files
     IF KillTmp=True then begin
        DeleteFile( TempIn  );
        DeleteFile( TempOut );
        end;

end.
 
