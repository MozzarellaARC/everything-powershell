function envs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)]
        [string]$Var,

        [Parameter(Position=1)]
        [ValidateSet('Process','User','Machine')]
        [string]$Scope = 'Process',

        [Parameter(Position=2)]
        [string]$Value,

        [switch]$Append
    )

    # Command examples : envs path user 'C:\MyTools'
    
    if ($Append) {
        if (-not $PSBoundParameters.ContainsKey('Value')) {
            throw "-Append requires -Value to supply what to append."
        }
        $current = [Environment]::GetEnvironmentVariable($Var, $Scope)
        if ([string]::IsNullOrEmpty($current)) {
            $new = $Value
        } else {
            # Use ';' like PATH style by default. User can include leading separator in -Value if they need something else.
            $separator = ';'
            # Avoid double separators
            if ($current.EndsWith($separator)) {
                $new = "$current$Value"
            } elseif ($Value.StartsWith($separator)) {
                $new = "$current$Value"
            } else {
                $new = "$current$separator$Value"
            }
        }
        [Environment]::SetEnvironmentVariable($Var, $new, $Scope)
        return $new
    }

    if ($PSBoundParameters.ContainsKey('Value')) {
        [Environment]::SetEnvironmentVariable($Var, $Value, $Scope)
        return $Value
    } else {
        return [Environment]::GetEnvironmentVariable($Var, $Scope)
    }
}