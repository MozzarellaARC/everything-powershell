function envs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)]
        [string]$Var,

        [Parameter(Position=1)]
        [ValidateSet('Process','User','Machine')]
        [string]$Scope = 'Process',

        [Parameter(Position=2)]
        [string]$Value
    )

    # Get the Path environment variable for the current user
    if ($PSBoundParameters.ContainsKey('Value')) {
        # Set
        [Environment]::SetEnvironmentVariable($Var, $Value, $Scope)
    } else {
        # Get
        [Environment]::GetEnvironmentVariable($Var, $Scope)
    }
}