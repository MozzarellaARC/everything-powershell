function envs {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)]
        [string]$Var,

        [Parameter(Position=1)]
        [ArgumentCompleter({
            param($commandName,$parameterName,$wordToComplete)
            'Process','User','Machine' | Where-Object { $_ -like "$wordToComplete*" }
        })]
        [string]$Scope = 'Process',

        [Parameter(Position=2)]
        [string]$Value,

        [switch]$Append,
        [switch]$Refresh,
        [switch]$Set,
        [Alias('h','?')][switch]$Help
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

    function New-EnvRecord {
        param(
            [string]$RecordScope,
            [string]$RecordName,
            $RecordValue
        )

        [pscustomobject][ordered]@{
            Scope = $RecordScope
            Name  = $RecordName
            Value = $RecordValue
        }
    }

    function Format-EnvValueForDisplay {
        param($InputValue)

        if ($null -eq $InputValue) { return $null }

        if ($InputValue -is [string]) {
              $normalized = $InputValue -replace ';', ";`n"
            return $normalized.TrimEnd("`n")
        }

        return $InputValue
    }

    function Join-SemicolonValue {
        param(
            [string]$Current,
            [string]$Addition
        )

        if ([string]::IsNullOrEmpty($Current)) { return $Addition }
        if ([string]::IsNullOrEmpty($Addition)) { return $Current }

        $separator = ';'
        if ($Current.EndsWith($separator) -or $Addition.StartsWith($separator)) {
            return "$Current$Addition"
        }

        return "$Current$separator$Addition"
    }

    function Split-SemicolonValue {
        param([string]$ValueToSplit)

        if ([string]::IsNullOrEmpty($ValueToSplit)) { return @() }

        return ($ValueToSplit -split ';') | Where-Object { $_ -ne '' } | ForEach-Object { $_.Trim() }
    }

    function Test-ContainsSemicolonValue {
        param(
            [string]$Current,
            [string]$Candidate
        )

        if ([string]::IsNullOrEmpty($Candidate)) { return $false }

        $candidateNormalized = $Candidate.Trim()
        $candidateInfo = Get-PathComparisonInfo -Value $candidateNormalized

        foreach ($entry in (Split-SemicolonValue -ValueToSplit $Current)) {
            $entryInfo = Get-PathComparisonInfo -Value $entry

            if ($entryInfo.Raw.Equals($candidateInfo.Raw, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
            if ($entryInfo.Expanded.Equals($candidateInfo.Raw, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
            if ($entryInfo.Raw.Equals($candidateInfo.Expanded, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
            if ($entryInfo.Expanded.Equals($candidateInfo.Expanded, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
            if ($entryInfo.Normalized.Equals($candidateInfo.Normalized, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        }

        return $false
    }

    function Throw-EnvError {
        param(
            [string]$Message,
            [string]$ErrorId,
            [object]$Target
        )

        $exception = [System.InvalidOperationException]::new($Message)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            $ErrorId,
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $Target
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    function Get-PathComparisonInfo {
        param([string]$Value)

        $raw = ($Value ?? '').Trim().Trim('"')
        $expanded = $raw
        if ($null -ne $raw) {
            $expanded = [Environment]::ExpandEnvironmentVariables($raw)
        }

        $normalized = $expanded
        if (-not [string]::IsNullOrWhiteSpace($expanded)) {
            try {
                if ([System.IO.Path]::IsPathRooted($expanded)) {
                    $normalized = [System.IO.Path]::GetFullPath($expanded)
                }
            } catch {
                $normalized = $expanded
            }
        }

        $normalizedClean = $normalized ?? ''
        if ($normalizedClean) {
            $root = $null
            try { $root = [System.IO.Path]::GetPathRoot($normalizedClean) } catch { $root = $null }
            $trimmed = $normalizedClean.TrimEnd([System.IO.Path]::DirectorySeparatorChar)
            if (-not $root -or -not $trimmed.Equals($root.TrimEnd([System.IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase)) {
                $normalizedClean = $trimmed
            }
        }

        return [pscustomobject]@{
            Raw        = $raw ?? ''
            Expanded   = $expanded ?? ''
            Normalized = $normalizedClean
        }
    }

    $validScopes = @('Process','User','Machine')

    if ($PSBoundParameters.ContainsKey('Var') -and $PSBoundParameters.ContainsKey('Scope')) {
        $varLooksLikeScope = $Var -and ($validScopes | Where-Object { $_ -ieq $Var })
        $scopeLooksLikeScope = $Scope -and ($validScopes | Where-Object { $_ -ieq $Scope })

        if ($varLooksLikeScope -and -not $scopeLooksLikeScope) {
            $temp = $Var
            $Var = $Scope
            $Scope = $temp
        }
    }

    if ($Scope) {
        $normalizedScope = ($validScopes | Where-Object { $_ -ieq $Scope } | Select-Object -First 1)
        if (-not $normalizedScope) {
            throw "Scope must be one of: $($validScopes -join ', ')."
        }
        $Scope = $normalizedScope
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

        # Help requested -> print and exit early
        if ($Help) {
                @'
envs - Environment variable helper

USAGE:
    envs <Var> [Scope]                 Get variable at scope (default Scope=Process)
    envs <Scope> [Var]                 Scope-first aliases (envs User Path)
    envs <Scope>                       List all variables for that scope (Process|User|Machine)
    envs                               List all variables for all scopes

    envs <Var> <Scope> <Value>         Set variable
    envs <Var> <Scope> <Value> -Append Append literal value to existing variable (semicolon separator)
    envs <Var> <Scope> <Value> -Set    Set variable then append %Var% token to PATH at same scope

SWITCHES:
    -Append     Append provided Value to existing variable (adds ';' if needed)
    -Set        Set variable and add %Var% to PATH (if not already there)
    -Refresh    After modifying User/Machine, rebuild process PATH (Machine;User) and load changed var
    -Help/-?    Show this help

EXAMPLES:
    envs Path User                     Get user PATH
    envs User                          List all user variables
    envs User Path                     Get user PATH using scope-first syntax
    envs                               List all variables (Process, User, Machine)
    envs TOOLS_HOME User 'C:\Tools' -Set -Refresh
    envs Path User 'C:\ExtraBin' -Append -Refresh
    envs MY_TEMP Process '123'         Set process-only variable

NOTES:
    - Use -Set for directory variables you want on PATH via %VARNAME% expansion.
    - Append expects directories (for PATH) not executables.
    - -Set appends when the variable already exists and errors if the value/path already matches (raw or expanded).
    - -Refresh only needed for persistent scopes (User/Machine) to update current session.
    - Interactive output auto-splits ';' separated values onto new lines for readability.
    - Returned objects are PSCustomObjects, ready for further pipeline processing.
'@ | Write-Host
                return
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

    $originalProcessValue = $null
    $didModify = $false
    $result = $null

    if ($singleScopeList) {
        $result = Get-AllScopeVars -ListScope ($Var ?? $Scope)
    }
    else {
        if ($Set) {
            if (-not $Var) { throw "-Set requires a variable name (first positional argument)." }
            if (-not $PSBoundParameters.ContainsKey('Value')) { throw "-Set requires -Value (third positional argument)." }
            $incoming = $Value
            $existing = [Environment]::GetEnvironmentVariable($Var, $Scope)
            if (Test-ContainsSemicolonValue -Current $existing -Candidate $incoming) {
                Throw-EnvError -Message "Variable '$Var' at scope '$Scope' already contains value '$incoming'." -ErrorId 'EnvVariableDuplicateValue' -Target $Var
            }
            $Value = if (-not [string]::IsNullOrEmpty($existing)) {
                Join-SemicolonValue -Current $existing -Addition $incoming
            } else {
                $incoming
            }
            # Validate PATH addition before making any changes
            $pathCurrent = $null
            $token = $null
            $newPath = $null
            $shouldUpdatePath = $false
            if ($Var -ine 'PATH') {
                $pathCurrent = [Environment]::GetEnvironmentVariable('Path', $Scope)
                if (Test-ContainsSemicolonValue -Current $pathCurrent -Candidate $incoming) {
                    Throw-EnvError -Message "PATH at scope '$Scope' already contains value '$incoming'." -ErrorId 'EnvPathDuplicateValue' -Target 'Path'
                }
                $token = "%$Var%"
                $shouldUpdatePath = $true
                $already = $false
                if ($pathCurrent) {
                    $parts = $pathCurrent -split ';'
                    foreach ($p in $parts) {
                        if ($p.Trim().ToLower() -eq $token.ToLower()) { $already = $true; break }
                    }
                }
                if ($already) {
                    $shouldUpdatePath = $false
                } else {
                    $newPath = if ([string]::IsNullOrEmpty($pathCurrent)) { $token } elseif ($pathCurrent.EndsWith(';')) { "$pathCurrent$token" } else { "$pathCurrent;$token" }
                }
            }

            # Set the variable itself first
            [Environment]::SetEnvironmentVariable($Var, $Value, $Scope)
            $didModify = $true
            $result = New-EnvRecord -RecordScope $Scope -RecordName $Var -RecordValue ([Environment]::GetEnvironmentVariable($Var, $Scope))

            # Now append a reference %Var% to PATH at same scope (if Var not PATH itself)
            if ($Var -ine 'PATH') {
                if ($shouldUpdatePath -and $newPath) {
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
            if (Test-ContainsSemicolonValue -Current $current -Candidate $Value) {
                Throw-EnvError -Message "Variable '$Var' at scope '$Scope' already contains value '$Value'." -ErrorId 'EnvVariableDuplicateValue' -Target $Var
            }
            $new = Join-SemicolonValue -Current $current -Addition $Value
            [Environment]::SetEnvironmentVariable($Var, $new, $Scope)
            $didModify = $true
            $result = New-EnvRecord -RecordScope $Scope -RecordName $Var -RecordValue ([Environment]::GetEnvironmentVariable($Var, $Scope))
        }
        elseif ($PSBoundParameters.ContainsKey('Value')) {
            if (-not $Var) { throw "Setting a value requires a variable name (first positional argument)." }
            [Environment]::SetEnvironmentVariable($Var, $Value, $Scope)
            $didModify = $true
            $result = New-EnvRecord -RecordScope $Scope -RecordName $Var -RecordValue ([Environment]::GetEnvironmentVariable($Var, $Scope))
        }
        else {
            if (-not $Var) { throw "Provide a variable name or a single scope (Process/User/Machine) to list all." }
            $result = New-EnvRecord -RecordScope $Scope -RecordName $Var -RecordValue ([Environment]::GetEnvironmentVariable($Var, $Scope))
        }
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
    if ($null -eq $result) { return }

    $pipelineLength  = $PSCmdlet.MyInvocation.PipelineLength
    $pipelinePosition = $PSCmdlet.MyInvocation.PipelinePosition

    $inPipeline = $pipelineLength -gt 1 -and $pipelinePosition -lt $pipelineLength

    if ($inPipeline) {
        return $result
    }

    $items = @($result)

    $items | Format-Table -AutoSize -Wrap -Property Scope, Name, @{ Name = 'Value'; Expression = { Format-EnvValueForDisplay $_.Value } }
    return
}