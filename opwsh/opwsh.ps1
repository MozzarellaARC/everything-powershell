# Simplified app cache
$Script:CachedApps = $null

# Get shortcut target path
function Get-ShortcutTarget {
    param([string]$ShortcutPath)
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($ShortcutPath)
        return $shortcut.TargetPath
    } catch {
        return $null
    } finally {
        if ($shell) { 
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null 
        }
    }
}

# Parse Start Menu applications
function Get-Apps {
    # Check if cache exists and is not empty
    if ($Script:CachedApps -and $Script:CachedApps.Count -gt 0) {
        Write-Host "📋 Using cached applications ($($Script:CachedApps.Count) apps)" -ForegroundColor Green
        return $Script:CachedApps
    }
    
    Write-Host "🔍 Scanning Start Menu applications..." -ForegroundColor Cyan
    
    $paths = @(
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
    )
    
    $apps = @()
    $seenTargets = @{}
    
    foreach ($path in $paths) {
        if (Test-Path $path) {
            Write-Host "  📂 Processing: $path" -ForegroundColor Gray
            $shortcuts = Get-ChildItem -Path $path -Recurse -Filter *.lnk -ErrorAction SilentlyContinue
            foreach ($shortcut in $shortcuts) {
                $targetPath = Get-ShortcutTarget -ShortcutPath $shortcut.FullName
                
                if ($targetPath -and (Test-Path $targetPath -ErrorAction SilentlyContinue)) {
                    $normalizedTarget = $targetPath.ToLower()
                    
                    if (-not $seenTargets.ContainsKey($normalizedTarget)) {
                        $apps += [PSCustomObject]@{
                            Name = $shortcut.BaseName
                            TargetPath = $targetPath
                            ShortcutPath = $shortcut.FullName
                        }
                        $seenTargets[$normalizedTarget] = $true
                    }
                }
            }
        }
    }
    
    $Script:CachedApps = $apps | Sort-Object Name
    Write-Host "✅ Found $($Script:CachedApps.Count) applications (cached for future use)" -ForegroundColor Green
    return $Script:CachedApps
}

# Clear cache
function Clear-AppCache {
    Write-Host "🧹 Clearing application cache..." -ForegroundColor Cyan
    $Script:CachedApps = $null
    Write-Host "✅ Cache cleared." -ForegroundColor Green
}

# Deprecated Everything SDK removed.
# TODO: Implement a new fast executable/file search backend.
# Desired replacement characteristics:
#   - Cross-volume enumeration with caching (avoid full recursive scan every call)
#   - Supports patterns (wildcards) and fuzzy substring
#   - Returns full paths for executables prioritizing likely launch targets
#   - Pure PowerShell or lightweight external binary (fd, rg, custom indexer)

function Search-ExecutablesPlaceholder {
    param([string]$Query)
    <#
    TODO: Replace this stub with real search logic.
    Temporary behavior: naive recursive search limited to a small set of root folders
    for demonstration. This is intentionally conservative to avoid performance issues.
    #>
    if (-not $Query) { return @() }

    $roots = @(
        "$env:ProgramFiles",
        "$env:ProgramFiles(x86)",
        "$env:LOCALAPPDATA"
    ) | Where-Object { $_ -and (Test-Path $_) }

    $pattern = "*${Query}*.exe"
    $results = @()
    foreach ($root in $roots) {
        try {
            $results += Get-ChildItem -Path $root -Recurse -Filter $pattern -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
            if ($results.Count -gt 50) { break } # guardrail to prevent huge scans
        } catch { }
    }
    return ($results | Sort-Object -Unique)
}

