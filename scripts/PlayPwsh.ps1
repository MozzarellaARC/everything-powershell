# PlayPwsh.ps1 - Music player using ffplay and fuzzy finder
# Requires: ffmpeg (ffplay), fzf

param(
    [Parameter(Position=0)]
    [string]$Query,
    [string]$MusicFolder = "C:\Users\M\Music",
    [switch]$Recursive,
    [switch]$Shuffle,
    [string]$FileTypes = "*.mp3,*.flac,*.wav,*.m4a,*.ogg,*.wma,*.aac,*.opus,*.mp4,*.mkv,*.avi,*.webm,*.mov",
    [switch]$Loop,
    [switch]$All,
    [switch]$Help
)

function Show-Help {
    Write-Host "`nPlayPwsh - Music Player with Fuzzy Finder" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "`nDESCRIPTION:" -ForegroundColor Yellow
    Write-Host "  Play music files using ffplay with fzf fuzzy finder for easy selection."
    Write-Host "`nUSAGE:" -ForegroundColor Yellow
    Write-Host "  .\PlayPwsh.ps1 <query> [options]"
    Write-Host "  play <query> [options]          (using alias)"
    Write-Host "`nPARAMETERS:" -ForegroundColor Yellow
    Write-Host "  <query>" -ForegroundColor Green
    Write-Host "      Search query to filter music files (e.g., 'bohemian rhapsody')"
    Write-Host "      If provided, pre-filters results with fzf"
    Write-Host "`n  -MusicFolder <path>" -ForegroundColor Green
    Write-Host "      Path to your music folder (default: %USERPROFILE%\Music)"
    Write-Host "`n  -Recursive" -ForegroundColor Green
    Write-Host "      Scan subfolders recursively for music files"
    Write-Host "`n  -Shuffle" -ForegroundColor Green
    Write-Host "      Shuffle the file list before displaying"
    Write-Host "`n  -FileTypes <extensions>" -ForegroundColor Green
    Write-Host "      Comma-separated list of file extensions to search for"
    Write-Host "      (default: *.mp3,*.flac,*.wav,*.m4a,*.ogg,*.wma,*.aac,*.opus)"    Write-Host "`n  -Loop" -ForegroundColor Green
    Write-Host "      Loop the selected music after it finishes playing"
    Write-Host "      (cannot be used with -All)"
    Write-Host "`n  -All" -ForegroundColor Green
    Write-Host "      Play all music files in the folder"
    Write-Host "      (cannot be used with -Loop)"    Write-Host "`n  -Help" -ForegroundColor Green
    Write-Host "      Display this help message"
    Write-Host "`nEXAMPLES:" -ForegroundColor Yellow
    Write-Host "  .\PlayPwsh.ps1"
    Write-Host "      Browse all music files"
    Write-Host "`n  play 'bohemian rhapsody'"
    Write-Host "      Search for 'bohemian rhapsody' and play (using alias)"
    Write-Host "`n  .\PlayPwsh.ps1 -Recursive -Shuffle"
    Write-Host "      Scan recursively and shuffle the list"
    Write-Host "`n  .\PlayPwsh.ps1 -MusicFolder 'D:\MyMusic' -Recursive"
    Write-Host "      Use custom music folder with recursive scan"
    Write-Host "`n  .\PlayPwsh.ps1 -FileTypes '*.mp3,*.flac'"
    Write-Host "      Only show MP3 and FLAC files"
    Write-Host "`n  .\PlayPwsh.ps1 -All"
    Write-Host "      Play all music files in the folder sequentially"
    Write-Host "`n  play 'favorite song' -Loop"
    Write-Host "      Loop the selected song continuously"
    Write-Host "`nPLAYBACK CONTROLS:" -ForegroundColor Yellow
    Write-Host "  q     - Quit playback"
    Write-Host "  s     - Toggle pause"
    Write-Host "  ←/→   - Seek backward/forward 10 seconds"
    Write-Host "  ↑/↓   - Seek backward/forward 1 minute"
    Write-Host "`nREQUIREMENTS:" -ForegroundColor Yellow
    Write-Host "  - ffmpeg (ffplay):  winget install ffmpeg"
    Write-Host "  - fzf:              winget install fzf"
    Write-Host ""
}

function Test-Dependencies {
    $missing = @()
    
    if (-not (Get-Command ffplay -ErrorAction SilentlyContinue)) {
        $missing += "ffplay (from ffmpeg)"
    }
    
    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        $missing += "fzf"
    }
    
    if ($missing.Count -gt 0) {
        Write-Host "Missing dependencies: $($missing -join ', ')" -ForegroundColor Red
        Write-Host "`nInstall instructions:" -ForegroundColor Yellow
        Write-Host "  ffmpeg: winget install ffmpeg or choco install ffmpeg"
        Write-Host "  fzf:    winget install fzf or choco install fzf"
        return $false
    }
    
    return $true
}

