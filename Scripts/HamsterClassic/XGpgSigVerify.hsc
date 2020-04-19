#!hs2
#!load hamster.hsm
var( $XSig, $msg )
$msg = ArtAlloc
ArtLoad( $msg, paramstr(2) )

if( ArtHeaderExists( $msg, "X-PGP-Sig" ) )
    $XSig="E:\Programme\XGpgSig\XGpgSig.exe verify -i" + paramstr(2) + " -o" + paramstr(2)
    execute( $XSig, "E:\Programme\XGpgSig\", 0, true )
endif

ArtFree( $msg )
quit