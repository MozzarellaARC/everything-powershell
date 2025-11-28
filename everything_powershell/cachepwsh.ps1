<#
.SYNOPSIS
    Move files to another folder with workspace scope management.

.DESCRIPTION
    This script provides file movement operations within a defined workspace scope.
    The workspace is defined by a top-level index file that tracks all files in scope.

.PARAMETER Source
    The source file(s) to move. Supports wildcards and multiple files.

.PARAMETER Destination
    The destination folder where files will be moved.

.PARAMETER WorkspaceRoot
    The root directory of the workspace. Defaults to the script's directory.

.PARAMETER IndexFile
    Path to the workspace index file. Defaults to .workspace-index in WorkspaceRoot.

.PARAMETER Force
    Force move even if destination exists.

.PARAMETER UpdateIndex
    Update the workspace index after moving files.

.PARAMETER WhatIf
    Show what would happen without actually moving files.

.EXAMPLE
    .\cachepwsh.ps1 -Source "file.txt" -Destination "archive"
    Moves file.txt to the archive folder within workspace scope.

.EXAMPLE
    .\cachepwsh.ps1 -Source "*.log" -Destination "logs" -UpdateIndex
    Moves all .log files to logs folder and updates the workspace index.

.EXAMPLE
    .\cachepwsh.ps1 -Init
    Initialize the workspace index by scanning all files in the workspace.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0, ValueFromPipeline = $true)]
    [string[]]$Source,

    [Parameter(Position = 1)]
    [string]$Destination,

    [Parameter()]
    [string]$WorkspaceRoot = $PSScriptRoot,

    [Parameter()]
    [string]$IndexFile,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$UpdateIndex,

    [Parameter()]
    [switch]$Init,

    [Parameter()]
    [switch]$List,

    [Parameter()]
    [switch]$Verify
)

# Set default index file if not specified
if (-not $IndexFile)
{
    $IndexFile = Join-Path $WorkspaceRoot ".workspace-index.json"
}

#region Helper Functions

function Initialize-WorkspaceIndex
{
    <#
    .SYNOPSIS
        Initialize or create the workspace index.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [Parameter(Mandatory)]
        [string]$IndexPath
    )

    Write-Host "Initializing workspace index at: $IndexPath" -ForegroundColor Cyan

    $files = Get-ChildItem -Path $RootPath -Recurse -File | Where-Object {
        $_.FullName -ne $IndexPath -and
        $_.Name -notlike ".*" -and
        $_.Directory.Name -notlike ".*"
    }

    $index = @{
        WorkspaceRoot = $RootPath
        Created = Get-Date -Format "o"
        LastUpdated = Get-Date -Format "o"
        Files = @()
    }

    foreach ($file in $files)
    {
        $relativePath = $file.FullName.Substring($RootPath.Length).TrimStart('\', '/')
        $index.Files += @{
            Path = $relativePath
            OriginalPath = $relativePath
            Hash = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash
            Size = $file.Length
            LastModified = $file.LastWriteTime.ToString("o")
            Moved = $false
        }
    }

    $index | ConvertTo-Json -Depth 10 | Set-Content -Path $IndexPath -Encoding UTF8
    Write-Host "Workspace indexed: $($index.Files.Count) files tracked" -ForegroundColor Green

    return $index
}

function Get-WorkspaceIndex
{
    <#
    .SYNOPSIS
        Load the workspace index from file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IndexPath
    )

    if (-not (Test-Path $IndexPath))
    {
        Write-Warning "Workspace index not found. Run with -Init to create it."
        return $null
    }

    try
    {
        $index = Get-Content -Path $IndexPath -Raw | ConvertFrom-Json
        return $index
    } catch
    {
        Write-Error "Failed to load workspace index: $_"
        return $null
    }
}

function Save-WorkspaceIndex
{
    <#
    .SYNOPSIS
        Save the workspace index to file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Index,

        [Parameter(Mandatory)]
        [string]$IndexPath
    )

    $Index.LastUpdated = Get-Date -Format "o"
    $Index | ConvertTo-Json -Depth 10 | Set-Content -Path $IndexPath -Encoding UTF8
}

