#!hs2
#!load hamster.hsm
var($msg,$XSig )
HamWaitIdle
$msg = ArtAlloc
ArtLoad( $msg, paramstr(2) )
If ArtHeaderExists( $msg, "X-PGP-Sig"  ) 
 ArtDelHeader( $msg, "X-PGP-Sig" )
endif
If ArtHeaderExists( $msg, "X-PGP-Hash"  )
 ArtDelHeader( $msg, "X-PGP-Hash" )
endif
If ArtHeaderExists( $msg, "X-PGP-CHECK"  )
 ArtDelHeader( $msg, "X-PGP-CHECK" )
endif
ArtSave( $msg, paramstr(2) )
ArtFree( $msg )

$XSig="E:\Programme\XGpgSig\XGpgSig.exe sign -i" + paramstr(2) + " -o" + paramstr(2)
execute( $XSig, "E:\Programme\XGpgSig\", 0, True)

Quit