function Get-MusicFiles {
    param(
        [string]$Path,
        [string[]]$Extensions,
        [bool]$IsRecursive
    )
    
    if (-not (Test-Path $Path)) {
        Write-Host "Music folder not found: $Path" -ForegroundColor Red
        return @()
    }
    
    $files = @()
    foreach ($ext in $Extensions) {
        if ($IsRecursive) {
            $files += @(Get-ChildItem -Path $Path -Filter $ext -Recurse -File -ErrorAction SilentlyContinue)
        } else {
            $files += @(Get-ChildItem -Path $Path -Filter $ext -File -ErrorAction SilentlyContinue)
        }
    }
    
    return ,@($files)
}

function Test-FuzzyMatch {
    param(
        [string]$Text,
        [string]$Pattern
    )
    
    # Convert to lowercase for case-insensitive matching
    $text = $Text.ToLower()
    $pattern = $Pattern.ToLower()
    
    $patternIndex = 0
    $textIndex = 0
    
    # Check if all characters in pattern appear in text in order
    while ($patternIndex -lt $pattern.Length -and $textIndex -lt $text.Length) {
        if ($pattern[$patternIndex] -eq $text[$textIndex]) {
            $patternIndex++
        }
        $textIndex++
    }
    
    # Return true if all pattern characters were found in order
    return $patternIndex -eq $pattern.Length
}

function Get-ActualFFplayPath {
    # Try to find the actual ffplay.exe, not the shim
    $ffplayCmd = Get-Command ffplay -ErrorAction SilentlyContinue
    
    if ($ffplayCmd) {
        $ffplayPath = $ffplayCmd.Source
        
        # If it's a shim from Chocolatey, find the actual exe
        if ($ffplayPath -match 'chocolatey.*shims') {
            $chocoPath = Join-Path $env:ChocolateyInstall "lib\ffmpeg\tools\ffmpeg\bin\ffplay.exe"
            if (Test-Path $chocoPath) {
                return $chocoPath
            }
        }
        
        # If it's a shim from Scoop, find the actual exe
        if ($ffplayPath -match 'scoop.*shims') {
            $scoopPath = Join-Path $env:SCOOP "apps\ffmpeg\current\bin\ffplay.exe"
            if (Test-Path $scoopPath) {
                return $scoopPath
            }
            # Try user scoop path
            $userScoopPath = Join-Path $env:USERPROFILE "scoop\apps\ffmpeg\current\bin\ffplay.exe"
            if (Test-Path $userScoopPath) {
                return $userScoopPath
            }
        }
        
        return $ffplayPath
    }
    
    return "ffplay"
}