function Update-WorkspaceIndexEntry
{
    <#
    .SYNOPSIS
        Update an entry in the workspace index after moving.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Index,

        [Parameter(Mandatory)]
        [string]$OldPath,

        [Parameter(Mandatory)]
        [string]$NewPath
    )

    $entry = $Index.Files | Where-Object { $_.Path -eq $OldPath }

    if ($entry)
    {
        $entry.Path = $NewPath
        $entry.Moved = $true
        $entry.LastModified = (Get-Date -Format "o")
        Write-Verbose "Updated index entry: $OldPath -> $NewPath"
    } else
    {
        Write-Warning "Entry not found in index: $OldPath"
    }
}

function Test-InWorkspace
{
    <#
    .SYNOPSIS
        Check if a path is within the workspace scope.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$WorkspaceRoot
    )

    $fullPath = if ([System.IO.Path]::IsPathRooted($Path))
    {
        $Path
    } else
    {
        Join-Path $WorkspaceRoot $Path
    }

    $resolvedPath = [System.IO.Path]::GetFullPath($fullPath)
    $resolvedRoot = [System.IO.Path]::GetFullPath($WorkspaceRoot)

    return $resolvedPath.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)
}

function Move-WorkspaceFile
{
    <#
    .SYNOPSIS
        Move a file within the workspace scope.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$DestinationPath,

        [Parameter()]
        [switch]$Force
    )

    if (-not (Test-Path $SourcePath))
    {
        Write-Error "Source file not found: $SourcePath"
        return $false
    }

    # Create destination directory if it doesn't exist
    $destDir = Split-Path $DestinationPath -Parent
    if ($destDir -and -not (Test-Path $destDir))
    {
        if ($PSCmdlet.ShouldProcess($destDir, "Create directory"))
        {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            Write-Verbose "Created directory: $destDir"
        }
    }

    # Check if destination exists
    if ((Test-Path $DestinationPath) -and -not $Force)
    {
        Write-Error "Destination already exists: $DestinationPath (use -Force to overwrite)"
        return $false
    }

    # Perform the move
    if ($PSCmdlet.ShouldProcess($SourcePath, "Move to $DestinationPath"))
    {
        try
        {
            Move-Item -Path $SourcePath -Destination $DestinationPath -Force:$Force
            Write-Host "✓ Moved: $SourcePath -> $DestinationPath" -ForegroundColor Green
            return $true
        } catch
        {
            Write-Error "Failed to move file: $_"
            return $false
        }
    }

    return $false
}

function Show-WorkspaceIndex
{
    <#
    .SYNOPSIS
        Display the workspace index contents.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Index
    )

    Write-Host "`n=== Workspace Index ===" -ForegroundColor Cyan
    Write-Host "Root: $($Index.WorkspaceRoot)"
    Write-Host "Created: $($Index.Created)"
    Write-Host "Last Updated: $($Index.LastUpdated)"
    Write-Host "Total Files: $($Index.Files.Count)"
    Write-Host "`nFiles:" -ForegroundColor Yellow

    $Index.Files | Sort-Object Path | ForEach-Object {
        $status = if ($_.Moved)
        { "[MOVED]"
        } else
        { "[    ]"
        }
        $color = if ($_.Moved)
        { "Yellow"
        } else
        { "White"
        }
        Write-Host "$status $($_.Path)" -ForegroundColor $color

        if ($_.Moved -and $_.Path -ne $_.OriginalPath)
        {
            Write-Host "       Original: $($_.OriginalPath)" -ForegroundColor DarkGray
        }
    }
}

function Test-WorkspaceIntegrity
{
    <#
    .SYNOPSIS
        Verify workspace integrity by checking if indexed files exist.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Index,

        [Parameter(Mandatory)]
        [string]$WorkspaceRoot
    )

    Write-Host "`n=== Verifying Workspace Integrity ===" -ForegroundColor Cyan

    $missing = @()
    $found = 0

    foreach ($entry in $Index.Files)
    {
        $fullPath = Join-Path $WorkspaceRoot $entry.Path

        if (Test-Path $fullPath)
        {
            $found++
            Write-Host "✓ $($entry.Path)" -ForegroundColor Green
        } else
        {
            $missing += $entry.Path
            Write-Host "✗ $($entry.Path)" -ForegroundColor Red
        }
    }

    Write-Host "`nSummary:" -ForegroundColor Cyan
    Write-Host "  Found: $found / $($Index.Files.Count)"
    Write-Host "  Missing: $($missing.Count)"

    if ($missing.Count -gt 0)
    {
        Write-Warning "Some files are missing from the workspace!"
    } else
    {
        Write-Host "All files are present in the workspace." -ForegroundColor Green
    }
}

