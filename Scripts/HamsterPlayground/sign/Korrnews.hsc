# File: KorrNews.hsc
#!load hamster.hsm
#-----------------------------------------------------------------------#
# Sign with XGpgSig & HPG  - for use with XGpgSig 0.0.2.9 & HPG         #
# Place this Script in Action Tasks 'NewsWaiting'                       #
# Mark 'Wait'                                                           #
# This is part 2 from the sign routine,                                 #
# you also have to use 'XGpgSigSignHPG.hsc' in combination              #
# with this script.                                                     #
# Gnu Key & Password have to be in XGpgSig.ini                          #
# by Hermann Hippen 25.06.08 - always 'Good Sig :-)'                    #
# thanks to Wolfgang Bauer.                                             #
#                                                                       #
#---------------------Type in your own data-----------------------------#
# if anything won't work, look here first!                              #
#-----------------------------------------------------------------------#
var ($msg)
varset ( $KnHome, "N:\hpg25\Korrnews\"    )
varset ( $XHome,  "E:\Programme\XGpgSig\" )
HamWaitIdle
# delete X-PGP Headers to prevent doubles with Supersede
$msg=MsgAlloc
MsgLoad($msg, paramstr(2))
if( MsgHeaderExists  ( $msg, "Supersedes" ))
	if( MsgHeaderExists  ( $msg, "X-PGP-CHECK" ))
 		MsgDelHeader( $msg, "X-PGP-CHECK" )
	endif
	if( MsgHeaderExists  ( $msg, "X-PGP-Sig"   ))
 		MsgDelHeader( $msg, "X-PGP-Sig"   )
	endif
	if( MsgHeaderExists  ( $msg, "X-PGP-Hash"  ))
 		MsgDelHeader( $msg, "X-PGP-Hash"  )
	endif
       MsgSave($msg, paramstr(2))
endif
MsgFree( $msg )
#------------------!!! no changes below !!! ----------------------------#
Execute( $KnHome + "Only_kn.exe Type:News Filename:" + ParamStr( 2 ),$KnHome,0,1 )
Execute( $XHome  + "work.bat" , $XHome, 0, 1)
#-----------------------------------------------------------------------#
quit        
