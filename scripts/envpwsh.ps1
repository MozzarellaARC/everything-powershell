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

    function Test-IsAdmin {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]$identity
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    function Test-ValidVariableName {
        param([string]$VarName)
        
        if ([string]::IsNullOrWhiteSpace($VarName)) { return $false }
        
        # Windows environment variable naming restrictions:
        # - Cannot contain =
        # - Should not contain null characters
        # - Typically avoid special characters for compatibility
        if ($VarName -match '[=\x00]') {
            return $false
        }
        
        return $true
    }

    function Write-EnvHeader {
        param([string]$Title)
        
        Write-Host "`n========================================" -ForegroundColor Yellow
        Write-Host "  $Title" -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor Yellow
    }

    function Write-EnvError {
        param(
            [string]$Message,
            [string[]]$Details,
            [string[]]$Examples
        )
        
        Write-EnvHeader "ERROR"
        Write-Host $Message -ForegroundColor Red
        
        if ($Details) {
            Write-Host ""
            foreach ($detail in $Details) {
                Write-Host "  $detail" -ForegroundColor DarkYellow
            }
        }
        
        if ($Examples) {
            Write-Host "`nExamples:" -ForegroundColor White
            foreach ($example in $Examples) {
                Write-Host "  $example" -ForegroundColor Gray
            }
        }
        
        Write-Host "========================================`n" -ForegroundColor Yellow
    }

    function Write-EnvInfo {
        param(
            [string]$Message,
            [string[]]$Examples
        )
        
        Write-Host "`n$Message" -ForegroundColor Yellow
        
        if ($Examples) {
            foreach ($example in $Examples) {
                Write-Host "  $example" -ForegroundColor Cyan
            }
        }
        Write-Host ""
    }

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

        # Confirmation prompt
        Write-Host ""
        Write-Host "Confirm" -ForegroundColor Yellow
        Write-Host "$Action" -ForegroundColor White
        Write-Host "Target: " -NoNewline -ForegroundColor DarkGray
        Write-Host "$Target" -ForegroundColor Cyan
        Write-Host ""
        
        do {
            Write-Host "[Y] Yes  [N] No: " -ForegroundColor Gray -NoNewline
            $response = Read-Host
            $response = $response.Trim().ToUpper()
            
            if ($response -eq 'Y' -or $response -eq 'YES') {
                return $true
            }
            elseif ($response -eq 'N' -or $response -eq 'NO') {
                Write-Host "Operation cancelled.`n" -ForegroundColor Red
                return $false
            }
            else {
                Write-Host "Invalid input. Please enter Y or N." -ForegroundColor Red
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
            [object]$Target,
            [string[]]$Details,
            [string[]]$Suggestions
        )

        # Build complete error message with formatting
        $fullMessage = $Message
        
        if ($Details) {
            $fullMessage += "`n"
            foreach ($detail in $Details) {
                $fullMessage += "`n  • $detail"
            }
        }
        
        if ($Suggestions) {
            $fullMessage += "`n`nSuggestions:"
            foreach ($suggestion in $Suggestions) {
                $fullMessage += "`n  $suggestion"
            }
        }

        # Throw the error (PowerShell will display it)
        $exception = [System.InvalidOperationException]::new($fullMessage)
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
            Write-EnvInfo -Message "Do you mean -Clean? Clean requires parameters: [Scope] and [Variable]." -Examples @("envs User Path -Clean")
            return
        }
        if ($Name -ieq 'merge') {
            Write-EnvInfo -Message "Do you mean -Merge? Merge requires parameters: [Scope] and [Variable]." -Examples @("envs User Path -Merge")
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
                Write-EnvError -Message "'$Name' looks like a path value, not a variable name." `
                    -Details @("To add a path to an environment variable, specify the operation:") `
                    -Examples @(
                        "envs $Scope Path '$Name' -Append    # Add to PATH",
                        "envs $Scope MyVar '$Name' -New      # Create new variable",
                        "envs $Scope TOOLS '$Name' -Set      # Set variable and add to PATH"
                    )
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
            Write-EnvError -Message "When providing a Value, you must specify one of: -New, -Append, or -Set" `
                -Examples @(
                    "envs User MyVar 'C:\Path' -New      # Create/overwrite variable",
                    "envs User Path 'C:\Tools' -Append   # Append to existing variable",
                    "envs User JAVA_HOME 'C:\Java' -Set  # Set variable and add %JAVA_HOME% to PATH"
                )
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

    # Validate variable name if provided
    if ($Name -and -not (Test-ValidVariableName -VarName $Name)) {
        Throw-EnvError -Message "Invalid variable name '$Name'." `
            -Details @("Variable names cannot contain '=' or null characters.") `
            -Suggestions @("Use alphanumeric characters and underscores only.") `
            -ErrorId 'EnvInvalidVariableName' -Target $Name
    }

    # Check for admin rights when modifying Machine scope
    if ($Scope -eq 'Machine') {
        $isModifying = $New -or $Append -or $Set -or $Clean -or $Merge -or $PSBoundParameters.ContainsKey('Value')
        if ($isModifying -and -not (Test-IsAdmin)) {
            Throw-EnvError -Message "Modifying Machine scope environment variables requires administrator privileges." `
                -Suggestions @(
                    "Right-click PowerShell and select 'Run as Administrator'",
                    "Or use 'User' scope instead: envs User $Name ..."
                ) `
                -ErrorId 'EnvMachineRequiresAdmin' -Target $Scope
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

        # Help requested -> print and exit early
        if ($Help) {
            Write-EnvHeader "ENVS - ENVIRONMENT VARIABLE HELPER"
            
            Write-Host "`nUSAGE:" -ForegroundColor White
            Write-Host "  envs [Scope] [Name]                  " -NoNewline -ForegroundColor Gray
            Write-Host "Get variable at scope (default: Process)" -ForegroundColor DarkGray
            Write-Host "  envs [Scope]                         " -NoNewline -ForegroundColor Gray
            Write-Host "List all variables for that scope" -ForegroundColor DarkGray
            Write-Host "  envs                                 " -NoNewline -ForegroundColor Gray
            Write-Host "List all variables (all scopes)" -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "  envs <Scope> <Name> <Value> -New     " -NoNewline -ForegroundColor Gray
            Write-Host "Create or overwrite variable" -ForegroundColor DarkGray
            Write-Host "  envs <Scope> <Name> <Value> -Append  " -NoNewline -ForegroundColor Gray
            Write-Host "Append value to variable" -ForegroundColor DarkGray
            Write-Host "  envs <Scope> <Name> <Value> -Set     " -NoNewline -ForegroundColor Gray
            Write-Host "Set variable and add %Name% to PATH" -ForegroundColor DarkGray
            Write-Host "  envs <Scope> <Name> -Clean           " -NoNewline -ForegroundColor Gray
            Write-Host "Remove duplicate values" -ForegroundColor DarkGray
            Write-Host "  envs <Scope> <Name> -Merge           " -NoNewline -ForegroundColor Gray
            Write-Host "Expand %VAR% references and delete vars" -ForegroundColor DarkGray
            
            Write-Host "`nPARAMETER ORDER:" -ForegroundColor White
            Write-Host "  1. Scope  " -NoNewline -ForegroundColor Cyan
            Write-Host "- Process, User, or Machine (optional, defaults to Process)" -ForegroundColor Gray
            Write-Host "  2. Name   " -NoNewline -ForegroundColor Cyan
            Write-Host "- Variable name (required for most operations)" -ForegroundColor Gray
            Write-Host "  3. Value  " -NoNewline -ForegroundColor Cyan
            Write-Host "- Variable value (required with -New, -Append, or -Set)" -ForegroundColor Gray
            
            Write-Host "`nSWITCHES:" -ForegroundColor White
            Write-Host "  -New     " -NoNewline -ForegroundColor Cyan
            Write-Host " Create or overwrite the variable with the provided Value" -ForegroundColor Gray
            Write-Host "  -Append  " -NoNewline -ForegroundColor Cyan
            Write-Host " Append provided Value to existing variable (adds ';' separator)" -ForegroundColor Gray
            Write-Host "  -Set     " -NoNewline -ForegroundColor Cyan
            Write-Host " Set variable and add %Name% to PATH (if not already there)" -ForegroundColor Gray
            Write-Host "  -Clean   " -NoNewline -ForegroundColor Cyan
            Write-Host " Remove duplicate entries (case-insensitive, normalized paths)" -ForegroundColor Gray
            Write-Host "  -Merge   " -NoNewline -ForegroundColor Cyan
            Write-Host " Expand all %VAR% references and delete those variables" -ForegroundColor Gray
            Write-Host "  -Refresh " -NoNewline -ForegroundColor Cyan
            Write-Host " Update process environment after modifying User/Machine scope" -ForegroundColor Gray
            Write-Host "  -Confirm " -NoNewline -ForegroundColor Cyan
            Write-Host " Prompt for confirmation (enabled by default for modifications)" -ForegroundColor Gray
            Write-Host "  -WhatIf  " -NoNewline -ForegroundColor Cyan
            Write-Host " Preview changes without executing them" -ForegroundColor Gray
            Write-Host "  -Help/-? " -NoNewline -ForegroundColor Cyan
            Write-Host " Show this help" -ForegroundColor Gray
            
            Write-Host "`nEXAMPLES:" -ForegroundColor White
            Write-Host "  envs User Path                           " -NoNewline -ForegroundColor Cyan
            Write-Host "# Get user PATH" -ForegroundColor DarkGray
            Write-Host "  envs User                                " -NoNewline -ForegroundColor Cyan
            Write-Host "# List all user variables" -ForegroundColor DarkGray
            Write-Host "  envs                                     " -NoNewline -ForegroundColor Cyan
            Write-Host "# List all variables (all scopes)" -ForegroundColor DarkGray
            Write-Host "  envs User MY_VAR 'C:\MyPath' -New        " -NoNewline -ForegroundColor Cyan
            Write-Host "# Create new variable" -ForegroundColor DarkGray
            Write-Host "  envs User TOOLS_HOME 'C:\Tools' -Set     " -NoNewline -ForegroundColor Cyan
            Write-Host "# Set variable + add to PATH" -ForegroundColor DarkGray
            Write-Host "  envs User Path 'C:\ExtraBin' -Append     " -NoNewline -ForegroundColor Cyan
            Write-Host "# Append to PATH" -ForegroundColor DarkGray
            Write-Host "  envs Process MY_TEMP '123' -New          " -NoNewline -ForegroundColor Cyan
            Write-Host "# Set process-only variable" -ForegroundColor DarkGray
            Write-Host "  envs User Path -Clean -Refresh           " -NoNewline -ForegroundColor Cyan
            Write-Host "# Remove duplicate paths" -ForegroundColor DarkGray
            Write-Host "  envs User Path -Merge -Refresh           " -NoNewline -ForegroundColor Cyan
            Write-Host "# Expand %VAR% references" -ForegroundColor DarkGray
            
            Write-Host "`nNOTES:" -ForegroundColor White
            Write-Host "  • When providing a Value, you MUST specify -New, -Append, or -Set" -ForegroundColor DarkYellow
            Write-Host "  • All modifications require confirmation by default (use -Confirm:`$false to skip)" -ForegroundColor DarkYellow
            Write-Host "  • Use -WhatIf to preview changes without executing them" -ForegroundColor DarkYellow
            Write-Host "  • -Set is for directory variables you want on PATH via %VARNAME% expansion" -ForegroundColor DarkYellow
            Write-Host "  • -Refresh only needed for persistent scopes (User/Machine) to update session" -ForegroundColor DarkYellow
            Write-Host "  • Interactive output auto-splits ';' separated values onto new lines" -ForegroundColor DarkYellow
            Write-Host "  • Missing/invalid paths are displayed in " -NoNewline -ForegroundColor DarkYellow
            Write-Host "red" -NoNewline -ForegroundColor Red
            Write-Host " for easy identification" -ForegroundColor DarkYellow
            Write-Host "  • -Clean uses normalized path comparison (e.g., C:\Tools\ = C:\Tools)" -ForegroundColor DarkYellow
            Write-Host "  • Returned objects are PSCustomObjects for pipeline processing" -ForegroundColor DarkYellow
            
            Write-Host "========================================`n" -ForegroundColor Yellow
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
            if (-not $Name) {
                Throw-EnvError -Message "The -Clean parameter requires a variable name." `
                    -Suggestions @("envs User Path -Clean", "envs Machine CLASSPATH -Clean") `
                    -ErrorId 'EnvCleanMissingName' -Target $null
            }

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
            if (-not $Name) {
                Throw-EnvError -Message "The -Merge parameter requires a variable name." `
                    -Suggestions @("envs User Path -Merge", "envs User CLASSPATH -Merge") `
                    -ErrorId 'EnvMergeMissingName' -Target $null
            }

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

                            # Use proper .NET API instead of direct registry access
                            try {
                                [Environment]::SetEnvironmentVariable($refVarName, $null, $Scope)
                                Write-Verbose "Successfully deleted '$refVarName' from scope '$Scope'."
                            }
                            catch {
                                Write-Warning "Failed to delete variable '$refVarName': $_"
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
            if (-not $Name) {
                Throw-EnvError -Message "The -Set parameter requires a variable name." `
                    -Suggestions @("envs User JAVA_HOME 'C:\\Java' -Set") `
                    -ErrorId 'EnvSetMissingName' -Target $null
            }
            if (-not $PSBoundParameters.ContainsKey('Value')) {
                Throw-EnvError -Message "The -Set parameter requires a value." `
                    -Suggestions @("envs User $Name 'C:\\SomePath' -Set") `
                    -ErrorId 'EnvSetMissingValue' -Target $Name
            }
            $incoming = $Value
            $existing = [Environment]::GetEnvironmentVariable($Name, $Scope)
            if (Test-ContainsSemicolonValue -Current $existing -Candidate $incoming) {
                Throw-EnvError -Message "Variable '$Name' at scope '$Scope' already contains value '$incoming'." `
                    -Suggestions @(
                        "Use -New to overwrite the entire variable",
                        "Use -Clean to remove duplicates: envs $Scope $Name -Clean"
                    ) `
                    -ErrorId 'EnvVariableDuplicateValue' -Target $Name
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
                    Throw-EnvError -Message "PATH at scope '$Scope' already contains value '$incoming'." `
                        -Suggestions @("Use -Clean to remove duplicates from PATH: envs $Scope Path -Clean") `
                        -ErrorId 'EnvPathDuplicateValue' -Target 'Path'
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
                Throw-EnvError -Message "The -Append parameter requires a value to append." `
                    -Suggestions @("envs User Path 'C:\\Tools' -Append") `
                    -ErrorId 'EnvAppendMissingValue' -Target $Name
            }
            if (-not $Name) {
                Throw-EnvError -Message "The -Append parameter requires a variable name." `
                    -Suggestions @("envs User Path 'C:\\Tools' -Append") `
                    -ErrorId 'EnvAppendMissingName' -Target $null
            }
            $current = [Environment]::GetEnvironmentVariable($Name, $Scope)
            if (Test-ContainsSemicolonValue -Current $current -Candidate $Value) {
                Throw-EnvError -Message "Variable '$Name' at scope '$Scope' already contains value '$Value'." `
                    -Suggestions @("Use -Clean to remove duplicates: envs $Scope $Name -Clean") `
                    -ErrorId 'EnvVariableDuplicateValue' -Target $Name
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
            if (-not $Name) {
                Throw-EnvError -Message "Setting a value requires a variable name." `
                    -Suggestions @("envs User MY_VAR 'value' -New") `
                    -ErrorId 'EnvValueMissingName' -Target $null
            }
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
            if (-not $Name) {
                Throw-EnvError -Message "Please provide a variable name or a single scope to list all variables." `
                    -Suggestions @(
                        "envs User              # List all User variables",
                        "envs User Path         # Show User PATH variable"
                    ) `
                    -ErrorId 'EnvMissingNameOrScope' -Target $null
            }
            
            # Check if user provided -New, -Set, or -Append without -Value
            if ($New) {
                Throw-EnvError -Message "The -New parameter requires a value." `
                    -Suggestions @("envs $Scope $Name 'some value' -New") `
                    -ErrorId 'EnvNewMissingValue' -Target $Name
            }
            elseif ($Set) {
                Throw-EnvError -Message "The -Set parameter requires a value." `
                    -Suggestions @("envs $Scope $Name 'C:\\SomePath' -Set") `
                    -ErrorId 'EnvSetMissingValue' -Target $Name
            }
            
            # User is querying a variable
            $varValue = [Environment]::GetEnvironmentVariable($Name, $Scope)
            if ($null -eq $varValue) {
                Throw-EnvError -Message "Environment variable '$Name' does not exist in scope '$Scope'." `
                    -Suggestions @("envs $Scope $Name 'value' -New    # Create the variable") `
                    -ErrorId 'EnvVariableNotFound' -Target $Name
            }
            $result = New-EnvRecord -RecordScope $Scope -RecordName $Name -RecordValue $varValue
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
