function REPWSH-Organization {
    <#
    .SYNOPSIS
        Renames files and folders to snake_case or camelCase
    
    .DESCRIPTION
        Renames all files in the current directory to either snake_case or camelCase.
        Use -Dir switch to include directories in the renaming process.
    
    .PARAMETER Snake
        Rename items to snake_case format
    
    .PARAMETER Camel
        Rename items to camelCase format
    
    .PARAMETER Dir
        Include directories in the renaming process (files only by default)
    
    .PARAMETER Path
        Path to process (defaults to current directory)
    
    .EXAMPLE
        REPWSH-Organization -Snake
        Renames all files in current directory to snake_case
    
    .EXAMPLE
        REPWSH-Organization -Camel -Dir
        Renames all files and directories to camelCase
    
    .EXAMPLE
        rep -Snake -Path "C:\MyFolder"
        Renames all files in specified path to snake_case
    #>
    
    [CmdletBinding()]
    param (
        [Parameter(ParameterSetName='Snake')]
        [switch]$Snake,
        
        [Parameter(ParameterSetName='Camel')]
        [switch]$Camel,
        
        [switch]$Dir,
        
        [string]$Path = (Get-Location)
    )
    
    # Validate that either Snake or Camel is specified
    if (-not $Snake -and -not $Camel) {
        Write-Error "Please specify either -Snake or -Camel parameter"
        return
    }
    
    # Validate path exists
    if (-not (Test-Path $Path)) {
        Write-Error "Path '$Path' does not exist"
        return
    }
    
    # Function to convert string to snake_case
    function ConvertTo-SnakeCase {
        param([string]$InputString)
        
        # Remove extension
        $extension = [System.IO.Path]::GetExtension($InputString)
        $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($InputString)
        
        # Insert underscore before capital letters (for camelCase/PascalCase conversion)
        # This handles transitions like "aB" -> "a_B"
        $result = $nameWithoutExt -creplace '([a-z0-9])([A-Z])', '$1_$2'
        
        # Insert underscore between consecutive capitals followed by lowercase
        # This handles "HTTPResponse" -> "HTTP_Response"
        $result = $result -creplace '([A-Z]+)([A-Z][a-z])', '$1_$2'
        
        # Replace spaces and special characters with underscores
        $result = $result -replace '[^a-zA-Z0-9]+', '_'
        
        # Convert to lowercase
        $result = $result.ToLower()
        
        # Remove leading/trailing underscores
        $result = $result.Trim('_')
        
        # Replace multiple underscores with single underscore
        $result = $result -replace '_+', '_'
        
        return $result + $extension.ToLower()
    }
    
    # Function to convert string to camelCase
    function ConvertTo-CamelCase {
        param([string]$InputString)
        
        # Remove extension
        $extension = [System.IO.Path]::GetExtension($InputString)
        $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($InputString)
        
        # Split on non-alphanumeric characters and capital letters
        $words = @($nameWithoutExt -split '[^a-zA-Z0-9]+' | Where-Object { $_ })
        
        if ($words.Count -eq 0) {
            return $InputString
        }
        
        # First word lowercase, capitalize first letter of subsequent words
        $result = $words[0].ToLower()
        
        for ($i = 1; $i -lt $words.Count; $i++) {
            if ($words[$i].Length -gt 0) {
                $result += $words[$i].Substring(0, 1).ToUpper()
                if ($words[$i].Length -gt 1) {
                    $result += $words[$i].Substring(1).ToLower()
                }
            }
        }
        
        return $result + $extension.ToLower()
    }
    
    # Get items to rename
    $items = if ($Dir) {
        Get-ChildItem -Path $Path | Sort-Object { $_.PSIsContainer } -Descending
    } else {
        Get-ChildItem -Path $Path -File
    }
    
    $renamedCount = 0
    $skippedCount = 0
    
    foreach ($item in $items) {
        $oldName = $item.Name
        
        # Convert based on selected case
        $newName = if ($Snake) {
            ConvertTo-SnakeCase -InputString $oldName
        } else {
            ConvertTo-CamelCase -InputString $oldName
        }
        
        # Skip if name hasn't changed
        if ($oldName -eq $newName) {
            Write-Verbose "Skipped: $oldName (no change needed)"
            $skippedCount++
            continue
        }
        
        # Build full paths
        $oldPath = $item.FullName
        $parentPath = if ($item.PSIsContainer) { 
            Split-Path -Path $item.FullName -Parent 
        } else { 
            $item.DirectoryName 
        }
        $newPath = Join-Path -Path $parentPath -ChildPath $newName
        
        # Check if target already exists
        if (Test-Path $newPath) {
            Write-Warning "Skipped: $oldName -> $newName (target already exists)"
            $skippedCount++
            continue
        }
        
        try {
            Rename-Item -Path $oldPath -NewName $newName -ErrorAction Stop
            Write-Host "Renamed: $oldName -> $newName" -ForegroundColor Green
            $renamedCount++
        }
        catch {
            Write-Error "Failed to rename '$oldName': $_"
            $skippedCount++
        }
    }
    
    # Summary
    Write-Host "`nSummary:" -ForegroundColor Cyan
    Write-Host "  Renamed: $renamedCount" -ForegroundColor Green
    Write-Host "  Skipped: $skippedCount" -ForegroundColor Yellow
}

# Set alias
Set-Alias -Name rep -Value REPWSH-Organization