# Window management for bringing apps to foreground
function Invoke-BringToForeground {
    param([string]$AppName, [string]$TargetPath)
    
    if (-not ([System.Management.Automation.PSTypeName]'Win32WindowManager').Type) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;

public class Win32WindowManager {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    
    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);
    
    public const int SW_RESTORE = 9;
    public const int SW_SHOW = 5;
}
"@
    }
    
    # Find running processes
    $processes = @()
    
    # Try by target executable name
    if ($TargetPath) {
        $exeName = [System.IO.Path]::GetFileNameWithoutExtension($TargetPath)
        $processes += Get-Process -Name $exeName -ErrorAction SilentlyContinue
    }
    
    # Common process mappings
    $appNameLower = $AppName.ToLower()
    $commonProcessNames = @{
        'visual studio code' = @('Code')
        'visual studio' = @('devenv')
        'chrome' = @('chrome')
        'firefox' = @('firefox')
        'edge' = @('msedge')
        'notepad++' = @('notepad++')
    }
    
    foreach ($key in $commonProcessNames.Keys) {
        if ($appNameLower -like "*$key*") {
            foreach ($procName in $commonProcessNames[$key]) {
                $processes += Get-Process -Name $procName -ErrorAction SilentlyContinue
            }
        }
    }
    
    # Try to bring window to foreground
    foreach ($proc in ($processes | Sort-Object Id -Unique)) {
        if ($proc.MainWindowHandle -ne 0) {
            try {
                if ([Win32WindowManager]::IsIconic($proc.MainWindowHandle)) {
                    [void][Win32WindowManager]::ShowWindow($proc.MainWindowHandle, [Win32WindowManager]::SW_RESTORE)
                }
                [void][Win32WindowManager]::ShowWindow($proc.MainWindowHandle, [Win32WindowManager]::SW_SHOW)
                [void][Win32WindowManager]::SetForegroundWindow($proc.MainWindowHandle)
                return $true
            } catch {
                continue
            }
        }
    }
    
    return $false
}
# Here is start the main script functionality
# Here is start the main script functionality
# Here is start the main script functionality
# Here is start the main script functionality
# Here is start the main script functionality
function open-dir {
    param(
        [Parameter(Mandatory=$true, Position=0, ValueFromRemainingArguments=$true)]
        [string[]]$Name
    )
    
    $userInput = ($Name -join ' ')
    if ([string]::IsNullOrWhiteSpace($userInput)) {
        Write-Host "❌ No app name provided." -ForegroundColor Yellow
        return
    }
    
    Write-Host "🔍 Searching for executables (placeholder backend): $userInput" -ForegroundColor Cyan
    $exeResults = Search-ExecutablesPlaceholder -Query $userInput
    
    if ($exeResults.Count -eq 0) {
        Write-Host "❌ No .exe files found for: $userInput" -ForegroundColor Red
        return
    }
    
    if ($exeResults.Count -eq 1) {
        $exeToOpen = $exeResults[0]
    } else {
        Write-Host "`nAvailable executables:"
        for ($i = 0; $i -lt $exeResults.Count; $i++) {
            Write-Host ("  [{0}] {1}" -f ($i + 1), $exeResults[$i])
        }
        $choice = Read-Host "Enter number (1-$($exeResults.Count)) or 'n' to cancel"
        if ($choice -match '^(n|no)$') {
            return
        }
        if ($choice -notmatch '^[0-9]+$' -or [int]$choice -lt 1 -or [int]$choice -gt $exeResults.Count) {
            Write-Host "❌ Invalid selection." -ForegroundColor Red
            return
        }
        $exeToOpen = $exeResults[[int]$choice - 1]
    }
    
    $exeDir = Split-Path $exeToOpen -Parent
    Write-Host "📂 Opening directory: $exeDir" -ForegroundColor Green
    Start-Process "explorer.exe" -ArgumentList "`"$exeDir`""
}

function open {
    param(
        [Parameter(Mandatory=$true, Position=0, ValueFromRemainingArguments=$true)]
        [string[]]$Name
    )
    
    # App aliases for faster typing
    $appAliases = @{
        'vsc' = 'Visual Studio Code'
        'vscode' = 'Visual Studio Code'
        'vs' = 'Visual Studio'
        'word' = 'Word'
        'excel' = 'Excel'
        'ppt' = 'PowerPoint'
        'ps' = 'PowerShell'
    }
    
    $userInput = ($Name -join ' ')
    if ([string]::IsNullOrWhiteSpace($userInput)) {
        Write-Host "❌ No app name provided." -ForegroundColor Yellow
        return
    }
    
    # Check for alias
    $searchInput = $userInput
    $userInputLower = $userInput.ToLower()
    if ($appAliases.ContainsKey($userInputLower)) {
        $searchInput = $appAliases[$userInputLower]
        Write-Host "📝 Using alias: '$userInput' → '$searchInput'" -ForegroundColor Gray
    }
    
    # Get Start Menu apps
    Write-Host "🔍 Searching for applications: $searchInput" -ForegroundColor Cyan
    $apps = Get-Apps
    $appMatches = @($apps | Where-Object { $_.Name -like "*$searchInput*" })
    
    # If no Start Menu matches, fallback to placeholder executable search
    if ($appMatches.Count -eq 0) {
        Write-Host "⚠️  No Start Menu matches found, searching executables..." -ForegroundColor Yellow
    $exeResults = Search-ExecutablesPlaceholder -Query $userInput
        
        if ($exeResults.Count -eq 0) {
            Write-Host "❌ No apps found for: $userInput" -ForegroundColor Red
            return
        }
        
        if ($exeResults.Count -eq 1) {
            $exeToLaunch = $exeResults[0]
        } else {
            Write-Host "`nAvailable executables:"
            for ($i = 0; $i -lt $exeResults.Count; $i++) {
                Write-Host ("  [{0}] {1}" -f ($i + 1), $exeResults[$i])
            }
            $choice = Read-Host "Enter number (1-$($exeResults.Count)) or 'n' to cancel"
            if ($choice -match '^(n|no)$') { return }
            if ($choice -notmatch '^[0-9]+$' -or [int]$choice -lt 1 -or [int]$choice -gt $exeResults.Count) {
                Write-Host "❌ Invalid selection." -ForegroundColor Red
                return
            }
            $exeToLaunch = $exeResults[[int]$choice - 1]
        }
        
        # Launch executable directly
        try {
            Write-Host "🚀 Launching: $exeToLaunch" -ForegroundColor Green
            Start-Process -FilePath $exeToLaunch -WindowStyle Normal | Out-Null
        } catch {
            Write-Host "❌ Failed to launch: $exeToLaunch" -ForegroundColor Red
        }
        return
    }
    
    # Handle Start Menu app matches
    if ($appMatches.Count -eq 1) {
        $appSelected = $appMatches[0]
    } else {
        Write-Host "`nAvailable matches:"
        $maxNameLen = ($appMatches | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
        Write-Host ("    {0,-$maxNameLen}  {1}" -f 'Name', 'Target Path')
        
        for ($i = 0; $i -lt $appMatches.Count; $i++) {
            $app = $appMatches[$i]
            Write-Host ("  [{0}] {1,-$maxNameLen}  {2}" -f ($i + 1), $app.Name, $app.TargetPath)
        }
        
        $choice = Read-Host "Enter number (1-$($appMatches.Count)) or 'n' to cancel"
        if ($choice -match '^(n|no)$') { return }
        if ($choice -notmatch '^[0-9]+$' -or [int]$choice -lt 1 -or [int]$choice -gt $appMatches.Count) {
            Write-Host "❌ Invalid selection." -ForegroundColor Red
            return
        }
        $appSelected = $appMatches[[int]$choice - 1]
    }
    
    # Try to bring existing window to foreground
    Write-Host "🔄 Checking if application is already running..." -ForegroundColor Gray
    if (Invoke-BringToForeground -AppName $appSelected.Name -TargetPath $appSelected.TargetPath) {
        Write-Host "✅ Brought existing window to foreground: $($appSelected.Name)" -ForegroundColor Green
        return
    }
    
    # Launch the app using shortcut
    try {
        Write-Host "🚀 Launching: $($appSelected.Name)" -ForegroundColor Green
        Start-Process -FilePath $appSelected.ShortcutPath -WindowStyle Normal | Out-Null
    } catch {
        Write-Host "❌ Failed to launch: $($appSelected.Name)" -ForegroundColor Red
    }
}

    Set-Alias o open
    Set-Alias od open-dir
    Set-Alias oget Get-Apps
    Set-Alias oclear Clear-AppCache

# Main script entry point