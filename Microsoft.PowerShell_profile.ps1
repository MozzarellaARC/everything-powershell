set-alias -name coc -value choco
# set-alias -name python -value python3.14
set-alias -name godot -value Godot_v4.6-dev4_win64
set-alias -name godot-cli -value Godot_v4.6-dev4_win64_console
set-alias -name imgto -value imageto
set-alias -name ff -value firefox
set-alias -name img -value magick


if ($PSStyle.OutputRendering -ne "ANSI")
{
    $PSStyle.OutputRendering = "PlainText"
}


# Load opener functions
. "$PSScriptRoot\scripts\OPwsh.ps1"

# Load Everything SDK wrapper
. "$PSScriptRoot\scripts\EPwsh.ps1"

# Load ImageTools functions
. "$PSScriptRoot\scripts\ImgPwsh.ps1"

# Auto cd to the foreground Windows Explorer folder
. "$PSScriptRoot\scripts\CdxPwsh.ps1"

# Load Environment Variable functions
. "$PSScriptRoot\scripts\EnvPwsh.ps1"

# Load Context Menu Override function
. "$PSScriptRoot\scripts\WinApiOverride.ps1"

# Initialize Headless Blender
. "$PSScriptRoot\scripts\InitPwsh.ps1"

# Batch Organization
. "$PSScriptRoot\scripts\RePwsh.ps1"

# Play Music
. "$PSScriptRoot\scripts\PlayPwsh.ps1"