function REPWSH-Organization {
    <#
    .SYNOPSIS
        Renames files in the current directory to snake_case, SCREAMING_SNAKE_CASE, or camelCase.

    .DESCRIPTION
        Converts all separators (spaces, dashes, etc.) into underscores.
        Does not split camelCase or PascalCase.
        Safe for case-only renames on Windows.
    #>

    [CmdletBinding()]
    param (
        [Parameter(ParameterSetName='Snake')]
        [switch]$Snake,
        
        [Parameter(ParameterSetName='ScreamingSnake')]
        [switch]$ScreamingSnake,
        
        [Parameter(ParameterSetName='Camel')]
        [switch]$Camel
    )
    
    if (-not $Snake -and -not $ScreamingSnake -and -not $Camel) {
        Write-Error "Please specify either -Snake, -ScreamingSnake, or -Camel parameter"
        return
    }

    # Convert functions
    function ConvertTo-SimpleSnake {
        param([string]$InputString, [bool]$Screaming = $false)
        $extension = [System.IO.Path]::GetExtension($InputString)
        $name = [System.IO.Path]::GetFileNameWithoutExtension($InputString)

        $name = $name -replace '[^a-zA-Z0-9]+', '_'
        $name = $name.Trim('_') -replace '_+', '_'

        if ($Screaming) {
            return ($name + $extension).ToUpper()
        } else {
            return ($name + $extension).ToLower()
        }
    }

    function ConvertTo-SimpleCamel {
        param([string]$InputString)
        $extension = [System.IO.Path]::GetExtension($InputString)
        $name = [System.IO.Path]::GetFileNameWithoutExtension($InputString)

        $words = @($name -split '[^a-zA-Z0-9]+' | Where-Object { $_ })
        if ($words.Count -ceq 0) { return $InputString }

        $result = $words[0].ToLower()
        for ($i = 1; $i -lt $words.Count; $i++) {
            $result += ($words[$i].Substring(0,1).ToUpper() + $words[$i].Substring(1).ToLower())
        }
        return $result + $extension.ToLower()
    }

    $items = Get-ChildItem -File
    $renamedCount = 0
    $skippedCount = 0

    foreach ($item in $items) {
        $oldName = $item.Name
        $newName = if ($Snake) {
            ConvertTo-SimpleSnake -InputString $oldName -Screaming:$false
        } elseif ($ScreamingSnake) {
            ConvertTo-SimpleSnake -InputString $oldName -Screaming:$true
        } else {
            ConvertTo-SimpleCamel -InputString $oldName
        }

        if ($oldName -ceq $newName) {
            Write-Verbose "Skipped: $oldName (no change needed)"
            $skippedCount++
            continue
        }

        $oldPath = $item.FullName
        $parentPath = $item.DirectoryName
        $newPath = Join-Path -Path $parentPath -ChildPath $newName

        try {
                # Attempt normal rename first
                Rename-Item -Path $oldPath -NewName $newName -ErrorAction Stop
            }
            catch {
                # If it fails because the name only differs by case (Windows issue)
                if ($_.Exception.Message -match 'already exists') {
                    try {
                        $tempName = "$newName.__temp__"
                        Rename-Item -Path $oldPath -NewName $tempName -ErrorAction Stop
                        Rename-Item -Path (Join-Path $parentPath $tempName) -NewName $newName -ErrorAction Stop
                        Write-Host "Renamed (case-only): $oldName -> $newName" -ForegroundColor Cyan
                        $renamedCount++
                        continue
                    }
                    catch {
                        Write-Warning "Failed to perform case-only rename for $oldName -> $newName"
                        $skippedCount++
                        continue
                    }
                } else {
                    Write-Warning "Skipped: $oldName -> $newName ($($_.Exception.Message))"
                    $skippedCount++
                    continue
                }
            }

            Write-Host "Renamed: $oldName -> $newName" -ForegroundColor Green
            $renamedCount++
    }

    Write-Host "`nSummary:" -ForegroundColor Cyan
    Write-Host "  Renamed: $renamedCount" -ForegroundColor Green
    Write-Host "  Skipped: $skippedCount" -ForegroundColor Yellow
}

# Alias for quick use
Set-Alias -Name rep -Value REPWSH-Organization