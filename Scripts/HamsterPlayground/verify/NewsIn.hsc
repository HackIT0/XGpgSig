# File: NewsIn.hsc
#!load hamster.hsm
#--------------------------------------------------------------------------#
# Verify with XGpgSig & HPG - for use with XGpgSig 0.0.2.9 & HPG           #
# Place this Script in Action Tasks 'NewsIn'                               #
# Mark 'Wait' & 'Lock'                                                     #
# Gnu Key & Password have to be in XGpgSig.ini                             #
# by Hermann Hippen 25.06.08 - always 'Good Sig :-)'                       #
# thanks to Wolfgang Bauer.                                                #
#                                                                          #
#---------------------Type in your own data--------------------------------#
# if anything won't work, look here first!                                 #
#--------------------------------------------------------------------------#

varset( $XGpgSigHome, "E:\Programme\XGpgSig\"     )

#---------------     !!! No changes below !!! -----------------------------#

varset( $OrgMsg  , $XGpgSigHome + "OrgM.msg"   )
varset( $SigMsg  , $XGpgSigHome + "SigM.msg"   )
varset( $SigProg , $XGpgSigHome + "XGpgSig.exe")
varset( $ToDo    , $SigProg     + " verify -i" + $OrgMsg + " -o" + $SigMsg )

#--------------------------------------------------------------------------#
var     ($msg                       )
$msg=Int(paramstr(3)                )

if( MsgHeaderExists( $msg, "X-PGP-Sig" ) )
     MsgSave ($msg,  $OrgMsg             )
     Execute ($ToDo, $XGpgSigHome , 1, 1 )
     MsgLoad ($msg,  $SigMsg             )
endif
#--------------------------------------------------------------------------#
quit     