function Play-Music {
    param(
        [string]$FilePath,
        [bool]$ShouldLoop = $false
    )
    
    if (-not (Test-Path $FilePath)) {
        Write-Host "File not found: $FilePath" -ForegroundColor Red
        return
    }
    
    Write-Host "`nNow playing: " -NoNewline -ForegroundColor Green
    Write-Host (Split-Path $FilePath -Leaf) -ForegroundColor Cyan
    if ($ShouldLoop) {
        Write-Host "(Looping - Press 'q' or Ctrl+C to stop)`n" -ForegroundColor Yellow
    } else {
        Write-Host "Press 'q' or Ctrl+C to stop playback`n" -ForegroundColor Gray
    }
    
    # Get the actual ffplay.exe path, bypassing shims
    $ffplayExe = Get-ActualFFplayPath
    
    # Build arguments - file path must be quoted if it contains spaces
    $loopArg = if ($ShouldLoop) { @("-loop", "0") } else { @() }
    $arguments = @("-nodisp", "-autoexit", "-loglevel", "error") + $loopArg + @("`"$FilePath`"")
    
    # Join arguments into a single string for proper space handling
    $argumentString = $arguments -join ' '
    
    # Use & operator to call directly in the current console - this allows Ctrl+C to work
    $process = Start-Process -FilePath $ffplayExe -ArgumentList $argumentString -PassThru -NoNewWindow
    
    # Animation characters
    $frames = @('♪♫', '♫♪', '♪ ♫', '♫ ♪', '♪  ♫', '♫  ♪')
    $bars = @('▁▂▃▄▅▆▇█', '█▇▆▅▄▃▂▁', '▃▄▅▆▇█▇▆', '▆▅▄▃▂▁▂▃')
    $colors = @('Cyan', 'Magenta', 'Blue', 'Green', 'Yellow')
    
    $frameIndex = 0
    $barIndex = 0
    $colorIndex = 0
    
    # Hide cursor
    [Console]::CursorVisible = $false
    
    try {
        while (-not $process.HasExited) {
            $frame = $frames[$frameIndex % $frames.Length]
            $bar = $bars[$barIndex % $bars.Length]
            $color = $colors[$colorIndex % $colors.Length]
            
            # Display animation
            Write-Host "`r  $frame  $bar  $frame  " -NoNewline -ForegroundColor $color
            
            $frameIndex++
            if ($frameIndex % 2 -eq 0) { $barIndex++ }
            if ($frameIndex % 6 -eq 0) { $colorIndex++ }
            
            Start-Sleep -Milliseconds 200
            
            # Check if process still exists
            if ($process.HasExited) { break }
        }
    }
    finally {
        # Show cursor again
        [Console]::CursorVisible = $true
        Write-Host "`r                              `r" -NoNewline
        
        # Cleanup process if still running
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

# Export alias function for 'play' command
function global:Invoke-PlayMusic {
    param(
        [Parameter(Position=0)]
        [string]$Query,
        [switch]$Recursive,
        [switch]$Shuffle,
        [switch]$Loop,
        [switch]$All,
        [switch]$Help
    )
    
    $scriptPath = Join-Path $PSScriptRoot "PlayPwsh.ps1"
    
    if ($Help) {
        & $scriptPath -Help
    } else {
        & $scriptPath -Query $Query -Recursive:$Recursive -Shuffle:$Shuffle -Loop:$Loop -All:$All
    }
}

Set-Alias -Name play -Value Invoke-PlayMusic -Scope Global

# Only run main script if not dot-sourced
if ($MyInvocation.InvocationName -ne '.') {
    # Main script
    if ($Help) {
        Show-Help
        exit 0
    }

    # Validate that -Loop and -All are not used together
    if ($Loop -and $All) {
        Write-Host "Error: -Loop and -All parameters cannot be used together" -ForegroundColor Red
        exit 1
    }

    if (-not (Test-Dependencies)) {
        exit 1
    }

# Parse file extensions
$extensions = $FileTypes -split ',' | ForEach-Object { $_.Trim() }

Write-Host "Scanning music folder: $MusicFolder" -ForegroundColor Cyan
$musicFiles = Get-MusicFiles -Path $MusicFolder -Extensions $extensions -IsRecursive $Recursive

if ($musicFiles.Count -eq 0) {
    Write-Host "No music files found in $MusicFolder" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($musicFiles.Count) music files" -ForegroundColor Green

# Prepare file list for fzf
$fileList = $musicFiles | ForEach-Object {
    if ($Recursive) {
        # Show relative path for better navigation
        $relativePath = $_.FullName.Replace($MusicFolder, "").TrimStart('\', '/')
        "$relativePath`t$($_.FullName)"
    } else {
        "$($_.Name)`t$($_.FullName)"
    }
}

# Shuffle if requested
if ($Shuffle) {
    $fileList = $fileList | Get-Random -Count $fileList.Count
}

# If -All parameter is used, select all files
if ($All) {
    Write-Host "Playing all $($fileList.Count) music files..." -ForegroundColor Green
    $selected = $fileList
}
# If query provided, try to auto-play best match
elseif ($Query) {
    # Split query into words for flexible fuzzy matching
    $queryWords = $Query -split '\s+' | Where-Object { $_.Trim() -ne '' }
    
    # Filter files where all query words fuzzy match (allows typos, order-independent)
    $matches = @($fileList | Where-Object {
        $fileName = $_
        $allWordsMatch = $true
        foreach ($word in $queryWords) {
            if (-not (Test-FuzzyMatch -Text $fileName -Pattern $word)) {
                $allWordsMatch = $false
                break
            }
        }
        $allWordsMatch
    })
    
    if ($matches.Count -eq 0) {
        Write-Host "No files matching '$Query' found" -ForegroundColor Yellow
        exit 0
    }
    
    # Auto-play the first match
    Write-Host "Found $($matches.Count) match(es) for '$Query'" -ForegroundColor Green
    $selected = $matches | Select-Object -First 1
} else {
    # Use fzf to select file(s)
    # --multi: allow multiple selections
    # --preview: show file info
    # --header: display instructions
    $fzfOptions = @(
        '--multi'
        '--reverse'
        '--height=100%'
        '--header=Select music file(s) to play (Tab to select multiple, Enter to confirm)'
        '--preview=echo File: {1}'
        '--preview-window=up:3:wrap'
    )
    
    $selected = $fileList | fzf @fzfOptions
    
    if (-not $selected) {
        Write-Host "No file selected" -ForegroundColor Yellow
        exit 0
    }
}

# Play selected files
$selectedFiles = @()
if ($selected -is [array]) {
    $selectedFiles = $selected
} else {
    $selectedFiles = @($selected)
}

foreach ($item in $selectedFiles) {
    $fullPath = ($item -split "`t")[1]
    Play-Music -FilePath $fullPath -ShouldLoop $Loop
}

Write-Host "`nPlayback complete!" -ForegroundColor Green
}