#endregion

#region Main Script Logic

# Initialize workspace if requested
if ($Init)
{
    Initialize-WorkspaceIndex -RootPath $WorkspaceRoot -IndexPath $IndexFile
    exit 0
}

# Load workspace index
$index = Get-WorkspaceIndex -IndexPath $IndexFile

if (-not $index)
{
    Write-Host "Run with -Init to create a workspace index first." -ForegroundColor Yellow
    exit 1
}

# List workspace contents
if ($List)
{
    Show-WorkspaceIndex -Index $index
    exit 0
}

# Verify workspace integrity
if ($Verify)
{
    Test-WorkspaceIntegrity -Index $index -WorkspaceRoot $WorkspaceRoot
    exit 0
}

# Validate parameters for move operation
if (-not $Source -or -not $Destination)
{
    Write-Error "Both -Source and -Destination are required for move operations."
    Write-Host "Use -Init to initialize workspace, -List to view files, or -Verify to check integrity."
    exit 1
}

# Resolve destination path
$destPath = if ([System.IO.Path]::IsPathRooted($Destination))
{
    $Destination
} else
{
    Join-Path $WorkspaceRoot $Destination
}

# Validate destination is in workspace
if (-not (Test-InWorkspace -Path $destPath -WorkspaceRoot $WorkspaceRoot))
{
    Write-Error "Destination is outside workspace scope: $destPath"
    exit 1
}

# Process each source file
$movedFiles = @()

foreach ($sourcePattern in $Source)
{
    # Resolve source path
    $srcPath = if ([System.IO.Path]::IsPathRooted($sourcePattern))
    {
        $sourcePattern
    } else
    {
        Join-Path $WorkspaceRoot $sourcePattern
    }

    # Validate source is in workspace
    if (-not (Test-InWorkspace -Path $srcPath -WorkspaceRoot $WorkspaceRoot))
    {
        Write-Warning "Source is outside workspace scope, skipping: $srcPath"
        continue
    }

    # Get matching files
    $files = Get-Item -Path $srcPath -ErrorAction SilentlyContinue

    if (-not $files)
    {
        Write-Warning "No files found matching: $sourcePattern"
        continue
    }

    foreach ($file in $files)
    {
        # Calculate destination file path
        $destFilePath = if (Test-Path $destPath -PathType Container)
        {
            Join-Path $destPath $file.Name
        } else
        {
            $destPath
        }

        # Move the file
        $success = Move-WorkspaceFile -SourcePath $file.FullName -DestinationPath $destFilePath -Force:$Force

        if ($success)
        {
            # Track for index update
            $oldRelPath = $file.FullName.Substring($WorkspaceRoot.Length).TrimStart('\', '/')
            $newRelPath = $destFilePath.Substring($WorkspaceRoot.Length).TrimStart('\', '/')

            $movedFiles += @{
                OldPath = $oldRelPath
                NewPath = $newRelPath
            }
        }
    }
}

# Update index if requested
if ($UpdateIndex -and $movedFiles.Count -gt 0)
{
    Write-Host "`nUpdating workspace index..." -ForegroundColor Cyan

    foreach ($move in $movedFiles)
    {
        Update-WorkspaceIndexEntry -Index $index -OldPath $move.OldPath -NewPath $move.NewPath
    }

    Save-WorkspaceIndex -Index $index -IndexPath $IndexFile
    Write-Host "Index updated with $($movedFiles.Count) file movement(s)." -ForegroundColor Green
}

Write-Host "`nOperation completed: $($movedFiles.Count) file(s) moved." -ForegroundColor Cyan

if ($movedFiles.Count -gt 0 -and -not $UpdateIndex)
{
    Write-Host "Tip: Use -UpdateIndex to track these changes in the workspace index." -ForegroundColor Yellow
}
