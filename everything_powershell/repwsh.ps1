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

    [CmdletBinding(DefaultParameterSetName='Help')]
    param (
        [Parameter(ParameterSetName='Snake', Mandatory=$true)]
        [switch]$Snake,

        [Parameter(ParameterSetName='ScreamingSnake', Mandatory=$true)]
        [switch]$ScreamingSnake,

        [Parameter(ParameterSetName='Camel', Mandatory=$true)]
        [switch]$Camel,

        [Parameter(ParameterSetName='Title', Mandatory=$true)]
        [switch]$Title,

        [Parameter(ParameterSetName='Kebab', Mandatory=$true)]
        [switch]$Kebab,

        [Parameter(ParameterSetName='Pascal', Mandatory=$true)]
        [switch]$Pascal,

        [Parameter(ParameterSetName='Snake')]
        [Parameter(ParameterSetName='ScreamingSnake')]
        [Parameter(ParameterSetName='Camel')]
        [Parameter(ParameterSetName='Title')]
        [Parameter(ParameterSetName='Kebab')]
        [Parameter(ParameterSetName='Pascal')]
        [switch]$Dir,

        [Parameter(ParameterSetName='Help')]
        [switch]$Help
    )

    if ($Help) {
        Write-Host "`nREPWSH-Organization - File/Folder Renaming Tool" -ForegroundColor Cyan
        Write-Host "=" * 50 -ForegroundColor Cyan
        Write-Host "`nDESCRIPTION:" -ForegroundColor Yellow
        Write-Host "  Renames files or folders in the current directory to different naming conventions."
        Write-Host "  Converts separators (spaces, dashes, etc.) into underscores, camelCase, etc."
        Write-Host "`nPARAMETERS:" -ForegroundColor Yellow
        Write-Host "  -Snake              Convert to snake_case (lowercase with underscores)"
        Write-Host "  -ScreamingSnake     Convert to SCREAMING_SNAKE_CASE (uppercase with underscores)"
        Write-Host "  -Camel              Convert to camelCase"
        Write-Host "  -Title              Convert to Title Case (spaces between words)"
        Write-Host "  -Kebab              Convert to kebab-case (lowercase with dashes)"
        Write-Host "  -Pascal             Convert to PascalCase (no separators, capitalized words)"
        Write-Host "  -Dir                Apply to directories instead of files"
        Write-Host "  -Help               Display this help message"
        Write-Host "`nEXAMPLES:" -ForegroundColor Yellow
        Write-Host "  # Convert files with spaces to snake_case:"
        Write-Host "  rep -Snake          # 'My Document.txt' -> 'my_document.txt'"
        Write-Host ""
        Write-Host "  # Convert mixed separators to SCREAMING_SNAKE_CASE:"
        Write-Host "  rep -ScreamingSnake # 'user-data_file.json' -> 'USER_DATA_FILE.JSON'"
        Write-Host ""
        Write-Host "  # Convert to camelCase (good for JS/web files):"
        Write-Host "  rep -Camel          # 'header-component.js' -> 'headerComponent.js'"
        Write-Host ""
        Write-Host "  # Convert to Title Case (human readable):"
        Write-Host "  rep -Title          # 'project_notes.md' -> 'Project Notes.md'"
        Write-Host ""
        Write-Host "  # Convert to kebab-case (web-friendly):"
        Write-Host "  rep -Kebab          # 'UserProfile.css' -> 'user-profile.css'"
        Write-Host ""
        Write-Host "  # Convert to PascalCase (class names):"
        Write-Host "  rep -Pascal         # 'api_helper.py' -> 'ApiHelper.py'"
        Write-Host ""
        Write-Host "  # Rename directories instead of files:"
        Write-Host "  rep -Snake -Dir     # Rename folders to snake_case"
        Write-Host ""
        return
    }

    if (-not $Snake -and -not $ScreamingSnake -and -not $Camel -and -not $Title -and -not $Kebab -and -not $Pascal) {
        Write-Error "Please specify either -Snake, -ScreamingSnake, -Camel, -Title, -Kebab, or -Pascal parameter"
        Write-Host "Use -Help for usage information" -ForegroundColor Cyan
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
        $newName = if ($Snake) {
            ConvertTo-SimpleSnake -InputString $oldName -Screaming:$false
        } elseif ($ScreamingSnake) {
            ConvertTo-SimpleSnake -InputString $oldName -Screaming:$true
        } elseif ($Camel) {
            ConvertTo-SimpleCamel -InputString $oldName
        } elseif ($Title) {
            ConvertTo-TitleCase -InputString $oldName
        } elseif ($Kebab) {
            ConvertTo-KebabCase -InputString $oldName
        } else {
            ConvertTo-PascalCase -InputString $oldName
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
