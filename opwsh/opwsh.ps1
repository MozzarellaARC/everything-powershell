# File-based cache for app list
$Script:AppCacheFile = "$env:TEMP\PowerShell_AppCache.xml"

# Load apps from cache file or create cache if it doesn't exist
function open-pwsh-get {
    if (Test-Path $Script:AppCacheFile) {
        try {
            $Script:CachedApps = Import-Clixml $Script:AppCacheFile
            return $Script:CachedApps
        } catch {
            Write-Host "⚠️ Cache file corrupted, rebuilding..." -ForegroundColor Yellow
        }
    }
    
    # Cache doesn't exist or is corrupted, create it
    Write-Host "🔄 Building app cache (first time setup)..." -ForegroundColor Cyan
    open-pwsh-refresh
    return $Script:CachedApps
}

# Function to manually refresh the app cache
function open-pwsh-refresh {
    Write-Host "🔄 Refreshing app cache..." -ForegroundColor Cyan
    
    # Parse Start Menu directories for .lnk files
    # Process user directory first (higher priority), then system directory
    $paths = @(
        @{ Path = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"; Priority = "User" },
        @{ Path = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"; Priority = "System" }
    )
    
    $apps = @()
    $seenApps = @{}  # Hash table to track duplicates by name
    
    foreach ($pathInfo in $paths) {
        if (Test-Path $pathInfo.Path) {
            $lnkFiles = Get-ChildItem -Path $pathInfo.Path -Recurse -Filter *.lnk -ErrorAction SilentlyContinue
            foreach ($lnk in $lnkFiles) {
                $appName = $lnk.BaseName
                
                # If we haven't seen this app name before, or if this is a user-specific path
                # (which takes priority over system-wide), add it
                if (-not $seenApps.ContainsKey($appName) -or $pathInfo.Priority -eq "User") {
                    $appObject = [PSCustomObject]@{
                        Name = $appName
                        FullPath = $lnk.FullName
                        AppID = $lnk.FullName  # Use full path as AppID for launching
                        Source = $pathInfo.Priority
                    }
                    
                    if ($seenApps.ContainsKey($appName)) {
                        # Replace the system-wide version with user-specific version
                        $indexToReplace = $apps.FindIndex({ param($app) $app.Name -eq $appName })
                        if ($indexToReplace -ge 0) {
                            $apps[$indexToReplace] = $appObject
                        }
                    } else {
                        # First time seeing this app
                        $apps += $appObject
                    }
                    
                    $seenApps[$appName] = $pathInfo.Priority
                }
            }
        }
    }
    
    $Script:CachedApps = $apps | Sort-Object Name
    
    # Save to cache file
    try {
        $Script:CachedApps | Export-Clixml $Script:AppCacheFile -Force
        $userApps = ($Script:CachedApps | Where-Object { $_.Source -eq "User" }).Count
        $systemApps = ($Script:CachedApps | Where-Object { $_.Source -eq "System" }).Count
        Write-Host "✅ App cache refreshed and saved! Found $($Script:CachedApps.Count) unique apps ($userApps user, $systemApps system)." -ForegroundColor Green
    } catch {
        Write-Host "⚠️ Failed to save cache file: $_" -ForegroundColor Yellow
        Write-Host "✅ App cache refreshed (memory only)! Found $($Script:CachedApps.Count) unique apps." -ForegroundColor Green
    }
}

# Function to clear the app cache
function open-pwsh-clear {
    if (Test-Path $Script:AppCacheFile) {
        Remove-Item $Script:AppCacheFile -Force
        Write-Host "🗑️ App cache cleared!" -ForegroundColor Green
    } else {
        Write-Host "ℹ️ No cache file to clear." -ForegroundColor Gray
    }
    $Script:CachedApps = $null
}

function open-dir {
    param(
        [Parameter(Mandatory=$true, Position=0, ValueFromRemainingArguments=$true)]
        [string[]]$Name
    )
    
    # ALIASES FOR FASTER TYPING TO OPEN APP DIRECTORIES
    $appAliases = @{
        'vsc' = 'Visual Studio Code'
        'vscode' = 'Visual Studio Code'
        'vs'  = 'Visual Studio'
        'word' = 'Word'
        'excel' = 'Excel'
        'ppt' = 'PowerPoint'
        'ps' = 'PowerShell'
        # ADD MORE HERE
    }
    
    $userInput = ($Name -join ' ')
    if ([string]::IsNullOrWhiteSpace($userInput)) {
        Write-Host "❌ No app name provided." -ForegroundColor Yellow
        return
    }
    
    $searchInput = $userInput
    $userInputLower = $userInput.ToLower()
    if ($appAliases.ContainsKey($userInputLower)) {
        $searchInput = $appAliases[$userInputLower]
    }
    
    # Load Everything SDK if not already loaded
    if (-not ([System.Management.Automation.PSTypeName]'Everything').Type) {
        $scriptDir = $PSScriptRoot
        if (-not $scriptDir) { $scriptDir = Split-Path $PSCommandPath }
        $everythingDllPath = Resolve-Path (Join-Path $scriptDir "..\epwsh\Everything-SDK\dll\Everything64.dll")
        $dllPath = $everythingDllPath.Path
        $source = @"
using System;
using System.Runtime.InteropServices;

public class Everything
{
    [DllImport(@"$dllPath", CharSet = CharSet.Unicode)]
    public static extern void Everything_SetSearchW(string search);

    [DllImport(@"$dllPath")]
    public static extern void Everything_QueryW(bool bWait);

    [DllImport(@"$dllPath")]
    public static extern int Everything_GetNumResults();

    [DllImport(@"$dllPath", CharSet = CharSet.Unicode)]
    public static extern int Everything_GetResultFullPathNameW(int nIndex, System.Text.StringBuilder lpString, int nMaxCount);
    
    [DllImport(@"$dllPath")]
    public static extern void Everything_SetMax(int dwMax);
    
    [DllImport(@"$dllPath")]
    public static extern void Everything_SetOffset(int dwOffset);
}
"@
        Add-Type -TypeDefinition $source -Language CSharp
    }

    # Use Everything SDK to search for executables
    # For multi-word searches, we want to find paths that contain ALL terms
    $searchTerms = $searchInput -split '\s+'
    $mainAppName = $searchTerms[0]
    
    # Start with searching for the main app name
    $everythingQuery = "$mainAppName *.exe"
    try {
        [Everything]::Everything_SetSearchW($everythingQuery)
        [Everything]::Everything_QueryW($true)
        $numResults = [Everything]::Everything_GetNumResults()
    } catch {
        Write-Host "❌ Everything SDK error during search" -ForegroundColor Red
        return
    }

    if ($numResults -eq 0) {
        Write-Host "❌ No executables found for: $searchInput" -ForegroundColor Red
        return
    }

    $exeResults = @()
    for ($i = 0; $i -lt $numResults; $i++) {
        $sb = New-Object System.Text.StringBuilder 1024
        $null = [Everything]::Everything_GetResultFullPathNameW($i, $sb, $sb.Capacity)
        $result = $sb.ToString()
        
        # Check if it's an exe file and contains all search terms
        if ($result -match '(?i)\.exe$') {
            # Check if the full path contains ALL search terms
            $pathContainsAllTerms = $true
            foreach ($term in $searchTerms) {
                if ($result -notlike "*$term*") {
                    $pathContainsAllTerms = $false
                    break
                }
            }
            
            if ($pathContainsAllTerms) {
            $exeResults += $result
            }
        }
    }

    $exeResults = $exeResults | Sort-Object -Unique
    if ($exeResults.Count -eq 0) {
        Write-Host "❌ No .exe files found for input: $searchInput" -ForegroundColor Red
        return
    }
    
    if ($exeResults.Count -eq 1) {
        $exeToOpen = $exeResults[0]
    } else {
        Write-Host "\nAvailable executables found:"
        for ($i = 0; $i -lt $exeResults.Count; $i++) {
            Write-Host ("  [{0}] {1}" -f ($i + 1), $exeResults[$i])
        }
        $choice = Read-Host "Enter the number of the executable directory to open, or 'n' to cancel"
        if ($choice -match '^(n|no)$') {
            Write-Host "❌ Cancelled by user." -ForegroundColor Yellow
            return
        }
        if ($choice -notmatch '^[0-9]+$' -or [int]$choice -lt 1 -or [int]$choice -gt $exeResults.Count) {
            Write-Host "❌ Invalid selection." -ForegroundColor Red
            return
        }
        $exeToOpen = $exeResults[[int]$choice - 1]
    }
    
    # Open the directory containing the executable
    $exeDir = Split-Path $exeToOpen -Parent
    Write-Host ("📁 Opening directory: {0}" -f $exeDir) -ForegroundColor Green
    try {
        Start-Process "explorer.exe" -ArgumentList "`"$exeDir`""
    } catch {
        Write-Host "❌ Failed to open directory: $exeDir" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor DarkRed
    }
}

function open {
    param(
        [Parameter(Mandatory=$true, Position=0, ValueFromRemainingArguments=$true)]
        [string[]]$Name
    )
    # ALIASES FOR FASTER TYPING TO OPEN APPS
    $appAliases = @{
        'vsc' = 'Visual Studio Code'
        'vscode' = 'Visual Studio Code'
        'vs'  = 'Visual Studio'
        'word' = 'Word'
        'excel' = 'Excel'
        'ppt' = 'PowerPoint'
        'ps' = 'PowerShell'
        # ADD MORE HERE
    }

    # Use cached apps from file
    $apps = open-pwsh-get
    if (-not $apps) {
        Write-Host "❌ No Start Menu apps found." -ForegroundColor Red
        return
    }
    
    $userInput = ($Name -join ' ')
    if ([string]::IsNullOrWhiteSpace($userInput)) {
        Write-Host "❌ No app name provided." -ForegroundColor Yellow
        return
    }
    
    $searchInput = $userInput
    $userInputLower = $userInput.ToLower()
    if ($appAliases.ContainsKey($userInputLower)) {
        $searchInput = $appAliases[$userInputLower]
    }
    
    # Remove unnecessary Select-Object which copies all properties
    $appMatch = $apps | Where-Object { $_.Name -like "*$searchInput*" }
    if (-not $appMatch) {
        # Fallback: Use Everything SDK to search for executables
        # Load Everything SDK if not already loaded
        if (-not ([System.Management.Automation.PSTypeName]'Everything').Type) {
            $scriptDir = $PSScriptRoot
            if (-not $scriptDir) { $scriptDir = Split-Path $PSCommandPath }
            $everythingDllPath = Resolve-Path (Join-Path $scriptDir "..\epwsh\Everything-SDK\dll\Everything64.dll")
            $dllPath = $everythingDllPath.Path
            $source = @"
using System;
using System.Runtime.InteropServices;

public class Everything
{
    [DllImport(@"$dllPath", CharSet = CharSet.Unicode)]
    public static extern void Everything_SetSearchW(string search);

    [DllImport(@"$dllPath")]
    public static extern void Everything_QueryW(bool bWait);

    [DllImport(@"$dllPath")]
    public static extern int Everything_GetNumResults();

    [DllImport(@"$dllPath", CharSet = CharSet.Unicode)]
    public static extern int Everything_GetResultFullPathNameW(int nIndex, System.Text.StringBuilder lpString, int nMaxCount);
    
    [DllImport(@"$dllPath")]
    public static extern void Everything_SetMax(int dwMax);
    
    [DllImport(@"$dllPath")]
    public static extern void Everything_SetOffset(int dwOffset);
}
"@
            Add-Type -TypeDefinition $source -Language CSharp
        }

        $everythingQuery = "$userInput *.exe"
        try {
            [Everything]::Everything_SetSearchW($everythingQuery)
            [Everything]::Everything_QueryW($true)
            $numResults = [Everything]::Everything_GetNumResults()
        } catch {
            Write-Host "❌ Everything SDK error during fallback search" -ForegroundColor Red
            return
        }

        if ($numResults -eq 0) {
            Write-Host "❌ No app matches input: $userInput (not found in Start Menu or Everything index)" -ForegroundColor Red
            return
        }

        $exeResults = @()
        for ($i = 0; $i -lt $numResults; $i++) {
            $sb = New-Object System.Text.StringBuilder 1024
            $null = [Everything]::Everything_GetResultFullPathNameW($i, $sb, $sb.Capacity)
            $result = $sb.ToString()
            if ($result -match '(?i)\.exe$' -and $result -notmatch '\\?\$Recycle\.Bin') {
                $exeResults += $result
            }
        }

        $exeResults = $exeResults | Sort-Object -Unique
        if ($exeResults.Count -eq 0) {
            Write-Host "❌ No .exe files found by Everything for input: $userInput" -ForegroundColor Red
            return
        }
        if ($exeResults.Count -eq 1) {
            $exeToLaunch = $exeResults[0]
        } else {
            Write-Host "\nAvailable executables found by Everything:"
            for ($i = 0; $i -lt $exeResults.Count; $i++) {
                Write-Host ("  [{0}] {1}" -f ($i + 1), $exeResults[$i])
            }
            $choice = Read-Host "Enter the number of the executable to open, or 'n' to cancel"
            if ($choice -match '^(n|no)$') {
                Write-Host "❌ Cancelled by user." -ForegroundColor Yellow
                return
            }
            if ($choice -notmatch '^[0-9]+$' -or [int]$choice -lt 1 -or [int]$choice -gt $exeResults.Count) {
                Write-Host "❌ Invalid selection." -ForegroundColor Red
                return
            }
            $exeToLaunch = $exeResults[[int]$choice - 1]
        }
        Write-Host ("\n🚀 Launching: {0}" -f $exeToLaunch)
        try {
            # Use cmd /c start to completely detach the process
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.FileName = "cmd.exe"
            $startInfo.Arguments = "/c start `"`" `"$exeToLaunch`""
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            $process = [System.Diagnostics.Process]::Start($startInfo)
            $null = $process.WaitForExit(1000)  # Suppress the True output
        } catch {
            # Fallback to original method
            try {
                $null = Start-Process $exeToLaunch -WindowStyle Normal -PassThru
            } catch {
                Write-Host "❌ Failed to launch: $exeToLaunch" -ForegroundColor Red
                Write-Host $_.Exception.Message -ForegroundColor DarkRed
            }
        }
        return
    }

    # Convert to array only if multiple matches exist
    $appMatchArray = @($appMatch)
    
    if ($appMatchArray.Count -eq 1) {
        $appSelected = $appMatchArray[0]
    } else {
        Write-Host "`nAvailable matches:"
        # Pre-calculate lengths more efficiently
        $nameWidths = $appMatchArray | ForEach-Object { $_.Name.Length }
        $maxNameLen = ($nameWidths | Measure-Object -Maximum).Maximum
        
        $sourceWidths = $appMatchArray | ForEach-Object { 
            if ($_.Source) { $_.Source.Length } else { 6 } 
        }
        $maxSourceLen = ($sourceWidths | Measure-Object -Maximum).Maximum
        
        Write-Host ("    {0,-$maxNameLen}  {1,-$maxSourceLen}  {2}" -f 'Name', 'Source', 'Path')
        for ($i = 0; $i -lt $appMatchArray.Count; $i++) {
            $app = $appMatchArray[$i]
            $sourceDisplay = if ($app.Source) { $app.Source } else { 'System' }
            $pathDisplay = if ($app.FullPath) { Split-Path $app.FullPath -Parent } else { '<no path>' }
            Write-Host ("  [{0}] {1,-$maxNameLen}  {2,-$maxSourceLen}  {3}" -f ($i + 1), $app.Name, $sourceDisplay, $pathDisplay)
        }
        
        $choice = Read-Host "Enter the number of the app to open, or 'n' to cancel"
        if ($choice -match '^(n|no)$') {
            Write-Host "❌ Cancelled by user." -ForegroundColor Yellow
            return
        }
        if ($choice -notmatch '^[0-9]+$' -or [int]$choice -lt 1 -or [int]$choice -gt $appMatchArray.Count) {
            Write-Host "❌ Invalid selection." -ForegroundColor Red
            return
        }
        $appSelected = $appMatchArray[[int]$choice - 1]
    }

    # Check if we have a valid path to the .lnk file
    if (-not $appSelected.AppID -or -not (Test-Path $appSelected.AppID)) {
        Write-Host "❌ Selected app does not have a valid path." -ForegroundColor Red
        return
    }
    $appPath = $appSelected.AppID

    # Check if process is already running and bring to foreground if so
    $broughtToFront = $false
    
    # Enhanced Win32 API definitions for better window management
    if (-not ([System.Management.Automation.PSTypeName]'Win32WindowManager').Type) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class Win32WindowManager {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    
    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    
    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();
    
    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    
    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    
    [DllImport("user32.dll")]
    public static extern int GetWindowTextLength(IntPtr hWnd);
    
    // Window show states
    public const int SW_HIDE = 0;
    public const int SW_SHOWNORMAL = 1;
    public const int SW_SHOWMINIMIZED = 2;
    public const int SW_SHOWMAXIMIZED = 3;
    public const int SW_SHOWNOACTIVATE = 4;
    public const int SW_SHOW = 5;
    public const int SW_MINIMIZE = 6;
    public const int SW_SHOWMINNOACTIVE = 7;
    public const int SW_SHOWNA = 8;
    public const int SW_RESTORE = 9;
    public const int SW_SHOWDEFAULT = 10;
    public const int SW_FORCEMINIMIZE = 11;
    
    public static bool ForceSetForegroundWindow(IntPtr hWnd) {
        uint foreThread = GetWindowThreadProcessId(GetForegroundWindow(), out uint temp);
        uint appThread = GetCurrentThreadId();
        bool success = false;
        
        if (foreThread != appThread) {
            AttachThreadInput(foreThread, appThread, true);
            success = SetForegroundWindow(hWnd);
            AttachThreadInput(foreThread, appThread, false);
        } else {
            success = SetForegroundWindow(hWnd);
        }
        
        return success;
    }
}
"@
    }
    
    # Try multiple strategies to find the running process
    $targetProcesses = @()
    
    # Strategy 1: Direct process name match
    if ($appPath -notmatch '(^[A-Z]:\\|^\\\\|[\\{.,])') {
        $procName = [System.IO.Path]::GetFileNameWithoutExtension($appPath)
        $targetProcesses += Get-Process -Name $procName -ErrorAction SilentlyContinue
    }
    
    # Strategy 2: Try common process name variations for popular apps
    $appNameLower = $appSelected.Name.ToLower()
    $commonProcessNames = @{
        'discord' = @('Discord', 'DiscordPTB', 'DiscordCanary')
        'spotify' = @('Spotify')
        'chrome' = @('chrome')
        'firefox' = @('firefox')
        'edge' = @('msedge')
        'notepad++' = @('notepad++')
        'visual studio code' = @('Code')
        'visual studio' = @('devenv')
        'steam' = @('steam')
        'obs studio' = @('obs64', 'obs32')
        'vlc' = @('vlc')
        'photoshop' = @('Photoshop')
    }
    
    foreach ($key in $commonProcessNames.Keys) {
        if ($appNameLower -like "*$key*") {
            foreach ($procName in $commonProcessNames[$key]) {
                $targetProcesses += Get-Process -Name $procName -ErrorAction SilentlyContinue
            }
            break
        }
    }
    
    # Strategy 3: Search by main window title (partial match)
    if (-not $targetProcesses) {
        $allProcesses = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 }
        foreach ($proc in $allProcesses) {
            if ($proc.MainWindowTitle -and ($proc.MainWindowTitle -like "*$($appSelected.Name)*" -or $appSelected.Name -like "*$($proc.ProcessName)*")) {
                $targetProcesses += $proc
            }
        }
    }
    
    # Try to bring window to foreground
    if ($targetProcesses) {
        foreach ($proc in $targetProcesses) {
            if ($proc.MainWindowHandle -ne 0 -and [Win32WindowManager]::IsWindow($proc.MainWindowHandle)) {
                try {
                    # Check if window is minimized and restore it
                    if ([Win32WindowManager]::IsIconic($proc.MainWindowHandle)) {
                        [void][Win32WindowManager]::ShowWindow($proc.MainWindowHandle, [Win32WindowManager]::SW_RESTORE)
                    }
                    
                    # Make sure window is visible
                    [void][Win32WindowManager]::ShowWindow($proc.MainWindowHandle, [Win32WindowManager]::SW_SHOW)
                    
                    # Force bring to foreground
                    $success = [Win32WindowManager]::ForceSetForegroundWindow($proc.MainWindowHandle)
                    
                    if ($success) {
                        Write-Host ("`n🔎 $($appSelected.Name) is already running. Brought to foreground.") -ForegroundColor Cyan
                        $broughtToFront = $true
                        break
                    }
                } catch {
                    # Continue to next process if this one fails
                    continue
                }
            }
        }
    }
    if (-not $broughtToFront) {
        Write-Host ("`n🚀 Launching: {0}" -f $appSelected.Name)
        try {
            # Launch .lnk file directly using Start-Process
            $null = Start-Process -FilePath $appPath -WindowStyle Normal -PassThru
        } catch {
            # Fallback: Use cmd /c start with the .lnk file
            try {
                $startInfo = New-Object System.Diagnostics.ProcessStartInfo
                $startInfo.FileName = "cmd.exe"
                $startInfo.Arguments = "/c start `"`" `"$appPath`""
                $startInfo.UseShellExecute = $false
                $startInfo.CreateNoWindow = $true
                $startInfo.RedirectStandardOutput = $true
                $startInfo.RedirectStandardError = $true
                $process = [System.Diagnostics.Process]::Start($startInfo)
                $null = $process.WaitForExit(1000)  # Suppress the True output
            } catch {
                Write-Host "❌ Failed to launch: $appPath" -ForegroundColor Red
                Write-Host $_.Exception.Message -ForegroundColor DarkRed
            }
        }
    }
}

    Set-Alias o open
    Set-Alias od open-dir

    Set-Alias oget open-pwsh-get
    Set-Alias oref open-pwsh-refresh
    Set-Alias oclear open-pwsh-clear