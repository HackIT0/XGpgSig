unit oneonly;

interface

implementation

uses windows,Dialogs,sysutils;

var mHandle: THandle;    // Mutexhandle

Initialization

  mHandle := CreateMutex(nil,True,'XGpgSig.exe');
  if GetLastError = ERROR_ALREADY_EXISTS then begin
    Halt;
  end;
finalization  
  if mHandle <> 0 then
    CloseHandle(mHandle)
end.
