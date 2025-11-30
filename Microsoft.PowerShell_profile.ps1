set-alias -name coc -value choco
set-alias -name python -value python3.14
set-alias -name godot -value Godot_v4.6-dev4_win64
set-alias -name godot-cli -value Godot_v4.6-dev4_win64_console
set-alias -name imgto -value imageto


if ($PSStyle.OutputRendering -ne "ANSI")
{
    $PSStyle.OutputRendering = "PlainText"
}


# Load opener functions
. "$PSScriptRoot\scripts\opwsh.ps1"

# Load Everything SDK wrapper
. "$PSScriptRoot\scripts\epwsh.ps1"

# Load ImageTools functions
. "$PSScriptRoot\scripts\imgpwsh.ps1"

# Auto cd to the foreground Windows Explorer folder
. "$PSScriptRoot\scripts\cdxpwsh.ps1"

# Load Environment Variable functions
. "$PSScriptRoot\scripts\envpwsh.ps1"

# Load Context Menu Override function
. "$PSScriptRoot\scripts\winapi_override.ps1"

# Initialize Headless Blender
. "$PSScriptRoot\scripts\init_pwsh.ps1"

# Batch Organization
. "$PSScriptRoot\scripts\repwsh.ps1"
