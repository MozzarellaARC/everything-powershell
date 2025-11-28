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
        [string]$Scope,

        [Parameter(Position=2)]
        [string]$Value,

        [switch]$New,
        [switch]$Append,
        [switch]$Refresh,
        [switch]$Set,
        [switch]$Clean,
        [switch]$Merge,
        [Alias('h','?')][switch]$Help
    )

    # New capabilities:
    # 1. Single argument that matches a scope (envs User) lists all variables at that scope.
    # 2. -Set creates/updates variable Var with Value, then appends %Var% to PATH at same scope (if not already present).
    # 3. -Append (existing) appends literal Value to Var.
    # 4. -Refresh updates current process copy when modifying User/Machine.
    # 5. -Clean removes duplicate values from a semicolon-separated variable.
    # 6. -Merge expands all %VAR% references to actual values and optionally removes the referenced variables.

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
            # Split by semicolon and check if each path exists
            $parts = $InputValue -split ';'
            $coloredParts = @()

            foreach ($part in $parts) {
                if ([string]::IsNullOrWhiteSpace($part)) {
                    continue
                }

                # Expand environment variables in the path
                $expandedPath = [Environment]::ExpandEnvironmentVariables($part.Trim())

                # Check if this looks like a file system path
                $isPath = $false
                try {
                    $isPath = [System.IO.Path]::IsPathRooted($expandedPath) -or
                              $expandedPath -match '^[a-zA-Z]:\\' -or
                              $expandedPath -match '^\\\\' -or
                              (Test-Path -LiteralPath $expandedPath -ErrorAction SilentlyContinue)
                } catch {
                    $isPath = $false
                }

                # Color the path red if it looks like a path but doesn't exist
                if ($isPath) {
                    $exists = Test-Path -LiteralPath $expandedPath -ErrorAction SilentlyContinue
                    if (-not $exists) {
                        # Use ANSI escape codes for red text
                        $coloredPart = "$([char]27)[91m$part$([char]27)[0m"
                        $coloredParts += $coloredPart
                    } else {
                        $coloredParts += $part
                    }
                } else {
                    # Not a path, just add it as-is
                    $coloredParts += $part
                }
            }

            $normalized = ($coloredParts -join ";`n")
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

    function Remove-DuplicateValues {
        param(
            [string]$ValueString,
            [ref]$RemovedDuplicates
        )

        if ([string]::IsNullOrEmpty($ValueString)) { return '' }

        $parts = Split-SemicolonValue -ValueToSplit $ValueString
        $seen = @{}
        $unique = [System.Collections.Generic.List[string]]::new()
        $duplicates = [System.Collections.Generic.List[string]]::new()

        foreach ($part in $parts) {
            $info = Get-PathComparisonInfo -Value $part
            $key = $info.Normalized.ToLowerInvariant()

            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $unique.Add($part)
            } else {
                $duplicates.Add($part)
            }
        }

        if ($null -ne $RemovedDuplicates) {
            $RemovedDuplicates.Value = $duplicates.ToArray()
        }

        return ($unique -join ';')
    }

    function Expand-VariableReferences {
        param(
            [string]$ValueString,
            [string]$TargetScope,
            [ref]$ReferencedVars
        )

        if ([string]::IsNullOrEmpty($ValueString)) { return '' }

        $parts = Split-SemicolonValue -ValueToSplit $ValueString
        $expanded = [System.Collections.Generic.List[string]]::new()
        $varsFound = @{}

        foreach ($part in $parts) {
            $expandedPart = $part

            # Find all %VARNAME% patterns in this part
            $matches = [regex]::Matches($part, '%([^%]+)%')

            foreach ($match in $matches) {
                $varName = $match.Groups[1].Value

                # Get the value of the referenced variable from the same scope
                $varValue = [Environment]::GetEnvironmentVariable($varName, $TargetScope)

                if ($null -ne $varValue -and $varValue -ne '') {
                    # Track this variable for potential deletion
                    $varsFound[$varName] = $varValue

                    # Expand the reference in this part
                    $expandedPart = $expandedPart -replace "%$([regex]::Escape($varName))%", $varValue
                }
            }

            $expanded.Add($expandedPart)
        }

        if ($null -ne $ReferencedVars) {
            $ReferencedVars.Value = $varsFound
        }

        return ($expanded -join ';')
    }

    $validScopes = @('Process','User','Machine')

    # Safeguard: Check if user typed 'clean' or 'merge' as a variable name instead of using the switch
    if ($Var -and -not $Clean -and -not $Merge) {
        if ($Var -ieq 'clean') {
            Write-Host "Do you mean -Clean? Clean requires parameters: [Scope] and [Variable]." -ForegroundColor Yellow
            Write-Host "Example: envs User Path -Clean" -ForegroundColor Cyan
            return
        }
        if ($Var -ieq 'merge') {
            Write-Host "Do you mean -Merge? Merge requires parameters: [Scope] and [Variable]." -ForegroundColor Yellow
            Write-Host "Example: envs User Path -Merge" -ForegroundColor Cyan
            return
        }
    }

    # Safeguard: If Value is provided, user must specify -New, -Append, or -Set
    if ($PSBoundParameters.ContainsKey('Value')) {
        if (-not $New -and -not $Append -and -not $Set) {
            Write-Host "Error: When providing a Value, you must specify one of: -New, -Append, or -Set" -ForegroundColor Red
            Write-Host "Examples:" -ForegroundColor Cyan
            Write-Host "  envs MyVar User 'C:\Path' -New      # Create/overwrite variable" -ForegroundColor Gray
            Write-Host "  envs Path User 'C:\Tools' -Append   # Append to existing variable" -ForegroundColor Gray
            Write-Host "  envs JAVA_HOME User 'C:\Java' -Set  # Set variable and add %JAVA_HOME% to PATH" -ForegroundColor Gray
            return
        }
    }

    if ($PSBoundParameters.ContainsKey('Var') -and $PSBoundParameters.ContainsKey('Scope')) {
        $varLooksLikeScope = $Var -and ($validScopes | Where-Object { $_ -ieq $Var })
        $scopeLooksLikeScope = $Scope -and ($validScopes | Where-Object { $_ -ieq $Scope })

        if ($varLooksLikeScope -and -not $scopeLooksLikeScope) {
            $temp = $Var
            $Var = $Scope
            $Scope = $temp
        }
    }

    # Default Scope to 'Process' if not provided
    if ([string]::IsNullOrEmpty($Scope)) {
        $Scope = 'Process'
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

    envs <Var> <Scope> <Value> -New    Create or overwrite variable
    envs <Var> <Scope> <Value> -Append Append literal value to existing variable (semicolon separator)
    envs <Var> <Scope> <Value> -Set    Set variable then append %Var% token to PATH at same scope
    envs <Var> <Scope> -Clean          Remove duplicate values from semicolon-separated variable
    envs <Var> <Scope> -Merge          Expand %VAR% references to actual values and delete referenced vars

SWITCHES:
    -New        Create or overwrite the variable with the provided Value
    -Append     Append provided Value to existing variable (adds ';' if needed)
    -Set        Set variable and add %Var% to PATH (if not already there)
    -Clean      Remove duplicate entries from variable (case-insensitive, normalized path comparison)
    -Merge      Expand all %VAR% references in variable to their actual values, then delete those vars
    -Refresh    After modifying User/Machine, rebuild process PATH (Machine;User) and load changed var
    -Help/-?    Show this help

EXAMPLES:
    envs Path User                     Get user PATH
    envs User                          List all user variables
    envs User Path                     Get user PATH using scope-first syntax
    envs                               List all variables (Process, User, Machine)
    envs MY_VAR User 'C:\MyPath' -New -Refresh
    envs TOOLS_HOME User 'C:\Tools' -Set -Refresh
    envs Path User 'C:\ExtraBin' -Append -Refresh
    envs MY_TEMP Process '123' -New    Set process-only variable
    envs Path User -Clean -Refresh     Remove duplicate paths from user PATH
    envs Path User -Merge -Refresh     Expand %VAR% references and remove those variables

NOTES:
    - When providing a Value, you MUST specify -New, -Append, or -Set.
    - Use -New to create or overwrite a variable with a new value.
    - Use -Set for directory variables you want on PATH via %VARNAME% expansion.
    - Append expects directories (for PATH) not executables.
    - -Set appends when the variable already exists and errors if the value/path already matches (raw or expanded).
    - -Refresh only needed for persistent scopes (User/Machine) to update current session.
    - Interactive output auto-splits ';' separated values onto new lines for readability.
    - Missing/invalid paths are displayed in red for easy identification.
    - -Clean uses normalized path comparison to detect duplicates (e.g., C:\Tools\ = C:\Tools).
    - -Merge expands references like %JAVA_HOME% and deletes JAVA_HOME from the same scope.
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
        if ($Clean) {
            if (-not $Var) { throw "-Clean requires a variable name (first positional argument)." }

            $current = [Environment]::GetEnvironmentVariable($Var, $Scope)
            if ([string]::IsNullOrEmpty($current)) {
                Write-Warning "Variable '$Var' at scope '$Scope' is empty or does not exist."
                return
            }

            $removedDuplicates = $null
            $cleaned = Remove-DuplicateValues -ValueString $current -RemovedDuplicates ([ref]$removedDuplicates)

            if ($cleaned -eq $current) {
                Write-Host "$Scope $Var is clean! Skipping clean command." -ForegroundColor Green
                $result = New-EnvRecord -RecordScope $Scope -RecordName $Var -RecordValue $current
            } else {
                [Environment]::SetEnvironmentVariable($Var, $cleaned, $Scope)
                $didModify = $true

                # Show which values were cleaned
                foreach ($duplicate in $removedDuplicates) {
                    Write-Host "Removed duplicate: $duplicate" -ForegroundColor Yellow
                }

                $result = New-EnvRecord -RecordScope $Scope -RecordName $Var -RecordValue $cleaned
            }
        }
        elseif ($Merge) {
            if (-not $Var) { throw "-Merge requires a variable name (first positional argument)." }

            $current = [Environment]::GetEnvironmentVariable($Var, $Scope)
            if ([string]::IsNullOrEmpty($current)) {
                Write-Warning "Variable '$Var' at scope '$Scope' is empty or does not exist."
                return
            }

            $referencedVars = $null
            $merged = Expand-VariableReferences -ValueString $current -TargetScope $Scope -ReferencedVars ([ref]$referencedVars)

            if ($merged -eq $current) {
                Write-Host "No variable references found in '$Var' at scope '$Scope'."
                $result = New-EnvRecord -RecordScope $Scope -RecordName $Var -RecordValue $current
            } else {
                # Update the variable with expanded values
                [Environment]::SetEnvironmentVariable($Var, $merged, $Scope)
                $didModify = $true
                Write-Host "Merged variable references in '$Var' at scope '$Scope'."

                # Delete the referenced variables
                if ($referencedVars -and $referencedVars.Count -gt 0) {
                    foreach ($refVarName in $referencedVars.Keys) {
                        Write-Host "Deleting referenced variable '$refVarName' from scope '$Scope'..." -ForegroundColor Cyan

                        # Actually delete the variable based on scope
                        if ($Scope -eq 'User') {
                            Remove-ItemProperty -Path "HKCU:\Environment" -Name $refVarName -ErrorAction SilentlyContinue
                        }
                        elseif ($Scope -eq 'Machine') {
                            Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" -Name $refVarName -ErrorAction SilentlyContinue
                        }
                        else {
                            # Process scope - just remove from environment
                            Remove-Item -Path "Env:$refVarName" -ErrorAction SilentlyContinue
                        }
                    }
                }

                $result = New-EnvRecord -RecordScope $Scope -RecordName $Var -RecordValue $merged
            }
        }
        elseif ($Set) {
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
            $newValue = Join-SemicolonValue -Current $current -Addition $Value
            [Environment]::SetEnvironmentVariable($Var, $newValue, $Scope)
            $didModify = $true
            $result = New-EnvRecord -RecordScope $Scope -RecordName $Var -RecordValue ([Environment]::GetEnvironmentVariable($Var, $Scope))
        }
        elseif ($PSBoundParameters.ContainsKey('Value')) {
            if (-not $Var) { throw "Setting a value requires a variable name (first positional argument)." }
            # This handles -New switch: create or overwrite the variable
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
