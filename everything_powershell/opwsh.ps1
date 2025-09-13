# Simplified app cache
$Script:CachedApps = $null

# Progress-only mode (suppresses decorative icons / extra lines)
if (-not (Get-Variable -Name Script:ProgressOnly -Scope Script -ErrorAction SilentlyContinue)) {
    $Script:ProgressOnly = $true  # default to true per user request
}

function Set-OpenAppOutputMode {
    [CmdletBinding()] param(
        [switch]$VerboseMode,
        [switch]$Minimal,
        [switch]$ProgressOnly
    )
    if ($PSBoundParameters.ContainsKey('VerboseMode')) { $Script:ProgressOnly = $false }
    if ($PSBoundParameters.ContainsKey('Minimal')) { $Script:ProgressOnly = $true }
    if ($PSBoundParameters.ContainsKey('ProgressOnly')) { $Script:ProgressOnly = $true }
}

function Write-Info {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )
    if (-not $Script:ProgressOnly) {
        Write-Host $Message -ForegroundColor $Color
    }
}

function Write-Notice {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Cyan
    )
    if (-not $Script:ProgressOnly) {
        Write-Host $Message -ForegroundColor $Color
    }
}

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
        if (-not $Script:ProgressOnly) { Write-Host "Using cached applications ($($Script:CachedApps.Count) apps)" -ForegroundColor Green }
        return $Script:CachedApps
    }
    if (-not $Script:ProgressOnly) { Write-Host "Scanning Start Menu applications..." -ForegroundColor Cyan }
    
    $paths = @(
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
    )
    
    $apps = @()
    $seenTargets = @{}
    
    $totalShortcutCount = 0
    $collected = 0
    # Pre-count to have a determinate progress bar
    foreach ($p in $paths) {
        if (Test-Path $p) {
            try { $totalShortcutCount += (Get-ChildItem -Path $p -Recurse -Filter *.lnk -ErrorAction SilentlyContinue | Measure-Object).Count } catch { }
        }
    }
    if ($totalShortcutCount -eq 0) { $totalShortcutCount = 1 }

    foreach ($path in $paths) {
        if (Test-Path $path) {
            if (-not $Script:ProgressOnly) { Write-Host "  Processing: $path" -ForegroundColor Gray }
            $shortcuts = Get-ChildItem -Path $path -Recurse -Filter *.lnk -ErrorAction SilentlyContinue
            foreach ($shortcut in $shortcuts) {
                $collected++
                if ($Script:ProgressOnly) {
                    $pct = [int](($collected / $totalShortcutCount) * 100)
                    Write-Progress -Activity "Scanning Start Menu" -Status "${collected}/${totalShortcutCount} shortcuts" -PercentComplete $pct
                }
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
    if ($Script:ProgressOnly) { Write-Progress -Activity "Scanning Start Menu" -Completed -Status "Done" }
    $Script:CachedApps = $apps | Sort-Object Name
    if (-not $Script:ProgressOnly) { Write-Host "Found $($Script:CachedApps.Count) applications (cached for future use)" -ForegroundColor Green }
    return $Script:CachedApps
}

# Clear cache
function Clear-AppCache {
    if ($Script:ProgressOnly) {
        Write-Progress -Activity "Clear App Cache" -Status "Clearing..." -PercentComplete 50
    } else {
        Write-Host "Clearing application cache..." -ForegroundColor Cyan
    }
    $Script:CachedApps = $null
    if ($Script:ProgressOnly) {
        Write-Progress -Activity "Clear App Cache" -Completed -Status "Done"
    } else {
        Write-Host "Cache cleared." -ForegroundColor Green
    }
}

# fd integration (replacement for deprecated Everything SDK)
function Test-FdAvailable { return [bool](Get-Command fd -ErrorAction SilentlyContinue) }

function Search-ExecutablesFd {
    param(
        [Parameter(Mandatory)][string]$Query,
        [int]$Limit = 50
    )
    if (-not (Test-FdAvailable)) { return @() }
    if (-not $Query) { return @() }

    # Build fd args:
    # -t f : files only
    # -e exe : extension exe
    # Case-insensitive by default on Windows; use smart case behavior.
    $args = @('-t','f','-e','exe','--max-results',$Limit,'--color','never')

    # Standard program search roots (can be expanded later or made configurable)
    $roots = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:LOCALAPPDATA,
        "$env:ProgramData"
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($r in $roots) { $args += @('--search-path', (Resolve-Path $r).Path) }

    # Append the pattern (fd treats this as a regex / fuzzy style literal)
    $args += $Query
    try {
        $output = fd @args 2>$null
        $filtered = $output | Where-Object { $_ -match '\\.exe$' }
        return @($filtered)
    } catch { return @() }
}

function Search-Executables {
    param([string]$Query,[int]$Limit=50)
    if (-not (Test-FdAvailable)) { Write-Error "'fd' is required but not found in PATH. Install from https://github.com/sharkdp/fd/releases"; return @() }
    if (-not $Query) { return @() }
    $fd = Search-ExecutablesFd -Query $Query -Limit $Limit
    return @($fd)
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
        Write-Host "No app name provided." -ForegroundColor Yellow
        return
    }
    if (-not $Script:ProgressOnly) { Write-Host "Searching for executables: $userInput" -ForegroundColor Cyan }
    $exeResults = @(Search-Executables -Query $userInput)
    
    if (-not $exeResults -or ($exeResults | Measure-Object).Count -eq 0) {
        Write-Host "No .exe files found for: $userInput" -ForegroundColor Red
        return
    }
    
    if (($exeResults | Measure-Object).Count -eq 1) {
        $exeToOpen = $exeResults[0]
    } else {
        Write-Host "`nAvailable executables:"
        for ($i = 0; $i -lt ($exeResults | Measure-Object).Count; $i++) {
            Write-Host ("  [{0}] {1}" -f ($i + 1), $exeResults[$i])
        }
        $choice = Read-Host "Enter number (1-$((($exeResults)|Measure-Object).Count)) or 'n' to cancel"
        if ($choice -match '^(n|no)$') {
            return
        }
        $total = (($exeResults)|Measure-Object).Count
        if ($choice -notmatch '^[0-9]+$' -or [int]$choice -lt 1 -or [int]$choice -gt $total) {
            Write-Host "❌ Invalid selection." -ForegroundColor Red
            return
        }
        $exeToOpen = $exeResults[[int]$choice - 1]
    }
    
    $exeDir = Split-Path $exeToOpen -Parent
    if (-not $Script:ProgressOnly) { Write-Host "Opening directory: $exeDir" -ForegroundColor Green }
    Start-Process "explorer.exe" -ArgumentList "`"$exeDir`""
    if (-not $Script:ProgressOnly) { Write-Host "Done." -ForegroundColor DarkGreen }
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
        Write-Host "No app name provided." -ForegroundColor Yellow
        return
    }
    
    # Check for alias
    $searchInput = $userInput
    $userInputLower = $userInput.ToLower()
    if ($appAliases.ContainsKey($userInputLower)) {
        $searchInput = $appAliases[$userInputLower]
        if (-not $Script:ProgressOnly) { Write-Host "Using alias: '$userInput' -> '$searchInput'" -ForegroundColor Gray }
    }
    
    # Get Start Menu apps
    if (-not $Script:ProgressOnly) { Write-Host "Searching for applications: $searchInput" -ForegroundColor Cyan }
    $apps = Get-Apps
    $appMatches = @($apps | Where-Object { $_.Name -like "*$searchInput*" })
    
    # If no Start Menu matches, run fd executable search directly
    if ($appMatches.Count -eq 0) {
        if (-not $Script:ProgressOnly) { Write-Host "No Start Menu matches found, searching executables..." -ForegroundColor Yellow }
    $exeResults = @(Search-Executables -Query $userInput)
        
        if (-not $exeResults -or ($exeResults | Measure-Object).Count -eq 0) { Write-Host "No apps found for: $userInput" -ForegroundColor Red; return }
        
        if (($exeResults | Measure-Object).Count -eq 1) {
            $exeToLaunch = $exeResults[0]
        } else {
            Write-Host "`nAvailable executables:"
            for ($i = 0; $i -lt (($exeResults)|Measure-Object).Count; $i++) {
                Write-Host ("  [{0}] {1}" -f ($i + 1), $exeResults[$i])
            }
            $choice = Read-Host "Enter number (1-$((($exeResults)|Measure-Object).Count)) or 'n' to cancel"
            if ($choice -match '^(n|no)$') { return }
            $total = (($exeResults)|Measure-Object).Count
            if ($choice -notmatch '^[0-9]+$' -or [int]$choice -lt 1 -or [int]$choice -gt $total) {
                Write-Host "❌ Invalid selection." -ForegroundColor Red
                return
            }
            $exeToLaunch = $exeResults[[int]$choice - 1]
        }
        
        # Launch executable directly
        try {
            if (-not $Script:ProgressOnly) { Write-Host "Launching: $exeToLaunch" -ForegroundColor Green }
            Start-Process -FilePath $exeToLaunch -WindowStyle Normal | Out-Null
        } catch {
            Write-Host "Failed to launch: $exeToLaunch" -ForegroundColor Red
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
        if (-not $Script:ProgressOnly) { Write-Host "Checking if application is already running..." -ForegroundColor Gray }
    if (Invoke-BringToForeground -AppName $appSelected.Name -TargetPath $appSelected.TargetPath) {
        if (-not $Script:ProgressOnly) { Write-Host "Brought existing window to foreground: $($appSelected.Name)" -ForegroundColor Green }
        return
    }
    
    # Launch the app using shortcut
    try {
        if (-not $Script:ProgressOnly) { Write-Host "Launching: $($appSelected.Name)" -ForegroundColor Green }
        Start-Process -FilePath $appSelected.ShortcutPath -WindowStyle Normal | Out-Null
    } catch {
        Write-Host "Failed to launch: $($appSelected.Name)" -ForegroundColor Red
    }
    if (-not $Script:ProgressOnly) { Write-Host "Done." -ForegroundColor DarkGreen }
}

    Set-Alias o open
    Set-Alias od open-dir
    Set-Alias oget Get-Apps
    Set-Alias oclear Clear-AppCache

# Main script entry point