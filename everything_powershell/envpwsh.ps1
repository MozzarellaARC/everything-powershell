function envs {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)]
        [string]$Var,

        [Parameter(Position=1)]
        [ValidateSet('Process','User','Machine')]
        [string]$Scope = 'Process',

        [Parameter(Position=2)]
        [string]$Value,

        [switch]$Append,
        [switch]$Refresh,
        [switch]$Set
    )

    # New capabilities:
    # 1. Single argument that matches a scope (envs User) lists all variables at that scope.
    # 2. -Set creates/updates variable Var with Value, then appends %Var% to PATH at same scope (if not already present).
    # 3. -Append (existing) appends literal Value to Var.
    # 4. -Refresh updates current process copy when modifying User/Machine.

    function Get-AllScopeVars([string]$ListScope) {
        $target = [System.EnvironmentVariableTarget]::$ListScope
        $dict = [Environment]::GetEnvironmentVariables($target)
        foreach ($k in ($dict.Keys | Sort-Object)) {
            [pscustomobject]@{ Scope=$ListScope; Name = $k; Value = $dict[$k] }
        }
    }

    # If no arguments at all -> list every scope combined
    if ($PSBoundParameters.Count -eq 0) {
        $all = foreach ($sc in 'Process','User','Machine') { Get-AllScopeVars -ListScope $sc }
        # Return objects; user can format. Provide a default nice view if not part of a pipeline.
        if ($MyInvocation.ExpectingInput -or $PSCmdlet.MyInvocation.PipelinePosition -gt 1) {
            return $all
        } else {
            $all | Sort-Object Scope, Name | Format-Table -AutoSize
            return
        }
    }

    # Detect single scope usage BEFORE default Scope parameter masking it.
    $singleScopeList = $false
    if ($PSBoundParameters.Count -eq 1 -and $PSBoundParameters.ContainsKey('Var')) {
        if ($Var -in 'Process','User','Machine') { $singleScopeList = $true }
    }
    elseif ($PSBoundParameters.Count -eq 1 -and $PSBoundParameters.ContainsKey('Scope') -and -not $PSBoundParameters.ContainsKey('Var')) {
        # user used named -Scope only
        if ($Scope -in 'Process','User','Machine') { $singleScopeList = $true; $Var = $null }
    }

    if ($singleScopeList) {
        return Get-AllScopeVars -ListScope ($Var ?? $Scope)
    }

    $originalProcessValue = $null
    $didModify = $false
    $result = $null

    if ($Set) {
        if (-not $Var) { throw "-Set requires a variable name (first positional argument)." }
        if (-not $PSBoundParameters.ContainsKey('Value')) { throw "-Set requires -Value (third positional argument)." }
        # Set the variable itself first
        [Environment]::SetEnvironmentVariable($Var, $Value, $Scope)
        $didModify = $true
        $result = $Value

        # Now append a reference %Var% to PATH at same scope (if Var not PATH itself)
        if ($Var -ine 'PATH') {
            $pathCurrent = [Environment]::GetEnvironmentVariable('Path', $Scope)
            $token = "%$Var%"
            $already = $false
            if ($pathCurrent) {
                $parts = $pathCurrent -split ';'
                foreach ($p in $parts) { if ($p.Trim().ToLower() -eq $token.ToLower()) { $already = $true; break } }
            }
            if (-not $already) {
                $newPath = if ([string]::IsNullOrEmpty($pathCurrent)) { $token } elseif ($pathCurrent.EndsWith(';')) { "$pathCurrent$token" } else { "$pathCurrent;$token" }
                [Environment]::SetEnvironmentVariable('Path', $newPath, $Scope)
                Write-Verbose "Appended $token to PATH at scope $Scope." 
            } else {
                Write-Verbose "$token already present in PATH at scope $Scope."
            }
        }
    }
    elseif ($Append) {
        if (-not $PSBoundParameters.ContainsKey('Value')) {
            throw "-Append requires -Value to supply what to append."
        }
        if (-not $Var) { throw "-Append requires a variable name (first positional argument)." }
        $current = [Environment]::GetEnvironmentVariable($Var, $Scope)
        if ([string]::IsNullOrEmpty($current)) {
            $new = $Value
        } else {
            $separator = ';'
            if ($current.EndsWith($separator) -or $Value.StartsWith($separator)) {
                $new = "$current$Value"
            } else {
                $new = "$current$separator$Value"
            }
        }
        [Environment]::SetEnvironmentVariable($Var, $new, $Scope)
        $didModify = $true
        $result = $new
    }
    elseif ($PSBoundParameters.ContainsKey('Value')) {
        if (-not $Var) { throw "Setting a value requires a variable name (first positional argument)." }
        [Environment]::SetEnvironmentVariable($Var, $Value, $Scope)
        $didModify = $true
        $result = $Value
    }
    else {
        if (-not $Var) { throw "Provide a variable name or a single scope (Process/User/Machine) to list all." }
        $result = [Environment]::GetEnvironmentVariable($Var, $Scope)
    }

    if ($Refresh -and $didModify) {
        if ($Scope -in 'User','Machine') {
            if ($Var -ieq 'PATH' -or $Set -or $Append) {
                $machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
                $userPath    = [Environment]::GetEnvironmentVariable('Path','User')
                $combined = if ([string]::IsNullOrEmpty($machinePath)) { $userPath } elseif ([string]::IsNullOrEmpty($userPath)) { $machinePath } else { "$machinePath;$userPath" }
                $originalProcessValue = $env:Path
                $env:Path = $combined
                Write-Verbose "Process PATH refreshed (was length $($originalProcessValue.Length), now $($env:Path.Length))."
            } else {
                $valToLoad = [Environment]::GetEnvironmentVariable($Var, $Scope)
                if ($null -eq $valToLoad) {
                    Remove-Item -Path "Env:$Var" -ErrorAction SilentlyContinue
                } else {
                    Set-Item -Path "Env:$Var" -Value $valToLoad
                }
            }
        }
    }

    return $result
}