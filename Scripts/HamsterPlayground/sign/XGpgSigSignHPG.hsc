# File: XGpgSigSignHPG.hsc
#!load hamster.hsm
#-----------------------------------------------------------------------#
# Sign with XGpgSig & HPG  - for use with XGpgSig 0.0.2.9 & HPG         #
# Place this Script in Action Tasks 'NewsOut'                           #
# Mark 'Wait'                                                           #
# This is part 1 from the sign routine,                                 #
# you also have to use 'Korrnews.hsc' in combination with this script.  #
# Gnu Key & Password have to be in XGpgSig.ini                          #
# by Hermann Hippen 25.06.08 - always 'Good Sig :-)'                    #
# thanks to Wolfgang Bauer.                                             #
#                                                                       #
#---------------------Type in your own data-----------------------------#
# if anything won't work, look here first!                              #
#-----------------------------------------------------------------------#

varset( $XHome, "E:\Programme\XGpgSig\" )

#---------------   !!! No changes below !!!   --------------------------#
var ($XSig)

$XSig="XGpgSig.exe sign -i" + paramstr(2) + " -o" + paramstr(2)
execute( "cmd.exe /C Echo call " + $XSig + " > work.bat", $XHome, 0,1)
execute( "cmd.exe /C Echo exit >> work.bat", $XHome, 0,1)
#-----------------------------------------------------------------------#
quit


