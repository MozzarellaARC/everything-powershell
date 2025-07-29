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
    if ($Script:CachedApps) {
        return $Script:CachedApps
    }
    
    $paths = @(
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
    )
    
    $apps = @()
    $seenTargets = @{}
    
    foreach ($path in $paths) {
        if (Test-Path $path) {
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
    return $Script:CachedApps
}

# Clear cache
function Clear-AppCache {
    $Script:CachedApps = $null
    Write-Host "Cache cleared." -ForegroundColor Green
}

# Load Everything SDK
function Load-EverythingSDK {
    if (-not ([System.Management.Automation.PSTypeName]'Everything').Type) {
        $scriptDir = $PSScriptRoot
        if (-not $scriptDir) { $scriptDir = Split-Path $PSCommandPath }
        $dllPath = Resolve-Path (Join-Path $scriptDir "..\epwsh\Everything-SDK\dll\Everything64.dll")
        
        Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class Everything
{
    [DllImport(@"$($dllPath.Path)", CharSet = CharSet.Unicode)]
    public static extern void Everything_SetSearchW(string search);

    [DllImport(@"$($dllPath.Path)")]
    public static extern void Everything_QueryW(bool bWait);

    [DllImport(@"$($dllPath.Path)")]
    public static extern int Everything_GetNumResults();

    [DllImport(@"$($dllPath.Path)", CharSet = CharSet.Unicode)]
    public static extern int Everything_GetResultFullPathNameW(int nIndex, System.Text.StringBuilder lpString, int nMaxCount);
}
"@
    }
}

# Search for executables using Everything SDK
function Search-EverythingEXE {
    param([string]$Query)
    
    Load-EverythingSDK
    
    try {
        [Everything]::Everything_SetSearchW("$Query *.exe")
        [Everything]::Everything_QueryW($true)
        $numResults = [Everything]::Everything_GetNumResults()
        
        $results = @()
        for ($i = 0; $i -lt $numResults; $i++) {
            $sb = New-Object System.Text.StringBuilder 1024
            $null = [Everything]::Everything_GetResultFullPathNameW($i, $sb, $sb.Capacity)
            $result = $sb.ToString()
            
            if ($result -match '\.exe$' -and $result -notmatch '\$Recycle\.Bin') {
                $results += $result
            }
        }
        
        return $results | Sort-Object -Unique
    } catch {
        return @()
    }
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
    
    $exeResults = Search-EverythingEXE -Query $userInput
    
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
    }
    
    # Get Start Menu apps
    $apps = Get-App
    $appMatches = @($apps | Where-Object { $_.Name -like "*$searchInput*" })
    
    # If no Start Menu matches, fallback to Everything SDK
    if ($appMatches.Count -eq 0) {
        $exeResults = Search-EverythingEXE -Query $userInput
        
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
    if (Invoke-BringToForeground -AppName $appSelected.Name -TargetPath $appSelected.TargetPath) {
        return
    }
    
    # Launch the app using shortcut
    try {
        Start-Process -FilePath $appSelected.ShortcutPath -WindowStyle Normal | Out-Null
    } catch {
        Write-Host "❌ Failed to launch: $($appSelected.Name)" -ForegroundColor Red
    }
}

    Set-Alias o open
    Set-Alias od open-dir
    Set-Alias oget Get-Apps
    Set-Alias oclear Clear-AppCache