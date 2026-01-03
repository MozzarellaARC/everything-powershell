function envs {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Position=0)]
        [ArgumentCompleter({
            param($commandName,$parameterName,$wordToComplete)
            'Process','User','Machine' | Where-Object { $_ -like "$wordToComplete*" }
        })]
        [string]$Scope,

        [Parameter(Position=1)]
        [string]$Name,

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

    function Confirm-EnvAction {
        param(
            [string]$Target,
            [string]$Action
        )

        # Support -WhatIf
        if ($WhatIfPreference) {
            Write-Host "What if: $Action" -ForegroundColor Cyan
            return $false
        }

        # Support -Confirm:$false
        if ($PSBoundParameters.ContainsKey('Confirm') -and -not $Confirm) {
            return $true
        }

        # Detailed confirmation dialog
        Write-Host "`n========================================" -ForegroundColor Yellow
        Write-Host "  CONFIRMATION REQUIRED" -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host "`nAction:" -ForegroundColor White -NoNewline
        Write-Host "  $Action" -ForegroundColor Cyan
        Write-Host "Target:" -ForegroundColor White -NoNewline
        Write-Host "  $Target" -ForegroundColor Cyan
        Write-Host "`nThis operation will modify environment variables." -ForegroundColor DarkYellow
        Write-Host "Changes may affect system behavior and running applications." -ForegroundColor DarkYellow
        Write-Host "========================================`n" -ForegroundColor Yellow
        
        do {
            Write-Host "Do you want to proceed with this operation? " -ForegroundColor White -NoNewline
            Write-Host "[Y] Yes  [N] No" -ForegroundColor Gray -NoNewline
            Write-Host ": " -NoNewline
            $response = Read-Host
            $response = $response.Trim().ToUpper()
            
            if ($response -eq 'Y' -or $response -eq 'YES') {
                return $true
            }
            elseif ($response -eq 'N' -or $response -eq 'NO') {
                Write-Host "Operation cancelled." -ForegroundColor Red
                return $false
            }
            else {
                Write-Host "Invalid input. Please enter Y (Yes) or N (No)." -ForegroundColor Red
            }
        } while ($true)
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

    # Check if user typed a help-like argument (--help, -help, /?, etc.)
    if ($Scope -match '^(--?help|/\?|--?\?)$') {
        $Help = $true
        $Scope = $null
    }

    # Safeguard: Check if user typed 'clean' or 'merge' as a variable name instead of using the switch
    if ($Name -and -not $Clean -and -not $Merge) {
        if ($Name -ieq 'clean') {
            Write-Host "Do you mean -Clean? Clean requires parameters: [Scope] and [Variable]." -ForegroundColor Yellow
            Write-Host "Example: envs User Path -Clean" -ForegroundColor Cyan
            return
        }
        if ($Name -ieq 'merge') {
            Write-Host "Do you mean -Merge? Merge requires parameters: [Scope] and [Variable]." -ForegroundColor Yellow
            Write-Host "Example: envs User Path -Merge" -ForegroundColor Cyan
            return
        }
    }

    # Detect if Name looks like a path/value that should be expanded
    # This handles cases like: envs user . -Append (where . should be current dir)
    if ($PSBoundParameters.ContainsKey('Name') -and $Name) {
        $looksLikePathValue = $Name -match '^\.\.?$|^[/\\]|^[a-zA-Z]:[/\\]' -or (Test-Path -LiteralPath $Name -ErrorAction SilentlyContinue)
        
        if ($looksLikePathValue -and -not $PSBoundParameters.ContainsKey('Value')) {
            # User provided what looks like a value in the Name position
            # Error if no operation switch is provided
            if (-not $New -and -not $Append -and -not $Set) {
                Write-Host "Error: '$Name' looks like a path value, not a variable name." -ForegroundColor Red
                Write-Host "To add a path to an environment variable, specify the operation:" -ForegroundColor Yellow
                Write-Host "  envs $Scope Path '$Name' -Append    # Add to PATH" -ForegroundColor Cyan
                Write-Host "  envs $Scope MyVar '$Name' -New      # Create new variable" -ForegroundColor Cyan
                Write-Host "  envs $Scope TOOLS '$Name' -Set      # Set variable and add to PATH" -ForegroundColor Cyan
                return
            }
            
            # Move Name to Value and default Name to 'Path' for path operations
            $Value = $Name
            $Name = 'Path'
            
            # Expand . and .. to full paths
            if ($Value -eq '.') {
                $Value = $PWD.Path
            } elseif ($Value -eq '..') {
                $Value = Split-Path -Parent $PWD.Path
            } elseif (Test-Path -LiteralPath $Value -ErrorAction SilentlyContinue) {
                $Value = (Resolve-Path -LiteralPath $Value).Path
            }
        }
    }

    # Safeguard: If Value is provided, user must specify -New, -Append, or -Set
    if ($PSBoundParameters.ContainsKey('Value')) {
        if (-not $New -and -not $Append -and -not $Set) {
            Write-Host "Error: When providing a Value, you must specify one of: -New, -Append, or -Set" -ForegroundColor Red
            Write-Host "Examples:" -ForegroundColor Cyan
            Write-Host "  envs User MyVar 'C:\Path' -New      # Create/overwrite variable" -ForegroundColor Gray
            Write-Host "  envs User Path 'C:\Tools' -Append   # Append to existing variable" -ForegroundColor Gray
            Write-Host "  envs User JAVA_HOME 'C:\Java' -Set  # Set variable and add %JAVA_HOME% to PATH" -ForegroundColor Gray
            return
        }
        
        # Expand . and .. in Value parameter to full paths
        if ($Value -eq '.') {
            $Value = $PWD.Path
        } elseif ($Value -eq '..') {
            $Value = Split-Path -Parent $PWD.Path
        } elseif ($Value -and (Test-Path -LiteralPath $Value -ErrorAction SilentlyContinue)) {
            # Expand relative paths to absolute paths
            $Value = (Resolve-Path -LiteralPath $Value).Path
        }
    }

    # Validate Scope if provided
    if ($PSBoundParameters.ContainsKey('Scope') -and $Scope) {
        $normalizedScope = ($validScopes | Where-Object { $_ -ieq $Scope } | Select-Object -First 1)
        if (-not $normalizedScope) {
            throw "Scope must be one of: $($validScopes -join ', ')."
        }
        $Scope = $normalizedScope
    }

    # Default Scope to 'Process' if not provided
    if ([string]::IsNullOrEmpty($Scope)) {
        $Scope = 'Process'
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
    envs [Scope] [Name]                Get variable at scope (default Scope=Process)
    envs [Scope]                       List all variables for that scope (Process|User|Machine)
    envs                               List all variables for all scopes

    envs <Scope> <Name> <Value> -New    Create or overwrite variable
    envs <Scope> <Name> <Value> -Append Append literal value to existing variable (semicolon separator)
    envs <Scope> <Name> <Value> -Set    Set variable then append %Name% token to PATH at same scope
    envs <Scope> <Name> -Clean          Remove duplicate values from semicolon-separated variable
    envs <Scope> <Name> -Merge          Expand %VAR% references to actual values and delete referenced vars

PARAMETER ORDER (STRICT):
    1. Scope  - Process, User, or Machine (optional, defaults to Process)
    2. Name   - Variable name (required for most operations)
    3. Value  - Variable value (required with -New, -Append, or -Set)

SWITCHES:
    -New        Create or overwrite the variable with the provided Value
    -Append     Append provided Value to existing variable (adds ';' if needed)
    -Set        Set variable and add %Name% to PATH (if not already there)
    -Clean      Remove duplicate entries from variable (case-insensitive, normalized path comparison)
    -Merge      Expand all %VAR% references in variable to their actual values, then delete those vars
    -Refresh    After modifying User/Machine, rebuild process PATH (Machine;User) and load changed var
    -Confirm    Prompt for confirmation before making changes (enabled by default for all modifications)
    -WhatIf     Show what would happen without making actual changes
    -Help/-?    Show this help

EXAMPLES:
    envs User Path                     Get user PATH
    envs User                          List all user variables
    envs                               List all variables (Process, User, Machine)
    envs User MY_VAR 'C:\MyPath' -New -Refresh
    envs User TOOLS_HOME 'C:\Tools' -Set -Refresh
    envs User Path 'C:\ExtraBin' -Append -Refresh
    envs Process MY_TEMP '123' -New    Set process-only variable
    envs User Path -Clean -Refresh     Remove duplicate paths from user PATH
    envs User Path -Merge -Refresh     Expand %VAR% references and remove those variables

NOTES:
    - When providing a Value, you MUST specify -New, -Append, or -Set.
    - All modification operations (-New, -Append, -Set, -Clean, -Merge) require confirmation by default.
    - Use -Confirm:$false to skip confirmation prompts (e.g., in scripts).
    - Use -WhatIf to preview changes without executing them.
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
    if ($PSBoundParameters.Count -eq 1 -and $PSBoundParameters.ContainsKey('Scope') -and -not $PSBoundParameters.ContainsKey('Name')) {
        # user provided only scope
        if ($Scope -in 'Process','User','Machine') { $singleScopeList = $true }
    }

    $originalProcessValue = $null
    $didModify = $false
    $result = $null

    if ($singleScopeList) {
        $result = Get-AllScopeVars -ListScope $Scope
    }
    else {
        if ($Clean) {
            if (-not $Name) { throw "-Clean requires a variable name (second positional argument)." }

            $current = [Environment]::GetEnvironmentVariable($Name, $Scope)
            if ([string]::IsNullOrEmpty($current)) {
                Write-Warning "Variable '$Name' at scope '$Scope' is empty or does not exist."
                return
            }

            $removedDuplicates = $null
            $cleaned = Remove-DuplicateValues -ValueString $current -RemovedDuplicates ([ref]$removedDuplicates)

            if ($cleaned -eq $current) {
                Write-Host "$Scope $Name is clean! Skipping clean command." -ForegroundColor Green
                $result = New-EnvRecord -RecordScope $Scope -RecordName $Name -RecordValue $current
            } else {
                if (Confirm-EnvAction -Target "$Scope\$Name" -Action "Clean duplicate values") {
                    [Environment]::SetEnvironmentVariable($Name, $cleaned, $Scope)
                    $didModify = $true
                    # Show which values were cleaned
                    foreach ($duplicate in $removedDuplicates) {
                        Write-Host "Removed duplicate: $duplicate" -ForegroundColor Yellow
                    }

                    $result = New-EnvRecord -RecordScope $Scope -RecordName $Name -RecordValue $cleaned
                } else {
                    return
                }
            }
        }
        elseif ($Merge) {
            if (-not $Name) { throw "-Merge requires a variable name (second positional argument)." }

            $current = [Environment]::GetEnvironmentVariable($Name, $Scope)
            if ([string]::IsNullOrEmpty($current)) {
                Write-Warning "Variable '$Name' at scope '$Scope' is empty or does not exist."
                return
            }

            $referencedVars = $null
            $merged = Expand-VariableReferences -ValueString $current -TargetScope $Scope -ReferencedVars ([ref]$referencedVars)

            if ($merged -eq $current) {
                Write-Host "No variable references found in '$Name' at scope '$Scope'."
                $result = New-EnvRecord -RecordScope $Scope -RecordName $Name -RecordValue $current
            } else {
                if (Confirm-EnvAction -Target "$Scope\$Name" -Action "Merge variable references and delete referenced variables") {
                    # Update the variable with expanded values
                    [Environment]::SetEnvironmentVariable($Name, $merged, $Scope)
                    $didModify = $true
                    Write-Host "Merged variable references in '$Name' at scope '$Scope'."

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

                    $result = New-EnvRecord -RecordScope $Scope -RecordName $Name -RecordValue $merged
                } else {
                    return
                }
            }
        }
        elseif ($Set) {
            if (-not $Name) { throw "-Set requires a variable name (second positional argument)." }
            if (-not $PSBoundParameters.ContainsKey('Value')) { throw "-Set requires -Value (third positional argument)." }
            $incoming = $Value
            $existing = [Environment]::GetEnvironmentVariable($Name, $Scope)
            if (Test-ContainsSemicolonValue -Current $existing -Candidate $incoming) {
                Throw-EnvError -Message "Variable '$Name' at scope '$Scope' already contains value '$incoming'." -ErrorId 'EnvVariableDuplicateValue' -Target $Name
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
            if ($Name -ine 'PATH') {
                $pathCurrent = [Environment]::GetEnvironmentVariable('Path', $Scope)
                if (Test-ContainsSemicolonValue -Current $pathCurrent -Candidate $incoming) {
                    Throw-EnvError -Message "PATH at scope '$Scope' already contains value '$incoming'." -ErrorId 'EnvPathDuplicateValue' -Target 'Path'
                }
                $token = "%$Name%"
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
            $pathUpdateMsg = if ($shouldUpdatePath -and $newPath) { " and add %$Name% to PATH" } else { "" }
            if (Confirm-EnvAction -Target "$Scope\$Name = '$Value'" -Action "Set variable$pathUpdateMsg") {
                [Environment]::SetEnvironmentVariable($Name, $Value, $Scope)
                $didModify = $true
                $result = New-EnvRecord -RecordScope $Scope -RecordName $Name -RecordValue ([Environment]::GetEnvironmentVariable($Name, $Scope))

                # Now append a reference %Name% to PATH at same scope (if Name not PATH itself)
                if ($Name -ine 'PATH') {
                    if ($shouldUpdatePath -and $newPath) {
                        [Environment]::SetEnvironmentVariable('Path', $newPath, $Scope)
                        Write-Verbose "Appended $token to PATH at scope $Scope."
                    } else {
                        Write-Verbose "$token already present in PATH at scope $Scope."
                    }
                }
            } else {
                return
            }
        }
        elseif ($Append) {
            if (-not $PSBoundParameters.ContainsKey('Value')) {
                Throw-EnvError -Message "The -Append parameter requires a value to append. Please specify -Value followed by the content you want to add." -ErrorId 'EnvAppendMissingValue' -Target $Name
            }
            if (-not $Name) {
                Throw-EnvError -Message "The -Append parameter requires a variable name. Please specify the name of the environment variable as the second argument." -ErrorId 'EnvAppendMissingName' -Target $null
            }
            $current = [Environment]::GetEnvironmentVariable($Name, $Scope)
            if (Test-ContainsSemicolonValue -Current $current -Candidate $Value) {
                Throw-EnvError -Message "Variable '$Name' at scope '$Scope' already contains value '$Value'." -ErrorId 'EnvVariableDuplicateValue' -Target $Name
            }
            $newValue = Join-SemicolonValue -Current $current -Addition $Value
            if (Confirm-EnvAction -Target "$Scope\$Name" -Action "Append '$Value'") {
                [Environment]::SetEnvironmentVariable($Name, $newValue, $Scope)
                $didModify = $true
                $result = New-EnvRecord -RecordScope $Scope -RecordName $Name -RecordValue ([Environment]::GetEnvironmentVariable($Name, $Scope))
            } else {
                return
            }
        }
        elseif ($PSBoundParameters.ContainsKey('Value')) {
            if (-not $Name) { throw "Setting a value requires a variable name (second positional argument)." }
            # This handles -New switch: create or overwrite the variable
            $actionVerb = if ([Environment]::GetEnvironmentVariable($Name, $Scope)) { "Overwrite" } else { "Create" }
            if (Confirm-EnvAction -Target "$Scope\$Name = '$Value'" -Action "$actionVerb variable") {
                [Environment]::SetEnvironmentVariable($Name, $Value, $Scope)
                $didModify = $true
                $result = New-EnvRecord -RecordScope $Scope -RecordName $Name -RecordValue ([Environment]::GetEnvironmentVariable($Name, $Scope))
            } else {
                return
            }
        }
        else {
            if (-not $Name) { throw "Provide a variable name or a single scope (Process/User/Machine) to list all." }
            $result = New-EnvRecord -RecordScope $Scope -RecordName $Name -RecordValue ([Environment]::GetEnvironmentVariable($Name, $Scope))
        }
    }

    if ($Refresh -and $didModify) {
        if ($Scope -in 'User','Machine') {
            if ($Name -ieq 'PATH' -or $Set -or $Append) {
                $machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
                $userPath    = [Environment]::GetEnvironmentVariable('Path','User')
                $combined = if ([string]::IsNullOrEmpty($machinePath)) { $userPath } elseif ([string]::IsNullOrEmpty($userPath)) { $machinePath } else { "$machinePath;$userPath" }
                $originalProcessValue = $env:Path
                $env:Path = $combined
                Write-Verbose "Process PATH refreshed (was length $($originalProcessValue.Length), now $($env:Path.Length))."
            } else {
                $valToLoad = [Environment]::GetEnvironmentVariable($Name, $Scope)
                if ($null -eq $valToLoad) {
                    Remove-Item -Path "Env:$Name" -ErrorAction SilentlyContinue
                } else {
                    Set-Item -Path "Env:$Name" -Value $valToLoad
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
