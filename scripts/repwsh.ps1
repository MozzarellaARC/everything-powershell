function REPWSH-Organization {
    <#
    .SYNOPSIS
        Renames files or folders in the current directory to various naming conventions.

    .DESCRIPTION
        Converts file or folder names to snake, screaming, camel, pascal, title, or kebab naming conventions.
        Converts all separators (spaces, dashes, underscores, etc.) based on the selected convention.
        Does not split existing camelCase or PascalCase.
        Safe for case-only renames on Windows.
    #>

    [CmdletBinding(DefaultParameterSetName='Rename')]
    param (
        [Parameter(Position=0, ParameterSetName='Rename')]
        [ValidateSet('snake', 'screaming', 'camel', 'title', 'kebab', 'pascal', 'normal')]
        [string]$Case,

        [Parameter(ParameterSetName='Rename')]
        [switch]$Dir,

        [Parameter(ParameterSetName='Help')]
        [switch]$Help
    )

    if ($Help -or -not $Case) {
        Write-Host "`nREPWSH-Organization - File/Folder Renaming Tool" -ForegroundColor Cyan
        Write-Host "=" * 50 -ForegroundColor Cyan
        Write-Host "`nDESCRIPTION:" -ForegroundColor Yellow
        Write-Host "  Renames files or folders in the current directory to different naming conventions."
        Write-Host "  Converts separators (spaces, dashes, etc.) into underscores, camelCase, etc."
        Write-Host "`nPARAMETERS:" -ForegroundColor Yellow
        Write-Host "  snake               Convert to snake_case (lowercase with underscores)"
        Write-Host "  screaming           Convert to SCREAMING_SNAKE_CASE (uppercase with underscores)"
        Write-Host "  camel               Convert to camelCase"
        Write-Host "  title               Convert to Title Case (spaces between words)"
        Write-Host "  kebab               Convert to kebab-case (lowercase with dashes)"
        Write-Host "  pascal              Convert to PascalCase (no separators, capitalized words)"
        Write-Host "  normal              Convert to Normal case (spaces with capitalized words)"
        Write-Host "  -Dir                Apply to directories instead of files"
        Write-Host "  -Help               Display this help message"
        Write-Host "`nEXAMPLES:" -ForegroundColor Yellow
        Write-Host "  # Convert files with spaces to snake_case:"
        Write-Host "  rep snake           # 'My Document.txt' -> 'my_document.txt'"
        Write-Host ""
        Write-Host "  # Convert mixed separators to SCREAMING_SNAKE_CASE:"
        Write-Host "  rep screaming       # 'user-data_file.json' -> 'USER_DATA_FILE.JSON'"
        Write-Host ""
        Write-Host "  # Convert to camelCase (good for JS/web files):"
        Write-Host "  rep camel           # 'header-component.js' -> 'headerComponent.js'"
        Write-Host ""
        Write-Host "  # Convert to Title Case (human readable):"
        Write-Host "  rep title           # 'project_notes.md' -> 'Project Notes.md'"
        Write-Host ""
        Write-Host "  # Convert to kebab-case (web-friendly):"
        Write-Host "  rep kebab           # 'UserProfile.css' -> 'user-profile.css'"
        Write-Host ""
        Write-Host "  # Convert to PascalCase (class names):"
        Write-Host "  rep pascal          # 'api_helper.py' -> 'ApiHelper.py'"
        Write-Host ""
        Write-Host "  # Convert to Normal case (natural spacing):"
        Write-Host "  rep normal          # 'reference-image' -> 'Reference Image'"
        Write-Host ""
        Write-Host "  # Rename directories instead of files:"
        Write-Host "  rep snake -Dir      # Rename folders to snake_case"
        Write-Host ""
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
        if ($words.Count -eq 0) { return $InputString }

        $result = $words[0].ToLower()
        for ($i = 1; $i -lt $words.Count; $i++) {
            $result += ($words[$i].Substring(0,1).ToUpper() + $words[$i].Substring(1).ToLower())
        }
        return $result + $extension.ToLower()
    }

    function ConvertTo-TitleCase {
        param([string]$InputString)
        $extension = [System.IO.Path]::GetExtension($InputString)
        $name = [System.IO.Path]::GetFileNameWithoutExtension($InputString)

        $words = @($name -split '[^a-zA-Z0-9]+' | Where-Object { $_ })
        if ($words.Count -eq 0) { return $InputString }

        $result = ($words | ForEach-Object {
            $_.Substring(0,1).ToUpper() + $_.Substring(1).ToLower()
        }) -join ' '

        return $result + $extension.ToLower()
    }

    function ConvertTo-KebabCase {
        param([string]$InputString)
        $extension = [System.IO.Path]::GetExtension($InputString)
        $name = [System.IO.Path]::GetFileNameWithoutExtension($InputString)

        $name = $name -replace '[^a-zA-Z0-9]+', '-'
        $name = $name.Trim('-') -replace '-+', '-'

        return ($name + $extension).ToLower()
    }

    function ConvertTo-PascalCase {
        param([string]$InputString)
        $extension = [System.IO.Path]::GetExtension($InputString)
        $name = [System.IO.Path]::GetFileNameWithoutExtension($InputString)

        $words = @($name -split '[^a-zA-Z0-9]+' | Where-Object { $_ })
        if ($words.Count -eq 0) { return $InputString }

        $result = ($words | ForEach-Object {
            $_.Substring(0,1).ToUpper() + $_.Substring(1).ToLower()
        }) -join ''

        return $result + $extension.ToLower()
    }

    function ConvertTo-NormalCase {
        param([string]$InputString)
        $extension = [System.IO.Path]::GetExtension($InputString)
        $name = [System.IO.Path]::GetFileNameWithoutExtension($InputString)

        $words = @($name -split '[^a-zA-Z0-9]+' | Where-Object { $_ })
        if ($words.Count -eq 0) { return $InputString }

        # Capitalize first letter of every word
        $result = ($words | ForEach-Object {
            $_.Substring(0,1).ToUpper() + $_.Substring(1).ToLower()
        }) -join ' '

        return $result + $extension.ToLower()
    }

    # Select files or directories depending on flag
    $items = if ($Dir) {
        Get-ChildItem -Directory
    } else {
        Get-ChildItem -File
    }

    $renamedCount = 0
    $skippedCount = 0

    foreach ($item in $items) {
        $oldName = $item.Name
        $newName = switch ($Case.ToLower()) {
            'snake' {
                ConvertTo-SimpleSnake -InputString $oldName -Screaming:$false
            }
            'screaming' {
                ConvertTo-SimpleSnake -InputString $oldName -Screaming:$true
            }
            'camel' {
                ConvertTo-SimpleCamel -InputString $oldName
            }
            'title' {
                ConvertTo-TitleCase -InputString $oldName
            }
            'kebab' {
                ConvertTo-KebabCase -InputString $oldName
            }
            'pascal' {
                ConvertTo-PascalCase -InputString $oldName
            }
            'normal' {
                ConvertTo-NormalCase -InputString $oldName
            }
        }

        if ($oldName -ceq $newName) {
            Write-Verbose "Skipped: $oldName (no change needed)"
            $skippedCount++
            continue
        }

        $oldPath = $item.FullName
        $parentPath = Split-Path -Path $item.FullName -Parent
        $newPath = Join-Path -Path $parentPath -ChildPath $newName

        try {
            # Attempt normal rename first
            Rename-Item -Path $oldPath -NewName $newName -ErrorAction Stop
            Write-Host "Renamed: $oldName -> $newName" -ForegroundColor Green
            $renamedCount++
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
                }
                catch {
                    Write-Warning "Failed to perform case-only rename for $oldName -> $newName"
                    $skippedCount++
                }
            } else {
                Write-Warning "Skipped: $oldName -> $newName ($($_.Exception.Message))"
                $skippedCount++
            }
        }
    }

    Write-Host "`nSummary:" -ForegroundColor Cyan
    Write-Host "  Renamed: $renamedCount" -ForegroundColor Green
    Write-Host "  Skipped: $skippedCount" -ForegroundColor Yellow
}

# Alias for quick use
Set-Alias -Name rep -Value REPWSH-Organization
