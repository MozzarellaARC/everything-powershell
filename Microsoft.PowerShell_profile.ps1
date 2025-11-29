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
. "$PSScriptRoot\everything_powershell\opwsh.ps1"

# Load Everything SDK wrapper
. "$PSScriptRoot\everything_powershell\epwsh.ps1"

# Load ImageTools functions
. "$PSScriptRoot\everything_powershell\imgpwsh.ps1"

# Auto cd to the foreground Windows Explorer folder
. "$PSScriptRoot\everything_powershell\cdxpwsh.ps1"

# Load Environment Variable functions
. "$PSScriptRoot\everything_powershell\envpwsh.ps1"

# Load Context Menu Override function
. "$PSScriptRoot\everything_powershell\winapi_override.ps1"

# Initialize Headless Blender
. "$PSScriptRoot\everything_powershell\init_pwsh.ps1"

# Batch Organization
. "$PSScriptRoot\everything_powershell\repwsh.ps1"
